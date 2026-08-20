import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:reserveflash/core/design_system/rf_colors.dart';
import 'package:reserveflash/core/design_system/rf_spacing.dart';
import 'package:reserveflash/core/design_system/rf_typography.dart';
import 'package:reserveflash/core/providers/app_providers.dart';
import 'package:reserveflash/core/router/app_router.dart';
import 'package:reserveflash/data/ai_queue_processor.dart';
import 'package:reserveflash/domain/entities/ai_queue_item.dart';
import 'package:reserveflash/domain/entities/candidate_fact_set.dart' as domain;
import 'package:reserveflash/domain/entities/confirmed_fact_set.dart' as domain;
import 'package:reserveflash/domain/entities/issue.dart' as domain;
import 'package:reserveflash/domain/errors/domain_errors.dart';
import 'package:reserveflash/domain/fact_set/candidate_fact_data.dart';
import 'package:reserveflash/domain/fact_set/confirmed_fact_data.dart';
import 'package:reserveflash/domain/repositories/incident_repository.dart' show NoConfirmedFactsException;
import 'package:reserveflash/domain/value_objects/issue_type.dart';
import 'package:reserveflash/features/common/presentation/missing_incident_view.dart';
import 'package:reserveflash/features/facts_review/presentation/fact_review_field.dart';

/// S11 - Revue des faits (F09, GATE).
///
/// "Le bouton 'Confirmer' doit être désactivé tant que les champs critiques
/// requis pour le type d'incident ne sont pas résolus ou explicitement
/// marqués UNKNOWN." (section 2.3)
///
/// Câblage réel R2 (avant ce câblage : écran à champs codés en dur, jamais
/// branché sur `IncidentRepository` - voir docs/GATE_R2_STATUS.md, "Reste
/// à faire"). Une anomalie (`Issue`) à la fois par section : chaque
/// `CandidateFactSet` est rattaché à une anomalie, jamais à l'incident
/// entier (voir `lib/data/ai_queue_processor.dart`). Fonctionne
/// intégralement SANS extraction IA préalable (tous les champs démarrent
/// alors "non détecté", modifiables/marquables UNKNOWN comme n'importe quel
/// champ candidat) - c'est la vraie bascule "saisie manuelle/UNKNOWN"
/// exigée par le retour d'équipe (exigence coût IA, point 7), pas
/// uniquement un cas particulier après épuisement du disjoncteur de retry.
///
/// V1 (limite documentée) : TOUS les champs V1 prioritaires (liste
/// [_v1PriorityFields], alignée sur `schemas/candidate_fact_set.v1.schema.json`)
/// doivent être résolus avant de pouvoir confirmer une anomalie - pas de
/// distinction fine "champ critique pour CE type d'anomalie" vs "champ
/// secondaire" (raffinement possible non nécessaire pour ce premier
/// câblage bout en bout, comme le disjoncteur de retry de
/// `ai_queue_processor.dart`).
class FactsReviewScreen extends ConsumerWidget {
  const FactsReviewScreen({required this.incidentId, super.key});

