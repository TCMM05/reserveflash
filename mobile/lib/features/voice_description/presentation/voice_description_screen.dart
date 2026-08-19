import 'package:flutter/material.dart';

import 'package:reserveflash/core/widgets/rf_screen_stub.dart';

/// S10 - Description voix/texte. "Bouton micro large, timer, lecture/
/// annulation, texte éditable" (section 3.2). F07 : "sortie de secours"
/// (section 3.1) - saisie manuelle toujours possible si l'IA est
/// indisponible.
class VoiceDescriptionScreen extends StatelessWidget {
  const VoiceDescriptionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const RfScreenStub(
      screenId: 'S10',
      title: 'Décrivez ce que vous constatez',
      designCriterion: 'Bouton micro large, timer, lecture/annulation, texte éditable.',
    );
  }
}
