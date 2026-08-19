import 'package:flutter/material.dart';

import 'package:reserveflash/core/widgets/rf_screen_stub.dart';

/// S14 - Checklist dossier. "Vert/orange ; items manquants actionnables"
/// (section 3.2, F12).
class ChecklistScreen extends StatelessWidget {
  const ChecklistScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const RfScreenStub(
      screenId: 'S14',
      title: 'Complétude du dossier',
      designCriterion: 'Vert/orange ; items manquants actionnables.',
    );
  }
}
