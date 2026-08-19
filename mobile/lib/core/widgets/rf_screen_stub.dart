import 'package:flutter/material.dart';

import 'package:reserveflash/core/design_system/rf_spacing.dart';
import 'package:reserveflash/core/design_system/rf_typography.dart';

/// Écran placeholder R0 : structure/navigation en place, logique métier à
/// venir aux étapes R1-R3 (section 18 - séquençage). Chaque écran final
/// listé section 3.2 remplace son stub sans changer la route (voir
/// app_router.dart) ni le contrat de navigation.
class RfScreenStub extends StatelessWidget {
  const RfScreenStub({
    required this.screenId,
    required this.title,
    required this.designCriterion,
    super.key,
  });

  /// Identifiant S01-S20 (section 3.2), gardé visible en dev pour tracer
  /// facilement quel écran du cahier des charges est en cours de câblage.
  final String screenId;
  final String title;
  final String designCriterion;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Padding(
        padding: const EdgeInsets.all(RfSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(screenId, style: RfTypography.secondary),
            const SizedBox(height: RfSpacing.xs),
            Text(title, style: RfTypography.screenTitle),
            const SizedBox(height: RfSpacing.md),
            Text(designCriterion, style: RfTypography.body),
          ],
        ),
      ),
    );
  }
}
