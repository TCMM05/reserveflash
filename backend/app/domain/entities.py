"""Entites du domaine (section 6.1 - modele de donnees canonique).

Ce sont des objets domaine purs (pydantic pour la validation, pas d'ORM ici :
le mapping SQLAlchemy vit dans app/infrastructure/db). Champs "minimum" repris
tels que definis dans le cahier des charges.
"""

from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict

from app.domain.fact_set import CandidateFactData, ConfirmedFactData
from app.domain.value_objects import (
    EvidenceAssetType,
    IncidentStatus,
    OrganizationRole,
    SyncStatus,
)


class _Entity(BaseModel):
    model_config = ConfigDict(extra="forbid")


class Organization(_Entity):
    id: UUID
    name: str
    plan: str
    created_at: datetime
    retention_policy_days: int


class User(_Entity):
    id: UUID
    organization_id: UUID
    email: str
    role: OrganizationRole
    created_at: datetime
    deleted_at: datetime | None = None


class Incident(_Entity):
    id: UUID
    organization_id: UUID
    creator_id: UUID
    status: IncidentStatus
    local_created_at: datetime
    server_created_at: datetime | None = None
    occurred_at: datetime
    supplier_name: str | None = None
    carrier_name: str | None = None
    delivery_ref: str | None = None
    notes: str | None = None

    def transition_to(self, target: IncidentStatus) -> Incident:
        from app.domain.errors import InvalidStateTransitionError

        if not self.status.can_transition_to(target):
            raise InvalidStateTransitionError(
                f"Transition {self.status} -> {target} interdite (section 2.2)."
            )
        return self.model_copy(update={"status": target})

    def advance_to(self, target: IncidentStatus) -> Incident:
        """Applique la transition directe si possible, sinon suit le plus
        court chemin autorisé (ex: EXPORTED -> REVIEW_REQUIRED -> ... quand
        un événement métier doit faire progresser l'incident de plusieurs
        étapes). Ne saute jamais un état interdit du graphe section 2.2."""
        from app.domain.errors import InvalidStateTransitionError

        path = self.status.path_to(target)
        if path is None:
            raise InvalidStateTransitionError(
                f"Aucun chemin autorisé de {self.status} vers {target} (section 2.2)."
            )
        current = self
        for step in path[1:]:
            current = current.transition_to(step)
        return current


class DeliveryDocument(_Entity):
    id: UUID
    incident_id: UUID
    document_type: str
    ocr_status: str
    extracted_metadata_json: dict
    confirmed_metadata_json: dict | None = None


class Issue(_Entity):
    id: UUID
    incident_id: UUID
    issue_type: str
    sort_order: int
    status: str


class CandidateFactSet(_Entity):
    id: UUID
    issue_id: UUID
    schema_version: str
    prompt_version: str
    model: str
    raw_structured_json: CandidateFactData
    created_at: datetime


class ConfirmedFactSet(_Entity):
    id: UUID
    issue_id: UUID
    schema_version: str
    confirmed_json: ConfirmedFactData
    confirmed_by: UUID
    confirmed_at: datetime
    revision: int


class EvidenceAsset(_Entity):
    id: UUID
    incident_id: UUID
    issue_id: UUID | None = None
    type: EvidenceAssetType
    original_object_key: str
    preview_object_key: str | None = None
    sha256: str
    mime_type: str
    bytes: int
    captured_at_device: datetime
    uploaded_at: datetime | None = None
    sync_status: SyncStatus = SyncStatus.LOCAL


class ReserveText(_Entity):
    id: UUID
    incident_id: UUID
    template_version: str
    confirmed_fact_revision: int
    text: str
    sha256: str
    created_at: datetime


class ExportBundle(_Entity):
    id: UUID
    incident_id: UUID
    version: int
    pdf_object_key: str
    sha256: str
    created_at: datetime
    superseded: bool = False


class Reminder(_Entity):
    id: UUID
    incident_id: UUID
    rule_pack_id: str | None = None
    due_at: datetime
    status: str
    label: str


class AuditEvent(_Entity):
    id: UUID
    organization_id: UUID
    incident_id: UUID | None = None
    actor_id: UUID | None = None
    event_type: str
    metadata_safe_json: dict
    created_at: datetime


class Entitlement(_Entity):
    organization_id: UUID
    source: str
    product_id: str
    status: str
    valid_until: datetime | None = None
