import 'package:flutter/material.dart';

import 'package:reserveflash/core/design_system/rf_colors.dart';
import 'package:reserveflash/core/design_system/rf_spacing.dart';
import 'package:reserveflash/core/design_system/rf_typography.dart';
import 'package:reserveflash/core/router/app_router.dart';
import 'package:reserveflash/features/facts_review/presentation/fact_review_field.dart';

/// S11 - Revue des faits (F09, GATE).
///
/// "Le bouton 'Confirmer' doit être désactivé tant que les champs critiques
/// requis pour le type d'incident ne sont pas résolus ou explicitement
/// marqués UNKNOWN." (section 2.3)
class FactsReviewScreen extends StatefulWidget {
  const FactsReviewScreen({super.key});

  @override
  State<FactsReviewScreen> createState() => _FactsReviewScreenState();
}

class _FactsReviewScreenState extends State<FactsReviewScreen> {
  // Champs illustratifs pour un incident MISSING_QTY - la liste réelle des
  // champs critiques par issue_type sera fournie par le backend (F03/F08,
  // POST /incidents/{id}/extractions) à l'intégration R2.
  final List<FactReviewField> _fields = <FactReviewField>[
    FactReviewField(
      fieldKey: 'product_label',
      label: 'Produit',
      candidateValue: 'Ballon eau chaude 200L',
    ),
    FactReviewField(
      fieldKey: 'expected_quantity',
      label: 'Quantité attendue',
      candidateValue: '8',
    ),
    FactReviewField(
      fieldKey: 'received_quantity',
      label: 'Quantité reçue',
      candidateValue: null, // ambigu : rien de candidat, doit être résolu.
    ),
  ];

  bool get _allCriticalFieldsResolved => _fields.every((f) => f.isResolved);

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
              TextField(controller: controller, autofocus: true),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vérifiez les faits')),
      body: ListView.separated(
        padding: const EdgeInsets.all(RfSpacing.lg),
        itemCount: _fields.length,
        separatorBuilder: (_, __) => const SizedBox(height: RfSpacing.sm),
        itemBuilder: (BuildContext context, int index) {
          return _FactCard(
            field: _fields[index],
            onConfirm: () => _confirmField(_fields[index]),
            onEdit: () => _editField(_fields[index]),
            onMarkUnknown: () => _markUnknown(_fields[index]),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(RfSpacing.lg),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              // GATE section 2.3 : désactivé tant que tout n'est pas résolu.
              onPressed: _allCriticalFieldsResolved
                  ? () => context.pushReserve()
                  : null,
              child: const Text('Confirmer'),
            ),
          ),
        ),
      ),
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
