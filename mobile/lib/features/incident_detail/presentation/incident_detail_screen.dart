import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:reserveflash/core/design_system/rf_colors.dart';
import 'package:reserveflash/core/design_system/rf_spacing.dart';
import 'package:reserveflash/core/design_system/rf_typography.dart';
import 'package:reserveflash/core/providers/app_providers.dart';
import 'package:reserveflash/core/router/app_router.dart';
import 'package:reserveflash/core/widgets/rf_confirm_dialog.dart';
import 'package:reserveflash/domain/entities/evidence_asset.dart' as domain;
import 'package:reserveflash/domain/entities/incident.dart' as domain;
import 'package:reserveflash/domain/entities/issue.dart' as domain;
import 'package:reserveflash/domain/value_objects/issue_type.dart';
import 'package:reserveflash/features/common/presentation/evidence_audio_player_screen.dart';
import 'package:reserveflash/features/common/presentation/evidence_photo_viewer_screen.dart';
import 'package:reserveflash/features/common/presentation/evidence_thumbnail_tile.dart';
import 'package:reserveflash/features/common/presentation/missing_incident_view.dart';

const Map<IssueType, String> _issueTypeLabels = <IssueType, String>{
  IssueType.packagingDamage: 'Emballage endommagé',
  IssueType.productDamage: 'Produit endommagé',
  IssueType.missingQty: 'Quantité manquante',
  IssueType.wrongQty: 'Mauvaise quantité',
  IssueType.wrongProduct: 'Mauvais produit',
  IssueType.visibleNonconformity: 'Non-conformité visible',
  IssueType.other: 'Autre',
};

/// S17 - Détail incident. "Timeline, faits confirmés, preuves, exports"
/// (section 3.2) - en R1, sans faits confirmés/export (hors périmètre) :
/// informations saisies, type(s) de problème, photo BL, photos preuves,
/// note texte/audio, date/heure (point 6), avec correction/suppression
/// (point 7) et reprise du parcours si le dossier est incomplet (point 6 -
/// "pouvoir continuer un incident commencé précédemment"). R1-T07 :
/// `incidentEvidenceProvider` appelle `verifyEvidenceAssetsIntegrity`, donc
/// rouvrir ce dossier revérifie l'intégrité disque de chaque preuve à
/// chaque fois.
class IncidentDetailScreen extends ConsumerWidget {
  const IncidentDetailScreen({required this.incidentId, super.key});

  final String incidentId;

