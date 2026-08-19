"""Cas d'usage F09 'Faire valider chaque fait' (GATE, section 2.1) - crée une
nouvelle révision de ConfirmedFactSet et applique l'invariant : "Une révision
de faits confirmés invalide automatiquement la réserve et le PDF précédents ;
nouvelle version obligatoire" (section 6.3).

Depuis R0.1 (correctif point 8), ce cas d'usage applique aussi le garde-fou
anti-attribution de responsabilité (app.domain.liability_guard) DÈS la
confirmation, pour un retour immédiat à l'utilisateur - en plus de l'appel
fait par app.domain.reserve_composer.compose_reserve() en défense en
profondeur (voir docstring de ce dernier module)."""

from __future__ import annotations

from datetime import UTC, datetime
from uuid import UUID, uuid4

from app.application.ports import IncidentRepository
from app.domain.entities import ConfirmedFactSet, Incident
from app.domain.errors import CrossTenantAccessError
from app.domain.fact_set import ConfirmedFactData
from app.domain.liability_guard import screen_confirmed_fact
from app.domain.value_objects import IncidentStatus


def confirm_facts(
    *,
    repo: IncidentRepository,
    organization_id: UUID,
    incident_id: UUID,
    issue_id: UUID,
    fact_payload: dict,
    confirmed_by: UUID,
    schema_version: str,
) -> tuple[Incident, ConfirmedFactSet]:
    incident = repo.get_incident(organization_id, incident_id)
    if incident is None:
        raise KeyError(str(incident_id))

    issue = repo.get_issue(organization_id, issue_id)
    if issue is None or issue.incident_id != incident_id:
        raise CrossTenantAccessError("Issue introuvable pour cet incident/organisation.")

    # fact_payload ne doit contenir QUE des champs validés utilisateur ; on
    # force user_confirmed=True car cette route EST l'acte de confirmation
    # (F09). Le modèle pydantic rejette toute clé additionnelle inattendue.
    confirmed_data = ConfirmedFactData(**{**fact_payload, "user_confirmed": True})

    # Garde-fou R0.1 (point 8) : rejette dès la confirmation tout champ texte
    # libre contenant une attribution de responsabilité, une promesse
    # d'indemnisation, une conclusion/qualification juridique ou un montant
    # inventé (ex: packaging_condition = "transporteur responsable"). Lève
    # LiabilityAttributionError -> 400 LIABILITY_ATTRIBUTION_BLOCKED (voir
    # app/api/errors.py). L'utilisateur doit reformuler et confirmer à
    # nouveau ; rien n'est perdu (aucune sanitization silencieuse).
    screen_confirmed_fact(confirmed_data)

    previous = repo.latest_confirmed_fact_set(issue_id)
    next_revision = 1 if previous is None else previous.revision + 1

    fact_set = ConfirmedFactSet(
        id=uuid4(),
        issue_id=issue_id,
        schema_version=schema_version,
        confirmed_json=confirmed_data,
        confirmed_by=confirmed_by,
        confirmed_at=datetime.now(UTC),
        revision=next_revision,
    )
    repo.save_confirmed_fact_set(fact_set)

    # Invariant section 6.3 : toute nouvelle révision invalide la réserve et
    # les exports précédents. On ne supprime pas l'historique (traçabilité/
    # audit) : la réserve composée est effacée (recomposition obligatoire) et
    # les exports existants sont marqués superseded, jamais écrasés
    # silencieusement (section 8.2).
    repo.invalidate_reserve_text(incident_id)
    repo.supersede_previous_exports(incident_id)

    updated_incident = _advance_incident_after_confirmation(incident)
    if updated_incident.status != incident.status:
        repo.update_incident_metadata(
            organization_id, incident_id, {"status": updated_incident.status}
        )

    return updated_incident, fact_set


# États depuis lesquels une confirmation de faits fait progresser l'incident
# jusqu'à FACTS_CONFIRMED en suivant le graphe section 2.2 (via
# REVIEW_REQUIRED si nécessaire). Pour RESERVE_READY / EVIDENCE_COMPLETE, le
# cahier des charges ne définit aucune transition de retour explicite : on
# laisse le statut inchangé (la réserve/les exports ont déjà été invalidés
# ci-dessus, une recomposition explicite est requise - ROADMAP: clarifier ce
# cas avec le Product Owner si le besoin terrain se confirme).
_ADVANCE_TO_FACTS_CONFIRMED_FROM = {
    IncidentStatus.DRAFT_LOCAL,
    IncidentStatus.SYNCING,
    IncidentStatus.EXTRACTION_PENDING,
    IncidentStatus.REVIEW_REQUIRED,
    IncidentStatus.FACTS_CONFIRMED,
    IncidentStatus.EXPORTED,
    IncidentStatus.ARCHIVED,
}


def _advance_incident_after_confirmation(incident: Incident) -> Incident:
    if incident.status not in _ADVANCE_TO_FACTS_CONFIRMED_FROM:
        return incident
    if incident.status is IncidentStatus.FACTS_CONFIRMED:
        return incident
    return incident.advance_to(IncidentStatus.FACTS_CONFIRMED)
