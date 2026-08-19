/// Grille et rayons (section 4.4). Base 4dp, espacements privilégiés
/// 8/12/16/24/32.
abstract final class RfSpacing {
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;

  /// Coins des cartes/champs.
  static const double cardRadius = 12;

  /// Coins des modales (bottom sheets).
  static const double modalRadius = 16;

  /// Coins du bouton primaire.
  static const double primaryButtonRadius = 13;

  /// Hauteur des boutons (section 4.3 : "Boutons : 16sp Semibold, hauteur
  /// 52-56dp").
  static const double buttonHeight = 54;

  /// Taille minimale des cibles tactiles (section 3.1 : "CTA principal en
  /// zone basse ; cibles tactiles >= 48dp" - repris comme gate de recette
  /// UX section 19).
  static const double minTouchTarget = 48;
}
