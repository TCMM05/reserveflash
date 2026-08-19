import 'package:flutter/material.dart';

import 'package:reserveflash/core/design_system/rf_colors.dart';
import 'package:reserveflash/core/design_system/rf_spacing.dart';
import 'package:reserveflash/core/design_system/rf_typography.dart';
import 'package:reserveflash/core/router/app_router.dart';
import 'package:reserveflash/features/common/presentation/missing_incident_view.dart';

/// S15 - Dossier terminé. En R1, "exporter PDF, partager" (section 3.2,
/// F13/F14) reste HORS PÉRIMÈTRE (voir demande corrective - "PDF final" est
/// explicitement exclu de R1) : cet écran confirme uniquement que le
/// dossier est intégralement sauvegardé localement, et permet de le
/// consulter (S17) ou de revenir à l'accueil (S04).
class DossierCompleteScreen extends StatelessWidget {
  const DossierCompleteScreen({required this.incidentId, super.key});

  final String incidentId;

  @override
  Widget build(BuildContext context) {
    if (incidentId.isEmpty) {
      return const MissingIncidentView();
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Dossier terminé'), automaticallyImplyLeading: false),
      body: Padding(
        padding: const EdgeInsets.all(RfSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(Icons.check_circle, color: RfColors.success, size: 56),
            const SizedBox(height: RfSpacing.md),
            const Text('Dossier enregistré', style: RfTypography.screenTitle),
            const SizedBox(height: RfSpacing.sm),
            const Text(
              'Toutes les informations et preuves sont sauvegardées sur cet '
              "appareil, sans connexion requise. Vous pouvez fermer l'application "
              'en toute sécurité : le dossier sera intact à la réouverture.',
              style: RfTypography.body,
            ),
            const SizedBox(height: RfSpacing.xl),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => context.pushIncidentDetail(incidentId),
                child: const Text('Voir le dossier'),
              ),
            ),
            const SizedBox(height: RfSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => context.go(AppRoutes.home),
                child: const Text("Retour à l'accueil"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
