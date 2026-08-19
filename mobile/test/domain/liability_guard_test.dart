import 'package:flutter_test/flutter_test.dart';
import 'package:reserveflash/domain/errors/domain_errors.dart';
import 'package:reserveflash/domain/fact_set/confirmed_fact_data.dart';
import 'package:reserveflash/domain/liability_guard.dart';
import 'package:reserveflash/domain/reserve_composer.dart';
import 'package:reserveflash/domain/value_objects/issue_type.dart';

/// Tests adversariaux du garde-fou anti-attribution de responsabilité
/// (R0.1, correctif point 8) - miroir Dart de
/// `backend/tests/domain/test_liability_guard.py`. Rejoue le bug signalé
/// explicitement par le donneur d'ordre : `packagingCondition =
/// "transporteur responsable"` ne doit JAMAIS pouvoir traverser jusqu'à une
/// réserve, y compris quand la réserve est composée entièrement hors ligne
/// sur l'appareil (voir lib/domain/reserve_composer.dart).
void main() {
  ConfirmedFactData fact({
    IssueType issueType = IssueType.packagingDamage,
    String? packagingCondition,
    String? productCondition,
    String? locationOnItem,
    String? productLabel,
  }) {
    return ConfirmedFactData(
      issueType: issueType,
      packagingCondition: packagingCondition,
      productCondition: productCondition,
      locationOnItem: locationOnItem,
      productLabel: productLabel,
    );
  }

  group('Cas nommément cité dans la demande corrective', () {
    test('packagingCondition = "transporteur responsable" est bloqué', () {
      final ConfirmedFactData f = fact(packagingCondition: 'transporteur responsable');
      expect(
        () => screenConfirmedFact(f),
        throwsA(
          isA<LiabilityAttributionException>()
              .having((e) => e.violationCode, 'violationCode', 'LIABILITY_ATTRIBUTION')
              .having((e) => e.fieldName, 'fieldName', 'packagingCondition'),
        ),
      );
    });

    test('le bug signalé ne peut jamais atteindre composeReserve', () {
      final ConfirmedFactData f = fact(
        productCondition: 'le transporteur est responsable du dommage',
      );
      expect(
        () => composeReserve(<ConfirmedFactData>[f]),
        throwsA(isA<LiabilityAttributionException>()),
      );
    });
  });

  group('Attribution de responsabilité (autres formulations)', () {
    for (final (String field, String value) in <(String, String)>[
      ('packagingCondition', 'transporteur responsable'),
      ('packagingCondition', 'faute du livreur'),
      ('productCondition', 'dommage imputable au transporteur'),
      ('productCondition', 'carton à la charge du fournisseur'),
      ('locationOnItem', 'coin endommagé, fautif : entrepôt'),
    ]) {
      test('$field = "$value" est bloqué', () {
        final ConfirmedFactData f = switch (field) {
          'packagingCondition' => fact(packagingCondition: value),
          'productCondition' => fact(productCondition: value),
          'locationOnItem' => fact(locationOnItem: value),
          _ => throw StateError('champ inattendu'),
        };
        expect(
          () => screenConfirmedFact(f),
          throwsA(
            isA<LiabilityAttributionException>()
                .having((e) => e.violationCode, 'violationCode', 'LIABILITY_ATTRIBUTION'),
          ),
        );
      });
    }
  });

  group("Promesse d'indemnisation", () {
    for (final String value in <String>[
      'sera indemnisé intégralement',
      'dédommagement prévu',
      'remboursement dû au client',
    ]) {
      test('"$value" est bloqué (INDEMNIFICATION_PROMISE)', () {
        final ConfirmedFactData f = fact(productCondition: value);
        expect(
          () => screenConfirmedFact(f),
          throwsA(
            isA<LiabilityAttributionException>()
                .having((e) => e.violationCode, 'violationCode', 'INDEMNIFICATION_PROMISE'),
          ),
        );
      });
    }
  });

  group('Conclusion juridique', () {
    for (final String value in <String>[
      'manquement contractuel du transporteur',
      'vice caché constaté',
      'négligence lors du transport',
    ]) {
      test('"$value" est bloqué (LEGAL_CONCLUSION)', () {
        final ConfirmedFactData f = fact(packagingCondition: value);
        expect(
          () => screenConfirmedFact(f),
          throwsA(
            isA<LiabilityAttributionException>()
                .having((e) => e.violationCode, 'violationCode', 'LEGAL_CONCLUSION'),
          ),
        );
      });
    }
  });

  group('Montant inventé', () {
    for (final String value in <String>[
      'dommage estimé à 150€',
      'montant de 300 euros',
      '50 EUR de perte',
    ]) {
      test('"$value" est bloqué (INVENTED_AMOUNT)', () {
        final ConfirmedFactData f = fact(productCondition: value);
        expect(
          () => screenConfirmedFact(f),
          throwsA(
            isA<LiabilityAttributionException>()
                .having((e) => e.violationCode, 'violationCode', 'INVENTED_AMOUNT'),
          ),
        );
      });
    }
  });

  group('Qualification juridique', () {
    for (final String value in <String>[
      'cas de force majeure',
      'infraction constatée lors du transport',
    ]) {
      test('"$value" est bloqué (LEGAL_QUALIFICATION)', () {
        final ConfirmedFactData f = fact(packagingCondition: value);
        expect(
          () => screenConfirmedFact(f),
          throwsA(
            isA<LiabilityAttributionException>()
                .having((e) => e.violationCode, 'violationCode', 'LEGAL_QUALIFICATION'),
          ),
        );
      });
    }
  });

  group('Non-régression : constats factuels légitimes doivent PASSER', () {
    for (final (String field, String value) in <(String, String)>[
      ('packagingCondition', 'carton enfoncé sur un angle'),
      ('packagingCondition', 'emballage déchiré, film plastique arraché'),
      ('productCondition', 'rayure visible sur la face avant'),
      ('productCondition', 'verre fissuré sur 5 cm'),
      ('locationOnItem', 'coin inférieur gauche'),
      ('productLabel', 'Ballon eau chaude 200L'),
    ]) {
      test('$field = "$value" ne lève rien', () {
        final ConfirmedFactData f = switch (field) {
          'packagingCondition' => fact(packagingCondition: value),
          'productCondition' => fact(productCondition: value),
          'locationOnItem' => fact(locationOnItem: value),
          'productLabel' => fact(productLabel: value),
          _ => throw StateError('champ inattendu'),
        };
        expect(() => screenConfirmedFact(f), returnsNormally);
      });
    }
  });

  test('screenConfirmedFacts vérifie chaque fait de la séquence', () {
    final ConfirmedFactData ok = fact(packagingCondition: 'carton écrasé');
    final ConfirmedFactData bad = fact(
      issueType: IssueType.productDamage,
      productCondition: 'transporteur fautif',
    );
    expect(
      () => screenConfirmedFacts(<ConfirmedFactData>[ok, bad]),
      throwsA(isA<LiabilityAttributionException>()),
    );
  });
}
