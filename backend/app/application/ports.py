"""Ports (interfaces) vers les providers externes.

Section 5.3 - "Règle de dépendance" : "Les couches doivent dépendre vers le
domaine, jamais vers le provider IA. Le domaine ne connaît ni OpenAI, ni
Supabase, ni Flutter. Les adapters implémentent des interfaces définies côté
application/domaine."

Ces `Protocol` sont la frontière stricte : `app/domain` et `app/application`
ne dépendent QUE de ce module. Les implémentations concrètes (mock, OpenAI,
Supabase Storage, ...) vivent dans `app/infrastructure/*` et sont injectées
au démarrage de l'application (voir app/api/deps.py), jamais importées
directement par une route ou un cas d'usage.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Protocol
from uuid import UUID

from app.domain.entities import ConfirmedFactSet, ExportBundle, Incident, Issue, ReserveText
from app.domain.fact_set import CandidateFactData


@dataclass(frozen=True, slots=True)
class TranscriptionResult:
    text: str
    provider: str
    model_id: str
    latency_ms: int
    request_id: str | None = None


@dataclass(frozen=True, slots=True)
class ExtractionResult:
    """Sortie du pipeline d'extraction (section 7.2, étape 4 "Affichage des
    candidats"). `candidate` doit être conforme à
    schemas/candidate_fact_set.v1.schema.json - c'est l'adapter qui est
    responsable de cette conformité (validée ensuite côté backend, étape 3
    "Validation backend du JSON Schema")."""

    candidate: CandidateFactData
    provider: str
    model_id: str
    prompt_version: str
    schema_version: str
    latency_ms: int
    request_id: str | None = None


class AIProvider(Protocol):
    """Rôle autorisé strictement limité à la section 7.1 : transcrire,
    extraire des champs candidats, détecter l'ambiguïté. Jamais décider
    d'une responsabilité, jamais composer un texte de réserve."""

    def transcribe(self, audio_bytes: bytes, mime_type: str) -> TranscriptionResult:
        """Peut lever AIUnavailableError / AIRateLimitedError (section 7.4).
        Ne doit jamais être appelé sur un flux réseau requis pour la capture
        locale (section 8.1 : la capture ne dépend jamais de l'API/cloud)."""
        ...

    def extract_candidate_facts(
        self,
        *,
        document_text: str | None,
        transcript: str | None,
        prompt_version: str,
    ) -> ExtractionResult:
        """Peut lever AIUnavailableError / AIInvalidOutputError / AIRateLimitedError."""
        ...


@dataclass(frozen=True, slots=True)
class PresignedUpload:
    upload_url: str
    object_key: str
    expires_at: datetime
    fields: dict[str, str]


@dataclass(frozen=True, slots=True)
class UploadConfirmation:
    object_key: str
    sha256: str
    bytes: int
    mime_type: str


class StorageProvider(Protocol):
    """SEC-03 : buckets privés, accès aux médias par URL signée courte.
    L'implémentation ne doit jamais retourner d'URL publique permanente."""

    def create_presigned_upload(
        self, *, organization_id: UUID, incident_id: UUID, content_type: str
    ) -> PresignedUpload: ...

    def confirm_upload(self, object_key: str) -> UploadConfirmation: ...

    def create_signed_download(self, object_key: str, ttl_seconds: int = 300) -> str: ...

    def delete(self, object_key: str) -> None: ...

    def put_object(
        self,
        *,
        organization_id: UUID,
        incident_id: UUID,
        data: bytes,
        content_type: str,
        key_hint: str,
    ) -> UploadConfirmation:
        """Écriture directe côté serveur (ex: PDF généré par le backend,
        section 6.1 ExportBundle) - distincte du flux presign/upload client
        (F02/F06/F11) qui passe toujours par une URL signée courte (SEC-03)."""
        ...


@dataclass(frozen=True, slots=True)
class AuthContext:
    user_id: UUID
    organization_id: UUID
    role: str


