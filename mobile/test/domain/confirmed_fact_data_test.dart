import 'package:flutter_test/flutter_test.dart';
import 'package:reserveflash/domain/fact_set/confirmed_fact_data.dart';
import 'package:reserveflash/domain/value_objects/issue_type.dart';

void main() {
  group('ConfirmedFactData - section 6.3', () {
    test('missingQuantity calcule la différence quand les deux valeurs sont connues', () {
      final ConfirmedFactData fact = ConfirmedFactData(
        issueType: IssueType.missingQty,
        expectedQuantity: 8,
        receivedQuantity: 6,
      );
      expect(fact.missingQuantity, 2);
    });

    test('missingQuantity est null si une quantité est inconnue (pas d\'invention)', () {
      final ConfirmedFactData fact = ConfirmedFactData(
        issueType: IssueType.missingQty,
        expectedQuantity: 8,
      );
      expect(fact.missingQuantity, isNull);
    });

    test('les quantités négatives sont rejetées', () {
      expect(
        () => ConfirmedFactData(issueType: IssueType.wrongQty, expectedQuantity: -1),
        throwsArgumentError,
      );
    });

    test('userConfirmed est toujours true (invariant de type)', () {
      final ConfirmedFactData fact = ConfirmedFactData(issueType: IssueType.other);
      expect(fact.userConfirmed, isTrue);
    });

    test('isFieldUnknown reflète unknownFields', () {
      final ConfirmedFactData fact = ConfirmedFactData(
        issueType: IssueType.productDamage,
        unknownFields: const <String>['product_reference'],
      );
      expect(fact.isFieldUnknown('product_reference'), isTrue);
      expect(fact.isFieldUnknown('product_label'), isFalse);
    });

    test('toConfirmPayload omet les champs null et n\'inclut jamais user_confirmed', () {
      final ConfirmedFactData fact = ConfirmedFactData(
        issueType: IssueType.packagingDamage,
        packagingCondition: 'carton écrasé',
      );
      final Map<String, dynamic> payload = fact.toConfirmPayload();
      expect(payload['issue_type'], 'PACKAGING_DAMAGE');
      expect(payload['packaging_condition'], 'carton écrasé');
      expect(payload.containsKey('product_label'), isFalse);
      expect(payload.containsKey('user_confirmed'), isFalse);
    });
  });
}
