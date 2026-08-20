import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:reserveflash/core/design_system/rf_spacing.dart';
import 'package:reserveflash/core/design_system/rf_typography.dart';
import 'package:reserveflash/core/providers/app_providers.dart';
import 'package:reserveflash/core/router/app_router.dart';
import 'package:reserveflash/core/widgets/rf_confirm_dialog.dart';
import 'package:reserveflash/data/ai_queue_processor.dart';
import 'package:reserveflash/domain/entities/ai_queue_item.dart';
import 'package:reserveflash/domain/entities/candidate_fact_set.dart' as domain;
import 'package:reserveflash/domain/entities/evidence_asset.dart' as domain;
import 'package:reserveflash/domain/entities/issue.dart' as domain;
import 'package:reserveflash/features/common/presentation/camera_capture_page.dart';
import 'package:reserveflash/features/common/presentation/evidence_photo_viewer_screen.dart';
import 'package:reserveflash/features/common/presentation/evidence_thumbnail_tile.dart';
import 'package:reserveflash/features/common/presentation/missing_incident_view.dart';

/// S09 - Capture preuves. "Checklist photo ; compteur ; supprimer/reprendre"
/// (section 3.2). R1 point 4 : capture GUIDÉE - Photo 1 (vue générale),
/// Photo 2 (étiquette/référence), Photo 3 (vue rapprochée du dommage), puis
/// photos supplémentaires facultatives. Chaque photo est sauvegardée
/// (écriture atomique + SHA-256, voir evidence_storage.dart) AVANT toute
/// autre opération - jamais d'appel réseau/IA (points 4/8/9/R1-T10).
///
/// R1 : les 3 emplacements guidés sont déterminés par ORDRE de capture
/// (1ère photo = vue générale, etc.) - aucun champ de "libellé de preuve"
/// n'existe dans le schéma `LocalEvidenceAssets` (voir app_database.dart),
/// c'est donc une convention d'affichage uniquement, pas une contrainte
/// stockée. Documenté comme limitation connue (voir CHANGELOG.md/
/// GATE_R1_STATUS.md) : une future révision pourrait ajouter un champ
/// `slotLabel` explicite si ce point s'avère gênant en usage réel.
///
/// R2 (lot OCR preuve photo générique, `AiOperationKind.extractFromPhoto`) :
/// SEULE la photo "Étiquette / référence" (la plus susceptible de contenir
/// du texte utile - contrairement à une vue générale ou un gros plan de
/// dommage) déclenche une mise en file OCR+IA au mieux-effort, et
/// uniquement si aucun `CandidateFactSet` n'existe encore pour l'anomalie
/// (voir `_enqueueOcrExtractionBestEffort` ci-dessous) - pour ne jamais
/// écraser silencieusement un résultat déjà obtenu par ailleurs (bon de
/// livraison à S06/S08, note vocale à S10) par un résultat moins bon issu
/// d'une simple photo d'étiquette. Cette anomalie existe forcément à ce
/// stade (S08 la crée, S09 vient après - contrairement au bug corrigé pour
/// S06, voir `issue_type_screen.dart`).
class EvidenceCaptureScreen extends ConsumerStatefulWidget {
  const EvidenceCaptureScreen({required this.incidentId, super.key});

  final String incidentId;

  @override
  ConsumerState<EvidenceCaptureScreen> createState() => _EvidenceCaptureScreenState();
}

const List<String> _guidedLabels = <String>[
  'Photo 1 - Vue générale',
  'Photo 2 - Étiquette / référence',
  'Photo 3 - Vue rapprochée du dommage',
];

const int _minimumGuidedPhotos = 3;

class _EvidenceCaptureScreenState extends ConsumerState<EvidenceCaptureScreen> {
  bool _isProcessing = false;
  String? _errorMessage;