  Future<void> _editMetadata(BuildContext context, WidgetRef ref, domain.Incident incident) async {
    final TextEditingController supplierController =
        TextEditingController(text: incident.supplierName ?? '');
    final TextEditingController carrierController =
        TextEditingController(text: incident.carrierName ?? '');
    final TextEditingController deliveryRefController =
        TextEditingController(text: incident.deliveryRef ?? '');
    final TextEditingController notesController = TextEditingController(text: incident.notes ?? '');
    // R2 (S07) - même champ que `document_metadata_screen.dart`, éditable
    // aussi depuis ici (`ValueNotifier` plutôt qu'un `TextEditingController`
    // - pas de saisie libre, uniquement `showDatePicker`, voir ci-dessous).
    final ValueNotifier<DateTime?> deliveryDateNotifier =
        ValueNotifier<DateTime?>(incident.deliveryDate);

    final bool? confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
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
              const Text('Corriger les informations', style: RfTypography.sectionTitle),
              const SizedBox(height: RfSpacing.md),
              TextField(
                controller: supplierController,
                decoration: const InputDecoration(labelText: 'Fournisseur (optionnel)'),
              ),
              const SizedBox(height: RfSpacing.sm),
              TextField(
                controller: carrierController,
                decoration: const InputDecoration(labelText: 'Transporteur (optionnel)'),
              ),
              const SizedBox(height: RfSpacing.sm),
              TextField(
                controller: deliveryRefController,
                decoration: const InputDecoration(labelText: 'Référence BL (optionnel)'),
              ),
              const SizedBox(height: RfSpacing.sm),
              ValueListenableBuilder<DateTime?>(
                valueListenable: deliveryDateNotifier,
                builder: (BuildContext context, DateTime? value, Widget? child) {
                  return Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          value == null
                              ? 'Date du BL : non renseignée'
                              : 'Date du BL : ${DateFormat('dd/MM/yyyy').format(value.toLocal())}',
                          style: RfTypography.body,
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final DateTime now = DateTime.now();
                          final DateTime? picked = await showDatePicker(
                            context: sheetContext,
                            initialDate: value ?? now,
                            firstDate: DateTime(now.year - 5),
                            lastDate: now,
                          );
                          if (picked != null) {
                            deliveryDateNotifier.value = picked;
                          }
                        },
                        child: const Text('Choisir'),
                      ),
                      if (value != null)
                        TextButton(
                          onPressed: () => deliveryDateNotifier.value = null,
                          child: const Text('Effacer'),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: RfSpacing.sm),
              TextField(
                controller: notesController,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Commentaire (optionnel)'),
              ),
              const SizedBox(height: RfSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(sheetContext).pop(true),
                  child: const Text('Enregistrer'),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (confirmed != true) {
      deliveryDateNotifier.dispose();
      return;
    }
    String? nullIfEmpty(String value) {
      final String trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    await ref.read(incidentRepositoryProvider).updateIncidentMetadata(
          incidentId: incident.id,
          occurredAt: incident.occurredAt,
          supplierName: nullIfEmpty(supplierController.text),
          carrierName: nullIfEmpty(carrierController.text),
          deliveryRef: nullIfEmpty(deliveryRefController.text),
          deliveryDate: deliveryDateNotifier.value,
          notes: nullIfEmpty(notesController.text),
        );
    deliveryDateNotifier.dispose();
    notifyDataChanged(ref);
  }

  Future<void> _deleteEvidence(BuildContext context, WidgetRef ref, domain.EvidenceAsset asset) async {
    final bool confirmed = await confirmDestructiveAction(
      context,
      title: 'Supprimer cette preuve ?',
      message: 'Cette action est définitive.',
    );
    if (!confirmed) {
      return;
    }
    await ref.read(evidenceStorageServiceProvider).deleteFile(asset.localFilePath);
    await ref.read(incidentRepositoryProvider).deleteEvidenceAsset(asset.id);
    notifyDataChanged(ref);
  }

  Future<void> _deleteIncident(BuildContext context, WidgetRef ref, String incidentId) async {
    final bool confirmed = await confirmDestructiveAction(
      context,
      title: "Supprimer tout le dossier ?",
      message:
          'Toutes les informations, photos et notes de ce dossier seront '
          'supprimées définitivement de cet appareil.',
      confirmLabel: 'Supprimer le dossier',
    );
    if (!confirmed) {
      return;
    }
    final List<domain.EvidenceAsset> assets =
        await ref.read(incidentRepositoryProvider).listEvidenceAssets(incidentId);
    for (final domain.EvidenceAsset asset in assets) {
      await ref.read(evidenceStorageServiceProvider).deleteFile(asset.localFilePath);
    }
    await ref.read(incidentRepositoryProvider).deleteIncident(incidentId);
    notifyDataChanged(ref);
    if (context.mounted) {
      context.go(AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (incidentId.isEmpty) {
      return const MissingIncidentView();
    }
    final AsyncValue<domain.Incident?> incidentAsync = ref.watch(incidentDetailProvider(incidentId));

    return incidentAsync.when(
      data: (domain.Incident? incident) {
        if (incident == null) {
          return const MissingIncidentView(title: 'Dossier introuvable');
        }
        return _IncidentDetailBody(
          incident: incident,
          onEdit: () => _editMetadata(context, ref, incident),
          onDeleteEvidence: (domain.EvidenceAsset a) => _deleteEvidence(context, ref, a),
          onDeleteIncident: () => _deleteIncident(context, ref, incident.id),
        );
      },
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (Object e, StackTrace stackTrace) =>
          Scaffold(body: Center(child: Text('Erreur de lecture locale : $e'))),
    );
  }
}

class _IncidentDetailBody extends ConsumerWidget {
  const _IncidentDetailBody({
    required this.incident,
    required this.onEdit,
    required this.onDeleteEvidence,
    required this.onDeleteIncident,
  });

  final domain.Incident incident;
  final VoidCallback onEdit;
  final void Function(domain.EvidenceAsset) onDeleteEvidence;
  final VoidCallback onDeleteIncident;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<domain.Issue>> issuesAsync = ref.watch(incidentIssuesProvider(incident.id));
    final AsyncValue<List<domain.EvidenceAsset>> evidenceAsync =
        ref.watch(incidentEvidenceProvider(incident.id));

    return Scaffold(
      appBar: AppBar(
        title: Text(DateFormat('dd/MM/yyyy HH:mm').format(incident.occurredAt.toLocal())),
        actions: <Widget>[
          IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Corriger', onPressed: onEdit),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: RfColors.danger),
            tooltip: 'Supprimer le dossier',
            onPressed: onDeleteIncident,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(RfSpacing.lg),
        children: <Widget>[
          _InfoRow(label: 'Fournisseur', value: incident.supplierName),
          _InfoRow(label: 'Transporteur', value: incident.carrierName),
          _InfoRow(label: 'Référence BL', value: incident.deliveryRef),
          _InfoRow(
            label: 'Date du BL',
            value: incident.deliveryDate == null
                ? null
                : DateFormat('dd/MM/yyyy').format(incident.deliveryDate!.toLocal()),
          ),
          _InfoRow(label: 'Commentaire', value: incident.notes),
          const SizedBox(height: RfSpacing.lg),
          const Text('Type(s) de problème', style: RfTypography.sectionTitle),
          const SizedBox(height: RfSpacing.sm),
          issuesAsync.when(
            data: (List<domain.Issue> issues) => issues.isEmpty
                ? const Text('Aucun type de problème sélectionné.', style: RfTypography.secondary)
                : Wrap(
                    spacing: RfSpacing.xs,
                    children: issues
                        .map(
                          (domain.Issue i) => Chip(
                            label: Text(_issueTypeLabels[i.issueType] ?? i.issueType.wireValue),
                          ),
                        )
                        .toList(),
                  ),
            loading: () => const CircularProgressIndicator(),
            error: (Object e, StackTrace stackTrace) => Text('Erreur : $e'),
          ),
          const SizedBox(height: RfSpacing.lg),
          const Text('Preuves', style: RfTypography.sectionTitle),
          const SizedBox(height: RfSpacing.sm),
          evidenceAsync.when(
            data: (List<domain.EvidenceAsset> assets) {
              if (assets.isEmpty) {
                return const Text('Aucune preuve capturée.', style: RfTypography.secondary);
              }
              return Column(
                children: assets
                    .map(
                      (domain.EvidenceAsset a) => EvidenceThumbnailTile(
                        asset: a,
                        label: _labelForAsset(a),
                        onDelete: () => onDeleteEvidence(a),
                        onTap: () => _openEvidence(context, incident.id, a),
                      ),
                    )
                    .toList(),
              );
            },
            loading: () => const CircularProgressIndicator(),
            error: (Object e, StackTrace stackTrace) => Text('Erreur : $e'),
          ),
          const SizedBox(height: RfSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => context.pushDocumentCapture(incident.id),
              child: const Text('Continuer / ajouter des preuves'),
            ),
          ),
        ],
      ),
    );
  }

  /// Correction ciblée post-recette terrain R1 : ouvre la visionneuse
  /// photo ou le lecteur audio plein écran selon le type de la preuve -
  /// aucun des deux n'est une étape nommée du parcours S01-S20, donc
  /// poussés via `Navigator.push` (même convention que `CameraCapturePage`),
  /// jamais via go_router.
  void _openEvidence(BuildContext context, String incidentId, domain.EvidenceAsset asset) {
    if (asset.documentType == domain.EvidenceDocumentType.audio) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => EvidenceAudioPlayerScreen(
            incidentId: incidentId,
            asset: asset,
            label: _labelForAsset(asset),
          ),
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EvidencePhotoViewerScreen(
          incidentId: incidentId,
          asset: asset,
          label: _labelForAsset(asset),
        ),
      ),
    );
  }

  String _labelForAsset(domain.EvidenceAsset asset) {
    switch (asset.documentType) {
      case domain.EvidenceDocumentType.deliveryNote:
        return 'Bon de livraison';
      case domain.EvidenceDocumentType.photo:
        return 'Photo preuve';
      case domain.EvidenceDocumentType.audio:
        return 'Note vocale';
      case domain.EvidenceDocumentType.exportedPdf:
        return 'Export PDF';
    }
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: RfSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(width: 120, child: Text(label, style: RfTypography.secondary)),
          Expanded(child: Text(value?.isNotEmpty == true ? value! : '-', style: RfTypography.body)),
        ],
      ),
    );
  }
}
