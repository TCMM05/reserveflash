import 'package:flutter/material.dart';

import 'package:reserveflash/core/widgets/rf_screen_stub.dart';

/// S03 - Connexion / inscription. "Minimal, recovery inclus" (section 3.2).
/// Auth : email + mot de passe ou magic link, pas de social login en 1.0
/// (section 2.6).
///
/// R0.1 (point 13 - "pas de création de compte cloud obligatoire pour la V1
/// locale") : cet écran devient OPTIONNEL. Il reste dans le routeur
/// (`AppRoutes.auth`) pour une fonctionnalité de compte/synchronisation
/// différée à une version ultérieure (voir docs/adr/0002-local-first-pivot.md),
/// mais AUCUNE route (`AppRoutes.home`, `AppRoutes.createIncident`, ...) ne
/// doit dépendre d'un état d'authentification - voir `app_router.dart`, qui
/// ne définit volontairement aucun `redirect` de garde vers cet écran.
class AuthScreen extends StatelessWidget {
  const AuthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const RfScreenStub(
      screenId: 'S03',
      title: 'Connexion',
      designCriterion: 'Minimal, recovery inclus.',
    );
  }
}
