import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:reserveflash/core/design_system/rf_spacing.dart';
import 'package:reserveflash/core/design_system/rf_typography.dart';
import 'package:reserveflash/core/providers/app_providers.dart';
import 'package:reserveflash/core/router/app_router.dart';
import 'package:reserveflash/data/ai_queue_processor.dart';
import 'package:reserveflash/domain/entities/ai_queue_item.dart';
import 'package:reserveflash/domain/entities/evidence_asset.dart' as domain;
import 'package:reserveflash/domain/entities/issue.dart' as domain;
import 'package:reserveflash/features/common/presentation/camera_capture_page.dart';
import 'package:reserveflash/features/common/presentation/evidence_photo_viewer_screen.dart';
import 'package:reserveflash/features/common/presentation/evidence_thumbnail_tile.dart';
import 'package:reserveflash/features/common/presentation/missing_incident_view.dart';

/// S06 - Capture document. "Caméra plein écran + cadrage + reprise photo"
/// (section 3.2). R1 point 2 : à l'enregistrement, une preuve
/// `EvidenceAsset` complète (id, incident associé, type document de
/// livraison, date/heure, chemin local, taille, SHA-256) est écrite AVANT
/// toute opération réseau/IA (points 4/8/9) - aucun OCR/IA obligatoire ici
/// (point 2, capture 100% hors ligne, R1-T10). R2 (lot OCR, correctif) : une
/// tentative de mise en file de l'extraction OCR+IA a lieu ici au
/// mieux-effort (voir `_enqueueOcrExtractionBestEffort` ci-dessous), mais
/// dans le parcours nominal (S06 -> S07 documentMetadata -> S08 issueType)
/// elle est un no-op silencieux, faute d'`Issue` encore créée à ce stade
/// (S07 ne crée pas non plus d'`Issue` - voir `document_metadata_screen.dart` :
/// il ne fait qu'éditer les métadonnées déjà existantes de l'`Incident`
/// lui-même) - la mise en file réelle a lieu à S08, voir
/// `issue_type_screen.dart`. Même philosophie que
/// `voice_description_screen.dart` en tout état de cause : l'échec (ou
/// l'absence) de cette étape optionnelle ne doit jamais donner l'impression
/// que la photo elle-même a été perdue, ni bloquer la suite du parcours.
class DocumentCaptureScreen extends ConsumerStatefulWidget {
  const DocumentCaptureScreen({required this.incidentId, super.key});

  final String incidentId;

  @override
  ConsumerState<DocumentCaptureScreen> createState() => _DocumentCaptureScreenState();
}

class _DocumentCaptureScreenState extends ConsumerState<DocumentCaptureScreen> {
  bool _isProcessing = false;
  String? _errorMessage;

