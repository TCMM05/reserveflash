/// Miroir Dart de `schemas/candidate_fact_set.v1.schema.json` /
/// `backend/app/domain/fact_set.py::CandidateField`/`CandidateFactData`.
///
/// Sortie BRUTE du pipeline IA (transcription + extraction, section 7.2,
/// étapes 1-4), en attente de revue utilisateur (écran F09/S11). Ne DOIT
/// JAMAIS être utilisée directement pour composer une réserve (GATE zéro
/// invention, section 2.4) - seule `ConfirmedFactData`
/// (`lib/domain/fact_set/confirmed_fact_data.dart`), obtenue après
/// validation humaine explicite, peut alimenter
/// `lib/domain/reserve_composer.dart`.
///
/// Les clés du `Map` `fields` sont les noms de champ EXACTS échangés en JSON
/// (snake_case : `product_label`, `expected_quantity`, ...), PAS des
/// identifiants Dart camelCase - alignées avec
/// `backend/app/domain/fact_set.py` et
/// `lib/domain/clarification_questions.dart`, pour que
/// `rawStructuredJson` (voir `LocalCandidateFactSets`,
/// `lib/data/local/app_database.dart`) soit un round-trip JSON fidèle, sans
/// aucune conversion de casse à mémoriser.
library;

import '../value_objects/confidence_level.dart';
import '../value_objects/issue_type.dart';

const String candidateFactSetSchemaVersion = 'candidate_fact_set.v1';

/// Un champ candidat individuel - une entrée de `CandidateFactData.fields`.
/// `value` est volontairement non typé (`Object?`, cf. schéma JSON
/// `"value": {}`) pour rester fidèle à ce que le pipeline IA a effectivement
/// produit avant toute validation métier.
final class CandidateField {
  const CandidateField({
    required this.value,
    required this.source,
    required this.confidence,
    this.ambiguous = false,
  });

  final Object? value;
  final FactSource source;
  final ConfidenceLevel confidence;
  final bool ambiguous;

  factory CandidateField.fromJson(Map<String, dynamic> json) {
    return CandidateField(
      value: json['value'],
      source: _factSourceFromWire(json['source'] as String),
      confidence: _confidenceFromWire(json['confidence'] as String),
      ambiguous: json['ambiguous'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'value': value,
      'source': source.wireValue,
      'confidence': confidence.wireValue,
      'ambiguous': ambiguous,
    };
  }
}

/// Correspond exactement à `schemas/candidate_fact_set.v1.schema.json`.
final class CandidateFactData {
  const CandidateFactData({
    required this.issueTypeCandidate,
    required this.fields,
    required this.requiresReview,
    this.clarificationQuestionId,
  });

  final IssueType? issueTypeCandidate;
  final Map<String, CandidateField> fields;

  /// `true` si au moins un champ critique pour `issueTypeCandidate` est
  /// absent, `AMBIGUOUS` ou en contradiction entre sources (règle UX 2.3).
  final bool requiresReview;

  /// Référence à une question du catalogue contrôlé
  /// (`lib/domain/clarification_questions.dart`), jamais une question
  /// générée librement par le LLM.
  final String? clarificationQuestionId;

  factory CandidateFactData.fromJson(Map<String, dynamic> json) {
    final String? issueTypeWire = json['issue_type_candidate'] as String?;
    final Map<String, dynamic> rawFields =
        (json['fields'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    return CandidateFactData(
      issueTypeCandidate: issueTypeWire == null ? null : IssueType.fromWire(issueTypeWire),
      fields: rawFields.map(
        (String key, dynamic value) => MapEntry<String, CandidateField>(
          key,
          CandidateField.fromJson(value as Map<String, dynamic>),
        ),
      ),
      requiresReview: json['requires_review'] as bool,
      clarificationQuestionId: json['clarification_question_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'issue_type_candidate': issueTypeCandidate?.wireValue,
      'fields': fields.map(
        (String key, CandidateField field) => MapEntry<String, dynamic>(key, field.toJson()),
      ),
      'requires_review': requiresReview,
      if (clarificationQuestionId != null) 'clarification_question_id': clarificationQuestionId,
    };
  }

  /// Retourne un `CandidateFactData` équivalent avec `fields`/
  /// `requiresReview` remplacés - jamais de mutation en place, même
  /// politique d'immutabilité que `ConfirmedFactData`. Utilisé par
  /// `lib/domain/candidate_guard.dart::screenCandidateFactData`.
  CandidateFactData copyWith({
    Map<String, CandidateField>? fields,
    bool? requiresReview,
  }) {
    return CandidateFactData(
      issueTypeCandidate: issueTypeCandidate,
      fields: fields ?? this.fields,
      requiresReview: requiresReview ?? this.requiresReview,
      clarificationQuestionId: clarificationQuestionId,
    );
  }
}

FactSource _factSourceFromWire(String value) {
  return FactSource.values.firstWhere(
    (candidate) => candidate.wireValue == value,
    orElse: () => throw ArgumentError('FactSource inconnu: $value'),
  );
}

ConfidenceLevel _confidenceFromWire(String value) {
  return ConfidenceLevel.values.firstWhere(
    (candidate) => candidate.wireValue == value,
    orElse: () => throw ArgumentError('ConfidenceLevel inconnu: $value'),
  );
}
