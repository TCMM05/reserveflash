import 'package:flutter/material.dart';

import 'package:reserveflash/core/router/app_router.dart';
import 'package:reserveflash/core/widgets/rf_screen_stub.dart';

/// S01 - Splash / restauration session.
/// Critère de conception (section 3.2) : "<1s visuel ; ne bloque pas le
/// mode local plus que nécessaire."
///
/// R1 (préalable technique nécessaire au Gate R1, découvert pendant
/// l'implémentation - ce stub n'avait AUCUNE navigation avant R1, donc
/// l'app ne pouvait jamais atteindre l'accueil) : navigue directement vers
/// `AppRoutes.home` dès le premier frame, sans jamais passer par `auth` ni
/// nécessiter de réseau (points 8/13 - "l'utilisateur doit pouvoir
/// commencer à créer un incident immédiatement, pas de compte cloud
/// obligatoire"). `context.go` (pas `push`) : remplace l'écran splash dans
/// la pile, qui ne doit jamais être atteignable via le bouton retour.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.go(AppRoutes.home);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return const RfScreenStub(
      screenId: 'S01',
      title: 'ReserveFlash',
      designCriterion: '<1s visuel ; ne bloque pas le mode local plus que nécessaire.',
    );
  }
}
