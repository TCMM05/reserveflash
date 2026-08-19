import 'package:flutter/material.dart';

import 'package:reserveflash/core/widgets/rf_screen_stub.dart';

/// S08 - Type de problème. "Cartes simples multi-sélectionnables"
/// (section 3.2) - une carte par IssueType (F05), sélection multiple pour
/// gérer les incidents multiples (section 2.5).
class IssueTypeScreen extends StatelessWidget {
  const IssueTypeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const RfScreenStub(
      screenId: 'S08',
      title: 'Quel est le problème ?',
      designCriterion: 'Cartes simples multi-sélectionnables.',
    );
  }
}
