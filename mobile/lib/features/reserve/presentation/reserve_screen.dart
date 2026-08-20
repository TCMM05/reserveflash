import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:reserveflash/core/design_system/rf_colors.dart';
import 'package:reserveflash/core/design_system/rf_spacing.dart';
import 'package:reserveflash/core/design_system/rf_typography.dart';
import 'package:reserveflash/core/providers/app_providers.dart';
import 'package:reserveflash/core/router/app_router.dart';
import 'package:reserveflash/domain/entities/reserve_text.dart' as domain;
import 'package:reserveflash/features/common/presentation/missing_incident_view.dart';

/// S12 - Réserve générée.
/// "Texte non juridique, copiable, bouton 'Modifier les faits' ; pas
/// d'édition libre par défaut" (section 3.2). Depuis R0.1 (pivot
/// Local-First), F10 "Composer la réserve descriptive" tourne sur
/// l'appareil (`IncidentRepository.composeAndSaveReserve`,
/// `lib/domain/reserve_composer.dart`), jamais généré côté client par ce
/// widget lui-même - cet écran se contente d'AFFICHER la dernière réserve
/// déjà composée et persistée (`latestReserveText`).
///
/// Câblage réel R2 (avant : texte d'exemple codé en dur, voir
/// docs/GATE_R2_STATUS.md). La composition elle-même est déclenchée par
/// `facts_review_screen.dart` (bouton "Générer la réserve") avant d'arriver
/// ici - si cet écran est atteint sans réserve existante (ex : deep link,
/// état incohérent), il l'indique clairement plutôt que d'afficher un texte
/// factice.
class ReserveScreen extends ConsumerWidget {
  const ReserveScreen({required this.incidentId, super.key});

  final String incidentId;

  static const String _prudenceMention =
      'ReserveFlash vous aide à structurer vos constats et vos preuves. Il ne '
      'remplace pas un conseil juridique. Vérifiez les conditions applicables '
      'à votre transport et à vos contrats.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (incidentId.isEmpty) {
      return const MissingIncidentView();
    }
    final AsyncValue<domain.ReserveText?> reserveAsync =
        ref.watch(latestReserveTextProvider(incidentId));

    return Scaffold(
      appBar: AppBar(title: const Text('Réserve générée')),
      body: Padding(
        padding: const EdgeInsets.all(RfSpacing.lg),
        child: reserveAsync.when(
          data: (domain.ReserveText? reserve) {
            if (reserve == null) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    "Aucune réserve n'a encore été générée pour ce dossier.",
                    style: RfTypography.body,
                  ),
                  const SizedBox(height: RfSpacing.md),
                  OutlinedButton.icon(
                    onPressed: () => context.pop(),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Revoir les faits'),
                  ),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(RfSpacing.md),
                    child: SelectableText(reserve.text, style: RfTypography.body),
                  ),
                ),
                const SizedBox(height: RfSpacing.sm),
                const Text(_prudenceMention, style: RfTypography.secondary),
                const SizedBox(height: RfSpacing.md),
                Row(
                  children: <Widget>[
                    OutlinedButton.icon(
                      onPressed: () => context.pop(),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Modifier les faits'),
                    ),
                    const SizedBox(width: RfSpacing.sm),
                    OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: reserve.text));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Texte copié.')),
                        );
                      },
                      icon: const Icon(Icons.copy_outlined),
                      label: const Text('Copier'),
                    ),
                  ],
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: RfColors.navy),
                    onPressed: () => context.pushFinalDocument(),
                    child: const Text('Continuer'),
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
