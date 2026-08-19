import 'package:flutter/material.dart';

import 'rf_colors.dart';
import 'rf_spacing.dart';
import 'rf_typography.dart';

/// Thème Material assemblant le design system ReserveFlash (section 4).
///
/// Accessibilité (section 4.6) :
///  - Contraste cible WCAG 2.2 AA (4.5:1 texte normal / 3:1 gros texte) -
///    la paire navy/background et text/background ont été choisies pour
///    satisfaire ce seuil ; toute nouvelle combinaison doit être vérifiée
///    avant usage (voir docs/architecture.md).
///  - `MediaQuery.textScaler` n'est jamais plafonné ici : le support du
///    text scaling jusqu'à 200% (section 4.3) implique de ne PAS utiliser
///    `MediaQuery.textScalerOf(context).clamp(...)` pour réduire la taille
///    du texte utilisateur.
final class RfTheme {
  const RfTheme._();

  static ThemeData light() {
    final ColorScheme colorScheme = ColorScheme.fromSeed(
      seedColor: RfColors.navy,
      brightness: Brightness.light,
      primary: RfColors.navy,
      secondary: RfColors.signal,
      error: RfColors.danger,
      surface: RfColors.background,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: RfColors.background,
      textTheme: const TextTheme(
        headlineSmall: RfTypography.screenTitle,
        titleMedium: RfTypography.sectionTitle,
        bodyLarge: RfTypography.body,
        bodySmall: RfTypography.secondary,
        labelLarge: RfTypography.button,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: RfColors.background,
        foregroundColor: RfColors.text,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: RfTypography.sectionTitle,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: RfColors.navy,
          foregroundColor: RfColors.background,
          minimumSize: const Size.fromHeight(RfSpacing.buttonHeight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(RfSpacing.primaryButtonRadius),
          ),
          textStyle: RfTypography.button,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: RfColors.signal,
          foregroundColor: RfColors.text,
          minimumSize: const Size.fromHeight(RfSpacing.buttonHeight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(RfSpacing.primaryButtonRadius),
          ),
          textStyle: RfTypography.button,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(RfSpacing.cardRadius),
          side: const BorderSide(color: RfColors.border),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(RfSpacing.cardRadius),
          borderSide: const BorderSide(color: RfColors.border),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: RfSpacing.md,
          vertical: RfSpacing.sm,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(RfSpacing.modalRadius),
          ),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: RfColors.navy,
        contentTextStyle: TextStyle(color: RfColors.background),
      ),
    );
  }
}