  Future<void> _captureDeliveryDocument() async {
    final String? path = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => const CameraCapturePage(title: 'Photo du bon de livraison'),
      ),
    );
    if (path == null || !mounted) {
      // Annulé ou permission refusée (R1-T06) : aucune perte de dossier,
      // l'utilisateur reste simplement sur cet écran.
      return;
    }
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });
    try {
      final domain.EvidenceAsset asset =
          await ref.read(evidenceStorageServiceProvider).captureFromFile(
                incidentId: widget.incidentId,
                sourcePath: path,
                documentType: domain.EvidenceDocumentType.deliveryNote,
                mimeType: 'image/jpeg',
              );
      // Point 4 : la preuve est écrite sur disque (ligne ci-dessus) AVANT
      // toute autre opération - l'enregistrement des métadonnées ci-dessous
      // ne fait, lui non plus, aucun appel réseau.
      await ref.read(incidentRepositoryProvider).registerEvidenceAsset(asset);
      notifyDataChanged(ref);
      await _enqueueOcrExtractionBestEffort(asset);
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = "Impossible d'enregistrer la photo : $e");
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  /// R2 (lot OCR, correctif) : déclenche l'extraction OCR+IA du document qui
  /// vient d'être capturé, au mieux-effort - jamais un blocage de
  /// l'utilisateur, jamais une erreur affichée ici (voir docstring de
  /// fichier). Un `CandidateFactSet` est toujours rattaché à une anomalie
  /// (`Issue`), jamais à l'incident entier - or dans le parcours NOMINAL (S06
  /// documentCapture -> S07 documentMetadata -> S08 issueType -> ...), aucune
  /// `Issue` n'existe encore à ce stade (elle n'est créée qu'à S08) : cet
  /// appel-ci est donc un no-op silencieux dans le cas normal, volontairement
  /// laissé pour le seul cas
  /// où cet écran est atteint avec une anomalie déjà existante (ex :
  /// "Reprendre la photo" depuis `incident_detail_screen.dart` sur un
  /// dossier déjà avancé). **La mise en file réelle, pour le parcours
  /// nominal, a lieu dans
  /// `issue_type_screen.dart::_enqueueOcrExtractionBestEffort`**, juste
  /// après la création de la première `Issue` - voir la docstring de ce
  /// fichier pour l'explication complète. `enqueueAiOperation` étant
  /// idempotent par clé, les deux points d'appel ne créent jamais de
  /// doublon.
  Future<void> _enqueueOcrExtractionBestEffort(domain.EvidenceAsset asset) async {
    try {
      final List<domain.Issue> issues =
          await ref.read(incidentRepositoryProvider).listIssues(widget.incidentId);
      if (issues.isEmpty) {
        if (kDebugMode) {
          debugPrint(
            '[RF][extractFromDocument] aucune anomalie pour incident '
            '${widget.incidentId} - mise en file annulée (cas nominal S06, '
            'voir docstring - la vraie mise en file a lieu à S08).',
          );
        }
        return;
      }
      final ExtractFromDocumentPayload payload =
          ExtractFromDocumentPayload(evidenceAssetId: asset.id);
      // sourceHash = SHA-256 déjà calculé à la capture (evidence_storage.dart)
      // - même principe que la note vocale (voir
      // voice_description_screen.dart::_enqueueTranscriptionBestEffort).
      final String sourceHash = asset.sha256 ?? asset.id;
      await ref.read(incidentRepositoryProvider).enqueueAiOperation(
            incidentId: widget.incidentId,
            issueId: issues.first.id,
            operationKind: AiOperationKind.extractFromDocument,
            payloadJson: payload.encode(),
            idempotencyKey: aiOperationIdempotencyKey(
              incidentId: widget.incidentId,
              operationKind: AiOperationKind.extractFromDocument,
              sourceHash: sourceHash,
            ),
          );
      if (kDebugMode) {
        debugPrint(
          '[RF][extractFromDocument] mise en file pour asset ${asset.id} '
          '(issue ${issues.first.id}, sourceHash=$sourceHash).',
        );
      }
      // Déclenchement "online" au mieux-effort - si l'OCR/extraction échoue
      // maintenant (réseau, quota IA...), l'item reste `pending` en base et
      // sera retenté par un prochain appel à ce même processeur (ex : écran
      // de revue des faits) - jamais une perte. `.then()` (plutôt qu'un
      // `await` qui bloquerait ce best-effort) pour logguer le résultat sans
      // changer le caractère non-bloquant de cet appel.
      unawaited(
        ref.read(aiQueueProcessorProvider).processPendingOperations().then((
          AiQueueProcessingSummary summary,
        ) {
          if (kDebugMode) {
            debugPrint(
              '[RF][extractFromDocument] traitement terminé : '
              'succeeded=${summary.succeeded} failed=${summary.failed} '
              'skipped=${summary.skipped}.',
            );
          }
        }),
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[RF][extractFromDocument] EXCEPTION best-effort (avalée, jamais '
          'affichée à l\'utilisateur) : $e',
        );
      }
      // Best-effort explicite (voir docstring de fichier) : aucune erreur
      // affichée à l'utilisateur pour cette étape optionnelle.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.incidentId.isEmpty) {
      return const MissingIncidentView();
    }
    final AsyncValue<List<domain.EvidenceAsset>> evidenceAsync =
        ref.watch(incidentEvidenceProvider(widget.incidentId));

    return Scaffold(
      appBar: AppBar(title: const Text('Photo du document de transport')),
      body: Padding(
        padding: const EdgeInsets.all(RfSpacing.lg),
        child: evidenceAsync.when(
          data: (List<domain.EvidenceAsset> assets) {
            final List<domain.EvidenceAsset> deliveryDocs = assets
                .where((domain.EvidenceAsset a) => a.documentType == domain.EvidenceDocumentType.deliveryNote)
                .toList();
            final bool hasDocument = deliveryDocs.isNotEmpty;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Prenez en photo le bon de livraison. La photo est enregistrée '
                  "immédiatement sur l'appareil, sans connexion requise.",
                  style: RfTypography.secondary,
                ),
                const SizedBox(height: RfSpacing.lg),
                Expanded(
                  child: hasDocument
                      ? ListView(
                          children: deliveryDocs
                              .map(
                                (domain.EvidenceAsset a) => EvidenceThumbnailTile(
                                  asset: a,
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => EvidencePhotoViewerScreen(
                                        incidentId: widget.incidentId,
                                        asset: a,
                                        label: 'Bon de livraison',
                                      ),
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        )
                      : const Center(
                          child: Text(
                            'Aucune photo du bon de livraison pour le moment.',
                            style: RfTypography.secondary,
                          ),
                        ),
                ),
                if (_errorMessage != null) ...<Widget>[
                  Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: RfSpacing.sm),
                ],
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isProcessing ? null : _captureDeliveryDocument,
                    icon: const Icon(Icons.camera_alt),
                    label: Text(hasDocument ? 'Reprendre la photo' : 'Prendre la photo'),
                  ),
                ),
                const SizedBox(height: RfSpacing.sm),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    // R2 (câblage S07, voir document_metadata_screen.dart) :
                    // pousse désormais vers la vérification des informations
                    // du BL avant le type de problème, au lieu de sauter
                    // directement à S08 comme avant ce lot.
                    onPressed: hasDocument && !_isProcessing
                        ? () => context.pushDocumentMetadata(widget.incidentId)
                        : null,
                    child: const Text('Continuer'),
                  ),
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object e, StackTrace stackTrace) => Center(child: Text('Erreur de lecture locale : $e')),
        ),
      ),
    );
  }
}
