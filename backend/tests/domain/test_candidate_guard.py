"""Tests du garde-fou applique aux CandidateFactData (R2, "Validation
semantique obligatoire"). Rejoue explicitement l'exemple toujours interdit
donne par l'equipe : `packaging_condition = "transporteur responsable"` ne
doit jamais atteindre l'ecran de revue, meme comme simple *proposition*
candidate (pas encore confirmee)."""

from __future__ import annotations

import pytest

from app.domain.candidate_guard import screen_candidate_fact_data
from app.domain.fact_set import CandidateFactData
from app.domain.value_objects import ConfidenceLevel, FactSource, IssueType


def _field(value, *, source=FactSource.VOICE_TRANSCRIPT, confidence=ConfidenceLevel.HIGH):
    return {"value": value, "source": source, "confidence": confidence}


def _candidate(fields: dict, *, requires_review: bool = False) -> CandidateFactData:
    return CandidateFactData(
        issue_type_candidate=IssueType.PACKAGING_DAMAGE,
        fields=fields,
        requires_review=requires_review,
    )


# --- Cas nommement cite par l'equipe ---------------------------------------


def test_reported_example_transporteur_responsable_is_stripped_from_candidate():
    candidate = _candidate(
        {
            "packaging_condition": _field("transporteur responsable"),
            "product_label": _field("PAC-284"),
        }
    )
    screened = screen_candidate_fact_data(candidate)
    assert "packaging_condition" not in screened.fields
    assert "product_label" in screened.fields
    assert screened.requires_review is True


def test_last_liability_example_extracts_material_facts_without_the_conclusion():
    """« C'est clairement la faute du transporteur » doit pouvoir laisser
    passer des faits materiels utiles (ex: un produit_label deja identifie
    par ailleurs) sans jamais laisser passer une reformulation de la
    conclusion de responsabilite elle-meme dans un champ."""
    candidate = _candidate(
        {
            "product_condition": _field("c'est clairement la faute du transporteur"),
            "product_label": _field("PAC-284"),
        }
    )
    screened = screen_candidate_fact_data(candidate)
    assert "product_condition" not in screened.fields
    assert screened.fields["product_label"].value == "PAC-284"


# --- Autres motifs interdits (memes categories que liability_guard) -------


@pytest.mark.parametrize(
    "text",
    [
        "le transporteur devra indemniser le client",
        "manquement contractuel du fournisseur",
        "dommage estime a 350 euros",
        "cas de force majeure",
    ],
)
def test_various_forbidden_patterns_are_stripped(text):
    candidate = _candidate({"packaging_condition": _field(text)})
    screened = screen_candidate_fact_data(candidate)
    assert "packaging_condition" not in screened.fields
    assert screened.requires_review is True


def test_neutral_factual_description_is_kept_untouched():
    candidate = _candidate({"packaging_condition": _field("carton enfonce sur un coin")})
    screened = screen_candidate_fact_data(candidate)
    assert screened.fields["packaging_condition"].value == "carton enfonce sur un coin"
    assert screened is candidate  # aucune copie si rien n'est retire


# --- Coherence des quantites -----------------------------------------------


@pytest.mark.parametrize(
    "field_name", ["expected_quantity", "received_quantity", "affected_quantity"]
)
def test_negative_quantity_is_stripped(field_name):
    candidate = _candidate({field_name: _field(-2, source=FactSource.LLM_NORMALIZATION)})
    screened = screen_candidate_fact_data(candidate)
    assert field_name not in screened.fields
    assert screened.requires_review is True


def test_positive_quantity_is_kept():
    candidate = _candidate({"received_quantity": _field(11, source=FactSource.LLM_NORMALIZATION)})
    screened = screen_candidate_fact_data(candidate)
    assert screened.fields["received_quantity"].value == 11


def test_zero_quantity_is_kept_not_treated_as_negative():
    """0 est une valeur legitime (ex: "il n'en reste aucun") - seule une
    valeur strictement negative est une impossibilite physique."""
    candidate = _candidate({"affected_quantity": _field(0, source=FactSource.LLM_NORMALIZATION)})
    screened = screen_candidate_fact_data(candidate)
    assert screened.fields["affected_quantity"].value == 0


def test_multiple_removed_fields_all_stripped_in_one_pass():
    candidate = _candidate(
        {
            "packaging_condition": _field("transporteur responsable"),
            "affected_quantity": _field(-1, source=FactSource.LLM_NORMALIZATION),
            "product_label": _field("PAC-284"),
        }
    )
    screened = screen_candidate_fact_data(candidate)
    assert set(screened.fields) == {"product_label"}
    assert screened.requires_review is True


def test_screening_never_raises_it_only_strips():
    """Contrairement a liability_guard (ConfirmedFactData -> exception
    bloquante), un candidat degrade proprement : jamais d'exception, jamais
    de dossier bloque (section "Echec IA")."""
    candidate = _candidate(
        {"packaging_condition": _field("indemnisation garantie de 500 euros")}
    )
    screened = screen_candidate_fact_data(candidate)  # ne doit pas lever
    assert "packaging_condition" not in screened.fields
