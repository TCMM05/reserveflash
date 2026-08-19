"""Implémentation de référence en mémoire du port IncidentRepository.

Utilisée pour R0 (fondation) et R1 (capture offline) : permet de développer
et de tester l'intégralité du contrat API sans dépendance PostgreSQL. La
version SQLAlchemy/PostgreSQL réelle (schéma défini dans
app/infrastructure/db/models.py + migrations Alembic, section 6/17.1) sera
branchée derrière le même port en R4 (section 18 - séquençage), sans changer
ni les routes ni le domaine (section 5.3).

Toute donnée ici vit en mémoire process : redémarrer l'API la vide
entièrement. Ce n'est PAS un stockage de production.
"""

from __future__ import annotations

import base64
from dataclasses import dataclass, field
from uuid import UUID

from app.application.ports import IncidentRepository, Page
from app.domain.entities import ConfirmedFactSet, ExportBundle, Incident, Issue, ReserveText
from app.domain.errors import CrossTenantAccessError


def _encode_cursor(index: int) -> str:
    return base64.urlsafe_b64encode(str(index).encode()).decode()


def _decode_cursor(cursor: str | None) -> int:
    if not cursor:
        return 0
    return int(base64.urlsafe_b64decode(cursor.encode()).decode())


@dataclass
class InMemoryIncidentRepository(IncidentRepository):
    _incidents: dict[UUID, Incident] = field(default_factory=dict)
    _idempotency_index: dict[tuple[UUID, str], UUID] = field(default_factory=dict)
    _issues: dict[UUID, Issue] = field(default_factory=dict)
    # issue_id -> liste de révisions, la dernière étant la révision courante.
    _confirmed_fact_sets: dict[UUID, list[ConfirmedFactSet]] = field(default_factory=dict)
    # incident_id -> dernière réserve composée.
    _reserve_texts: dict[UUID, ReserveText] = field(default_factory=dict)
    _export_bundles: dict[UUID, ExportBundle] = field(default_factory=dict)

    # -- Incidents ---------------------------------------------------
    def create_incident(self, incident: Incident, *, idempotency_key: str) -> Incident:
        index_key = (incident.organization_id, idempotency_key)
        existing_id = self._idempotency_index.get(index_key)
        if existing_id is not None:
            return self._incidents[existing_id]
        self._incidents[incident.id] = incident
        self._idempotency_index[index_key] = incident.id
        return incident

    def get_incident(self, organization_id: UUID, incident_id: UUID) -> Incident | None:
        incident = self._incidents.get(incident_id)
        if incident is None:
            return None
        self._assert_same_tenant(incident.organization_id, organization_id)
        return incident

    def list_incidents(
        self,
        organization_id: UUID,
        *,
        status: str | None = None,
        cursor: str | None = None,
        limit: int = 20,
    ) -> Page:
        all_for_org = [
            i for i in self._incidents.values() if i.organization_id == organization_id
        ]
        all_for_org.sort(key=lambda i: i.local_created_at)
        if status:
            all_for_org = [i for i in all_for_org if i.status == status]
        start = _decode_cursor(cursor)
        window = all_for_org[start : start + limit]
        next_cursor = _encode_cursor(start + limit) if start + limit < len(all_for_org) else None
        return Page(items=window, next_cursor=next_cursor)

    def update_incident_metadata(
        self, organization_id: UUID, incident_id: UUID, patch: dict
    ) -> Incident:
        incident = self.get_incident(organization_id, incident_id)
        if incident is None:
            raise KeyError(str(incident_id))
        updated = incident.model_copy(update=patch)
        self._incidents[incident_id] = updated
        return updated

    def delete_incident(self, organization_id: UUID, incident_id: UUID) -> None:
        incident = self.get_incident(organization_id, incident_id)
        if incident is None:
            return
        del self._incidents[incident_id]

    # -- Issues --------------------------------------------------------
    def save_issue(self, issue: Issue) -> Issue:
        self._issues[issue.id] = issue
        return issue

    def get_issue(self, organization_id: UUID, issue_id: UUID) -> Issue | None:
        issue = self._issues.get(issue_id)
        if issue is None:
            return None
        incident = self._incidents.get(issue.incident_id)
        if incident is not None:
            self._assert_same_tenant(incident.organization_id, organization_id)
        return issue

    def list_issues_for_incident(self, incident_id: UUID) -> list[Issue]:
        return sorted(
            (i for i in self._issues.values() if i.incident_id == incident_id),
            key=lambda i: i.sort_order,
        )

    # -- ConfirmedFactSet ------------------------------------------------
    def save_confirmed_fact_set(self, fact_set: ConfirmedFactSet) -> ConfirmedFactSet:
        self._confirmed_fact_sets.setdefault(fact_set.issue_id, []).append(fact_set)
        return fact_set

    def latest_confirmed_fact_set(self, issue_id: UUID) -> ConfirmedFactSet | None:
        revisions = self._confirmed_fact_sets.get(issue_id)
        if not revisions:
            return None
        return revisions[-1]

    def list_latest_confirmed_fact_sets_for_incident(
        self, incident_id: UUID
    ) -> list[ConfirmedFactSet]:
        latest: list[ConfirmedFactSet] = []
        for issue in self.list_issues_for_incident(incident_id):
            current = self.latest_confirmed_fact_set(issue.id)
            if current is not None:
                latest.append(current)
        return latest

    # -- ReserveText ------------------------------------------------------
    def save_reserve_text(self, reserve: ReserveText) -> ReserveText:
        self._reserve_texts[reserve.incident_id] = reserve
        return reserve

    def latest_reserve_text(self, incident_id: UUID) -> ReserveText | None:
        return self._reserve_texts.get(incident_id)

    def invalidate_reserve_text(self, incident_id: UUID) -> None:
        self._reserve_texts.pop(incident_id, None)

    # -- ExportBundle -------------------------------------------------
    def save_export_bundle(self, export: ExportBundle) -> ExportBundle:
        self._export_bundles[export.id] = export
        return export

    def get_export_bundle(
        self, organization_id: UUID, incident_id: UUID, export_id: UUID
    ) -> ExportBundle | None:
        export = self._export_bundles.get(export_id)
        if export is None or export.incident_id != incident_id:
            return None
        incident = self._incidents.get(incident_id)
        if incident is not None:
            self._assert_same_tenant(incident.organization_id, organization_id)
        return export

    def next_export_version(self, incident_id: UUID) -> int:
        versions = [
            b.version for b in self._export_bundles.values() if b.incident_id == incident_id
        ]
        return max(versions, default=0) + 1

    def supersede_previous_exports(self, incident_id: UUID) -> None:
        for export in self._export_bundles.values():
            if export.incident_id == incident_id and not export.superseded:
                self._export_bundles[export.id] = export.model_copy(update={"superseded": True})

    # -- Helpers -----------------------------------------------------
    @staticmethod
    def _assert_same_tenant(owner_org_id: UUID, requester_org_id: UUID) -> None:
        if owner_org_id != requester_org_id:
            # SEC-04 / scénario E2E-09 : ne jamais révéler l'existence de la
            # ressource à une autre organisation.
            raise CrossTenantAccessError("Ressource hors périmètre de l'organisation.")
