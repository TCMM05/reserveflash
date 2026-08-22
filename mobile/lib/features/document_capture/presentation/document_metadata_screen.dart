import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:reserveflash/core/design_system/rf_spacing.dart';
import 'package:reserveflash/core/design_system/rf_typography.dart';
import 'package:reserveflash/core/providers/app_providers.dart';
import 'package:reserveflash/core/router/app_router.dart';
import 'package:reserveflash/domain/entities/incident.dart' as domain;
import 'package:reserveflash/features/common/presentation/missing_incident_view.dart';

/// S07 - Métadonnées du bon de livraison. "Champs éditables" (section 3.2).
///
/// R2 (câblage) : jusqu'ici cet écran était un `RfScreenStub` jamais atteint
/// par aucune navigation (`AppNavigation.pushDocumentMetadata` existait mais
/// n'était appelé nulle part) - le parcours nominal sautait directement de
/// S06 (photo BL) à S08 (type de problème). Câblé désormais entre les deux :
/// `document_capture_screen.dart` (S06) pousse ici après la photo, ce écran
/// pousse vers S08 (`issue_type_screen.dart`) à la validation.
///
/// Champs couverts : fournisseur/transporteur/référence BL/date du BL
/// (voir `docs/GATE_R2_STATUS.md`, section "Décisions de périmètre", point
/// 4) - PAS les champs V1 prioritaires de l'anomalie (`product_label`,
/// `expected_quantity`, ...), qui restent exclusivement dans le flux
/// `CandidateFactSet`/`facts_review_screen.dart` (S11), rattaché à une
/// anomalie (`Issue`), jamais à l'incident lui-même. `supplierName`/
/// `carrierName`/`deliveryRef` existent déjà depuis R1 comme champs
/// optionnels de `Incident`, saisissables dès la création du dossier (S05,
/// `create_incident_screen.dart`, avant même la photo du BL) ou corrigés
/// plus tard (S17, `incident_detail_screen.dart`) - cet écran n'introduit
/// donc PAS de nouveau champ de données pour ces trois-là, seulement le bon
/// MOMENT dans le parcours pour les vérifier/corriger, une fois le vrai BL
/// en main. Seul `deliveryDate` (date figurant sur le BL lui-même, distincte
/// de la date/heure de l'incident) est nouveau (voir
/// `lib/data/local/app_database.dart`, migration v2 -> v3).
///
/// **Décision de périmètre explicite (transparence)** : contrairement à
/// `facts_review_screen.dart` (S11), cet écran n'affiche AUCUNE valeur
/// "compris par l'IA" - la décision 4 de `docs/GATE_R2_STATUS.md` exclut
/// délibérément ces champs du pipeline `CandidateFactData`/OCR IA (schéma
/// `candidate_fact_set.v1` inchangé). Purement une saisie/correction
/// manuelle, au même titre que S05/S17. Une extraction OCR automatique de
/// ces champs depuis la photo du BL serait une extension de périmètre
/// distincte (nouveau schéma, nouveau prompt IA côté backend, implications
/// coût/benchmark) - non demandée pour ce lot, à confirmer explicitement
/// avec l'équipe avant de l'entreprendre.
class DocumentMetadataScreen extends ConsumerStatefulWidget {
  const DocumentMetadataScreen({required this.incidentId, super.key});

  final String incidentId;

  @override
  ConsumerState<DocumentMetadataScreen> createState() => _DocumentMetadataScreenState();
}

class _DocumentMetadataScreenState extends ConsumerState<DocumentMetadataScreen> {
  final TextEditingController _supplierController = TextEditingController();
  final TextEditingController _carrierController = TextEditingController();
  final TextEditingController _deliveryRefController = TextEditingController();

  // Voir `_IssueFactsSectionState._initialized`
  // (facts_review_screen.dart) - même principe : les `TextEditingController`
  // ne doivent être remplis qu'UNE FOIS depuis les données chargées de
  // manière asynchrone (`incidentDetailProvider`), jamais à chaque
  // reconstruction (qui écraserait la saisie en cours de l'utilisateur).
  bool _initialized = false;
  DateTime? _deliveryDate;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _supplierController.dispose();
    _carrierController.dispose();
    _deliveryRefController.dispose();
    super.dispose();
  }

  String? _nullIfEmpty(String value) {
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _pickDeliveryDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _deliveryDate ?? now,
      firstDate: DateTime(now.year - 5),
      // Un BL peut techniquement être daté du jour même (livraison en cours
      // de traitement) - jamais dans le futur au-delà d'aujourd'hui.
      lastDate: now,
    );
    if (picked != null) {
      setState(() => _deliveryDate = picked);
    }
  }

  Future<void> _continue(domain.Incident incident) async {
    if (_isSaving) {
      return;
    }
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      await ref.read(incidentRepositoryProvider).updateIncidentMetadata(
            incidentId: incident.id,
            // Ce champ n'est pas édité ici (voir docstring de fichier) -
            // conservé tel quel, jamais réinitialisé silencieusement.
            occurredAt: incident.occurredAt,
            supplierName: _nullIfEmpty(_supplierController.text),
            carrierName: _nullIfEmpty(_carrierController.text),
            deliveryRef: _nullIfEmpty(_deliveryRefController.text),
            deliveryDate: _deliveryDate,
            notes: incident.notes,
          );
      notifyDataChanged(ref);
      if (!mounted) {
        return;
      }
      context.pushIssueType(widget.incidentId);
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Impossible d\'enregistrer les informations : $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.incidentId.isEmpty) {
      return const MissingIncidentView();
    }
    final AsyncValue<domain.Incident?> incidentAsync =
        ref.watch(incidentDetailProvider(widget.incidentId));

    return incidentAsync.when(
      data: (domain.Incident? incident) {
        if (incident == null) {
          return const MissingIncidentView(title: 'Dossier introuvable');
        }
        if (!_initialized) {
          _supplierController.text = incident.supplierName ?? '';
          _carrierController.text = incident.carrierName ?? '';
          _deliveryRefController.text = incident.deliveryRef ?? '';
          _deliveryDate = incident.deliveryDate;
          _initialized = true;
        }
        return Scaffold(
          appBar: AppBar(title: const Text('Vérifier les informations')),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(RfSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Vérifiez ou complétez ces informations à partir du bon de '
                  'livraison que vous venez de photographier. Tous les champs '
                  'sont optionnels.',
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
                  decoration: const InputDecoration(
                    labelText: 'Référence bon de livraison (optionnel)',
                  ),
                ),
                const SizedBox(height: RfSpacing.md),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        _deliveryDate == null
                            ? 'Date du bon de livraison : non renseignée'
                            : 'Date du bon de livraison : '
                                '${DateFormat('dd/MM/yyyy').format(_deliveryDate!.toLocal())}',
                        style: RfTypography.body,
                      ),
                    ),
                    TextButton(
                      onPressed: _isSaving ? null : _pickDeliveryDate,
                      child: const Text('Choisir'),
                    ),
                    if (_deliveryDate != null)
                      TextButton(
                        onPressed: _isSaving ? null : () => setState(() => _deliveryDate = null),
                        child: const Text('Effacer'),
                      ),
                  ],
                ),
                if (_errorMessage != null) ...<Widget>[
                  const SizedBox(height: RfSpacing.md),
                  Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: RfSpacing.xl),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : () => _continue(incident),
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
      },
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (Object e, StackTrace stackTrace) =>
          Scaffold(body: Center(child: Text('Erreur de lecture locale : $e'))),
    );
  }
}
