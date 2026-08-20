import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:reserveflash/core/design_system/rf_spacing.dart';
import 'package:reserveflash/core/design_system/rf_typography.dart';
import 'package:reserveflash/core/providers/app_providers.dart';
import 'package:reserveflash/core/router/app_router.dart';
import 'package:reserveflash/data/ai_queue_processor.dart';
import 'package:reserveflash/domain/entities/ai_queue_item.dart';
import 'package:reserveflash/domain/entities/evidence_asset.dart' as domain;
import 'package:reserveflash/domain/entities/issue.dart' as domain;
import 'package:reserveflash/domain/value_objects/issue_type.dart';
import 'package:reserveflash/features/common/presentation/missing_incident_view.dart';

/// S08 - Type de problème. "Cartes simples multi-sélectionnables"
/// (section 3.2) - une carte par [IssueType] (point 3), sélection multiple
/// pour gérer les incidents multiples (section 2.5) : "plusieurs problèmes
/// associables au même incident si l'architecture le permet proprement" -
/// c'est le cas ici, `LocalIssues` est une table à part (voir
/// app_database.dart), pas un champ unique de l'incident.
///
/// R2 (lot OCR, correctif) : c'est ICI, et non dans
/// `document_capture_screen.dart`, que l'extraction OCR+IA du bon de
/// livraison est mise en file au mieux-effort (voir
/// `_enqueueOcrExtractionBestEffort` ci-dessous). Dans le parcours nominal
/// (S06 documentCapture -> S08 issueType -> ...), AUCUNE `Issue` n'existe
/// encore au moment de la capture du document (`Issue` n'est créée qu'ici,
/// à la confirmation du type de problème) - une tentative de mise en file
/// depuis S06 y était donc systématiquement un no-op silencieux dans le
/// parcours normal (l'IA ne trouvait jamais de "Non détecté" pour cause
/// d'erreur, mais parce que l'opération n'avait tout simplement jamais été
/// créée). `enqueueAiOperation` est idempotent par clé (voir
/// `local_incident_repository.dart`), donc l'appel best-effort laissé dans
/// `document_capture_screen.dart` (utile pour "Reprendre la photo" sur un
/// incident qui a déjà une anomalie) reste inoffensif et ne crée jamais de
/// doublon avec celui-ci.
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
      String? firstIssueId = existing.isNotEmpty ? existing.first.id : null;
      for (final IssueType type in _selected) {
        if (!alreadyPersisted.contains(type)) {
          final domain.Issue created =
              await ref.read(incidentRepositoryProvider).addIssue(widget.incidentId, type);
          firstIssueId ??= created.id;
        }
      }
      notifyDataChanged(ref);
      if (firstIssueId != null) {
        // Best-effort explicite (voir docstring de fichier) : jamais
        // d'erreur affichée ici pour cette étape optionnelle - seule la
        // persistance du/des type(s) de problème ci-dessus est requise pour
        // continuer.
        await _enqueueOcrExtractionBestEffort(firstIssueId);
      }
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

  /// R2 (lot OCR, correctif) : voir docstring de fichier. Cherche la photo
  /// du bon de livraison (capturée à S06, éventuellement absente si
  /// l'utilisateur a atteint cet écran par un autre chemin) et met en file
  /// son extraction OCR+IA, rattachée à la première anomalie disponible
  /// ([firstIssueId] - existante ou tout juste créée ci-dessus).
  Future<void> _enqueueOcrExtractionBestEffort(String firstIssueId) async {
    try {
      final List<domain.EvidenceAsset> assets =
          await ref.read(incidentRepositoryProvider).listEvidenceAssets(widget.incidentId);
      domain.EvidenceAsset? deliveryDoc;
      for (final domain.EvidenceAsset a in assets) {
        if (a.documentType == domain.EvidenceDocumentType.deliveryNote) {
          deliveryDoc = a;
          break;
        }
      }
      if (deliveryDoc == null) {
        return;
      }
      final ExtractFromDocumentPayload payload =
          ExtractFromDocumentPayload(evidenceAssetId: deliveryDoc.id);
      // sourceHash = SHA-256 déjà calculé à la capture (evidence_storage.dart)
      // - même principe que la note vocale (voir
      // voice_description_screen.dart::_enqueueTranscriptionBestEffort).
      final String sourceHash = deliveryDoc.sha256 ?? deliveryDoc.id;
      await ref.read(incidentRepositoryProvider).enqueueAiOperation(
            incidentId: widget.incidentId,
            issueId: firstIssueId,
            operationKind: AiOperationKind.extractFromDocument,
            payloadJson: payload.encode(),
            idempotencyKey: aiOperationIdempotencyKey(
              incidentId: widget.incidentId,
              operationKind: AiOperationKind.extractFromDocument,
              sourceHash: sourceHash,
            ),
          );
      // Déclenchement "online" au mieux-effort - si l'OCR/extraction échoue
      // maintenant (réseau, quota IA...), l'item reste `pending` en base et
      // sera retenté par un prochain appel à ce même processeur (ex : écran
      // de revue des faits) - jamais une perte.
      unawaited(ref.read(aiQueueProcessorProvider).processPendingOperations());
    } catch (_) {
      // Best-effort explicite (voir docstring de fichier) : aucune erreur
      // affichée à l'utilisateur pour cette étape optionnelle.
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
