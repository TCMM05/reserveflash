import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:reserveflash/core/design_system/rf_theme.dart';
import 'package:reserveflash/core/router/app_router.dart';

void main() {
  // section 5.1 - "Pas de logique métier dans les widgets" : `main` reste
  // volontairement minimal, toute initialisation (base locale, secure
  // storage) est faite paresseusement par les providers Riverpod concernés
  // au premier accès, jamais ici.
  runApp(const ProviderScope(child: ReserveFlashApp()));
}

class ReserveFlashApp extends StatelessWidget {
  const ReserveFlashApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'ReserveFlash',
      debugShowCheckedModeBanner: false,
      theme: RfTheme.light(),
      routerConfig: appRouter,
      // Accessibilité (section 4.6) : ne jamais plafonner le text scaling
      // utilisateur (support jusqu'à 200%, section 4.3).
      builder: (BuildContext context, Widget? child) {
        return MediaQuery(
          data: MediaQuery.of(context),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
