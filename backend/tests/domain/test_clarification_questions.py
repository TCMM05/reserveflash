from __future__ import annotations

from app.domain.clarification_questions import (
    CLARIFICATION_QUESTION_CATALOG,
    clarification_question_id_for_field,
)


def test_known_field_maps_to_catalog_id():
    assert clarification_question_id_for_field("product_label") == "Q_PRODUCT_LABEL_MISSING"


def test_none_field_maps_to_none():
    assert clarification_question_id_for_field(None) is None


def test_unknown_or_hallucinated_field_name_is_ignored_not_invented():
    assert clarification_question_id_for_field("this_is_not_a_real_field") is None
    assert clarification_question_id_for_field("") is None


def test_every_v1_priority_field_has_a_catalog_entry():
    v1_fields = {
        "issue_type_candidate",
        "product_label",
        "product_reference",
        "expected_quantity",
        "received_quantity",
        "affected_quantity",
        "packaging_condition",
        "product_condition",
        "location_on_item",
    }
    assert v1_fields.issubset(CLARIFICATION_QUESTION_CATALOG)