  final String incidentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (incidentId.isEmpty) {
      return const MissingIncidentView();
    }
    final AsyncValue<List<domain.Issue>> issuesAsync =
        ref.watch(incidentIssuesProvider(incidentId));
    final AsyncValue<List<domain.ConfirmedFactSet>> confirmedAsync =
        ref.watch(incidentConfirmedFactSetsProvider(incidentId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vérifiez les faits'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Relancer le traitement IA en attente pour ce dossier",
            onPressed: () async {
              await ref.read(aiQueueProcessorProvider).processPendingOperations();
              notifyDataChanged(ref);
            },
          ),
        ],
      ),
      body: issuesAsync.when(
        data: (List<domain.Issue> issues) {
          if (issues.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(RfSpacing.lg),
                child: Text(
                  "Aucune anomalie déclarée pour ce dossier - revenez à l'étape "
                  '"Type de problème" avant de revoir des faits.',
                  style: RfTypography.secondary,
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(RfSpacing.lg),
            itemCount: issues.length,
            separatorBuilder: (_, __) => const SizedBox(height: RfSpacing.md),
            itemBuilder: (BuildContext context, int index) {
              final domain.Issue issue = issues[index];
              return _IssueFactsSection(
                key: ValueKey<String>(issue.id),
                incidentId: incidentId,
                issue: issue,
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, StackTrace stackTrace) => Center(child: Text('Erreur de lecture locale : $e')),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(RfSpacing.lg),
          child: confirmedAsync.maybeWhen(
            data: (List<domain.ConfirmedFactSet> confirmed) => _GenerateReserveButton(
              incidentId: incidentId,
              hasConfirmed: confirmed.isNotEmpty,
            ),
            orElse: () => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

/// Libellés FR des types d'anomalie - même contenu que la copie déjà
/// utilisée par `issue_type_screen.dart`/`incident_detail_screen.dart` (pas
/// de constante partagée à ce jour dans le projet, voir ces fichiers).
const Map<IssueType, String> _issueTypeLabels = <IssueType, String>{
  IssueType.packagingDamage: 'Emballage endommagé',
  IssueType.productDamage: 'Produit endommagé',
  IssueType.missingQty: 'Quantité manquante',
  IssueType.wrongQty: 'Mauvaise quantité',
  IssueType.wrongProduct: 'Mauvais produit',
  IssueType.visibleNonconformity: 'Non-conformité visible',
  IssueType.other: 'Autre',
};

class _FieldSpec {
  const _FieldSpec(this.key, this.label, {this.isQuantity = false});
  final String key;
  final String label;
  final bool isQuantity;
}

/// Champs V1 prioritaires (section "champs V1 prioritaires" de la demande
/// R2) - alignés EXACTEMENT sur `ConfirmedFactData`/
/// `schemas/candidate_fact_set.v1.schema.json` (clés snake_case).
/// `issueTypeCandidate` n'en fait pas partie : le type d'anomalie reste
/// celui choisi à l'étape S08 (`IssueTypeScreen`), jamais silencieusement
/// remplacé par la suggestion IA - voir affichage informatif dédié dans
/// `_IssueFactsSection`.
const List<_FieldSpec> _v1PriorityFields = <_FieldSpec>[
  _FieldSpec('product_label', 'Produit'),
  _FieldSpec('product_reference', 'Référence produit'),
  _FieldSpec('expected_quantity', 'Quantité attendue', isQuantity: true),
  _FieldSpec('received_quantity', 'Quantité reçue', isQuantity: true),
  _FieldSpec('affected_quantity', 'Quantité concernée', isQuantity: true),
  _FieldSpec('packaging_condition', "État de l'emballage"),
  _FieldSpec('product_condition', 'État du produit'),
  _FieldSpec('location_on_item', 'Localisation sur le produit'),
];

bool _isQuantityField(String fieldKey) {
  return _v1PriorityFields.firstWhere((_FieldSpec s) => s.key == fieldKey).isQuantity;
}

String? _stringifyCandidateValue(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is double) {
    return _formatQuantity(value);
  }
  return value.toString();
}

String _formatQuantity(double value) {
  // Évite "8.0" pour une quantité entière - affichage plus naturel côté
  // revue utilisateur (même arrondi d'affichage que
  // `ConfirmedFactData.missingQuantity`, sans en dépendre ici).
  if (value == value.roundToDouble()) {
    return value.toInt().toString();
  }
  return value.toString();
}

String? _confirmedFieldValue(ConfirmedFactData data, String fieldKey) {
  final Object? raw = switch (fieldKey) {
    'product_label' => data.productLabel,
    'product_reference' => data.productReference,
    'expected_quantity' => data.expectedQuantity,
    'received_quantity' => data.receivedQuantity,
    'affected_quantity' => data.affectedQuantity,
    'packaging_condition' => data.packagingCondition,
    'product_condition' => data.productCondition,
    'location_on_item' => data.locationOnItem,
    _ => null,
  };
  return _stringifyCandidateValue(raw);
}

/// Construit l'état initial des champs affichés pour une anomalie, à partir
/// de la dernière extraction candidate (`candidateSet`, peut être `null` -
/// voir docstring de fichier) et de la dernière confirmation existante
/// (`confirmedSet`, peut être `null` si jamais confirmée). N'est appelé
/// qu'UNE FOIS par section (voir `_initialized` dans `_IssueFactsSectionState`)
/// : les corrections de l'utilisateur ensuite vivent uniquement en mémoire
/// locale jusqu'à confirmation explicite.
List<FactReviewField> _buildFields(
  domain.CandidateFactSet? candidateSet,
  domain.ConfirmedFactSet? confirmedSet,
) {
  final CandidateFactData? candidate = candidateSet?.candidateData;
  final ConfirmedFactData? confirmed = confirmedSet?.confirmedData;
  return _v1PriorityFields.map((_FieldSpec spec) {
    final CandidateField? candidateField = candidate?.fields[spec.key];
    final String? candidateValue = _stringifyCandidateValue(candidateField?.value);

    FactFieldReviewState state = FactFieldReviewState.candidate;
    String? currentValue;
    if (confirmed != null) {
      if (confirmed.isFieldUnknown(spec.key)) {
        state = FactFieldReviewState.unknown;
      } else {
        final String? confirmedValue = _confirmedFieldValue(confirmed, spec.key);
        if (confirmedValue != null) {
          currentValue = confirmedValue;
          state = confirmedValue == candidateValue
              ? FactFieldReviewState.confirmed
              : FactFieldReviewState.edited;
        }
      }
    }

    return FactReviewField(
      fieldKey: spec.key,
      label: spec.label,
      candidateValue: candidateValue,
      state: state,
      currentValue: currentValue,
    );
  }).toList();
}

/// Reconstitue un `ConfirmedFactData` à partir des champs affichés au
/// moment où l'utilisateur confirme cette anomalie. Les quantités sont
/// parsées depuis le texte affiché/édité (`double.tryParse`) - une valeur
/// non numérique saisie par erreur redevient silencieusement absente plutôt
/// que de bloquer la confirmation (limite V1 documentée : pas de validation
/// de saisie dédiée par type de champ au-delà du clavier numérique proposé
/// dans la feuille d'édition, voir `_editField`).
ConfirmedFactData _buildConfirmedData(IssueType issueType, List<FactReviewField> fields) {
  FactReviewField fieldFor(String key) =>
      fields.firstWhere((FactReviewField f) => f.fieldKey == key);

  String? strFor(String key) {
    final FactReviewField f = fieldFor(key);
    if (f.state == FactFieldReviewState.unknown) {
      return null;
    }
    final String? value = f.currentValue ?? f.candidateValue;
    return (value == null || value.trim().isEmpty) ? null : value;
  }

  double? numFor(String key) {
    final String? s = strFor(key);
    return s == null ? null : double.tryParse(s.replaceAll(',', '.'));
  }

  final List<String> unknownFields = fields
      .where((FactReviewField f) => f.state == FactFieldReviewState.unknown)
      .map((FactReviewField f) => f.fieldKey)
      .toList();

  return ConfirmedFactData(
    issueType: issueType,
    productLabel: strFor('product_label'),
    productReference: strFor('product_reference'),
    expectedQuantity: numFor('expected_quantity'),
    receivedQuantity: numFor('received_quantity'),
    affectedQuantity: numFor('affected_quantity'),
    packagingCondition: strFor('packaging_condition'),
    productCondition: strFor('product_condition'),
    locationOnItem: strFor('location_on_item'),
    userUncertainty: unknownFields.isNotEmpty,
    unknownFields: unknownFields,
  );
}

class _IssueFactsSection extends ConsumerStatefulWidget {
  const _IssueFactsSection({
    required this.incidentId,
    required this.issue,
    super.key,
  });

  final String incidentId;
  final domain.Issue issue;

  @override
  ConsumerState<_IssueFactsSection> createState() => _IssueFactsSectionState();
}

class _IssueFactsSectionState extends ConsumerState<_IssueFactsSection> {
  List<FactReviewField>? _fields;
  bool _initialized = false;
  bool _isConfirming = false;
  String? _errorMessage;

  bool get _allFieldsResolved =>
      (_fields ?? const <FactReviewField>[]).every((FactReviewField f) => f.isResolved);

  void _confirmField(FactReviewField field) {
    setState(() {
      field
        ..state = FactFieldReviewState.confirmed
        ..currentValue = field.candidateValue;
    });
  }

  void _markUnknown(FactReviewField field) {
    setState(() {
      field
        ..state = FactFieldReviewState.unknown
        ..currentValue = null;
    });
  }

  Future<void> _editField(FactReviewField field) async {
    final TextEditingController controller = TextEditingController(
      text: field.currentValue ?? field.candidateValue ?? '',
    );
    final String? result = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: RfSpacing.lg,
            right: RfSpacing.lg,
            top: RfSpacing.lg,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + RfSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(field.label, style: RfTypography.sectionTitle),
              const SizedBox(height: RfSpacing.sm),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: _isQuantityField(field.fieldKey)
                    ? const TextInputType.numberWithOptions(decimal: true)
                    : TextInputType.text,
              ),
              const SizedBox(height: RfSpacing.md),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(sheetContext).pop(controller.text),
                  child: const Text('Enregistrer la correction'),
                ),
              ),
            ],
          ),
        );
      },
    );
    controller.dispose();
    if (result != null && result.trim().isNotEmpty) {
      setState(() {
        field
          ..state = FactFieldReviewState.edited
          ..currentValue = result.trim();
      });
    }
  }

  Future<void> _confirmIssue() async {
    final List<FactReviewField>? fields = _fields;
    if (fields == null || _isConfirming) {
      return;
    }
    setState(() {
      _isConfirming = true;
      _errorMessage = null;
    });
    try {
      final ConfirmedFactData data = _buildConfirmedData(widget.issue.issueType, fields);
      await ref.read(incidentRepositoryProvider).confirmFacts(
            issueId: widget.issue.id,
            data: data,
          );
      notifyDataChanged(ref);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Faits confirmés pour cette anomalie.')),
        );
      }
    } on LiabilityAttributionException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Formulation à corriger (${e.fieldName}) : ${e.message}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Impossible de confirmer les faits : $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isConfirming = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<domain.CandidateFactSet?> candidateAsync =
        ref.watch(latestCandidateFactSetProvider(widget.issue.id));
    final AsyncValue<domain.ConfirmedFactSet?> confirmedAsync =
        ref.watch(latestConfirmedFactSetProvider(widget.issue.id));
    final AsyncValue<List<AiQueueItem>> pendingAsync = ref.watch(pendingAiOperationsProvider);

    return candidateAsync.when(
      data: (domain.CandidateFactSet? candidateSet) => confirmedAsync.when(
        data: (domain.ConfirmedFactSet? confirmedSet) {
          if (!_initialized) {
            _fields = _buildFields(candidateSet, confirmedSet);
            _initialized = true;
          }
          final List<FactReviewField> fields = _fields!;
          final List<AiQueueItem> pendingForIssue = pendingAsync.maybeWhen(
            data: (List<AiQueueItem> items) =>
                items.where((AiQueueItem i) => i.issueId == widget.issue.id).toList(),
            orElse: () => const <AiQueueItem>[],
          );
          final bool hasInFlight = pendingForIssue
              .any((AiQueueItem i) => i.retryCount < defaultAiQueueMaxRetryCount);
          final bool hasBlocked = pendingForIssue
              .any((AiQueueItem i) => i.retryCount >= defaultAiQueueMaxRetryCount);
          final IssueType? aiSuggestedType = candidateSet?.candidateData.issueTypeCandidate;
          final bool typeMismatch =
              aiSuggestedType != null && aiSuggestedType != widget.issue.issueType;

          return Card(
            child: Padding(
              padding: const EdgeInsets.all(RfSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          _issueTypeLabels[widget.issue.issueType] ?? widget.issue.issueType.wireValue,
                          style: RfTypography.sectionTitle,
                        ),
                      ),
                      if (confirmedSet != null)
                        _Chip(
                          label: 'Confirmé (rév. ${confirmedSet.revision})',
                          color: RfColors.success,
                        ),
                    ],
                  ),
                  if (typeMismatch)
                    Padding(
                      padding: const EdgeInsets.only(top: RfSpacing.xs),
                      child: Text(
                        "L'IA suggère plutôt : "
                        '${_issueTypeLabels[aiSuggestedType] ?? aiSuggestedType.wireValue}. '
                        "Le type retenu reste celui choisi à l'étape précédente.",
                        style: RfTypography.secondary,
                      ),
                    ),
                  if (hasInFlight)
                    Padding(
                      padding: const EdgeInsets.only(top: RfSpacing.sm),
                      child: Text(
                        'Traitement IA en cours pour cette anomalie (transcription/'
                        'extraction) - vous pouvez déjà corriger les champs '
                        'manuellement pendant ce temps.',
                        style: RfTypography.secondary.copyWith(color: RfColors.muted),
                      ),
                    ),
                  if (hasBlocked)
                    Padding(
                      padding: const EdgeInsets.only(top: RfSpacing.sm),
                      child: Text(
                        "L'IA n'a pas pu traiter cette source après plusieurs "
                        'tentatives. Complétez les champs manuellement ci-dessous '
                        "- rien n'est perdu.",
                        style: RfTypography.secondary.copyWith(color: RfColors.signal),
                      ),
                    ),
                  const SizedBox(height: RfSpacing.sm),
                  ...fields.map(
                    (FactReviewField f) => Padding(
                      padding: const EdgeInsets.only(bottom: RfSpacing.xs),
                      child: _FactCard(
                        field: f,
                        onConfirm: () => _confirmField(f),
                        onEdit: () => _editField(f),
                        onMarkUnknown: () => _markUnknown(f),
                      ),
                    ),
                  ),
                  if (_errorMessage != null) ...<Widget>[
                    Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: RfSpacing.xs),
                  ],
                  const SizedBox(height: RfSpacing.xs),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      // GATE section 2.3 : désactivé tant que tout n'est pas résolu.
                      onPressed: (_allFieldsResolved && !_isConfirming) ? _confirmIssue : null,
                      child: _isConfirming
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              confirmedSet == null
                                  ? 'Valider les faits de cette anomalie'
                                  : 'Mettre à jour les faits confirmés',
                            ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
        loading: () => const _SectionLoading(),
        error: (Object e, StackTrace stackTrace) => _SectionError(message: '$e'),
      ),
      loading: () => const _SectionLoading(),
      error: (Object e, StackTrace stackTrace) => _SectionError(message: '$e'),
    );
  }
}

