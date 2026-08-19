import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:reserveflash/core/design_system/rf_spacing.dart';
import 'package:reserveflash/core/design_system/rf_typography.dart';
import 'package:reserveflash/core/providers/app_providers.dart';
import 'package:reserveflash/core/router/app_router.dart';
import 'package:reserveflash/domain/entities/issue.dart' as domain;
import 'package:reserveflash/domain/value_objects/issue_type.dart';
import 'package:reserveflash/features/common/presentation/missing_incident_view.dart';

/// S08 - Type de problème. "Cartes simples multi-sélectionnables"
/// (section 3.2) - une carte par [IssueType] (point 3), sélection multiple
/// pour gérer les incidents multiples (section 2.5) : "plusieurs problèmes
/// associables au même incident si l'architecture le permet proprement" -
/// c'est le cas ici, `LocalIssues` est une table à part (voir
/// app_database.dart), pas un champ unique de l'incident.
class IssueTypeScreen extends ConsumerStatefulWidget {
  const IssueTypeScreen({required this.incidentId, super.key});

  final String incidentId;

  @override
  ConsumerState<IssueTypeScreen> createState() => _IssueTypeScreenState();
}

const Map<IssueType, String> _issueTypeLabels = <IssueType, String>{
  IssueType.packagingDamage: 'Emballage endommagé',
  IssueType.productDamage: 'Produit endommagé',
  IssueType.missingQty: 'Quantité manquante',
  IssueType.wrongQty: 'Mauvaise quantité',
  IssueType.wrongProduct: 'Mauvais produit',
  IssueType.visibleNonconformity: 'Non-conformité visible',
  IssueType.other: 'Autre',
};

class _IssueTypeScreenState extends ConsumerState<IssueTypeScreen> {
  final Set<IssueType> _selected = <IssueType>{};
  bool _initializedFromExisting = false;
  bool _isSaving = false;
  String? _errorMessage;

  Future<void> _continue() async {
    if (_isSaving || _selected.isEmpty) {
      return;
    }
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      final List<domain.Issue> existing =
          await ref.read(incidentRepositoryProvider).listIssues(widget.incidentId);
      final Set<IssueType> alreadyPersisted =
          existing.map((domain.Issue issue) => issue.issueType).toSet();
      for (final IssueType type in _selected) {
        if (!alreadyPersisted.contains(type)) {
          await ref.read(incidentRepositoryProvider).addIssue(widget.incidentId, type);
        }
      }
      notifyDataChanged(ref);
      if (!mounted) {
        return;
      }
      context.pushEvidenceCapture(widget.incidentId);
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = "Impossible d'enregistrer le(s) type(s) de problème : $e");
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
    final AsyncValue<List<domain.Issue>> issuesAsync =
        ref.watch(incidentIssuesProvider(widget.incidentId));

    return Scaffold(
      appBar: AppBar(title: const Text('Quel est le problème ?')),
      body: Padding(
        padding: const EdgeInsets.all(RfSpacing.lg),
        child: issuesAsync.when(
          data: (List<domain.Issue> issues) {
            if (!_initializedFromExisting) {
              _selected.addAll(issues.map((domain.Issue i) => i.issueType));
              _initializedFromExisting = true;
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Sélectionnez un ou plusieurs problèmes constatés.',
                  style: RfTypography.secondary,
                ),
                const SizedBox(height: RfSpacing.lg),
                Expanded(
                  child: ListView(
                    children: IssueType.values.map((IssueType type) {
                      final bool isSelected = _selected.contains(type);
                      return Card(
                        margin: const EdgeInsets.only(bottom: RfSpacing.sm),
                        child: CheckboxListTile(
                          value: isSelected,
                          title: Text(_issueTypeLabels[type] ?? type.wireValue),
                          onChanged: _isSaving
                              ? null
                              : (bool? checked) {
                                  setState(() {
                                    if (checked ?? false) {
                                      _selected.add(type);
                                    } else {
                                      _selected.remove(type);
                                    }
                                  });
                                },
                        ),
                      );
                    }).toList(),
                  ),
                ),
                if (_errorMessage != null) ...<Widget>[
                  Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: RfSpacing.sm),
                ],
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _selected.isEmpty || _isSaving ? null : _continue,
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
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object e, StackTrace stackTrace) => Center(child: Text('Erreur de lecture locale : $e')),
        ),
      ),
    );
  }
}
