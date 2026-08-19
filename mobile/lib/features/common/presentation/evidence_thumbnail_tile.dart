import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:reserveflash/core/design_system/rf_colors.dart';
import 'package:reserveflash/core/design_system/rf_spacing.dart';
import 'package:reserveflash/domain/entities/evidence_asset.dart' as domain;

/// Tuile réutilisée par S06/S09/S17 pour afficher une preuve capturée -
/// gère explicitement les statuts `missing`/`corrupted` (point 9/R1-T07) :
/// n'essaie JAMAIS de décoder l'image d'un fichier dont l'intégrité n'est
/// pas `available`, affiche une icône d'alerte contrôlée à la place.
///
/// [onTap] (correction ciblée post-recette terrain R1, avant freeze final) :
/// ouvre la visionneuse photo/le lecteur audio plein écran correspondant -
/// câblé par chaque écran appelant (qui sait quel type de visionneuse
/// ouvrir selon `asset.documentType`), voir `evidence_photo_viewer_screen.dart`
/// / `evidence_audio_player_screen.dart`.
class EvidenceThumbnailTile extends StatelessWidget {
  const EvidenceThumbnailTile({
    required this.asset,
    this.label,
    this.onDelete,
    this.onTap,
    super.key,
  });

  final domain.EvidenceAsset asset;
  final String? label;
  final VoidCallback? onDelete;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool isImage = asset.mimeType.startsWith('image/');
    final bool isAvailable = asset.availabilityStatus == domain.EvidenceAvailability.available;

    Widget leading;
    if (isAvailable && isImage) {
      leading = ClipRRect(
        borderRadius: BorderRadius.circular(RfSpacing.cardRadius / 2),
        child: Image.file(
          File(asset.localFilePath),
          width: 56,
          height: 56,
          fit: BoxFit.cover,
          // R1-T07 : un fichier référencé mais illisible au moment précis du
          // rendu (ex: supprimé hors app entre la vérification d'intégrité
          // et l'affichage) ne doit jamais planter l'UI.
          errorBuilder: (_, __, ___) => const _BrokenThumbnail(),
        ),
      );
    } else if (isAvailable) {
      leading = const CircleAvatar(child: Icon(Icons.audiotrack));
    } else {
      leading = const _BrokenThumbnail();
    }

    return Card(
      margin: const EdgeInsets.only(bottom: RfSpacing.sm),
      child: ListTile(
        onTap: onTap,
        leading: leading,
        title: Text(
          label ?? DateFormat('dd/MM/yyyy HH:mm').format(asset.capturedAtDevice.toLocal()),
        ),
        subtitle: Text(_availabilityLabel(asset.availabilityStatus)),
        trailing: onDelete == null
            ? null
            : IconButton(
                icon: const Icon(Icons.delete_outline, color: RfColors.danger),
                onPressed: onDelete,
                tooltip: 'Supprimer',
              ),
      ),
    );
  }

  String _availabilityLabel(domain.EvidenceAvailability status) {
    switch (status) {
      case domain.EvidenceAvailability.available:
        return 'Enregistrée sur cet appareil';
      case domain.EvidenceAvailability.missing:
        return 'Fichier introuvable sur cet appareil';
      case domain.EvidenceAvailability.corrupted:
        return 'Fichier corrompu - à reprendre si possible';
    }
  }
}

class _BrokenThumbnail extends StatelessWidget {
  const _BrokenThumbnail();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: RfColors.border,
        borderRadius: BorderRadius.circular(RfSpacing.cardRadius / 2),
      ),
      child: const Icon(Icons.broken_image_outlined, color: RfColors.danger),
    );
  }
}