class _SectionLoading extends StatelessWidget {
  const _SectionLoading();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(RfSpacing.md),
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _SectionError extends StatelessWidget {
  const _SectionError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(RfSpacing.md),
        child: Text('Erreur de lecture locale : $message'),
      ),
    );
  }
}

class _GenerateReserveButton extends ConsumerStatefulWidget {
  const _GenerateReserveButton({required this.incidentId, required this.hasConfirmed});

  final String incidentId;
  final bool hasConfirmed;

  @override
  ConsumerState<_GenerateReserveButton> createState() => _GenerateReserveButtonState();
}

class _GenerateReserveButtonState extends ConsumerState<_GenerateReserveButton> {
  bool _isGenerating = false;
  String? _errorMessage;

  Future<void> _generate() async {
    if (_isGenerating) {
      return;
    }
    setState(() {
      _isGenerating = true;
      _errorMessage = null;
    });
    try {
      await ref.read(incidentRepositoryProvider).composeAndSaveReserve(widget.incidentId);
      notifyDataChanged(ref);
      if (mounted) {
        context.pushReserve(widget.incidentId);
      }
    } on NoConfirmedFactsException catch (e) {
      if (mounted) {
        setState(() => _errorMessage = e.message);
      }
    } on LiabilityAttributionException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Formulation à corriger (${e.fieldName}) : ${e.message}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Impossible de générer la réserve : $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (_errorMessage != null) ...<Widget>[
          Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: RfSpacing.sm),
        ],
        if (!widget.hasConfirmed)
          const Padding(
            padding: EdgeInsets.only(bottom: RfSpacing.sm),
            child: Text(
              "Confirmez les faits d'au moins une anomalie avant de générer la réserve.",
              style: RfTypography.secondary,
            ),
          ),
        ElevatedButton(
          onPressed: (!widget.hasConfirmed || _isGenerating) ? null : _generate,
          child: _isGenerating
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Générer la réserve'),
        ),
      ],
    );
  }
}

