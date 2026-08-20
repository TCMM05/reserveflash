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

class ForbiddenPattern {
  const ForbiddenPattern(this.violationCode, this.pattern);
  final String violationCode;
  final RegExp pattern;
}

// Motifs volontairement larges (faux positifs > faux négatifs) : ces champs
// ne doivent décrire QU'UN état physique constaté ("carton enfoncé"), jamais
// une cause, une conséquence juridique/financière, ou une partie
// responsable.
//
// R0.2 (hotfix decouvert par execution reelle du test suite sur un poste
// equipe - CORRIGE UNE SECONDE FOIS apres un premier correctif insuffisant,
// voir CHANGELOG.md) : `\b` de `package:dart:core` RegExp ne reconnait QUE
// les caracteres ASCII comme "mots" - CE COMPORTEMENT N'EST PAS CHANGE par
// `unicode: true` (contrairement a ce qu'un premier correctif supposait a
// tort : ce flag active seulement `\p{...}`/`\P{...}`, il ne rend PAS `\b`
// ou `\w` sensibles a l'Unicode - meme comportement qu'en JavaScript, dont
// Dart hérite la semantique RegExp). Consequence reelle, prouvee par des
// tests qui echouaient encore APRES le premier correctif ("unicode: true"
// seul) : "carton à la charge du fournisseur" (LIABILITY_ATTRIBUTION, le
// motif commence par "à"), "remboursement dû au client"
// (INDEMNIFICATION_PROMISE, le motif "dû" se termine par "û"), "vice caché
// constaté" (LEGAL_CONCLUSION, le motif "caché" se termine par "é") -
// autrement dit le garde-fou laissait passer silencieusement exactement le
// type de formulation qu'il est censé bloquer, des que la formulation
// commençait ou finissait par une lettre accentuee.
//
// Correctif REEL : remplacer `\b` par des lookaround explicites sur la
// categorie Unicode "Lettre" (`\p{L}`) + chiffre/underscore, qui EUX sont
// bien Unicode-aware des lors que `unicode: true` est actif (c'est là son
// vrai role). `(?<![\p{L}\p{N}_])` = pas précédé d'un caractère de mot
// Unicode ; `(?![\p{L}\p{N}_])` = pas suivi d'un caractère de mot Unicode.
// R2 : rendu public (était `_forbiddenPatterns`) pour être réutilisé par
// `lib/domain/candidate_guard.dart` - même principe que le backend, où
// `app/domain/liability_guard.py::_FORBIDDEN_PATTERNS` a été renommé
// `FORBIDDEN_PATTERNS` pour la même raison (source unique de vérité sur "ce
// qu'est un contenu interdit", partagée entre le filtrage post-confirmation
// et le filtrage pré-revue des candidats IA).
final List<ForbiddenPattern> forbiddenPatterns = <ForbiddenPattern>[
  ForbiddenPattern(
    'LIABILITY_ATTRIBUTION',
    RegExp(
      r'(?<![\p{L}\p{N}_])(responsab(le|ilité)s?|fautifs?|faute|'
      r'imputable(\s+(au|à|aux))?|'
      r'à\s+la\s+charge\s+(du|de|des)|'
      r'de\s+la\s+faute\s+(du|de|des)|'
      r'engage\s+sa\s+responsabilité)(?![\p{L}\p{N}_])',
      caseSensitive: false,
      unicode: true,
    ),
  ),
  ForbiddenPattern(
    'INDEMNIFICATION_PROMISE',
    RegExp(
      // R0.2 (hotfix decouvert par execution reelle, troisieme vague) :
      // meme bug racine que les lookaround ci-dessus, mais a l'INTERIEUR
      // du motif cette fois - `\w` (utilise par `indemnis\w*`/
      // `dédommag\w*`) est LUI AUSSI ASCII-only en Dart (`[A-Za-z0-9_]`),
      // `unicode: true` ne change pas non plus ce comportement. Sur
      // "indemnisé" (avec un "é" APRES le radical "indemnis"), `\w*`
      // s'arretait avant le "é", puis le lookahead Unicode-aware
      // `(?![\p{L}\p{N}_])` juste apres refusait la position car "é" EST
      // un caractere de mot Unicode (`\p{L}`) - contradiction entre un
      // `\w*` ASCII et une frontiere verifiee en Unicode. Preuve reelle :
      // le test "sera indemnisé intégralement" ne levait plus
      // l'exception (`Actual: returned <null>`). Corrige en remplacant
      // `\w*` par `[\p{L}\p{N}_]*`, Unicode-aware au meme titre que les
      // lookaround de frontiere.
      r'(?<![\p{L}\p{N}_])(indemnis[\p{L}\p{N}_]*|dédommag[\p{L}\p{N}_]*|remboursera|'
      r'remboursement\s+(dû|du|garanti)|'
      r'prise\s+en\s+charge\s+financière)(?![\p{L}\p{N}_])',
      caseSensitive: false,
      unicode: true,
    ),
  ),
  ForbiddenPattern(
    'LEGAL_CONCLUSION',
    RegExp(
      r'(?<![\p{L}\p{N}_])(manquement\s+contractuel|inexécution\s+contractuelle|'
      r'violation\s+du\s+contrat|vice\s+caché|négligence|'
      r"défaut\s+d.exécution|obligation\s+de\s+résultat)(?![\p{L}\p{N}_])",
      caseSensitive: false,
      unicode: true,
    ),
  ),
  ForbiddenPattern(
    'INVENTED_AMOUNT',
    RegExp(
      r'(\d+[.,]?\d*\s?(€|eur\b|euros?)|montant\s+de\s+\d)',
      caseSensitive: false,
      unicode: true,
    ),
  ),
  ForbiddenPattern(
    'LEGAL_QUALIFICATION',
    RegExp(
      r'(?<![\p{L}\p{N}_])(délit|infraction|faute\s+lourde|force\s+majeure|'
      r'non[\s-]conformité\s+contractuelle|vice\s+de\s+forme)(?![\p{L}\p{N}_])',
      caseSensitive: false,
      unicode: true,
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
    for (final ForbiddenPattern forbidden in forbiddenPatterns) {
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
