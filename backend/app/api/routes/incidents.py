"""Endpoints /v1/incidents/* (section 9.1 - table des endpoints minimum).

STATUT DEPUIS R0.1 (pivot Local-First, point 4/11 de la demande corrective,
voir docs/adr/0002-local-first-pivot.md) : ce router devient un CHEMIN
OPTIONNEL/FUTUR, conservé tel quel (code déjà écrit et testé, 48+ tests) en
vue d'un usage cloud ultérieur (multi-appareil, comptes équipe, tableau de
bord web - hors scope V1), mais N'EST PLUS APPELÉ par l'application mobile
V1. L'app mobile V1 stocke et gère l'intégralité du cycle de vie d'un
incident en local (voir mobile/lib/data/local/local_incident_repository.dart)
et n'appelle le backend QUE via app/api/routes/ai.py (transcription/
extraction, sans état, sans notion d'incident côté serveur).

Ne pas ajouter de nouvelle fonctionnalité V1 ici : toute nouvelle
fonctionnalité de dossier va dans mobile/lib/domain/ +
mobile/lib/data/local/. Ce router ne doit évoluer que pour un futur
chantier cloud explicitement scope (post-V1)."""

from __future__ import annotations

from typing import Annotated
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, Query, status

from app.api.deps import (
    get_ai_provider,
    get_auth_context,
    get_idempotency_key,
    get_repository,
    get_storage_provider,
)
from app.api.schemas import (
    CompleteUploadRequest,
    CompleteUploadResponse,
    ConfirmedFactSetResponse,
    ConfirmFactsRequest,
    CreateIncidentRequest,
    CreateIssueRequest,
    ExportBundleResponse,
    ExportDownloadResponse,
    ExtractRequest,
    ExtractResponse,
    GenerateReserveResponse,
    IncidentListResponse,
    IncidentResponse,
    IssueResponse,
    PatchIncidentRequest,
    PresignUploadRequest,
    PresignUploadResponse,
    TranscribeRequest,
    TranscribeResponse,
)
from app.application.ports import AIProvider, AuthContext, IncidentRepository, StorageProvider
from app.application.use_cases.confirm_facts import confirm_facts
from app.application.use_cases.create_incident import create_incident
from app.application.use_cases.generate_export import generate_export
from app.application.use_cases.generate_reserve import generate_reserve
from app.config import Settings, get_settings
from app.domain.entities import Issue

router = APIRouter(prefix="/incidents", tags=["incidents"])

Repo = Annotated[IncidentRepository, Depends(get_repository)]
Auth = Annotated[AuthContext, Depends(get_auth_context)]
Sett = Annotated[Settings, Depends(get_settings)]
AI = Annotated[AIProvider, Depends(get_ai_provider)]
Storage = Annotated[StorageProvider, Depends(get_storage_provider)]


def _to_response(incident) -> IncidentResponse:
    return IncidentResponse(**incident.model_dump())


@router.post("", response_model=IncidentResponse, status_code=status.HTTP_201_CREATED)
def post_incident(
    body: CreateIncidentRequest,
    repo: Repo,
    auth: Auth,
    idempotency_key: Annotated[str, Depends(get_idempotency_key)],
) -> IncidentResponse:
    """F01 - "L'utilisateur peut créer un incident immédiatement, y compris
    sans réseau" (côté client). Ici : réception idempotente côté serveur."""
    incident = create_incident(
        repo=repo,
        organization_id=auth.organization_id,
        creator_id=auth.user_id,
        idempotency_key=idempotency_key,
        occurred_at=body.occurred_at,
        supplier_name=body.supplier_name,
        carrier_name=body.carrier_name,
        delivery_ref=body.delivery_ref,
        notes=body.notes,
    )
    return _to_response(incident)


@router.get("", response_model=IncidentListResponse)
def list_incidents(
    repo: Repo,
    auth: Auth,
    status_filter: Annotated[str | None, Query(alias="status")] = None,
    cursor: str | None = None,
    limit: int = 20,
) -> IncidentListResponse:
    page = repo.list_incidents(
        auth.organization_id, status=status_filter, cursor=cursor, limit=limit
    )
    return IncidentListResponse(
        items=[_to_response(i) for i in page.items], next_cursor=page.next_cursor
    )


@router.get("/{incident_id}", response_model=IncidentResponse)
def get_incident(incident_id: UUID, repo: Repo, auth: Auth) -> IncidentResponse:
    incident = repo.get_incident(auth.organization_id, incident_id)
    if incident is None:
        raise KeyError(str(incident_id))
    return _to_response(incident)


