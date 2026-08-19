import 'package:flutter/widgets.dart';

import 'rf_colors.dart';

/// Échelle typographique (section 4.3). Police système uniquement (Roboto
/// Android / SF Pro iOS via `TextTheme` par défaut de la plateforme) :
/// "aucune dépendance réseau pour la typographie" - donc pas de `fontFamily`
/// personnalisée chargée ici, on laisse le système choisir.
abstract final class RfTypography {
  static const TextStyle screenTitle = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w700,
    color: RfColors.text,
    height: 1.2,
  );

  static const TextStyle sectionTitle = TextStyle(
    fontSize: 19,
    fontWeight: FontWeight.w600,
    color: RfColors.text,
    height: 1.25,
  );

  static const TextStyle body = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: RfColors.text,
    height: 1.4,
  );

  static const TextStyle secondary = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: RfColors.muted,
    height: 1.35,
  );

  static const TextStyle button = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: RfColors.background,
    height: 1.2,
  );
}
