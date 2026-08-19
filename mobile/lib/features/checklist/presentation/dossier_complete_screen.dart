import 'package:flutter/material.dart';

import 'package:reserveflash/core/widgets/rf_screen_stub.dart';

/// S15 - Dossier terminé. "Exporter PDF, partager, voir détails"
/// (section 3.2, F13/F14).
class DossierCompleteScreen extends StatelessWidget {
  const DossierCompleteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const RfScreenStub(
      screenId: 'S15',
      title: 'Dossier terminé',
      designCriterion: 'Exporter PDF, partager, voir détails.',
    );
  }
}
