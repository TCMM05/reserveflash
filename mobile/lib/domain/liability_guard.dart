/// Garde-fou déterministe anti-attribution de responsabilité - miroir Dart
/// de `backend/app/domain/liability_guard.py`.
///
/// Depuis R0.1 (pivot Local-First), le Reserve Composer tourne sur
/// l'appareil (voir `lib/domain/reserve_composer.dart`) pour permettre la
/// génération du dossier hors ligne (point 6 de la demande corrective). Ce
/// garde-fou doit donc exister ICI, côté Dart, et pas seulement côté
/// backend : sans lui, le bug corrigé en R0.1 (packagingCondition =
/// "transporteur responsable" traversant jusqu'à la réserve finale) serait
/// réintroduit dès qu'un utilisateur génère une réserve sans connexion.
///
/// Les deux implémentations (Python et Dart) DOIVENT rester alignées :
/// mêmes catégories de violation, mêmes champs surveillés. Toute
/// modification ici doit être répercutée dans
/// `backend/app/domain/liability_guard.py` et vice-versa (voir
/// docs/architecture.md, section "duplication contrôlée du Reserve
/// Composer").
///
/// Déterministe : expressions régulières figées, aucun appel réseau/IA.
/// Volontairement PAS de sanitization automatique : on rejette et on
/// demande à l'utilisateur de reformuler en constat factuel neutre.
library;

import 'errors/domain_errors.dart';
import 'fact_set/confirmed_fact_data.dart';

/// Champs texte libre de [ConfirmedFactData] susceptibles de contenir une
/// formulation utilisateur non contrainte.
const List<String> liabilityGuardFreeTextFields = <String>[
  'packagingCondition',
  'productCondition',
  'locationOnItem',
  'productLabel',
  'productReference',
];

class _ForbiddenPattern {
  const _ForbiddenPattern(this.violationCode, this.pattern);
  final String violationCode;
  final RegExp pattern;
}

// Motifs volontairement larges (faux positifs > faux négatifs) : ces champs
// ne doivent décrire QU'UN état physique constaté ("carton enfoncé"), jamais
// une cause, une conséquence juridique/financière, ou une partie
// responsable.
final List<_ForbiddenPattern> _forbiddenPatterns = <_ForbiddenPattern>[
  _ForbiddenPattern(
    'LIABILITY_ATTRIBUTION',
    RegExp(
      r'\b(responsab(le|ilité)s?|fautifs?|faute|'
      r'imputable(\s+(au|à|aux))?|'
      r'à\s+la\s+charge\s+(du|de|des)|'
      r'de\s+la\s+faute\s+(du|de|des)|'
      r'engage\s+sa\s+responsabilité)\b',
      caseSensitive: false,
    ),
  ),
  _ForbiddenPattern(
    'INDEMNIFICATION_PROMISE',
    RegExp(
      r'\b(indemnis\w*|dédommag\w*|remboursera|'
      r'remboursement\s+(dû|du|garanti)|'
      r'prise\s+en\s+charge\s+financière)\b',
      caseSensitive: false,
    ),
  ),
  _ForbiddenPattern(
    'LEGAL_CONCLUSION',
    RegExp(
      r'\b(manquement\s+contractuel|inexécution\s+contractuelle|'
      r'violation\s+du\s+contrat|vice\s+caché|négligence|'
      r"défaut\s+d.exécution|obligation\s+de\s+résultat)\b",
      caseSensitive: false,
    ),
  ),
  _ForbiddenPattern(
    'INVENTED_AMOUNT',
    RegExp(
      r'(\d+[.,]?\d*\s?(€|eur\b|euros?)|montant\s+de\s+\d)',
      caseSensitive: false,
    ),
  ),
  _ForbiddenPattern(
    'LEGAL_QUALIFICATION',
    RegExp(
      r'\b(délit|infraction|faute\s+lourde|force\s+majeure|'
      r'non[\s-]conformité\s+contractuelle|vice\s+de\s+forme)\b',
      caseSensitive: false,
    ),
  ),
];

String? _fieldValue(ConfirmedFactData fact, String fieldName) {
  switch (fieldName) {
    case 'packagingCondition':
      return fact.packagingCondition;
    case 'productCondition':
      return fact.productCondition;
    case 'locationOnItem':
      return fact.locationOnItem;
    case 'productLabel':
      return fact.productLabel;
    case 'productReference':
      return fact.productReference;
    default:
      return null;
  }
}

/// Lève [LiabilityAttributionException] si un champ texte libre de [fact]
/// contient un motif interdit. Ne modifie jamais la donnée.
void screenConfirmedFact(ConfirmedFactData fact) {
  for (final String fieldName in liabilityGuardFreeTextFields) {
    final String? value = _fieldValue(fact, fieldName);
    if (value == null || value.isEmpty) {
      continue;
    }
    for (final _ForbiddenPattern forbidden in _forbiddenPatterns) {
      final RegExpMatch? match = forbidden.pattern.firstMatch(value);
      if (match != null) {
        throw LiabilityAttributionException(
          "Le champ '$fieldName' contient un contenu interdit dans une "
          'réserve (${forbidden.violationCode}) : « ${match.group(0)} ». '
          'Reformulez ce champ en constat factuel neutre (état physique '
          'observé uniquement), sans attribution de responsabilité, '
          "promesse d'indemnisation, conclusion ou qualification juridique, "
          'ni montant.',
          violationCode: forbidden.violationCode,
          fieldName: fieldName,
        );
      }
    }
  }
}

/// Applique [screenConfirmedFact] à chaque fait. Utilisé en défense en
/// profondeur juste avant `reserve_composer.composeReserve()`.
void screenConfirmedFacts(List<ConfirmedFactData> facts) {
  for (final ConfirmedFactData fact in facts) {
    screenConfirmedFact(fact);
  }
}
