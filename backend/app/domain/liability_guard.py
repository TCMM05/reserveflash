"""Garde-fou deterministe anti-attribution de responsabilite (R0.1, point 8
de la demande corrective "Local-First").

Bug corrige ici : la baseline R0 laissait `packaging_condition` et
`product_condition` (champs texte libre de `ConfirmedFactData`) totalement
libres de contenu. Rien n'empechait un utilisateur - ou une reparation IA
mal cadree en amont - de saisir par exemple :

    packaging_condition = "transporteur responsable"

Ce texte etant confirme (`user_confirmed=True`), il passait tel quel dans
`app.domain.templates.fr_v1._condition_clause()` et ressortait donc,
verbatim, dans la reserve finale generee par
`app.domain.reserve_composer.compose_reserve()` - alors meme que la GATE
zero-invention (section 2.4) et l'interdiction stricte du cahier des charges
("Aucune reserve ne doit jamais contenir : une attribution de faute ou de
responsabilite, une promesse d'indemnisation, une conclusion juridique, un
montant de reparation ou d'indemnisation invente, une qualification
juridique creee par l'IA") s'appliquent A LA RESERVE FINALE, quelle que soit
la provenance du texte (utilisateur, IA, ou les deux).

Principe de la correction : un ConfirmedFactData "confirme par l'utilisateur"
(invariant 6.3) garantit uniquement que l'utilisateur a valide la VALEUR du
champ, pas que cette valeur respecte le perimetre autorise d'une reserve
descriptive (constat factuel neutre). Ce module ajoute donc une deuxieme
barriere, independante de la confirmation utilisateur, appliquee :

  1. au moment de la confirmation (F09, voir
     app.application.use_cases.confirm_facts) pour un retour immediat a
     l'utilisateur ;
  2. juste AVANT app.domain.reserve_composer.compose_reserve(), en defense
     en profondeur - explicitement demande par le cahier des charges
     ("garde-fou deterministe AVANT le Reserve Composer") - de sorte
     qu'aucun chemin de code, present ou futur, ne puisse contourner l'appel
     (1) et laisser passer un contenu interdit.

Deterministe : regex figees, aucun appel IA/reseau. Memes entrees => meme
verdict a l'identique, pour toute relecture/audit (meme invariant que le
Reserve Composer lui-meme, cf. app/domain/reserve_composer.py).

Volontairement PAS de sanitization automatique (on ne reecrit jamais
silencieusement le texte d'un utilisateur) : le systeme rejette et demande a
l'utilisateur de reformuler en constat factuel neutre, conformement au
principe "aucune conclusion juridique generee par le systeme" (section 1.4).
"""

from __future__ import annotations

import re
from collections.abc import Sequence

from app.domain.errors import LiabilityAttributionError
from app.domain.fact_set import ConfirmedFactData

# Champs texte libre de ConfirmedFactData susceptibles de contenir une
# formulation utilisateur non contrainte (les autres champs sont soit des
# enums/nombres, soit calcules par code - voir app/domain/fact_set.py).
FREE_TEXT_FIELDS: tuple[str, ...] = (
    "packaging_condition",
    "product_condition",
    "location_on_item",
    "product_label",
    "product_reference",
)

# Chaque motif est deliberement large (faux positifs > faux negatifs) : ces
# champs ne doivent decrire QUE un etat physique constate ("carton enfonce",
# "produit raye"), jamais une cause, une consequence juridique/financiere ou
# une partie responsable. Un rejet legitime mais trop strict se corrige en
# reformulant le constat ; un contenu interdit qui fuite dans une reserve
# signee ne se corrige pas.
#
# R2 (voir app/domain/candidate_guard.py) : ces motifs sont desormais
# PUBLICS et partages avec le garde-fou applique aux CandidateFactData
# (sortie brute IA, avant toute confirmation utilisateur). Une seule source
# de verite pour "qu'est-ce qu'un contenu interdit dans une reserve" evite
# qu'un motif ajoute/corrige d'un cote (ex: nouvelle formulation de
# responsabilite reperee lors du benchmark R2) ne soit pas applique de
# l'autre.
FORBIDDEN_PATTERNS: dict[str, re.Pattern[str]] = {
    "LIABILITY_ATTRIBUTION": re.compile(
        r"\b(responsab(?:le|ilité)s?|fautifs?|\bfaute\b|"
        r"imputable(?:\s+(?:au|à|aux))?|"
        r"à\s+la\s+charge\s+(?:du|de|des)|"
        r"de\s+la\s+faute\s+(?:du|de|des)|"
        r"engage\s+sa\s+responsabilité)\b",
        re.IGNORECASE,
    ),
    "INDEMNIFICATION_PROMISE": re.compile(
        r"\b(indemnis\w*|dédommag\w*|remboursera|"
        r"remboursement\s+(?:dû|du|garanti)|"
        r"prise\s+en\s+charge\s+financière)\b",
        re.IGNORECASE,
    ),
    "LEGAL_CONCLUSION": re.compile(
        r"\b(manquement\s+contractuel|inexécution\s+contractuelle|"
        r"violation\s+du\s+contrat|vice\s+caché|négligence|"
        r"défaut\s+d.exécution|obligation\s+de\s+résultat)\b",
        re.IGNORECASE,
    ),
    "INVENTED_AMOUNT": re.compile(
        r"(\d+[.,]?\d*\s?(?:€|eur\b|euros?)|montant\s+de\s+\d)",
        re.IGNORECASE,
    ),
    "LEGAL_QUALIFICATION": re.compile(
        r"\b(délit|infraction|faute\s+lourde|force\s+majeure|"
        r"non[\s-]conformité\s+contractuelle|vice\s+de\s+forme)\b",
        re.IGNORECASE,
    ),
}


def screen_confirmed_fact(fact: ConfirmedFactData) -> None:
    """Leve LiabilityAttributionError si un champ texte libre de `fact`
    contient un motif interdit. Ne modifie jamais la donnee (pas de
    sanitization silencieuse)."""
    for field_name in FREE_TEXT_FIELDS:
        value = getattr(fact, field_name, None)
        if not value or not isinstance(value, str):
            continue
        for violation_code, pattern in FORBIDDEN_PATTERNS.items():
            match = pattern.search(value)
            if match:
                raise LiabilityAttributionError(
                    f"Le champ '{field_name}' contient un contenu interdit dans "
                    f"une reserve ({violation_code}) : « {match.group(0)} ». "
                    "Reformulez ce champ en constat factuel neutre (etat physique "
                    "observe uniquement), sans attribution de responsabilite, "
                    "promesse d'indemnisation, conclusion ou qualification "
                    "juridique, ni montant.",
                    violation_code=violation_code,
                    field_name=field_name,
                )


def screen_confirmed_facts(facts: Sequence[ConfirmedFactData]) -> None:
    """Applique `screen_confirmed_fact` a chaque fait. Utilise en defense en
    profondeur juste avant `reserve_composer.compose_reserve()` (voir
    docstring du module)."""
    for fact in facts:
        screen_confirmed_fact(fact)
