import 'package:flutter/material.dart';

import 'package:reserveflash/core/design_system/rf_colors.dart';

/// R1 (point 7 - "aucune suppression silencieuse") : boîte de dialogue de
/// confirmation partagée par toute action destructive (suppression d'une
/// photo, suppression d'un incident...). Retourne `true` uniquement si
/// l'utilisateur a explicitement confirmé.
Future<bool> confirmDestructiveAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Supprimer',
}) async {
  final bool? result = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) {
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: RfColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return result ?? false;
}
