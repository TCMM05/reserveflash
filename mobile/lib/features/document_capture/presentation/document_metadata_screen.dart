import 'package:flutter/material.dart';

import 'package:reserveflash/core/widgets/rf_screen_stub.dart';

/// S07 - Métadonnées candidates. "Champs éditables ; incertitudes mises en
/// évidence" (section 3.2). Transparence IA (section 3.1) : chaque valeur
/// affichée ici doit être visuellement distinguée comme "compris par l'IA"
/// tant qu'elle n'a pas été confirmée (F04 GATE).
class DocumentMetadataScreen extends StatelessWidget {
  const DocumentMetadataScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const RfScreenStub(
      screenId: 'S07',
      title: 'Vérifier les informations',
      designCriterion: 'Champs éditables ; incertitudes mises en évidence.',
    );
  }
}
