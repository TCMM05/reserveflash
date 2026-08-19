"""Invariants métier section 6.3 du cahier des charges."""

import pytest
from pydantic import ValidationError

from app.domain.errors import UnconfirmedFactSetError
from app.domain.fact_set import ConfirmedFactData
from app.domain.value_objects import IssueType


def test_user_confirmed_must_be_true():
    """'ConfirmedFactSet.user_confirmed = true avant toute génération de réserve.'"""
    with pytest.raises(UnconfirmedFactSetError):
        ConfirmedFactData(issue_type=IssueType.OTHER, user_confirmed=False)


def test_missing_quantity_is_computed_by_code_not_stored():
    """'Si expected_quantity et received_quantity sont connus, missing_quantity
    est calculée par code, jamais par le LLM.' -> le champ n'existe même pas
    en entrée du modèle (extra='forbid')."""
    with pytest.raises(ValidationError):
        ConfirmedFactData(
            issue_type=IssueType.MISSING_QTY,
            expected_quantity=8,
            received_quantity=6,
            missing_quantity=2,  # type: ignore[call-arg]
            user_confirmed=True,
        )


def test_missing_quantity_property_computes_difference():
    fact = ConfirmedFactData(
        issue_type=IssueType.MISSING_QTY,
        expected_quantity=8,
        received_quantity=6,
        user_confirmed=True,
    )
    assert fact.missing_quantity == 2


def test_missing_quantity_is_none_when_a_quantity_is_unknown():
    """Pas d'invention : si une des deux quantités manque, on ne calcule pas
    un écart halluciné."""
    fact = ConfirmedFactData(
        issue_type=IssueType.MISSING_QTY,
        expected_quantity=8,
        received_quantity=None,
        user_confirmed=True,
    )
    assert fact.missing_quantity is None


@pytest.mark.parametrize("field", ["expected_quantity", "received_quantity", "affected_quantity"])
def test_negative_quantities_are_rejected(field):
    with pytest.raises(ValidationError):
        ConfirmedFactData(issue_type=IssueType.WRONG_QTY, user_confirmed=True, **{field: -1})


def test_unknown_field_is_a_first_class_valid_value():
    """'La valeur UNKNOWN / Je ne sais pas est une réponse valide' (règle UX 2.3)."""
    fact = ConfirmedFactData(
        issue_type=IssueType.PRODUCT_DAMAGE,
        unknown_fields=("product_reference",),
        user_confirmed=True,
    )
    assert fact.is_field_unknown("product_reference")
    assert not fact.is_field_unknown("product_label")


def test_extra_fields_are_forbidden():
    """Le schéma est strict (additionalProperties: false côté JSON Schema)."""
    with pytest.raises(ValidationError):
        ConfirmedFactData(
            issue_type=IssueType.OTHER,
            user_confirmed=True,
            some_invented_field="oops",  # type: ignore[call-arg]
        )