@router.patch("/{incident_id}", response_model=IncidentResponse)
def patch_incident(
    incident_id: UUID, body: PatchIncidentRequest, repo: Repo, auth: Auth
) -> IncidentResponse:
    """"Modifier métadonnées non verrouillées" (section 9.1). Les champs
    verrouillés (faits confirmés, réserve, etc.) ne transitent jamais par
    cette route générique de métadonnées."""
    patch = {k: v for k, v in body.model_dump().items() if v is not None}
    updated = repo.update_incident_metadata(auth.organization_id, incident_id, patch)
    return _to_response(updated)


@router.delete("/{incident_id}", status_code=status.HTTP_204_NO_CONTENT, response_model=None)
def delete_incident(incident_id: UUID, repo: Repo, auth: Auth) -> None:
    repo.delete_incident(auth.organization_id, incident_id)


@router.post(
    "/{incident_id}/issues", response_model=IssueResponse, status_code=status.HTTP_201_CREATED
)
def post_issue(
    incident_id: UUID, body: CreateIssueRequest, repo: Repo, auth: Auth
) -> IssueResponse:
    """F05 - "Déclarer le type d'incident" ; une anomalie indépendante par
    appel (section 2.5 - incidents multiples)."""
    incident = repo.get_incident(auth.organization_id, incident_id)
    if incident is None:
        raise KeyError(str(incident_id))
    issue = Issue(
        id=uuid4(),
        incident_id=incident_id,
        issue_type=body.issue_type.value,
        sort_order=body.sort_order,
        status="OPEN",
    )
    repo.save_issue(issue)
    return IssueResponse(**issue.model_dump())


@router.post("/{incident_id}/assets/presign", response_model=PresignUploadResponse)
def post_asset_presign(
    incident_id: UUID, body: PresignUploadRequest, repo: Repo, auth: Auth, storage: Storage
) -> PresignUploadResponse:
    """F02/F06/F11 - "Créer upload privé signé" (SEC-03 : jamais d'URL
    publique permanente)."""
    incident = repo.get_incident(auth.organization_id, incident_id)
    if incident is None:
        raise KeyError(str(incident_id))
    presigned = storage.create_presigned_upload(
        organization_id=auth.organization_id,
        incident_id=incident_id,
        content_type=body.content_type,
    )
    return PresignUploadResponse(
        upload_url=presigned.upload_url,
        object_key=presigned.object_key,
        expires_at=presigned.expires_at,
        fields=presigned.fields,
    )


@router.post("/{incident_id}/assets/complete", response_model=CompleteUploadResponse)
def post_asset_complete(
    incident_id: UUID, body: CompleteUploadRequest, repo: Repo, auth: Auth, storage: Storage
) -> CompleteUploadResponse:
    """"Confirmer upload + hash" (section 9.1). Précondition : le client a
    déjà écrit les octets sur `upload_url` (hors périmètre backend)."""
    incident = repo.get_incident(auth.organization_id, incident_id)
    if incident is None:
        raise KeyError(str(incident_id))
    confirmation = storage.confirm_upload(body.object_key)
    return CompleteUploadResponse(
        object_key=confirmation.object_key,
        sha256=confirmation.sha256,
        bytes=confirmation.bytes,
        mime_type=confirmation.mime_type,
    )


@router.post("/{incident_id}/transcriptions", response_model=TranscribeResponse)
def post_transcription(
    incident_id: UUID, body: TranscribeRequest, repo: Repo, auth: Auth, ai: AI
) -> TranscribeResponse:
    """F07 - "Enregistrement audio local puis transcription" (section 7.2,
    étape 1). Rôle IA strictement limité à la transcription (section 7.1)."""
    incident = repo.get_incident(auth.organization_id, incident_id)
    if incident is None:
        raise KeyError(str(incident_id))
    # R0 : le contenu audio réel (lecture depuis le storage par object_key)
    # est hors périmètre fondation ; le provider mock retourne une
    # transcription déterministe configurée en amont pour les tests.
    result = ai.transcribe(audio_bytes=b"", mime_type="audio/wav")
    return TranscribeResponse(
        text=result.text,
        provider=result.provider,
        model_id=result.model_id,
        latency_ms=result.latency_ms,
    )


