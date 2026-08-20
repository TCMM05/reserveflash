/// Catalogue contrôlé des questions de clarification
/// (`schemas/candidate_fact_set.v1.schema.json`, champ
/// `clarification_question_id` : "Reference a une question du catalogue
/// controle (section 7.1), jamais une question generee librement par le
/// LLM.") - miroir Dart de `backend/app/domain/clarification_questions.py`.
///
/// Ce module est la SEULE source de vérité côté mobile pour les
/// identifiants valides. Le pipeline IA (backend, jamais appelé
/// directement par ce module) n'est jamais autorisé à produire directement
/// une valeur de `clarificationQuestionId` : il peut au plus indiquer le
/// NOM du champ candidat sur lequel il a le plus d'incertitude - c'est ce
/// code, jamais le modèle, qui traduit ce nom de champ en identifiant
/// catalogue. Un nom de champ hors de ce catalogue (halluciné ou mal
/// orthographié) est silencieusement ignoré (retourne `null`) plutôt que de
/// laisser passer un identifiant inventé.
///
/// Les deux implémentations (Python et Dart) DOIVENT rester alignées - même
/// principe que `lib/domain/liability_guard.dart` vis-à-vis de
/// `backend/app/domain/liability_guard.py`.
library;

/// Une entrée par champ V1 prioritaire (voir
/// `lib/domain/fact_set/candidate_fact_data.dart`,
/// `schemas/candidate_fact_set.v1.schema.json`) susceptible de nécessiter
/// une clarification utilisateur, plus une entrée dédiée à
/// `issueTypeCandidate` lui-même (clé spéciale `issue_type_candidate`, qui
/// n'est pas une entrée de `fields`).
///
/// Clés en snake_case (identiques au wire JSON, PAS aux noms de propriété
/// Dart camelCase) - voir la docstring de fichier de
/// `lib/domain/fact_set/candidate_fact_data.dart` pour l'explication de ce
/// choix.
const Map<String, String> clarificationQuestionCatalog = <String, String>{
  'issue_type_candidate': 'Q_ISSUE_TYPE_AMBIGUOUS',
  'product_label': 'Q_PRODUCT_LABEL_MISSING',
  'product_reference': 'Q_PRODUCT_REFERENCE_MISSING',
  'expected_quantity': 'Q_EXPECTED_QUANTITY_MISSING',
  'received_quantity': 'Q_RECEIVED_QUANTITY_MISSING',
  'affected_quantity': 'Q_AFFECTED_QUANTITY_MISSING',
  'packaging_condition': 'Q_PACKAGING_CONDITION_AMBIGUOUS',
  'product_condition': 'Q_PRODUCT_CONDITION_AMBIGUOUS',
  'location_on_item': 'Q_LOCATION_ON_ITEM_MISSING',
};

/// Traduit un nom de champ candidat en identifiant catalogue contrôlé.
///
/// Retourne `null` si [fieldName] est `null` ou absent du catalogue (y
/// compris un nom halluciné/mal orthographié) - jamais une valeur inventée
/// à la volée.
String? clarificationQuestionIdForField(String? fieldName) {
  if (fieldName == null) {
    return null;
  }
  return clarificationQuestionCatalog[fieldName];
}