  Future<void> _capturePhoto(String label) async {
    final String? path = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => CameraCapturePage(title: label)),
    );
    if (path == null || !mounted) {
      return; // Annulé ou permission refusée (R1-T06) : rien n'est perdu.
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
                documentType: domain.EvidenceDocumentType.photo,
                mimeType: 'image/jpeg',
              );
      await ref.read(incidentRepositoryProvider).registerEvidenceAsset(asset);
      notifyDataChanged(ref);
      if (label == _guidedLabels[1]) {
        await _enqueueOcrExtractionBestEffort(asset);
      }
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

  /// R2 (lot OCR preuve photo générique) : voir docstring de fichier. Best
  /// effort explicite (même politique que partout ailleurs dans le pipeline
  /// IA) : jamais d'erreur affichée pour cette étape optionnelle, jamais un
  /// blocage de la capture (déjà écrite sur disque avant cet appel).
  Future<void> _enqueueOcrExtractionBestEffort(domain.EvidenceAsset asset) async {
    try {
      final List<domain.Issue> issues =
          await ref.read(incidentRepositoryProvider).listIssues(widget.incidentId);
      if (issues.isEmpty) {
        return;
      }
      final String issueId = issues.first.id;
      // Garde-fou coût/qualité (voir docstring de fichier) : ne jamais
      // écraser un CandidateFactSet déjà obtenu (BL, note vocale) par un
      // résultat potentiellement moins bon issu d'une simple photo
      // d'étiquette.
      final domain.CandidateFactSet? existing =
          await ref.read(incidentRepositoryProvider).latestCandidateFactSet(issueId);
      if (existing != null) {
        return;
      }
      final ExtractFromPhotoPayload payload =
          ExtractFromPhotoPayload(evidenceAssetId: asset.id);
      // sourceHash = SHA-256 déjà calculé à la capture (evidence_storage.dart)
      // - même principe que le bon de livraison et la note vocale.
      final String sourceHash = asset.sha256 ?? asset.id;
      await ref.read(incidentRepositoryProvider).enqueueAiOperation(
            incidentId: widget.incidentId,
            issueId: issueId,
            operationKind: AiOperationKind.extractFromPhoto,
            payloadJson: payload.encode(),
            idempotencyKey: aiOperationIdempotencyKey(
              incidentId: widget.incidentId,
              operationKind: AiOperationKind.extractFromPhoto,
              sourceHash: sourceHash,
            ),
          );
      // Déclenchement "online" au mieux-effort - si l'OCR/extraction échoue
      // maintenant (réseau, quota IA...), l'item reste `pending` en base et
      // sera retenté par un prochain appel à ce même processeur (ex : écran
      // de revue des faits) - jamais une perte.
      unawaited(ref.read(aiQueueProcessorProvider).processPendingOperations());
    } catch (_) {
      // Best-effort explicite (voir docstring de fichier) : aucune erreur
      // affichée à l'utilisateur pour cette étape optionnelle.
    }
  }

  Future<void> _deletePhoto(domain.EvidenceAsset asset) async {
    final bool confirmed = await confirmDestructiveAction(
      context,
      title: 'Supprimer cette photo ?',
      message: 'Cette action est définitive. La photo sera retirée du dossier.',
    );
    if (!confirmed || !mounted) {
      return;
    }
    setState(() => _isProcessing = true);
    try {
      await ref.read(evidenceStorageServiceProvider).deleteFile(asset.localFilePath);
      await ref.read(incidentRepositoryProvider).deleteEvidenceAsset(asset.id);
      notifyDataChanged(ref);
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Impossible de supprimer la photo : $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
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
      appBar: AppBar(title: const Text('Photos des preuves')),
      body: Padding(
        padding: const EdgeInsets.all(RfSpacing.lg),
        child: evidenceAsync.when(
          data: (List<domain.EvidenceAsset> assets) {
            final List<domain.EvidenceAsset> photos = assets
                .where((domain.EvidenceAsset a) => a.documentType == domain.EvidenceDocumentType.photo)
                .toList()
              ..sort(
                (domain.EvidenceAsset a, domain.EvidenceAsset b) =>
                    a.capturedAtDevice.compareTo(b.capturedAtDevice),
              );
            final bool canContinue = photos.length >= _minimumGuidedPhotos;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${photos.length}/$_minimumGuidedPhotos photos guidées capturées'
                  '${photos.length > _minimumGuidedPhotos ? ' (+ ${photos.length - _minimumGuidedPhotos} supplémentaire(s))' : ''}',
                  style: RfTypography.secondary,
                ),
                const SizedBox(height: RfSpacing.md),
                Expanded(
                  child: ListView(
                    children: <Widget>[
                      ...photos.asMap().entries.map((MapEntry<int, domain.EvidenceAsset> entry) {
                        final int index = entry.key;
                        final String label = index < _guidedLabels.length
                            ? _guidedLabels[index]
                            : 'Photo supplémentaire';
                        return EvidenceThumbnailTile(
                          asset: entry.value,
                          label: label,
                          onDelete: _isProcessing ? null : () => _deletePhoto(entry.value),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => EvidencePhotoViewerScreen(
                                incidentId: widget.incidentId,
                                asset: entry.value,
                                label: label,
                              ),
                            ),
                          ),
                        );
                      }),
                      if (photos.length < _guidedLabels.length)
                        Padding(
                          padding: const EdgeInsets.only(bottom: RfSpacing.sm),
                          child: OutlinedButton.icon(
                            onPressed: _isProcessing
                                ? null
                                : () => _capturePhoto(_guidedLabels[photos.length]),
                            icon: const Icon(Icons.camera_alt),
                            label: Text('Prendre : ${_guidedLabels[photos.length]}'),
                          ),
                        ),
                      if (photos.length >= _guidedLabels.length)
                        Padding(
                          padding: const EdgeInsets.only(bottom: RfSpacing.sm),
                          child: OutlinedButton.icon(
                            onPressed: _isProcessing
                                ? null
                                : () => _capturePhoto('Photo supplémentaire'),
                            icon: const Icon(Icons.add_a_photo_outlined),
                            label: const Text('Ajouter une photo supplémentaire (optionnel)'),
                          ),
                        ),
                    ],
                  ),
                ),
                if (_errorMessage != null) ...<Widget>[
                  Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: RfSpacing.sm),
                ],
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: canContinue && !_isProcessing
                        ? () => context.pushVoiceDescription(widget.incidentId)
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