class AuthProvider(Protocol):
    """SEC-04/SEC-05 : le JWT est toujours vérifié côté backend ; aucun
    endpoint ne fait confiance à un organization_id fourni par le client
    sans cette vérification (section 9.2)."""

    def verify_token(self, token: str) -> AuthContext:
        """Lève une erreur (mappée en 401 AUTH_REQUIRED) si le token est
        invalide, expiré, ou révoqué."""
        ...

    def create_magic_link(self, email: str) -> str: ...


class BillingProvider(Protocol):
    """section 12.1 - abstraction obligatoire (BillingService) pour unifier
    les entitlements, indépendamment du store (Apple/Google) ou de
    RevenueCat. Le domaine ne connaît aucun de ces noms."""

    def get_entitlement_status(self, organization_id: UUID, product_id: str) -> str: ...


@dataclass(frozen=True, slots=True)
class Page:
    items: list[Incident]
    next_cursor: str | None


class IncidentRepository(Protocol):
    """Port de persistence (section 9 - endpoints /v1). L'implémentation de
    référence R0 est en mémoire (app/infrastructure/db/in_memory_repository.py) ;
    une implémentation PostgreSQL (section 6, 17.1 "DB") respectant le même
    port sera branchée en R4 sans changer les routes ni le domaine (section
    5.3)."""

    def create_incident(self, incident: Incident, *, idempotency_key: str) -> Incident:
        """Doit être idempotent sur (organization_id, idempotency_key)
        (section 9.2 : "Idempotency-Key obligatoire sur créations
        critiques")."""
        ...

    def get_incident(self, organization_id: UUID, incident_id: UUID) -> Incident | None: ...

    def list_incidents(
        self,
        organization_id: UUID,
        *,
        status: str | None = None,
        cursor: str | None = None,
        limit: int = 20,
    ) -> Page: ...

    def update_incident_metadata(
        self, organization_id: UUID, incident_id: UUID, patch: dict
    ) -> Incident: ...

    def delete_incident(self, organization_id: UUID, incident_id: UUID) -> None: ...

    def save_issue(self, issue: Issue) -> Issue: ...

    def get_issue(self, organization_id: UUID, issue_id: UUID) -> Issue | None: ...

    def list_issues_for_incident(self, incident_id: UUID) -> list[Issue]: ...

    def save_confirmed_fact_set(self, fact_set: ConfirmedFactSet) -> ConfirmedFactSet:
        """Une nouvelle révision invalide automatiquement la réserve/le PDF
        précédents (invariant section 6.3) - c'est à l'appelant (use case)
        d'orchestrer cette invalidation, ce port se contente de stocker."""
        ...

    def latest_confirmed_fact_set(self, issue_id: UUID) -> ConfirmedFactSet | None: ...

    def list_latest_confirmed_fact_sets_for_incident(
        self, incident_id: UUID
    ) -> list[ConfirmedFactSet]: ...

    def save_reserve_text(self, reserve: ReserveText) -> ReserveText: ...

    def latest_reserve_text(self, incident_id: UUID) -> ReserveText | None: ...

    def invalidate_reserve_text(self, incident_id: UUID) -> None:
        """section 6.3 : une nouvelle révision de faits confirmés invalide
        automatiquement la réserve précédente. Après cet appel,
        `latest_reserve_text` doit redevenir None jusqu'à recomposition
        explicite via POST /incidents/{id}/reserve."""
        ...

    def save_export_bundle(self, export: ExportBundle) -> ExportBundle: ...

    def get_export_bundle(
        self, organization_id: UUID, incident_id: UUID, export_id: UUID
    ) -> ExportBundle | None: ...

    def supersede_previous_exports(self, incident_id: UUID) -> None:
        """section 8.2 : "Export généré avant nouvelle révision -> Marquer
        export superseded ; ne pas l'écraser silencieusement."""
        ...

    def next_export_version(self, incident_id: UUID) -> int:
        """Numéro de version à utiliser pour le prochain ExportBundle de cet
        incident (1, 2, 3, ...)."""
        ...
