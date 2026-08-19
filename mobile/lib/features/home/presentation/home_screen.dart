import 'package:flutter/material.dart';

import 'package:reserveflash/core/design_system/rf_colors.dart';
import 'package:reserveflash/core/design_system/rf_spacing.dart';
import 'package:reserveflash/core/design_system/rf_typography.dart';
import 'package:reserveflash/core/router/app_router.dart';

/// S04 - Accueil. "CTA 'Nouvelle réception problématique' + derniers
/// dossiers + état sync" (section 3.2). C'est le seul écran avec CTA
/// primaire visible en permanence (principe "1 geste = 1 intention",
/// section 3.1).
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ReserveFlash'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Historique',
            onPressed: () => context.pushHistory(),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(RfSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Derniers dossiers', style: RfTypography.sectionTitle),
            const SizedBox(height: RfSpacing.sm),
            const Text(
              'Aucun incident pour le moment.',
              style: RfTypography.secondary,
            ),
            const Spacer(),
          ],
        ),
      ),
      // CTA principal en zone basse, pleine largeur (section 3.1/4.4).
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: RfSpacing.lg),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: RfColors.signal),
            onPressed: () => context.pushCreateIncident(),
            icon: const Icon(Icons.add_a_photo),
            label: const Text('Nouvelle réception problématique'),
          ),
        ),
      ),
    );
  }
}
