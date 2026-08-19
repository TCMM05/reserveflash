"""section 11 - Rules Engine et garde-fous juridiques."""

from datetime import date, datetime

import pytest
from pydantic import ValidationError

from app.domain.rule_pack import RulePack, RulePackReview, RulePackStatus
from app.infrastructure.rulepacks.loader import list_active_rule_packs, load_all_rule_packs


def _pack(**overrides) -> dict:
    base = dict(
        rule_pack_id="FR_ROAD_DOMESTIC_GENERAL_2026_01",
        jurisdiction="FR",
        transport_mode="ROAD",
        scope="DOMESTIC_GENERAL_CONTRACT_TYPE",
        status="DISABLED_PENDING_LEGAL_REVIEW",
        source_title="Code des transports",
        source_url="https://www.legifrance.gouv.fr/",
        version=1,
    )
    base.update(overrides)
    return base


def test_shipped_rule_pack_is_loadable_and_disabled():
    """section 20.2 : la release 1.0 ne fournit qu'un pack d'exemple, non
    activé (aucune décision juridique prise en dur dans le produit)."""
    packs = load_all_rule_packs()
    assert len(packs) >= 1
    fr_pack = next(p for p in packs if p.rule_pack_id == "FR_ROAD_DOMESTIC_GENERAL_2026_01")
    assert fr_pack.status is RulePackStatus.DISABLED_PENDING_LEGAL_REVIEW


def test_no_rule_pack_is_active_by_default():
    """section 11.3 : 'Aucun rule pack n'est sélectionné automatiquement à
    partir d'une supposition du LLM' - traduit ici par : aucun pack livré
    n'est ACTIVE tant qu'une revue humaine ne l'a pas explicitement basculé."""
    assert list_active_rule_packs() == []


def test_active_status_requires_reviewer_and_effective_date():
    """section 18.1 : 'Tout changement rule pack = source + reviewer +
    effective date + tests.'"""
    with pytest.raises(ValidationError):
        RulePack.model_validate(_pack(status="ACTIVE"))


def test_active_status_with_full_review_is_valid():
    pack = RulePack.model_validate(
        _pack(
            status="ACTIVE",
            effective_from=date(2026, 9, 1),
            review=RulePackReview(
                reviewer="Jane Avocat",
                reviewed_at=datetime(2026, 8, 20, 10, 0),
                legal_notes="Validé pour le transport routier domestique.",
            ).model_dump(),
        )
    )
    assert pack.status is RulePackStatus.ACTIVE


def test_extra_fields_are_rejected():
    with pytest.raises(ValidationError):
        RulePack.model_validate(_pack(unexpected_field="oops"))
