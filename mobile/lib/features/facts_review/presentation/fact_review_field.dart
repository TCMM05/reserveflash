/// État d'un champ affiché sur l'écran de revue des faits (S11, F09).
///
/// Section 2.3 - règles UX de validation des faits :
///  - "Chaque candidat IA est affiché à l'utilisateur avant confirmation."
///  - "La valeur UNKNOWN / 'Je ne sais pas' est une réponse valide et doit
///    être proposée explicitement."
///  - "Toute correction utilisateur remplace la proposition IA dans le
///    modèle confirmé [...], sans conserver le texte sensible dans
///    l'analytics produit."
enum FactFieldReviewState { candidate, confirmed, edited, unknown }

class FactReviewField {
  FactReviewField({
    required this.fieldKey,
    required this.label,
    required this.candidateValue,
    this.state = FactFieldReviewState.candidate,
    this.currentValue,
  });

  final String fieldKey;
  final String label;

  /// Valeur proposée par l'IA - jamais modifiée après extraction (audit),
  /// affichée grisée/annotée "compris par l'IA" tant que non confirmée.
  final String? candidateValue;

  FactFieldReviewState state;

  /// Valeur affichée à l'utilisateur : `candidateValue` par défaut, ou la
  /// correction saisie une fois éditée.
  String? currentValue;

  bool get isResolved =>
      state == FactFieldReviewState.confirmed ||
      state == FactFieldReviewState.edited ||
      state == FactFieldReviewState.unknown;
}
