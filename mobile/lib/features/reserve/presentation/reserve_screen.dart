import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:reserveflash/core/design_system/rf_colors.dart';
import 'package:reserveflash/core/design_system/rf_spacing.dart';
import 'package:reserveflash/core/design_system/rf_typography.dart';
import 'package:reserveflash/core/router/app_router.dart';

/// S12 - Réserve générée.
/// "Texte non juridique, copiable, bouton 'Modifier les faits' ; pas
/// d'édition libre par défaut" (section 3.2). Le texte affiché ici vient de
/// POST /incidents/{id}/reserve (F10, composé côté backend par le Reserve
/// Composer déterministe - jamais généré côté client).
class ReserveScreen extends StatelessWidget {
  const ReserveScreen({super.key});

  // Exemple illustratif : en intégration réelle, ce texte vient de la
  // réponse GenerateReserveResponse (voir backend/app/api/schemas.py).
  static const String _sampleReserveText =
      'Quantité manquante - Ballon eau chaude 200L. Quantité attendue 8, '
      'quantité reçue 6, écart constaté de 2.';
  static const String _prudenceMention =
      'ReserveFlash vous aide à structurer vos constats et vos preuves. Il ne '
      'remplace pas un conseil juridique. Vérifiez les conditions applicables '
      'à votre transport et à vos contrats.';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Réserve générée')),
      body: Padding(
        padding: const EdgeInsets.all(RfSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Card(
              child: Padding(
                padding: EdgeInsets.all(RfSpacing.md),
                child: SelectableText(_sampleReserveText, style: RfTypography.body),
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
                    Clipboard.setData(const ClipboardData(text: _sampleReserveText));
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
        ),
      ),
    );
  }
}
