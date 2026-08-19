import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:reserveflash/core/design_system/rf_colors.dart';
import 'package:reserveflash/core/design_system/rf_spacing.dart';
import 'package:reserveflash/core/design_system/rf_typography.dart';
import 'package:reserveflash/core/providers/app_providers.dart';
import 'package:reserveflash/core/router/app_router.dart';
import 'package:reserveflash/domain/entities/evidence_asset.dart' as domain;
import 'package:reserveflash/domain/entities/issue.dart' as domain;
import 'package:reserveflash/features/common/presentation/missing_incident_view.dart';

/// S14 - Checklist dossier. "Vert/orange ; items manquants actionnables"
/// (section 3.2, point 6). En R1 (sans Reserve Composer/faits confirmés
/// dans le parcours, hors périmètre - voir demande corrective), cette
/// checklist porte sur la COMPLÉTUDE DE LA CAPTURE : document de livraison,
/// type(s) de problème, photos preuves.
class ChecklistScreen extends ConsumerWidget {
  const ChecklistScreen({required this.incidentId, super.key});

  final String incidentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (incidentId.isEmpty) {
      return const MissingIncidentView();
    }
    final AsyncValue<List<domain.Issue>> issuesAsync = ref.watch(incidentIssuesProvider(incidentId));
    final AsyncValue<List<domain.EvidenceAsset>> evidenceAsync =
        ref.watch(incidentEvidenceProvider(incidentId));

    return Scaffold(
      appBar: AppBar(title: const Text('Complétude du dossier')),
      body: Padding(
        padding: const EdgeInsets.all(RfSpacing.lg),
        child: issuesAsync.when(
          data: (List<domain.Issue> issues) {
            return evidenceAsync.when(
              data: (List<domain.EvidenceAsset> assets) {
                final bool hasDocument = assets
                    .any((domain.EvidenceAsset a) => a.documentType == domain.EvidenceDocumentType.deliveryNote);
                final int photoCount = assets
                    .where((domain.EvidenceAsset a) => a.documentType == domain.EvidenceDocumentType.photo)
                    .length;
                final bool hasIssues = issues.isNotEmpty;
                final bool hasEnoughPhotos = photoCount >= 3;
                final bool canFinish = hasDocument && hasIssues && hasEnoughPhotos;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _ChecklistItem(
                      ok: hasDocument,
                      label: 'Photo du bon de livraison',
                      actionLabel: 'Compléter',
                      onAction: () => context.pushDocumentCapture(incidentId),
                    ),
                    _ChecklistItem(
                      ok: hasIssues,
                      label: 'Type(s) de problème (${issues.length})',
                      actionLabel: 'Compléter',
                      onAction: () => context.pushIssueType(incidentId),
                    ),
                    _ChecklistItem(
                      ok: hasEnoughPhotos,
                      label: 'Photos des preuves ($photoCount/3 minimum)',
                      actionLabel: 'Compléter',
                      onAction: () => context.pushEvidenceCapture(incidentId),
                    ),
                    _ChecklistItem(
                      ok: true,
                      optional: true,
                      label: 'Description texte/audio (optionnel)',
                      actionLabel: 'Modifier',
                      onAction: () => context.pushVoiceDescription(incidentId),
                    ),
                    const Spacer(),
                    if (!canFinish)
                      const Padding(
                        padding: EdgeInsets.only(bottom: RfSpacing.sm),
                        child: Text(
                          'Complétez les éléments en orange avant de terminer le dossier.',
                          style: RfTypography.secondary,
                        ),
                      ),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: canFinish ? () => context.pushDossierComplete(incidentId) : null,
                        child: const Text('Terminer le dossier'),
                      ),
                    ),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (Object e, StackTrace stackTrace) => Center(child: Text('Erreur de lecture locale : $e')),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object e, StackTrace stackTrace) => Center(child: Text('Erreur de lecture locale : $e')),
        ),
      ),
    );
  }
}

class _ChecklistItem extends StatelessWidget {
  const _ChecklistItem({
    required this.ok,
    required this.label,
    required this.actionLabel,
    required this.onAction,
    this.optional = false,
  });

  final bool ok;
  final bool optional;
  final String label;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final Color indicatorColor = ok ? RfColors.success : (optional ? RfColors.muted : RfColors.signal);
    return Card(
      margin: const EdgeInsets.only(bottom: RfSpacing.sm),
      child: ListTile(
        leading: Icon(
          ok ? Icons.check_circle : Icons.error_outline,
          color: indicatorColor,
        ),
        title: Text(label),
        trailing: TextButton(onPressed: onAction, child: Text(actionLabel)),
      ),
    );
  }
}