@router.post("/{incident_id}/extractions", response_model=ExtractResponse)
def post_extraction(
    incident_id: UUID, body: ExtractRequest, repo: Repo, auth: Auth, ai: AI, settings: Sett
) -> ExtractResponse:
    """F03/F08 - "Extraire les faits candidats" (section 7.2, étapes 2-4).
    Sortie CandidateFactData - jamais utilisée directement comme réserve
    (GATE zéro invention, section 2.4) : doit repasser par F09 (facts/confirm)."""
    incident = repo.get_incident(auth.organization_id, incident_id)
    if incident is None:
        raise KeyError(str(incident_id))
    result = ai.extract_candidate_facts(
        document_text=body.document_text,
        transcript=body.transcript,
        prompt_version=settings.prompt_version,
    )
    return ExtractResponse(
        issue_type_candidate=result.candidate.issue_type_candidate,
        fields={k: v.model_dump() for k, v in result.candidate.fields.items()},
        requires_review=result.candidate.requires_review,
        clarification_question_id=result.candidate.clarification_question_id,
        provider=result.provider,
        model_id=result.model_id,
        prompt_version=result.prompt_version,
        schema_version=result.schema_version,
    )


@router.post("/{incident_id}/facts/confirm", response_model=ConfirmedFactSetResponse)
def post_confirm_facts(
    incident_id: UUID, body: ConfirmFactsRequest, repo: Repo, auth: Auth, settings: Sett
) -> ConfirmedFactSetResponse:
    """F09 - GATE : écran de revue, confirme/corrige/marque UNKNOWN chaque
    champ. Crée une nouvelle révision de ConfirmedFactSet (section 6.3)."""
    payload = body.model_dump(exclude={"issue_id"})
    _, fact_set = confirm_facts(
        repo=repo,
        organization_id=auth.organization_id,
        incident_id=incident_id,
        issue_id=body.issue_id,
        fact_payload=payload,
        confirmed_by=auth.user_id,
        schema_version=settings.schema_version_confirmed,
    )
    return ConfirmedFactSetResponse(
        id=fact_set.id,
        issue_id=fact_set.issue_id,
        schema_version=fact_set.schema_version,
        revision=fact_set.revision,
        confirmed_at=fact_set.confirmed_at,
        missing_quantity=fact_set.confirmed_json.missing_quantity,
    )


@router.post("/{incident_id}/reserve", response_model=GenerateReserveResponse)
def post_reserve(
    incident_id: UUID, repo: Repo, auth: Auth, settings: Sett
) -> GenerateReserveResponse:
    """F10 - GATE zéro invention : compose la réserve UNIQUEMENT à partir des
    ConfirmedFactSet les plus récents (app.domain.reserve_composer)."""
    _, reserve = generate_reserve(
        repo=repo,
        organization_id=auth.organization_id,
        incident_id=incident_id,
        template_version=settings.reserve_template_version,
    )
    from app.domain.templates.fr_v1 import PRUDENCE_MENTION

    return GenerateReserveResponse(
        incident_id=incident_id,
        template_version=reserve.template_version,
        text=reserve.text,
        sha256=reserve.sha256,
        prudence_mention=PRUDENCE_MENTION,
        created_at=reserve.created_at,
    )


@router.post("/{incident_id}/exports", response_model=ExportBundleResponse)
def post_export(
    incident_id: UUID, repo: Repo, auth: Auth, storage: Storage
) -> ExportBundleResponse:
    """F13 - "Générer le dossier PDF" (rendu complet prévu R3, voir docstring
    de generate_export)."""
    export = generate_export(
        repo=repo,
        storage=storage,
        organization_id=auth.organization_id,
        incident_id=incident_id,
    )
    return ExportBundleResponse(**export.model_dump())


@router.get("/{incident_id}/exports/{export_id}", response_model=ExportDownloadResponse)
def get_export_download(
    incident_id: UUID, export_id: UUID, repo: Repo, auth: Auth, storage: Storage, settings: Sett
) -> ExportDownloadResponse:
    """"Signed download" (section 9.1) - SEC-03 : URL signée courte."""
    export = repo.get_export_bundle(auth.organization_id, incident_id, export_id)
    if export is None:
        raise KeyError(str(export_id))
    url = storage.create_signed_download(
        export.pdf_object_key, ttl_seconds=settings.signed_url_ttl_seconds
    )
    return ExportDownloadResponse(
        export_id=export_id, download_url=url, expires_in_seconds=settings.signed_url_ttl_seconds
    )
