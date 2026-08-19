"""Modeles Python miroir des schemas JSON versionnes (schemas/confirmed_fact_set.v1.schema.json
et schemas/candidate_fact_set.v1.schema.json).

Ces classes sont la SEULE porte d'entree autorisee vers le Reserve Composer
(GATE zero invention, section 2.4 : "Le Reserve Composer est un composant
deterministe. Il ne recoit pas le texte libre utilisateur ni la reponse brute
LLM ; seulement le ConfirmedFactSet type.").
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, model_validator

from app.domain.value_objects import ConfidenceLevel, FactSource, IssueType

SCHEMA_VERSION_CONFIRMED = "confirmed_fact_set.v1"
SCHEMA_VERSION_CANDIDATE = "candidate_fact_set.v1"


class ConfirmedFactData(BaseModel):
    """Correspond exactement a schemas/confirmed_fact_set.v1.schema.json.

    Notez l'absence volontaire de `missing_quantity` : cette valeur est
    calculee par code (invariant 6.3), jamais stockee ni ecrite par un humain
    ou un LLM.
    """

    model_config = ConfigDict(extra="forbid", frozen=True)

    issue_type: IssueType
    product_label: str | None = None
    product_reference: str | None = None
    expected_quantity: float | None = None
    received_quantity: float | None = None
    affected_quantity: float | None = None
    packaging_condition: str | None = None
    product_condition: str | None = None
    location_on_item: str | None = None
    user_uncertainty: bool = False
    unknown_fields: tuple[str, ...] = ()
    user_confirmed: bool

    @model_validator(mode="after")
    def _enforce_user_confirmed(self) -> ConfirmedFactData:
        # Invariant 6.3 applique au plus pres de la donnee : impossible de
        # construire un ConfirmedFactData valide sans confirmation explicite.
        if not self.user_confirmed:
            from app.domain.errors import UnconfirmedFactSetError

            raise UnconfirmedFactSetError(
                "ConfirmedFactSet.user_confirmed doit etre true (invariant section 6.3)."
            )
        for qty_field in ("expected_quantity", "received_quantity", "affected_quantity"):
            value = getattr(self, qty_field)
            if value is not None and value < 0:
                raise ValueError(f"{qty_field} ne peut pas etre negatif.")
        return self

    @property
    def missing_quantity(self) -> float | None:
        """Calculee par code uniquement (invariant 6.3), jamais par le LLM.

        Retourne None si l'une des deux quantites est inconnue - dans ce cas
        le Reserve Composer doit produire un texte prudent plutot qu'un chiffre
        invente.
        """
        if self.expected_quantity is None or self.received_quantity is None:
            return None
        return round(self.expected_quantity - self.received_quantity, 6)

    def is_field_unknown(self, field_name: str) -> bool:
        return field_name in self.unknown_fields


class CandidateField(BaseModel):
    model_config = ConfigDict(extra="forbid")

    value: object | None
    source: FactSource
    confidence: ConfidenceLevel
    ambiguous: bool = False


class CandidateFactData(BaseModel):
    """Correspond a schemas/candidate_fact_set.v1.schema.json. Sortie brute du
    pipeline IA (section 7.2, etapes 1 a 4). Ne DOIT jamais etre utilisee comme
    entree du Reserve Composer."""

    model_config = ConfigDict(extra="forbid")

    issue_type_candidate: IssueType | None
    fields: dict[str, CandidateField]
    requires_review: bool
    clarification_question_id: str | None = None
