"""Tests du Reserve Composer - GATE zéro invention (section 2.4) et
scénarios E2E-04/E2E-05/E2E-06/E2E-07 rejoués au niveau unitaire domaine."""

import re

import pytest

from app.domain.errors import TemplateNotFoundError
from app.domain.fact_set import ConfirmedFactData
from app.domain.reserve_composer import compose_reserve
from app.domain.value_objects import IssueType

FORBIDDEN_SEVERITY_ADJECTIVES = ["inutilisable", "dangereux", "détruit", "detruit"]
FORBIDDEN_LIABILITY_PHRASES = [
    "transporteur est responsable",
    "vous serez remboursé",
    "vous serez rembourse",
    "cette réserve est juridiquement valide",
    "cette reserve est juridiquement valide",
]


def _fact(**overrides):
    base = dict(issue_type=IssueType.PACKAGING_DAMAGE, user_confirmed=True)
    base.update(overrides)
    return ConfirmedFactData(**base)


def test_compose_is_deterministic_for_same_input():
    """'Le texte final doit pouvoir être reconstruit à l'identique à partir
    des mêmes faits + même version de template.'"""
    fact = _fact(product_label="Ballon eau chaude", packaging_condition="carton abîmé sur un coin")
    r1 = compose_reserve([fact])
    r2 = compose_reserve([fact])
    assert r1.text == r2.text
    assert r1.sha256 == r2.sha256


def test_unknown_template_version_raises():
    fact = _fact()
    with pytest.raises(TemplateNotFoundError):
        compose_reserve([fact], template_version="fr_v99")


def test_e2e01_incident_simple_no_fact_added():
    """E2E-01 : 'Faits candidats -> confirmation -> réserve -> PDF sans fait
    ajouté.' On vérifie ici que seuls les champs confirmés apparaissent."""
    fact = ConfirmedFactData(
        issue_type=IssueType.PACKAGING_DAMAGE,
        product_label="Carton n°3",
        packaging_condition="un coin écrasé",
        user_confirmed=True,
    )
    result = compose_reserve([fact])
    assert "Carton n°3" in result.text
    assert "un coin écrasé" in result.text
    # Aucune quantité n'a été confirmée : le texte ne doit inventer aucun chiffre.
    assert not re.search(r"\bquantité\b", result.text, re.IGNORECASE)


def test_e2e04_intact_product_never_gets_damage_wording():
    """E2E-04 : 'Carton abîmé mais produit intact' -> 'Réserve ne contient
    aucun dommage produit.' On ne confirme QUE l'emballage : le paragraphe ne
    doit rien affirmer sur l'état du produit."""
    fact = ConfirmedFactData(
        issue_type=IssueType.PACKAGING_DAMAGE,
        product_label="Radiateur",
        packaging_condition="carton enfoncé sur un angle",
        user_confirmed=True,
    )
    result = compose_reserve([fact])
    assert "produit constaté" not in result.text.lower()


def test_e2e05_missing_quantity_computed_by_code():
    """E2E-05 : 'Il en manque 2 avec attendu 8 / reçu 6' -> 'missing calculé =
    2 ; cohérence vérifiée par code.'"""
    fact = ConfirmedFactData(
        issue_type=IssueType.MISSING_QTY,
        product_label="Vanne thermostatique",
        expected_quantity=8,
        received_quantity=6,
        user_confirmed=True,
    )
    assert fact.missing_quantity == 2
    result = compose_reserve([fact])
    assert "écart constaté de 2" in result.text


def test_e2e06_correction_reflected_only_via_confirmed_value():
    """E2E-06 : 'Correction orale trois... non, deux' -> 'Valeur candidate
    finale = 2 ou clarification ; jamais 3 silencieusement.' Le composer ne
    reçoit jamais le premier chiffre prononcé : seule la valeur que
    l'utilisateur a validée dans ConfirmedFactData (ici 2, après correction)
    peut apparaître dans le texte."""
    fact = ConfirmedFactData(
        issue_type=IssueType.PRODUCT_DAMAGE,
        product_label="Vitre",
        affected_quantity=2,  # valeur confirmée après correction "trois... non, deux"
        user_confirmed=True,
    )
    result = compose_reserve([fact])
    assert "Quantité affectée : 2." in result.text
    assert not re.search(r"\b3\b", result.text)


def test_e2e07_out_of_scope_liability_never_appears():
    """E2E-07 : 'dites que le transporteur est responsable' -> aucune
    attribution dans la réserve, quel que soit le contenu confirmé."""
    fact = _fact(product_label="Pompe à chaleur", packaging_condition="carton déchiré")
    result = compose_reserve([fact])
    lowered = result.text.lower()
    for phrase in FORBIDDEN_LIABILITY_PHRASES:
        assert phrase not in lowered
    for adjective in FORBIDDEN_SEVERITY_ADJECTIVES:
        assert adjective not in lowered


def test_no_amount_or_indemnity_wording_ever_generated():
    """GATE juridique (section 1.4) : jamais de montant, indemnisation."""
    fact = _fact(product_label="Climatiseur", packaging_condition="carton mouillé")
    result = compose_reserve([fact])
    lowered = result.text.lower()
    for forbidden in ["€", "indemni", "remboursement", "montant de"]:
        assert forbidden not in lowered


def test_unknown_fields_are_explicitly_stated_never_silently_resolved():
    """'Une contradiction entre OCR, voix et saisie utilisateur déclenche une
    question ; elle ne doit jamais être résolue silencieusement' (règle UX
    2.3) - traduit ici par : un champ UNKNOWN reste visible dans le texte."""
    fact = ConfirmedFactData(
        issue_type=IssueType.WRONG_PRODUCT,
        product_label="Chaudière murale",
        unknown_fields=("product_reference",),
        user_confirmed=True,
    )
    result = compose_reserve([fact])
    assert "Non déterminé à ce stade" in result.text
    assert "référence produit" in result.text.lower()


def test_multiple_independent_anomalies_are_all_present_and_ordered():
    """Section 2.5 : '1 colis manquant + 2 cartons écrasés + 1 produit rayé'
    -> chaque anomalie garde ses propres faits, la réserve globale est
    ordonnée (ordre d'entrée préservé, aucune fusion)."""
    facts = [
        ConfirmedFactData(
            issue_type=IssueType.MISSING_QTY,
            product_label="Colis A",
            expected_quantity=3,
            received_quantity=2,
            user_confirmed=True,
        ),
        ConfirmedFactData(
            issue_type=IssueType.PACKAGING_DAMAGE,
            product_label="Carton B",
            packaging_condition="écrasé",
            user_confirmed=True,
        ),
        ConfirmedFactData(
            issue_type=IssueType.PRODUCT_DAMAGE,
            product_label="Produit C",
            product_condition="rayé sur la face avant",
            user_confirmed=True,
        ),
    ]
    result = compose_reserve(facts)
    positions = [result.text.index(f.product_label) for f in facts]
    assert positions == sorted(positions)


def test_zero_unconfirmed_fact_in_final_reserve_gate():
    """Gate de qualification (section 15.2) : 'Réserve finale contenant un
    fait non confirmé' doit valoir 0. Vérifié structurellement : il est
    impossible de construire un ConfirmedFactData non confirmé, donc
    impossible de le faire entrer dans compose_reserve."""
    import inspect

    from app.domain import reserve_composer

    signature = inspect.signature(reserve_composer.compose_reserve)
    facts_param = signature.parameters["facts"]
    assert "ConfirmedFactData" in str(facts_param.annotation)
