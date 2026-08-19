import 'package:flutter/material.dart';

import 'package:reserveflash/core/design_system/rf_spacing.dart';
import 'package:reserveflash/core/design_system/rf_typography.dart';

/// État d'erreur contrôlé partagé par tous les écrans du parcours de
/// capture R1 (S06-S15) : affiché si `incidentId` est vide/absent (`extra`
/// non transmis) ou si l'incident n'existe plus en base au moment de la
/// lecture. R1-T07 : jamais un crash/écran blanc, toujours une UI
/// explicite avec un chemin de sortie.
class MissingIncidentView extends StatelessWidget {
  const MissingIncidentView({super.key, this.title = 'Dossier introuvable'});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Padding(
        padding: const EdgeInsets.all(RfSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              "Ce dossier n'a pas pu être retrouvé sur cet appareil. Vos autres "
              'dossiers ne sont pas affectés.',
              style: RfTypography.body,
            ),
            const SizedBox(height: RfSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  }
                },
                child: const Text('Retour'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
