"""Reserve Composer - GATE zéro invention (section 2.4).

  "Le Reserve Composer est un composant déterministe. Il ne reçoit pas le
  texte libre utilisateur ni la réponse brute LLM ; seulement le
  ConfirmedFactSet typé."

Ce module est volontairement le SEUL point d'entrée pour produire un
`ReserveText`. Il n'importe aucun provider IA, aucun client HTTP : seulement
des `ConfirmedFactData` (déjà validés `user_confirmed=True` par construction,
voir app/domain/fact_set.py) et un registre de templates versionnés.

Invariant vérifié ici (section 6.3 + 15.2) :
  "Reserve finale contenant un fait non confirmé" doit toujours valoir 0.
Comme ConfirmedFactData ne peut pas exister avec user_confirmed=False (le
validateur pydantic lève avant), ce module n'a pas besoin de revalider ce
point — mais le test d'intégration (tests/domain/test_reserve_composer.py)
le vérifie explicitement pour non-régression.

Deuxième invariant vérifié ici depuis R0.1 (correctif point 8 de la demande
"Local-First") : une réserve ne doit jamais pouvoir contenir une attribution
de responsabilité, une promesse d'indemnisation, une conclusion/qualification
juridique ou un montant inventé - même si ce contenu provient d'un champ
« confirmé » par l'utilisateur (ex: packaging_condition = "transporteur
responsable"). Voir app.domain.liability_guard pour le détail du bug corrigé
et le raisonnement. L'appel ci-dessous est fait ICI, dans l'unique point
d'entrée de composition, pour qu'aucun appelant (présent ou futur) ne puisse
l'oublier.
"""

from __future__ import annotations

import hashlib
from collections.abc import Callable, Sequence
from dataclasses import dataclass

from app.domain.errors import TemplateNotFoundError
from app.domain.fact_set import ConfirmedFactData
from app.domain.liability_guard import screen_confirmed_facts
from app.domain.templates import fr_v1

# Registre des templates versionnés par langue (section 2.4). Ajouter une
# langue = ajouter une entrée ici, jamais modifier fr_v1 en place (une
# modification de rendu doit créer fr_v2 pour ne pas invalider les réserves
# déjà générées - invariant "reconstructible à l'identique").
_TEMPLATE_REGISTRY: dict[str, Callable[[ConfirmedFactData], str]] = {
    fr_v1.TEMPLATE_VERSION: fr_v1.compose_issue_paragraph,
}

_PRUDENCE_MENTION_REGISTRY: dict[str, str] = {
    fr_v1.TEMPLATE_VERSION: fr_v1.PRUDENCE_MENTION,
}


@dataclass(frozen=True, slots=True)
class ComposedReserve:
    """Résultat déterministe de la composition. `sha256` permet de vérifier
    qu'une réserve n'a pas été altérée après génération (voir ExportBundle,
    section 6.1) et de détecter une révision de faits non répercutée
    (invariant "une révision de faits confirmés invalide automatiquement la
    réserve et le PDF précédents")."""

    text: str
    template_version: str
    prudence_mention: str
    sha256: str


def compose_reserve(
    facts: Sequence[ConfirmedFactData],
    template_version: str = fr_v1.TEMPLATE_VERSION,
) -> ComposedReserve:
    """Compose la réserve globale ordonnée à partir d'un ou plusieurs
    `ConfirmedFactData` (section 2.5 - incidents multiples : "1 colis
    manquant + 2 cartons écrasés + 1 produit rayé").

    Déterministe : mêmes faits + même version de template => même texte et
    même hash, à l'identique, pour toute relecture ou audit.
    """
    if template_version not in _TEMPLATE_REGISTRY:
        raise TemplateNotFoundError(
            f"Aucun template de réserve pour la version '{template_version}'."
        )
    if not facts:
        raise ValueError("compose_reserve requiert au moins un ConfirmedFactData.")

    # Garde-fou déterministe R0.1 (point 8) : lève LiabilityAttributionError
    # AVANT toute composition si un champ confirmé contient une attribution
    # de responsabilité, une promesse d'indemnisation, une conclusion/
    # qualification juridique ou un montant inventé. Voir
    # app.domain.liability_guard pour le détail.
    screen_confirmed_facts(facts)

    paragraph_fn = _TEMPLATE_REGISTRY[template_version]
    paragraphs = [paragraph_fn(fact) for fact in facts]
    text = "\n\n".join(paragraphs)
    digest = hashlib.sha256(text.encode("utf-8")).hexdigest()

    return ComposedReserve(
        text=text,
        template_version=template_version,
        prudence_mention=_PRUDENCE_MENTION_REGISTRY[template_version],
        sha256=digest,
    )
