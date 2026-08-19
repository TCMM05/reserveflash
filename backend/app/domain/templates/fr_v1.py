"""Template de réserve FR, version fr_v1 (section 2.4 - "Templates versionnés
par langue et type d'incident").

Règles strictes appliquées ici (GATE zéro invention, section 2.4) :
  - Aucun adjectif de gravité ("inutilisable", "dangereux", "détruit") n'est
    généré par ce module ; seules les valeurs de `packaging_condition` /
    `product_condition` telles que confirmées par l'utilisateur sont citées.
  - Aucune attribution de faute ou de responsabilité.
  - Aucune mention de montant, indemnisation ou obligation juridique.
  - Un champ marqué UNKNOWN par l'utilisateur reste explicitement signalé
    comme non déterminé ; il n'est jamais tu ni inventé.

Pour une même entrée (ConfirmedFactData) et une même version de template, la
sortie est strictement identique (déterministe, pas d'appel LLM, pas
d'horodatage dans le texte).
"""

from __future__ import annotations

from app.domain.fact_set import ConfirmedFactData
from app.domain.value_objects import IssueType

TEMPLATE_VERSION = "fr_v1"

_ISSUE_LABELS: dict[IssueType, str] = {
    IssueType.PACKAGING_DAMAGE: "Dommage sur l'emballage",
    IssueType.PRODUCT_DAMAGE: "Dommage sur le produit",
    IssueType.MISSING_QTY: "Quantité manquante",
    IssueType.WRONG_QTY: "Quantité incorrecte",
    IssueType.WRONG_PRODUCT: "Produit non conforme à la commande",
    IssueType.VISIBLE_NONCONFORMITY: "Non-conformité visible",
    IssueType.OTHER: "Anomalie constatée",
}

_UNKNOWN_FIELD_LABELS: dict[str, str] = {
    "product_label": "la désignation du produit",
    "product_reference": "la référence produit",
    "expected_quantity": "la quantité attendue",
    "received_quantity": "la quantité reçue",
    "affected_quantity": "la quantité affectée",
    "packaging_condition": "l'état de l'emballage",
    "product_condition": "l'état du produit",
    "location_on_item": "la localisation sur l'article",
}


def _product_reference_clause(fact: ConfirmedFactData) -> str:
    parts: list[str] = []
    if fact.product_label:
        parts.append(fact.product_label)
    if fact.product_reference:
        parts.append(f"(référence {fact.product_reference})")
    if not parts:
        return "produit non identifié à ce stade"
    return " ".join(parts)


def _quantity_clause(fact: ConfirmedFactData) -> str:
    expected = fact.expected_quantity
    received = fact.received_quantity
    missing = fact.missing_quantity  # calculé par code, jamais par le LLM
    if expected is None and received is None:
        return "quantités non précisées à ce stade"
    if expected is not None and received is not None:
        clause = f"quantité attendue {_fmt_num(expected)}, quantité reçue {_fmt_num(received)}"
        if missing is not None:
            clause += f", écart constaté de {_fmt_num(missing)}"
        return clause
    if expected is not None:
        return f"quantité attendue {_fmt_num(expected)}, quantité reçue non précisée"
    return f"quantité reçue {_fmt_num(received)}, quantité attendue non précisée"


def _fmt_num(value: float) -> str:
    if float(value).is_integer():
        return str(int(value))
    return f"{value:g}"


def _condition_clause(fact: ConfirmedFactData) -> str | None:
    clauses: list[str] = []
    if fact.packaging_condition:
        clauses.append(f"emballage constaté : {fact.packaging_condition}")
    if fact.product_condition:
        clauses.append(f"produit constaté : {fact.product_condition}")
    if not clauses:
        return None
    return "; ".join(clauses)


def _unknown_clause(fact: ConfirmedFactData) -> str | None:
    if not fact.unknown_fields:
        return None
    labels = [_UNKNOWN_FIELD_LABELS.get(f, f) for f in fact.unknown_fields]
    return "Non déterminé à ce stade : " + ", ".join(sorted(labels)) + "."


def compose_issue_paragraph(fact: ConfirmedFactData) -> str:
    """Compose le paragraphe déterministe pour UNE anomalie (un ConfirmedFactData).

    Précondition : fact.user_confirmed est déjà garanti True par le modèle
    pydantic (voir ConfirmedFactData._enforce_user_confirmed) ; ce module ne
    revalide pas cet invariant, il fait confiance au type.
    """
    label = _ISSUE_LABELS[fact.issue_type]
    sentences: list[str] = [f"{label} - {_product_reference_clause(fact)}."]

    if fact.issue_type in (IssueType.MISSING_QTY, IssueType.WRONG_QTY):
        sentences.append(_quantity_clause(fact).capitalize() + ".")

    condition = _condition_clause(fact)
    if condition:
        sentences.append(condition.capitalize() + ".")

    if fact.location_on_item:
        sentences.append(f"Localisation : {fact.location_on_item}.")

    if fact.affected_quantity is not None:
        sentences.append(f"Quantité affectée : {_fmt_num(fact.affected_quantity)}.")

    unknown = _unknown_clause(fact)
    if unknown:
        sentences.append(unknown)

    if fact.user_uncertainty:
        sentences.append("L'utilisateur signale une incertitude résiduelle sur ces constats.")

    return " ".join(sentences)


PRUDENCE_MENTION = (
    "ReserveFlash vous aide à structurer vos constats et vos preuves. "
    "Il ne remplace pas un conseil juridique. Vérifiez les conditions applicables "
    "à votre transport et à vos contrats."
)
