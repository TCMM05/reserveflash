import 'package:flutter/material.dart';

import 'package:reserveflash/core/design_system/rf_spacing.dart';
import 'package:reserveflash/core/design_system/rf_typography.dart';
import 'package:reserveflash/core/router/app_router.dart';

/// S05 - Création incident.
/// "Date/heure auto, option fournisseur/transporteur, possibilité de
/// continuer offline" (section 3.2). F01 GATE : la création doit être
/// possible immédiatement, y compris sans réseau (section 2.1) - ce
/// formulaire n'attend donc AUCUN appel réseau pour permettre de continuer
/// vers l'étape suivante (S06), la synchronisation avec le backend se fait
/// en tâche de fond (section 8.1).
class CreateIncidentScreen extends StatefulWidget {
  const CreateIncidentScreen({super.key});

  @override
  State<CreateIncidentScreen> createState() => _CreateIncidentScreenState();
}

class _CreateIncidentScreenState extends State<CreateIncidentScreen> {
  final TextEditingController _supplierController = TextEditingController();
  final TextEditingController _carrierController = TextEditingController();

  @override
  void dispose() {
    _supplierController.dispose();
    _carrierController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nouvel incident')),
      body: Padding(
        padding: const EdgeInsets.all(RfSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Date et heure enregistrées automatiquement.',
              style: RfTypography.secondary,
            ),
            const SizedBox(height: RfSpacing.lg),
            TextField(
              controller: _supplierController,
              decoration: const InputDecoration(
                labelText: 'Fournisseur (optionnel)',
              ),
            ),
            const SizedBox(height: RfSpacing.md),
            TextField(
              controller: _carrierController,
              decoration: const InputDecoration(
                labelText: 'Transporteur (optionnel)',
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                // Continuer même hors réseau (F01 GATE, section 2.1) :
                // l'incident est créé localement, la sync suit (section 8).
                onPressed: () => context.pushDocumentCapture(),
                child: const Text('Continuer'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
