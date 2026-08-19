import 'package:flutter_test/flutter_test.dart';
import 'package:reserveflash/domain/errors/domain_errors.dart';
import 'package:reserveflash/domain/fact_set/confirmed_fact_data.dart';
import 'package:reserveflash/domain/reserve_composer.dart';
import 'package:reserveflash/domain/value_objects/issue_type.dart';

/// Tests du Reserve Composer local (R0.1) - miroir Dart de
/// `backend/tests/domain/test_reserve_composer.py`. Ces tests prouvent que
/// la génération de réserve fonctionne ENTIÈREMENT sur l'appareil (point 6
/// de la demande corrective "Local-First" : "générer un dossier à partir des
/// données locales quand l'IA n'est pas nécessaire"), avec les mêmes
/// garanties GATE que la version backend.
void main() {
  const List<String> forbiddenSeverityAdjectives = <String>[
    'inutilisable',
    'dangereux',
    'détruit',
    'detruit',
  ];
  const List<String> forbiddenLiabilityPhrases = <String>[
    'transporteur est responsable',
    'vous serez remboursé',
    'vous serez rembourse',
    'cette réserve est juridiquement valide',
    'cette reserve est juridiquement valide',
  ];

  test('composeReserve est déterministe pour une même entrée', () {
    final ConfirmedFactData fact = ConfirmedFactData(
      issueType: IssueType.packagingDamage,
      productLabel: 'Ballon eau chaude',
      packagingCondition: 'carton abîmé sur un coin',
    );
    final ComposedReserve r1 = composeReserve(<ConfirmedFactData>[fact]);
    final ComposedReserve r2 = composeReserve(<ConfirmedFactData>[fact]);
    expect(r1.text, r2.text);
    expect(r1.sha256, r2.sha256);
  });

  test('une version de template inconnue lève TemplateNotFoundException', () {
    final ConfirmedFactData fact = ConfirmedFactData(issueType: IssueType.other);
    expect(
      () => composeReserve(<ConfirmedFactData>[fact], templateVersion: 'fr_v99'),
      throwsA(isA<TemplateNotFoundException>()),
    );
  });

  test('E2E-01 : seuls les champs confirmés apparaissent, aucune quantité inventée', () {
    final ConfirmedFactData fact = ConfirmedFactData(
      issueType: IssueType.packagingDamage,
      productLabel: 'Carton n°3',
      packagingCondition: 'un coin écrasé',
    );
    final ComposedReserve result = composeReserve(<ConfirmedFactData>[fact]);
    expect(result.text.contains('Carton n°3'), isTrue);
    expect(result.text.contains('un coin écrasé'), isTrue);
    expect(RegExp(r'\bquantité\b', caseSensitive: false).hasMatch(result.text), isFalse);
  });

  test('E2E-04 : carton abîmé mais produit intact -> aucun dommage produit affirmé', () {
    final ConfirmedFactData fact = ConfirmedFactData(
      issueType: IssueType.packagingDamage,
      productLabel: 'Radiateur',
      packagingCondition: 'carton enfoncé sur un angle',
    );
    final ComposedReserve result = composeReserve(<ConfirmedFactData>[fact]);
    expect(result.text.toLowerCase().contains('produit constaté'), isFalse);
  });

  test('E2E-05 : quantité manquante calculée par code (8 attendu, 6 reçu -> écart 2)', () {
    final ConfirmedFactData fact = ConfirmedFactData(
      issueType: IssueType.missingQty,
      productLabel: 'Vanne thermostatique',
      expectedQuantity: 8,
      receivedQuantity: 6,
    );
    expect(fact.missingQuantity, 2);
    final ComposedReserve result = composeReserve(<ConfirmedFactData>[fact]);
    expect(result.text.contains('écart constaté de 2'), isTrue);
  });

  test('E2E-06 : seule la valeur confirmée après correction apparaît (jamais la première)', () {
    final ConfirmedFactData fact = ConfirmedFactData(
      issueType: IssueType.productDamage,
      productLabel: 'Vitre',
      affectedQuantity: 2, // valeur confirmée après correction "trois... non, deux"
    );
    final ComposedReserve result = composeReserve(<ConfirmedFactData>[fact]);
    expect(result.text.contains('Quantité affectée : 2.'), isTrue);
    expect(RegExp(r'\b3\b').hasMatch(result.text), isFalse);
  });

  test('E2E-07 : aucune attribution de responsabilité ne peut apparaître', () {
    final ConfirmedFactData fact = ConfirmedFactData(
      issueType: IssueType.packagingDamage,
      productLabel: 'Pompe à chaleur',
      packagingCondition: 'carton déchiré',
    );
    final ComposedReserve result = composeReserve(<ConfirmedFactData>[fact]);
    final String lowered = result.text.toLowerCase();
    for (final String phrase in forbiddenLiabilityPhrases) {
      expect(lowered.contains(phrase), isFalse, reason: phrase);
    }
    for (final String adjective in forbiddenSeverityAdjectives) {
      expect(lowered.contains(adjective), isFalse, reason: adjective);
    }
  });

  test('aucun montant ni mention d\'indemnisation n\'est jamais généré', () {
    final ConfirmedFactData fact = ConfirmedFactData(
      issueType: IssueType.packagingDamage,
      productLabel: 'Climatiseur',
      packagingCondition: 'carton mouillé',
    );
    final ComposedReserve result = composeReserve(<ConfirmedFactData>[fact]);
    final String lowered = result.text.toLowerCase();
    for (final String forbidden in <String>['€', 'indemni', 'remboursement', 'montant de']) {
      expect(lowered.contains(forbidden), isFalse, reason: forbidden);
    }
  });

  test('un champ UNKNOWN reste explicitement signalé, jamais résolu silencieusement', () {
    final ConfirmedFactData fact = ConfirmedFactData(
      issueType: IssueType.wrongProduct,
      productLabel: 'Chaudière murale',
      unknownFields: const <String>['productReference'],
    );
    final ComposedReserve result = composeReserve(<ConfirmedFactData>[fact]);
    expect(result.text.contains('Non déterminé à ce stade'), isTrue);
  });

  test('plusieurs anomalies indépendantes apparaissent toutes, dans l\'ordre d\'entrée', () {
    final List<ConfirmedFactData> facts = <ConfirmedFactData>[
      ConfirmedFactData(
        issueType: IssueType.missingQty,
        productLabel: 'Colis A',
        expectedQuantity: 3,
        receivedQuantity: 2,
      ),
      ConfirmedFactData(
        issueType: IssueType.packagingDamage,
        productLabel: 'Carton B',
        packagingCondition: 'écrasé',
      ),
      ConfirmedFactData(
        issueType: IssueType.productDamage,
        productLabel: 'Produit C',
        productCondition: 'rayé sur la face avant',
      ),
    ];
    final ComposedReserve result = composeReserve(facts);
    final List<int> positions = facts.map((f) => result.text.indexOf(f.productLabel!)).toList();
    final List<int> sorted = List<int>.from(positions)..sort();
    expect(positions, sorted);
  });

  test('composeReserve refuse une liste vide', () {
    expect(() => composeReserve(<ConfirmedFactData>[]), throwsArgumentError);
  });
}
