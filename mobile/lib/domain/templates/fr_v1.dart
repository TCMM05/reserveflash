/// Template de réserve FR, version fr_v1 - miroir Dart de
/// `backend/app/domain/templates/fr_v1.py`.
///
/// Règles strictes appliquées ici (GATE zéro invention, section 2.4) :
///   - Aucun adjectif de gravité ("inutilisable", "dangereux", "détruit")
///     n'est généré par ce module ; seules les valeurs de
///     `packagingCondition` / `productCondition` telles que confirmées par
///     l'utilisateur sont citées (après passage par
///     `lib/domain/liability_guard.dart`, voir reserve_composer.dart).
///   - Aucune attribution de faute ou de responsabilité.
///   - Aucune mention de montant, indemnisation ou obligation juridique.
///   - Un champ marqué UNKNOWN par l'utilisateur reste explicitement signalé
///     comme non déterminé ; il n'est jamais tu ni inventé.
///
/// Pour une même entrée (ConfirmedFactData) et une même version de template,
/// la sortie est strictement identique (déterministe, pas d'appel LLM, pas
/// d'horodatage dans le texte) - IDENTIQUE bit-à-bit à la sortie du même
/// template côté backend (`backend/app/domain/templates/fr_v1.py`), ce qui
/// permet de vérifier une réserve générée hors ligne contre un recalcul
/// serveur ultérieur si besoin (section 6.1).
library;

import '../fact_set/confirmed_fact_data.dart';
import '../value_objects/issue_type.dart';

const String templateVersionFrV1 = 'fr_v1';

const Map<IssueType, String> _issueLabels = <IssueType, String>{
  IssueType.packagingDamage: "Dommage sur l'emballage",
  IssueType.productDamage: 'Dommage sur le produit',
  IssueType.missingQty: 'Quantité manquante',
  IssueType.wrongQty: 'Quantité incorrecte',
  IssueType.wrongProduct: 'Produit non conforme à la commande',
  IssueType.visibleNonconformity: 'Non-conformité visible',
  IssueType.other: 'Anomalie constatée',
};

const Map<String, String> _unknownFieldLabels = <String, String>{
  'productLabel': 'la désignation du produit',
  'productReference': 'la référence produit',
  'expectedQuantity': 'la quantité attendue',
  'receivedQuantity': 'la quantité reçue',
  'affectedQuantity': 'la quantité affectée',
  'packagingCondition': "l'état de l'emballage",
  'productCondition': "l'état du produit",
  'locationOnItem': "la localisation sur l'article",
};

String _productReferenceClause(ConfirmedFactData fact) {
  final List<String> parts = <String>[];
  if (fact.productLabel != null && fact.productLabel!.isNotEmpty) {
    parts.add(fact.productLabel!);
  }
  if (fact.productReference != null && fact.productReference!.isNotEmpty) {
    parts.add('(référence ${fact.productReference})');
  }
  if (parts.isEmpty) {
    return 'produit non identifié à ce stade';
  }
  return parts.join(' ');
}

String _fmtNum(double value) {
  if (value == value.roundToDouble()) {
    return value.toInt().toString();
  }
  // Équivalent de Python `f"{value:g}"` : nombre de décimales minimal.
  String text = value.toString();
  if (text.contains('.')) {
    text = text.replaceFirst(RegExp(r'0+$'), '');
    text = text.replaceFirst(RegExp(r'\.$'), '');
  }
  return text;
}

String _quantityClause(ConfirmedFactData fact) {
  final double? expected = fact.expectedQuantity;
  final double? received = fact.receivedQuantity;
  final double? missing = fact.missingQuantity; // calculé par code uniquement
  if (expected == null && received == null) {
    return 'quantités non précisées à ce stade';
  }
  if (expected != null && received != null) {
    String clause =
        'quantité attendue ${_fmtNum(expected)}, quantité reçue ${_fmtNum(received)}';
    if (missing != null) {
      clause += ', écart constaté de ${_fmtNum(missing)}';
    }
    return clause;
  }
  if (expected != null) {
    return 'quantité attendue ${_fmtNum(expected)}, quantité reçue non précisée';
  }
  return 'quantité reçue ${_fmtNum(received!)}, quantité attendue non précisée';
}

String? _conditionClause(ConfirmedFactData fact) {
  final List<String> clauses = <String>[];
  if (fact.packagingCondition != null && fact.packagingCondition!.isNotEmpty) {
    clauses.add('emballage constaté : ${fact.packagingCondition}');
  }
  if (fact.productCondition != null && fact.productCondition!.isNotEmpty) {
    clauses.add('produit constaté : ${fact.productCondition}');
  }
  if (clauses.isEmpty) {
    return null;
  }
  return clauses.join('; ');
}

String? _unknownClause(ConfirmedFactData fact) {
  if (fact.unknownFields.isEmpty) {
    return null;
  }
  final List<String> labels = fact.unknownFields
      .map((String f) => _unknownFieldLabels[f] ?? f)
      .toList()
    ..sort();
  return 'Non déterminé à ce stade : ${labels.join(', ')}.';
}

String _capitalize(String value) {
  if (value.isEmpty) {
    return value;
  }
  return value[0].toUpperCase() + value.substring(1);
}

/// Compose le paragraphe déterministe pour UNE anomalie (un
/// ConfirmedFactData).
///
/// Précondition : `fact` a nécessairement `userConfirmed == true` (invariant
/// de type, voir `ConfirmedFactData`) ; ce module ne revalide pas cet
/// invariant. Précondition additionnelle depuis R0.1 : `fact` a déjà été
/// filtré par `lib/domain/liability_guard.dart::screenConfirmedFact` (fait
/// par `reserve_composer.composeReserve`, jamais par ce module directement).
String composeIssueParagraph(ConfirmedFactData fact) {
  final String label = _issueLabels[fact.issueType]!;
  final List<String> sentences = <String>[
    '$label - ${_productReferenceClause(fact)}.',
  ];

  if (fact.issueType == IssueType.missingQty || fact.issueType == IssueType.wrongQty) {
    sentences.add('${_capitalize(_quantityClause(fact))}.');
  }

  final String? condition = _conditionClause(fact);
  if (condition != null) {
    sentences.add('${_capitalize(condition)}.');
  }

  if (fact.locationOnItem != null && fact.locationOnItem!.isNotEmpty) {
    sentences.add('Localisation : ${fact.locationOnItem}.');
  }

  if (fact.affectedQuantity != null) {
    sentences.add('Quantité affectée : ${_fmtNum(fact.affectedQuantity!)}.');
  }

  final String? unknown = _unknownClause(fact);
  if (unknown != null) {
    sentences.add(unknown);
  }

  if (fact.userUncertainty) {
    sentences.add("L'utilisateur signale une incertitude résiduelle sur ces constats.");
  }

  return sentences.join(' ');
}

const String prudenceMentionFrV1 =
    'ReserveFlash vous aide à structurer vos constats et vos preuves. '
    "Il ne remplace pas un conseil juridique. Vérifiez les conditions applicables "
    'à votre transport et à vos contrats.';
