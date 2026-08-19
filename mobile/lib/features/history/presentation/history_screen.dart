import 'package:flutter/material.dart';

import 'package:reserveflash/core/widgets/rf_screen_stub.dart';

/// S16 - Historique. "Recherche, filtres, statuts, offline visible"
/// (section 3.2, F15).
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const RfScreenStub(
      screenId: 'S16',
      title: 'Historique',
      designCriterion: 'Recherche, filtres, statuts, offline visible.',
    );
  }
}
