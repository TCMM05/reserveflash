import 'package:flutter/material.dart';

import 'package:reserveflash/core/widgets/rf_screen_stub.dart';

/// S19 - Paywall.
/// "Uniquement après valeur démontrée ; jamais avant capture d'un premier
/// incident gratuit." (section 3.2, règles paywall 12.2). Cet écran ne doit
/// JAMAIS être poussé dans la navigation avant la fin d'un premier
/// incident complet (voir app_router.dart pour les gardes de navigation).
class PaywallScreen extends StatelessWidget {
  const PaywallScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const RfScreenStub(
      screenId: 'S19',
      title: 'Débloquez plus de dossiers',
      designCriterion:
          'Uniquement après valeur démontrée ; jamais avant capture d\'un premier incident gratuit.',
    );
  }
}
