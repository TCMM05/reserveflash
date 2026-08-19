import 'package:flutter/material.dart';

import 'package:reserveflash/core/widgets/rf_screen_stub.dart';

/// S02 - Onboarding court.
/// "3 bénéfices max + confidentialité ; permission caméra/micro demandée au
/// moment utile" (section 3.2, cohérent avec 10.2 privacy by design : les
/// permissions ne sont PAS demandées ici, seulement à l'usage réel).
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const RfScreenStub(
      screenId: 'S02',
      title: 'Bienvenue',
      designCriterion:
          '3 bénéfices max + confidentialité ; permission caméra/micro demandée au moment utile.',
    );
  }
}
