import 'package:flutter/widgets.dart';

/// Palette officielle ReserveFlash (section 4.2 du cahier des charges).
///
/// Positionnement visuel (section 4.1) : "bleu technique, signal orange,
/// surfaces claires, informations très lisibles" - explicitement PAS de
/// dégradés violets, néons ni imagerie robotique.
abstract final class RfColors {
  /// Logo, titres, navigation, surfaces fortes.
  static const Color navy = Color(0xFF173A5E);

  /// Action urgente, incident, CTA secondaire fort.
  static const Color signal = Color(0xFFF59E0B);

  /// Étape confirmée, dossier complet.
  static const Color success = Color(0xFF17845E);

  /// Erreur critique, suppression, incohérence bloquante.
  static const Color danger = Color(0xFFC94040);

  /// Fond d'application.
  static const Color background = Color(0xFFF5F7FA);

  /// Texte principal.
  static const Color text = Color(0xFF17212B);

  /// Métadonnées, aide.
  static const Color muted = Color(0xFF667085);

  /// Séparateurs, champs.
  static const Color border = Color(0xFFD6DCE4);
}
