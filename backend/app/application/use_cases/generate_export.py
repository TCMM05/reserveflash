"""Cas d'usage F13 'Générer le dossier PDF'.

Note de portée R0 : ce use case produit un document PLACEHOLDER déterministe
(texte de réserve + mention de prudence encodés en octets), pas encore le
rendu PDF final avec chronologie et preuves intégrées. Le rendu PDF complet
(section 2.1 F13, section 6.1 ExportBundle) est prévu en R3 "Composer &
dossier" (section 18 - séquençage). Le contrat d'API (endpoint, ExportBundle,
sha256, invalidation par supersede) est en revanche définitif dès R0.
"""

from __future__ import annotations

from datetime import UTC, datetime
from uuid import UUID, uuid4

from app.application.ports import IncidentRepository, StorageProvider
from app.domain.entities import ExportBundle
from app.domain.templates.fr_v1 import PRUDENCE_MENTION


class NoReserveTextError(Exception):
    """Aucune réserve composée pour cet incident : rien à exporter (F13
    suppose F10 déjà réalisé)."""


def generate_export(
    *,
    repo: IncidentRepository,
    storage: StorageProvider,
    organization_id: UUID,
    incident_id: UUID,
) -> ExportBundle:
    incident = repo.get_incident(organization_id, incident_id)
    if incident is None:
        raise KeyError(str(incident_id))

    reserve = repo.latest_reserve_text(incident_id)
    if reserve is None:
        raise NoReserveTextError(
            "Aucune réserve composée : appelez POST /incidents/{id}/reserve avant "
            "de générer un export."
        )

    # section 8.2 : "Export généré avant nouvelle révision -> marquer
    # superseded, ne pas écraser silencieusement."
    repo.supersede_previous_exports(incident_id)

    document_bytes = (
        f"RESERVEFLASH - DOSSIER DE RÉCEPTION (placeholder R0)\n"
        f"Incident: {incident_id}\n"
        f"Template: {reserve.template_version} / révision faits: "
        f"{reserve.confirmed_fact_revision}\n\n"
        f"{reserve.text}\n\n{PRUDENCE_MENTION}\n"
    ).encode()

    confirmation = storage.put_object(
        organization_id=organization_id,
        incident_id=incident_id,
        data=document_bytes,
        content_type="application/pdf",
        key_hint="exports",
    )

    next_version = repo.next_export_version(incident_id)

    export = ExportBundle(
        id=uuid4(),
        incident_id=incident_id,
        version=next_version,
        pdf_object_key=confirmation.object_key,
        sha256=confirmation.sha256,
        created_at=datetime.now(UTC),
        superseded=False,
    )
    repo.save_export_bundle(export)
    return export
