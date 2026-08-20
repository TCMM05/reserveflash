/// Garde-fou déterministe appliqué aux `CandidateFactData` (R2, section
/// "Validation sémantique obligatoire" de la demande de démarrage R2) -
/// miroir Dart de `backend/app/domain/candidate_guard.py`.
///
/// Contexte : `lib/domain/liability_guard.dart` protège déjà la réserve
/// finale en rejetant un `ConfirmedFactData` contenant une attribution de
/// responsabilité, une promesse d'indemnisation, une conclusion/
/// qualification juridique ou un montant inventé - mais seulement APRÈS que
/// l'utilisateur a confirmé le champ. Le risque R2 est différent : le
/// pipeline IA peut proposer un `CandidateFactData` contenant déjà ce type
/// de contenu interdit (ex: l'utilisateur dit "c'est clairement la faute du
/// transporteur" et un extracteur mal cadré écrit
/// `packaging_condition = "transporteur responsable"`). Si ce candidat est
/// affiché tel quel à l'écran de revue (F09), l'utilisateur peut le
/// confirmer sans le relire attentivement - le contenu interdit
/// contournerait alors `liability_guard` côté confirmation puisqu'il aurait
/// été "inventé" comme valeur proposée plutôt que saisi par l'utilisateur
/// lui-même.
///
/// Principe (défense en profondeur, même philosophie que
/// `liability_guard.dart`) :
///
///   1. Aucun champ candidat dont la valeur texte libre contient un motif
///      interdit (`lib/domain/liability_guard.dart::forbiddenPatterns` -
///      source unique) n'est jamais transmis à l'écran de revue. Le champ
///      est retiré du candidat (jamais réécrit/sanitisé silencieusement -
///      il disparaît, il ne devient pas une fausse valeur "propre").
///   2. Une quantité négative dans un champ de quantité connu
///      (`expected_quantity` / `received_quantity` / `affected_quantity`)
///      est physiquement impossible : elle indique une hallucination ou une
///      erreur de parsing du pipeline IA, jamais une donnée réelle. Le
///      champ est retiré.
///   3. Tout retrait force `requiresReview = true` (même si le candidat
///      l'affichait déjà à `false`) : l'utilisateur voit alors
///      explicitement qu'il manque une information plutôt que de croire le
///      dossier complet.
///
/// Déterministe, aucun appel réseau, aucune sanitization silencieuse. Ne
/// lève jamais d'exception : contrairement au `ConfirmedFactData` (où un
/// contenu interdit doit bloquer explicitement la confirmation via
/// `LiabilityAttributionException`), un `CandidateFactData` dégrade
/// proprement en retirant le champ fautif plutôt qu'en faisant échouer
/// toute l'extraction (section "Échec IA" de la demande R2 : "aucune boucle
/// infinie de retries", "ne jamais bloquer l'utilisateur").
///
/// Les deux implémentations (Python et Dart) DOIVENT rester alignées - même
/// principe de duplication contrôlée que `liability_guard.dart` vis-à-vis
/// de `backend/app/domain/liability_guard.py` (voir docs/architecture.md,
/// section "duplication contrôlée du Reserve Composer").
library;

import 'fact_set/candidate_fact_data.dart';
import 'liability_guard.dart';

/// Champs de quantité connus du schéma V1
/// (`schemas/candidate_fact_set.v1.schema.json`, section "Champs V1
/// prioritaires" de la demande R2). Une valeur négative sur l'un de ces
/// champs est toujours invalide - une quantité ne peut pas être négative
/// dans le monde réel. Clés en snake_case (wire JSON), voir docstring de
/// fichier de `lib/domain/fact_set/candidate_fact_data.dart`.
const Set<String> _knownQuantityFields = <String>{
  'expected_quantity',
  'received_quantity',
  'affected_quantity',
};

String? _firstForbiddenViolation(String value) {
  for (final ForbiddenPattern forbidden in forbiddenPatterns) {
    if (forbidden.pattern.hasMatch(value)) {
      return forbidden.violationCode;
    }
  }
  return null;
}

bool _isInvalidQuantity(String fieldName, Object? value) {
  if (!_knownQuantityFields.contains(fieldName)) {
    return false;
  }
  if (value is! num) {
    return false;
  }
  return value < 0;
}

/// Retourne un `CandidateFactData` équivalent à [candidate], privé de tout
/// champ contenant un contenu interdit (liability/indemnisation/conclusion
/// ou qualification juridique/montant inventé) ou une quantité négative.
///
/// Ne modifie jamais [candidate] en place : retourne le même objet si rien
/// n'a été retiré (pas d'allocation inutile), sinon une copie (via
/// `CandidateFactData.copyWith`) avec `fields` et `requiresReview` mis à
/// jour.
CandidateFactData screenCandidateFactData(CandidateFactData candidate) {
  final Map<String, CandidateField> screenedFields = <String, CandidateField>{};
  final List<String> removedFieldNames = <String>[];

  for (final MapEntry<String, CandidateField> entry in candidate.fields.entries) {
    final Object? value = entry.value.value;
    final String? violation = value is String ? _firstForbiddenViolation(value) : null;
    if (violation != null || _isInvalidQuantity(entry.key, value)) {
      removedFieldNames.add(entry.key);
      continue;
    }
    screenedFields[entry.key] = entry.value;
  }

  if (removedFieldNames.isEmpty) {
    return candidate;
  }

  return candidate.copyWith(fields: screenedFields, requiresReview: true);
}
