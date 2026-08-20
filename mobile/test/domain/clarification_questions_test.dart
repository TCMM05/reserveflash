import 'package:flutter_test/flutter_test.dart';
import 'package:reserveflash/domain/clarification_questions.dart';

/// Miroir Dart de `backend/tests/domain/test_clarification_questions.py`.
void main() {
  test('un champ connu se traduit en identifiant catalogue', () {
    expect(clarificationQuestionIdForField('product_label'), 'Q_PRODUCT_LABEL_MISSING');
  });

  test('un nom de champ null se traduit en null', () {
    expect(clarificationQuestionIdForField(null), isNull);
  });

  test('un nom de champ inconnu/halluciné est ignoré, jamais inventé', () {
    expect(clarificationQuestionIdForField('this_is_not_a_real_field'), isNull);
    expect(clarificationQuestionIdForField(''), isNull);
  });

  test('chaque champ V1 prioritaire a une entrée catalogue', () {
    const Set<String> v1Fields = <String>{
      'issue_type_candidate',
      'product_label',
      'product_reference',
      'expected_quantity',
      'received_quantity',
      'affected_quantity',
      'packaging_condition',
      'product_condition',
      'location_on_item',
    };
    expect(clarificationQuestionCatalog.keys.toSet().containsAll(v1Fields), isTrue);
  });
}
