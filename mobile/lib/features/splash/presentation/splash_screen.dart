import 'package:flutter/material.dart';

import 'package:reserveflash/core/widgets/rf_screen_stub.dart';

/// S01 - Splash / restauration session.
/// Critère de conception (section 3.2) : "<1s visuel ; ne bloque pas le
/// mode local plus que nécessaire."
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const RfScreenStub(
      screenId: 'S01',
      title: 'ReserveFlash',
      designCriterion:
          '<1s visuel ; ne bloque pas le mode local plus que nécessaire.',
    );
  }
}
