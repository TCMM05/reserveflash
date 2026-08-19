"""Cas d'usage F01 'Créer un incident' - GATE : "L'utilisateur peut créer un
incident immédiatement, y compris sans réseau" (section 2.1). Côté backend,
ceci se traduit par une création idempotente (section 9.2) une fois la
synchronisation effectuée par le client."""

from __future__ import annotations

from datetime import UTC, datetime
from uuid import UUID, uuid4

from app.application.ports import IncidentRepository
from app.domain.entities import Incident
from app.domain.value_objects import IncidentStatus


def create_incident(
    *,
    repo: IncidentRepository,
    organization_id: UUID,
    creator_id: UUID,
    idempotency_key: str,
    occurred_at: datetime,
    supplier_name: str | None = None,
    carrier_name: str | None = None,
    delivery_ref: str | None = None,
    notes: str | None = None,
) -> Incident:
    now = datetime.now(UTC)
    incident = Incident(
        id=uuid4(),
        organization_id=organization_id,
        creator_id=creator_id,
        status=IncidentStatus.DRAFT_LOCAL,
        local_created_at=now,
        server_created_at=now,
        occurred_at=occurred_at,
        supplier_name=supplier_name,
        carrier_name=carrier_name,
        delivery_ref=delivery_ref,
        notes=notes,
    )
    return repo.create_incident(incident, idempotency_key=idempotency_key)
