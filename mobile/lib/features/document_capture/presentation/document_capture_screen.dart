import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:reserveflash/core/design_system/rf_spacing.dart';
import 'package:reserveflash/core/design_system/rf_typography.dart';
import 'package:reserveflash/core/providers/app_providers.dart';
import 'package:reserveflash/core/router/app_router.dart';
import 'package:reserveflash/domain/entities/evidence_asset.dart' as domain;
import 'package:reserveflash/features/common/presentation/camera_capture_page.dart';
import 'package:reserveflash/features/common/presentation/evidence_photo_viewer_screen.dart';
import 'package:reserveflash/features/common/presentation/evidence_thumbnail_tile.dart';
import 'package:reserveflash/features/common/presentation/missing_incident_view.dart';

/// S06 - Capture document. "Caméra plein écran + cadrage + reprise photo"
/// (section 3.2). R1 point 2 : à l'enregistrement, une preuve
/// `EvidenceAsset` complète (id, incident associé, type document de
/// livraison, date/heure, chemin local, taille, SHA-256) est écrite AVANT
/// toute opération réseau/IA (points 4/8/9) - aucun OCR/IA obligatoire ici
/// (point 2). Fonctionne 100% hors ligne (R1-T10).
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
                    onPressed: hasDocument && !_isProcessing
                        ? () => context.pushIssueType(widget.incidentId)
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
