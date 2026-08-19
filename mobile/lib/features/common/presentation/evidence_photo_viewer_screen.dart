import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:reserveflash/core/design_system/rf_colors.dart';
import 'package:reserveflash/core/design_system/rf_spacing.dart';
import 'package:reserveflash/core/providers/app_providers.dart';
import 'package:reserveflash/core/widgets/rf_confirm_dialog.dart';
import 'package:reserveflash/domain/entities/evidence_asset.dart' as domain;
import 'package:reserveflash/features/common/presentation/camera_capture_page.dart';

/// Visionneuse plein écran d'une photo/bon de livraison déjà capturé.
///
/// Correction ciblée post-recette terrain R1 (avant freeze final) :
/// "après capture d'une photo, l'utilisateur ne peut pas réellement
/// contrôler le média enregistré." Ouverte au tap de n'importe quelle
/// [EvidenceThumbnailTile] de type photo/bon de livraison, depuis n'importe
/// quel écran du parcours (S06/S09/S17). Comme [CameraCapturePage], ce n'est
/// pas une étape nommée du parcours S01-S20 (section 3.2) : poussée via
/// `Navigator.push`, jamais via go_router.
///
/// 100% hors ligne (aucune dépendance réseau) et ne plante jamais sur un
/// fichier manquant/corrompu - même invariant que [EvidenceThumbnailTile]
/// (R1-T07), étendu ici au cas où le fichier serait référencé `available`
/// mais illisible au moment précis du rendu (`errorBuilder`).
class EvidencePhotoViewerScreen extends ConsumerStatefulWidget {
  const EvidencePhotoViewerScreen({
    required this.incidentId,
    required this.asset,
    this.label,
    this.allowRetake = true,
    super.key,
  });

  final String incidentId;
  final domain.EvidenceAsset asset;
  final String? label;

  /// `false` pour les contextes où reprendre la photo n'a pas de sens
  /// (aucun aujourd'hui, mais garde le composant réutilisable sans devoir
  /// toucher son API plus tard).
  final bool allowRetake;

  @override
  ConsumerState<EvidencePhotoViewerScreen> createState() => _EvidencePhotoViewerScreenState();
}

class _EvidencePhotoViewerScreenState extends ConsumerState<EvidencePhotoViewerScreen> {
  late domain.EvidenceAsset _asset;
  bool _isProcessing = false;
  bool _decodeFailed = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _asset = widget.asset;
  }

  Future<void> _delete() async {
    final bool confirmed = await confirmDestructiveAction(
      context,
      title: 'Supprimer cette photo ?',
      message: 'Cette action est définitive.',
    );
    if (!confirmed || !mounted) {
      return;
    }
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });
    try {
      await ref.read(evidenceStorageServiceProvider).deleteFile(_asset.localFilePath);
      await ref.read(incidentRepositoryProvider).deleteEvidenceAsset(_asset.id);
      notifyDataChanged(ref);
      if (mounted) {
        Navigator.of(context).pop();
      }
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

  Future<void> _retake() async {
    final String? path = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => CameraCapturePage(title: widget.label ?? 'Reprendre la photo'),
      ),
    );
    if (path == null || !mounted) {
      // Annulé ou permission refusée (R1-T06) : la photo existante reste
      // intacte, rien n'est perdu.
      return;
    }
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });
    try {
      // Remplacement explicite : la nouvelle preuve est capturée et
      // enregistrée AVANT que l'ancienne soit retirée (même invariant que
      // le reste de R1, point 9 - jamais d'état intermédiaire où le
      // dossier n'aurait ni l'ancienne ni la nouvelle photo si une erreur
      // survient entre les deux étapes).
      final domain.EvidenceAsset newAsset =
          await ref.read(evidenceStorageServiceProvider).captureFromFile(
                incidentId: widget.incidentId,
                sourcePath: path,
                documentType: _asset.documentType,
                mimeType: _asset.mimeType,
                issueId: _asset.issueId,
              );
      await ref.read(incidentRepositoryProvider).registerEvidenceAsset(newAsset);
      await ref.read(evidenceStorageServiceProvider).deleteFile(_asset.localFilePath);
      await ref.read(incidentRepositoryProvider).deleteEvidenceAsset(_asset.id);
      notifyDataChanged(ref);
      if (mounted) {
        setState(() {
          _asset = newAsset;
          _decodeFailed = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = "Impossible d'enregistrer la nouvelle photo : $e");
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isAvailable = _asset.availabilityStatus == domain.EvidenceAvailability.available;
    final bool canShowImage = isAvailable && !_decodeFailed;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.label ?? 'Photo'),
        // Bouton retour explicite (spec correction : "bouton retour clair").
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Retour',
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: <Widget>[
          if (widget.allowRetake)
            IconButton(
              icon: const Icon(Icons.camera_alt_outlined),
              tooltip: 'Reprendre la photo',
              onPressed: _isProcessing ? null : _retake,
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: RfColors.danger),
            tooltip: 'Supprimer',
            onPressed: _isProcessing ? null : _delete,
          ),
        ],
      ),
      body: Stack(
        children: <Widget>[
          Center(
            child: canShowImage
                ? InteractiveViewer(
                    minScale: 1,
                    maxScale: 5,
                    child: Image.file(
                      File(_asset.localFilePath),
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) {
                        // Fichier référencé "available" mais illisible au
                        // moment précis du rendu (R1-T07, étendu ici) :
                        // bascule vers l'état d'erreur contrôlé après le
                        // build en cours, jamais d'exception propagée.
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted && !_decodeFailed) {
                            setState(() => _decodeFailed = true);
                          }
                        });
                        return const SizedBox.shrink();
                      },
                    ),
                  )
                : _ControlledUnavailableView(
                    status: _asset.availabilityStatus,
                    decodeFailed: _decodeFailed,
                  ),
          ),
          if (_isProcessing)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x99000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          if (_errorMessage != null)
            Positioned(
              left: RfSpacing.lg,
              right: RfSpacing.lg,
              bottom: RfSpacing.lg,
              child: Container(
                padding: const EdgeInsets.all(RfSpacing.sm),
                decoration: BoxDecoration(
                  color: RfColors.danger,
                  borderRadius: BorderRadius.circular(RfSpacing.cardRadius / 2),
                ),
                child: Text(_errorMessage!, style: const TextStyle(color: Colors.white)),
              ),
            ),
        ],
      ),
    );
  }
}

class _ControlledUnavailableView extends StatelessWidget {
  const _ControlledUnavailableView({required this.status, required this.decodeFailed});

  final domain.EvidenceAvailability status;
  final bool decodeFailed;

  @override
  Widget build(BuildContext context) {
    final String message = decodeFailed
        ? 'Ce fichier ne peut pas être affiché comme une image (corrompu ou '
            'format inattendu). Vous pouvez le supprimer ou reprendre la photo.'
        : switch (status) {
            domain.EvidenceAvailability.missing =>
              'Photo introuvable sur cet appareil. Les autres preuves de ce '
                  'dossier ne sont pas affectées.',
            domain.EvidenceAvailability.corrupted =>
              'Fichier corrompu - la photo ne peut plus être affichée. Vous '
                  'pouvez la reprendre ou la supprimer.',
            domain.EvidenceAvailability.available => 'Photo momentanément indisponible.',
          };
    return Padding(
      padding: const EdgeInsets.all(RfSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.broken_image_outlined, color: Colors.white70, size: 64),
          const SizedBox(height: RfSpacing.md),
          Text(message, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
