"""Catalogue controle des questions de clarification (schemas/candidate_fact_set.v1.schema.json,
champ `clarification_question_id` : "Reference a une question du catalogue
controle (section 7.1), jamais une question generee librement par le LLM.").

Ce module est la SEULE source de verite pour les identifiants valides. Le
LLM (app/infrastructure/ai/openai_provider.py) n'est jamais autorise a
produire directement une valeur de `clarification_question_id` : il peut au
plus indiquer, via un champ interne separe non expose dans
CandidateFactData, le NOM du champ candidat (`product_label`,
`received_quantity`, ...) sur lequel il a le plus d'incertitude - c'est le
code (`clarification_question_id_for_field` ci-dessous), jamais le modele,
qui traduit ce nom de champ en identifiant catalogue. Un nom de champ hors
de ce catalogue (halluciné ou mal orthographie par le modele) est
silencieusement ignore (retourne None) plutot que de laisser passer un
identifiant invente.
"""

from __future__ import annotations

# Un identifiant par champ V1 prioritaire (voir app/domain/fact_set.py,
# schemas/candidate_fact_set.v1.schema.json) susceptible de necessiter une
# clarification utilisateur, plus un identifiant dedie a issue_type_candidate
# lui-meme (cle speciale "issue_type_candidate", qui n'est pas une entree de
# `fields`).
CLARIFICATION_QUESTION_CATALOG: dict[str, str] = {
    "issue_type_candidate": "Q_ISSUE_TYPE_AMBIGUOUS",
    "product_label": "Q_PRODUCT_LABEL_MISSING",
    "product_reference": "Q_PRODUCT_REFERENCE_MISSING",
    "expected_quantity": "Q_EXPECTED_QUANTITY_MISSING",
    "received_quantity": "Q_RECEIVED_QUANTITY_MISSING",
    "affected_quantity": "Q_AFFECTED_QUANTITY_MISSING",
    "packaging_condition": "Q_PACKAGING_CONDITION_AMBIGUOUS",
    "product_condition": "Q_PRODUCT_CONDITION_AMBIGUOUS",
    "location_on_item": "Q_LOCATION_ON_ITEM_MISSING",
}


def clarification_question_id_for_field(field_name: str | None) -> str | None:
    """Traduit un nom de champ candidat en identifiant catalogue controle.

    Retourne None si `field_name` est None ou absent du catalogue (y compris
    un nom halluciné/mal orthographie par le LLM) - jamais une valeur
    inventee a la volee."""
    if field_name is None:
        return None
    return CLARIFICATION_QUESTION_CATALOG.get(field_name)
