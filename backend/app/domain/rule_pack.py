"""RulePack - section 11 du cahier des charges.

GATE section 11.1 : "Les règles juridiques ou contractuelles ne doivent
jamais être stockées dans un prompt." Ce module ne fait QUE modéliser et
valider la structure d'un RulePack ; il n'implémente aucune règle métier
concrète (aucun rule pack livré en 1.0 n'est ACTIVE - section 20.2 le
confirme implicitement en ne fournissant qu'un exemple
DISABLED_PENDING_LEGAL_REVIEW)."""

from __future__ import annotations

from datetime import date, datetime
from enum import StrEnum

from pydantic import BaseModel, ConfigDict, model_validator


class RulePackStatus(StrEnum):
    DISABLED_PENDING_LEGAL_REVIEW = "DISABLED_PENDING_LEGAL_REVIEW"
    ACTIVE = "ACTIVE"
    RETIRED = "RETIRED"


class TransportMode(StrEnum):
    ROAD = "ROAD"
    # Hors périmètre release 1.0 (section 1.5) - présents pour que le
    # schéma reste stable si un pack hors-scope est déposé par erreur.
    MARITIME = "MARITIME"
    AIR = "AIR"


class RulePackReview(BaseModel):
    model_config = ConfigDict(extra="forbid")

    reviewer: str | None = None
    reviewed_at: datetime | None = None
    legal_notes: str | None = None


class RulePack(BaseModel):
    """Correspond à la structure section 11.2. Un RulePack ACTIVE sans
    `reviewer` ni `reviewed_at` est rejeté par le validateur ci-dessous
    (section 18.1 : "Tout changement rule pack = source + reviewer +
    effective date + tests.")."""

    model_config = ConfigDict(extra="forbid")

    rule_pack_id: str
    jurisdiction: str
    transport_mode: TransportMode
    scope: str
    status: RulePackStatus
    source_title: str
    source_url: str
    effective_from: date | None = None
    version: int
    rules: list[dict] = []
    review: RulePackReview = RulePackReview()

    @model_validator(mode="after")
    def _active_requires_review_and_effective_date(self) -> RulePack:
        if self.status is RulePackStatus.ACTIVE:
            if self.review.reviewer is None or self.review.reviewed_at is None:
                raise ValueError(
                    f"RulePack '{self.rule_pack_id}' ne peut pas être ACTIVE sans "
                    "reviewer/reviewed_at renseignés (section 18.1)."
                )
            if self.effective_from is None:
                raise ValueError(
                    f"RulePack '{self.rule_pack_id}' ACTIVE requiert effective_from."
                )
        return self
