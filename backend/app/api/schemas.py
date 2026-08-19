"""Schémas de requête/réponse HTTP (section 9). Distincts des entités
domaine (app.domain.entities) pour ne pas coupler le contrat public à la
représentation interne - mais réutilisent les types domaine par composition
quand c'est sûr (ConfirmedFactData, enums)."""

from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict

from app.domain.fact_set import CandidateFactData
from app.domain.value_objects import IncidentStatus, IssueType


class CreateIncidentRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    occurred_at: datetime
    supplier_name: str | None = None
    carrier_name: str | None = None
    delivery_ref: str | None = None
    notes: str | None = None


class PatchIncidentRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    supplier_name: str | None = None
    carrier_name: str | None = None
    delivery_ref: str | None = None
    notes: str | None = None


class IncidentResponse(BaseModel):
    id: UUID
    organization_id: UUID
    status: IncidentStatus
    occurred_at: datetime
    supplier_name: str | None
    carrier_name: str | None
    delivery_ref: str | None
    notes: str | None
    local_created_at: datetime
    server_created_at: datetime | None


class IncidentListResponse(BaseModel):
    items: list[IncidentResponse]
    next_cursor: str | None


class CreateIssueRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    issue_type: IssueType
    sort_order: int = 0


class IssueResponse(BaseModel):
    id: UUID
    incident_id: UUID
    issue_type: str
    sort_order: int
    status: str


class ConfirmFactsRequest(BaseModel):
    """Corps attendu : les champs de schemas/confirmed_fact_set.v1.schema.json
    SANS `user_confirmed` (imposé serveur = True, cette route étant l'acte de
    confirmation elle-même, F09)."""

    model_config = ConfigDict(extra="forbid")

    issue_id: UUID
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


class ConfirmedFactSetResponse(BaseModel):
    id: UUID
    issue_id: UUID
    schema_version: str
    revision: int
    confirmed_at: datetime
    missing_quantity: float | None


class GenerateReserveResponse(BaseModel):
    incident_id: UUID
    template_version: str
    text: str
    sha256: str
    prudence_mention: str
    created_at: datetime


class ExportBundleResponse(BaseModel):
    id: UUID
    incident_id: UUID
    version: int
    sha256: str
    created_at: datetime
    superseded: bool


class ExportDownloadResponse(BaseModel):
    export_id: UUID
    download_url: str
    expires_in_seconds: int


class PresignUploadRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    content_type: str


class PresignUploadResponse(BaseModel):
    upload_url: str
    object_key: str
    expires_at: datetime
    fields: dict[str, str]


class CompleteUploadRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    object_key: str


class CompleteUploadResponse(BaseModel):
    object_key: str
    sha256: str
    bytes: int
    mime_type: str


class TranscribeRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    object_key: str


class TranscribeResponse(BaseModel):
    text: str
    provider: str
    model_id: str
    latency_ms: int


class ExtractRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    document_text: str | None = None
    transcript: str | None = None


class ExtractResponse(BaseModel):
    issue_type_candidate: IssueType | None
    fields: dict
    requires_review: bool
    clarification_question_id: str | None
    provider: str
    model_id: str
    prompt_version: str
    schema_version: str


class TranscribeAudioRequest(BaseModel):
    """R0.1 (points 4/5/14) - route SANS ÉTAT (app/api/routes/ai.py) : ne
    référence aucun incident/organisation. `audio_base64` doit contenir
    UNIQUEMENT l'extrait audio strictement nécessaire à l'opération demandée
    (ex: une note vocale ponctuelle), jamais un enregistrement complet non
    pertinent - c'est à l'app mobile de garantir cette minimisation avant
    l'appel (voir docs/security.md)."""

    model_config = ConfigDict(extra="forbid")

    audio_base64: str
    mime_type: str


class TranscribeAudioResponse(BaseModel):
    text: str
    provider: str
    model_id: str
    latency_ms: int
    request_id: str | None = None


class ExtractCandidateFactsRequest(BaseModel):
    """R0.1 (points 4/5/14) - route SANS ÉTAT : `document_text`/`transcript`
    sont déjà des textes (OCR/transcription), jamais des images/audio bruts
    envoyés "au cas où". Voir docs/security.md pour le détail de ce qui est
    et n'est jamais transmis au provider IA."""

    model_config = ConfigDict(extra="forbid")

    document_text: str | None = None
    transcript: str | None = None
    prompt_version: str


class ExtractCandidateFactsResponse(BaseModel):
    candidate: CandidateFactData
    provider: str
    model_id: str
    prompt_version: str
    schema_version: str
    latency_ms: int
    request_id: str | None = None


class ConfigResponse(BaseModel):
    environment: str
    reserve_template_version: str
    prompt_version: str
    schema_version_confirmed: str
    schema_version_candidate: str


class HealthResponse(BaseModel):
    status: str
