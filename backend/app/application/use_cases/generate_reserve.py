"""Cas d'usage F10 'Composer la réserve descriptive' - orchestre l'appel au
Reserve Composer déterministe (app.domain.reserve_composer) à partir des
ConfirmedFactSet les plus récents de chaque anomalie de l'incident (section
2.5 - incidents multiples)."""

from __future__ import annotations

from datetime import UTC, datetime
from uuid import UUID, uuid4

from app.application.ports import IncidentRepository
from app.domain.entities import Incident, ReserveText
from app.domain.reserve_composer import compose_reserve
from app.domain.value_objects import IncidentStatus


class NoConfirmedFactsError(Exception):
    """Aucune anomalie n'a encore de faits confirmés : rien à composer."""


def generate_reserve(
    *,
    repo: IncidentRepository,
    organization_id: UUID,
    incident_id: UUID,
    template_version: str,
) -> tuple[Incident, ReserveText]:
    incident = repo.get_incident(organization_id, incident_id)
    if incident is None:
        raise KeyError(str(incident_id))

    latest_fact_sets = repo.list_latest_confirmed_fact_sets_for_incident(incident_id)
    if not latest_fact_sets:
        raise NoConfirmedFactsError(
            "Aucun ConfirmedFactSet pour cet incident : confirmez au moins une "
            "anomalie (F09) avant de composer la réserve (F10)."
        )

    composed = compose_reserve(
        [fs.confirmed_json for fs in latest_fact_sets], template_version=template_version
    )

    reserve = ReserveText(
        id=uuid4(),
        incident_id=incident_id,
        template_version=composed.template_version,
        confirmed_fact_revision=max(fs.revision for fs in latest_fact_sets),
        text=composed.text,
        sha256=composed.sha256,
        created_at=datetime.now(UTC),
    )
    repo.save_reserve_text(reserve)

    updated_incident = incident
    if incident.status.path_to(IncidentStatus.RESERVE_READY) is not None:
        updated_incident = incident.advance_to(IncidentStatus.RESERVE_READY)
        repo.update_incident_metadata(
            organization_id, incident_id, {"status": updated_incident.status}
        )

    return updated_incident, reserve
