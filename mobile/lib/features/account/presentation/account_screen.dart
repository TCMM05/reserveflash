import 'package:flutter/material.dart';

import 'package:reserveflash/core/widgets/rf_screen_stub.dart';

/// S18 - Compte / organisation. "Profil, abonnement, conservation,
/// suppression, mentions" (section 3.2). C'est ici, et uniquement ici, que
/// vit la suppression de compte (SEC-08, jamais paywallée - section 12.2).
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const RfScreenStub(
      screenId: 'S18',
      title: 'Compte',
      designCriterion: 'Profil, abonnement, conservation, suppression, mentions.',
    );
  }
}