class _FactCard extends StatelessWidget {
  const _FactCard({
    required this.field,
    required this.onConfirm,
    required this.onEdit,
    required this.onMarkUnknown,
  });

  final FactReviewField field;
  final VoidCallback onConfirm;
  final VoidCallback onEdit;
  final VoidCallback onMarkUnknown;

  @override
  Widget build(BuildContext context) {
    final bool isUnknown = field.state == FactFieldReviewState.unknown;
    final String displayValue = isUnknown
        ? 'Inconnu'
        : (field.currentValue ?? field.candidateValue ?? 'Non détecté');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(RfSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(field.label, style: RfTypography.sectionTitle),
                _StatusBadge(state: field.state),
              ],
            ),
            const SizedBox(height: RfSpacing.xs),
            Row(
              children: <Widget>[
                // Transparence IA (section 3.1) : distinguer "compris par
                // l'IA" de "confirmé par vous".
                if (field.state == FactFieldReviewState.candidate)
                  const Icon(Icons.auto_awesome, size: 16, color: RfColors.muted),
                if (field.state == FactFieldReviewState.candidate)
                  const SizedBox(width: RfSpacing.xs),
                Expanded(child: Text(displayValue, style: RfTypography.body)),
              ],
            ),
            const SizedBox(height: RfSpacing.sm),
            Wrap(
              spacing: RfSpacing.xs,
              children: <Widget>[
                FilledButton(onPressed: onConfirm, child: const Text('Confirmer')),
                OutlinedButton(onPressed: onEdit, child: const Text('Modifier')),
                TextButton(onPressed: onMarkUnknown, child: const Text('Je ne sais pas')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.state});

  final FactFieldReviewState state;

  @override
  Widget build(BuildContext context) {
    final (String label, Color color) = switch (state) {
      FactFieldReviewState.candidate => ('Compris par l\'IA', RfColors.muted),
      FactFieldReviewState.confirmed => ('Confirmé', RfColors.success),
      FactFieldReviewState.edited => ('Corrigé', RfColors.success),
      FactFieldReviewState.unknown => ('Inconnu', RfColors.signal),
    };
    return _Chip(label: label, color: color);
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: RfSpacing.xs, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: RfTypography.secondary.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
