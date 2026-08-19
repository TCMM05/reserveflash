import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:reserveflash/core/design_system/rf_spacing.dart';
import 'package:reserveflash/core/design_system/rf_typography.dart';
import 'package:reserveflash/core/providers/app_providers.dart';
import 'package:reserveflash/core/router/app_router.dart';
import 'package:reserveflash/domain/entities/incident.dart' as domain;
import 'package:reserveflash/domain/repositories/incident_repository.dart';

/// S05 - Création incident.
/// "Date/heure auto, option fournisseur/transporteur, possibilité de
/// continuer offline" (section 3.2). R1 point 1 : cet écran n'utilise plus
/// AUCUNE donnée fictive - la validation ("Continuer") crée réellement
/// l'incident dans Drift/SQLite (enregistrement immédiat, avant même toute
/// capture photo) via `IncidentRepository.createIncident`, sans jamais
/// attendre ni déclencher d'appel réseau (points 1/8/10 - R1-T01/T10).
class CreateIncidentScreen extends ConsumerStatefulWidget {
  const CreateIncidentScreen({super.key});

  @override
  ConsumerState<CreateIncidentScreen> createState() => _CreateIncidentScreenState();
}

class _CreateIncidentScreenState extends ConsumerState<CreateIncidentScreen> {
  final TextEditingController _supplierController = TextEditingController();
  final TextEditingController _carrierController = TextEditingController();
  final TextEditingController _deliveryRefController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  bool _isSaving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _supplierController.dispose();
    _carrierController.dispose();
    _deliveryRefController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String? _nullIfEmpty(String value) {
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _createAndContinue() async {
    if (_isSaving) {
      return;
    }
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      final IncidentRepository repository = ref.read(incidentRepositoryProvider);
      // Point 1 : "date/heure" enregistrée automatiquement, aucun champ
      // fictif - `occurredAt` est l'instant réel de création du dossier.
      // Point 1/8/10 : aucun appel réseau ici, l'incident existe déjà en
      // local avant même que S06 (photo BL) ne s'ouvre (R1-T01).
      final domain.Incident created = await repository.createIncident(
        occurredAt: DateTime.now().toUtc(),
        supplierName: _nullIfEmpty(_supplierController.text),
        carrierName: _nullIfEmpty(_carrierController.text),
        deliveryRef: _nullIfEmpty(_deliveryRefController.text),
        notes: _nullIfEmpty(_notesController.text),
      );
      notifyDataChanged(ref);
      if (!mounted) {
        return;
      }
      context.pushDocumentCapture(created.id);
    } catch (e) {
      // R1-T05/T07 : une écriture locale qui échoue (disque plein, erreur
      // SQLite...) doit rester une erreur contrôlée, jamais un crash - voir
      // aussi AppRoutes.error, déjà prévu pour ce type de message.
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = "Impossible d'enregistrer l'incident localement : $e";
      });
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nouvel incident')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(RfSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Date et heure enregistrées automatiquement. Fonctionne entièrement '
              'hors connexion.',
              style: RfTypography.secondary,
            ),
            const SizedBox(height: RfSpacing.lg),
            TextField(
              controller: _supplierController,
              enabled: !_isSaving,
              decoration: const InputDecoration(labelText: 'Fournisseur (optionnel)'),
            ),
            const SizedBox(height: RfSpacing.md),
            TextField(
              controller: _carrierController,
              enabled: !_isSaving,
              decoration: const InputDecoration(labelText: 'Transporteur (optionnel)'),
            ),
            const SizedBox(height: RfSpacing.md),
            TextField(
              controller: _deliveryRefController,
              enabled: !_isSaving,
              decoration: const InputDecoration(labelText: 'Référence bon de livraison (optionnel)'),
            ),
            const SizedBox(height: RfSpacing.md),
            TextField(
              controller: _notesController,
              enabled: !_isSaving,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Commentaire (optionnel)'),
            ),
            if (_errorMessage != null) ...<Widget>[
              const SizedBox(height: RfSpacing.md),
              Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: RfSpacing.xl),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                // Continuer même hors réseau (F01 GATE, section 2.1) :
                // l'incident est créé localement, la sync (hors scope R1)
                // suivra plus tard le cas échéant.
                onPressed: _isSaving ? null : _createAndContinue,
                child: _isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Continuer'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
