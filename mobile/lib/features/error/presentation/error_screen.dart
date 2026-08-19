import 'package:flutter/material.dart';

import 'package:reserveflash/core/design_system/rf_colors.dart';
import 'package:reserveflash/core/design_system/rf_spacing.dart';
import 'package:reserveflash/core/design_system/rf_typography.dart';

/// S20 - Erreur/fallback.
/// "Message actionnable : réessayer, saisir manuellement, synchroniser plus
/// tard." (section 3.2). GATE de résilience (section 7.4) : un échec IA ne
/// doit JAMAIS faire perdre une photo, un audio ou un incident - cet écran
/// est la sortie de secours systématique.
class ErrorScreen extends StatelessWidget {
  const ErrorScreen({
    required this.message,
    this.onRetry,
    this.onEnterManually,
    super.key,
  });

  final String message;
  final VoidCallback? onRetry;
  final VoidCallback? onEnterManually;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(RfSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.error_outline, color: RfColors.danger, size: 48),
              const SizedBox(height: RfSpacing.md),
              Text(
                message,
                textAlign: TextAlign.center,
                style: RfTypography.body,
              ),
              const SizedBox(height: RfSpacing.lg),
              if (onRetry != null)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(onPressed: onRetry, child: const Text('Réessayer')),
                ),
              if (onEnterManually != null) ...<Widget>[
                const SizedBox(height: RfSpacing.sm),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: onEnterManually,
                    child: const Text('Saisir manuellement'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
