import 'package:flutter_test/flutter_test.dart';
import 'package:reserveflash/domain/candidate_guard.dart';
import 'package:reserveflash/domain/fact_set/candidate_fact_data.dart';
import 'package:reserveflash/domain/value_objects/confidence_level.dart';
import 'package:reserveflash/domain/value_objects/issue_type.dart';

/// Tests du garde-fou appliqué aux `CandidateFactData` (R2, "Validation
/// sémantique obligatoire") - miroir Dart de
/// `backend/tests/domain/test_candidate_guard.py`. Rejoue explicitement
/// l'exemple toujours interdit donné par l'équipe : `packaging_condition =
/// "transporteur responsable"` ne doit jamais atteindre l'écran de revue,
/// même comme simple PROPOSITION candidate (pas encore confirmée).
void main() {
  CandidateField field(
    Object? value, {
    FactSource source = FactSource.voiceTranscript,
    ConfidenceLevel confidence = ConfidenceLevel.high,
  }) {
    return CandidateField(value: value, source: source, confidence: confidence);
  }

  CandidateFactData candidate(
    Map<String, CandidateField> fields, {
    bool requiresReview = false,
  }) {
    return CandidateFactData(
      issueTypeCandidate: IssueType.packagingDamage,
      fields: fields,
      requiresReview: requiresReview,
    );
  }

  group('Cas nommément cité par l\'équipe', () {
    test('packaging_condition = "transporteur responsable" est retiré', () {
      final CandidateFactData c = candidate(<String, CandidateField>{
        'packaging_condition': field('transporteur responsable'),
        'product_label': field('PAC-284'),
      });
      final CandidateFactData screened = screenCandidateFactData(c);
      expect(screened.fields.containsKey('packaging_condition'), isFalse);
      expect(screened.fields.containsKey('product_label'), isTrue);
      expect(screened.requiresReview, isTrue);
    });

    test(
      '« c\'est clairement la faute du transporteur » : le fait matériel '
      'associé passe, la conclusion de responsabilité jamais',
      () {
        final CandidateFactData c = candidate(<String, CandidateField>{
          'product_condition': field("c'est clairement la faute du transporteur"),
          'product_label': field('PAC-284'),
        });
        final CandidateFactData screened = screenCandidateFactData(c);
        expect(screened.fields.containsKey('product_condition'), isFalse);
        expect(screened.fields['product_label']!.value, 'PAC-284');
      },
    );
  });

  group('Autres motifs interdits (mêmes catégories que liability_guard)', () {
    for (final String text in <String>[
      'le transporteur devra indemniser le client',
      'manquement contractuel du fournisseur',
      'dommage estimé à 350 euros',
      'cas de force majeure',
    ]) {
      test('"$text" est retiré', () {
        final CandidateFactData c = candidate(<String, CandidateField>{
          'packaging_condition': field(text),
        });
        final CandidateFactData screened = screenCandidateFactData(c);
        expect(screened.fields.containsKey('packaging_condition'), isFalse);
        expect(screened.requiresReview, isTrue);
      });
    }
  });

  test('un constat factuel neutre est conservé tel quel (aucune copie)', () {
    final CandidateFactData c = candidate(<String, CandidateField>{
      'packaging_condition': field('carton enfoncé sur un coin'),
    });
    final CandidateFactData screened = screenCandidateFactData(c);
    expect(screened.fields['packaging_condition']!.value, 'carton enfoncé sur un coin');
    expect(identical(screened, c), isTrue);
  });

  group('Cohérence des quantités', () {
    for (final String fieldName in <String>[
      'expected_quantity',
      'received_quantity',
      'affected_quantity',
    ]) {
      test('$fieldName négatif est retiré', () {
        final CandidateFactData c = candidate(<String, CandidateField>{
          fieldName: field(-2, source: FactSource.llmNormalization),
        });
        final CandidateFactData screened = screenCandidateFactData(c);
        expect(screened.fields.containsKey(fieldName), isFalse);
        expect(screened.requiresReview, isTrue);
      });
    }

    test('une quantité positive est conservée', () {
      final CandidateFactData c = candidate(<String, CandidateField>{
        'received_quantity': field(11, source: FactSource.llmNormalization),
      });
      final CandidateFactData screened = screenCandidateFactData(c);
      expect(screened.fields['received_quantity']!.value, 11);
    });

    test('une quantité à zéro est conservée (pas traitée comme négative)', () {
      final CandidateFactData c = candidate(<String, CandidateField>{
        'affected_quantity': field(0, source: FactSource.llmNormalization),
      });
      final CandidateFactData screened = screenCandidateFactData(c);
      expect(screened.fields['affected_quantity']!.value, 0);
    });
  });

  test('plusieurs champs fautifs sont tous retirés en un seul passage', () {
    final CandidateFactData c = candidate(<String, CandidateField>{
      'packaging_condition': field('transporteur responsable'),
      'affected_quantity': field(-1, source: FactSource.llmNormalization),
      'product_label': field('PAC-284'),
    });
    final CandidateFactData screened = screenCandidateFactData(c);
    expect(screened.fields.keys.toSet(), <String>{'product_label'});
    expect(screened.requiresReview, isTrue);
  });

  test('le filtrage ne lève jamais d\'exception, il retire seulement', () {
    final CandidateFactData c = candidate(<String, CandidateField>{
      'packaging_condition': field('indemnisation garantie de 500 euros'),
    });
    final CandidateFactData screened = screenCandidateFactData(c);
    expect(screened.fields.containsKey('packaging_condition'), isFalse);
  });
}
