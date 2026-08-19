import 'package:flutter/material.dart';

import 'package:reserveflash/core/widgets/rf_screen_stub.dart';

/// S09 - Capture preuves. "Checklist photo ; compteur ; supprimer/reprendre"
/// (section 3.2). F06 GATE : conservation de l'original obligatoire.
class EvidenceCaptureScreen extends StatelessWidget {
  const EvidenceCaptureScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const RfScreenStub(
      screenId: 'S09',
      title: 'Photos des preuves',
      designCriterion: 'Checklist photo ; compteur ; supprimer/reprendre.',
    );
  }
}
