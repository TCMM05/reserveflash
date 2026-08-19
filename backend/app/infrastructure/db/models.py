"""Modèles SQLAlchemy 2.0 - mapping ORM du modèle de données canonique
(section 6.1). Distincts des entités domaine (app.domain.entities) : ce
module connaît PostgreSQL, le domaine ne le connaît jamais (section 5.3).

Conventions (section 6/5.1) :
  - UUID pour tous les identifiants (`gen_random_uuid()` côté PostgreSQL,
    extension pgcrypto requise - voir migration initiale).
  - Timestamps toujours en UTC (`timezone=True`, jamais de datetime naïf).
  - `organization_id` présent sur toute table multi-tenant, indexé, pour
    permettre l'isolation par organisation (SEC-04) même sans RLS activée.
  - Aucune migration manuelle en production (section 5.1) : tout schéma
    passe par une révision Alembic (voir alembic/versions/).
"""

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import (
    Boolean,
    ForeignKey,
    Index,
    Integer,
    String,
    UniqueConstraint,
)
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship
from sqlalchemy.sql import func


class Base(DeclarativeBase):
    pass


def _uuid_pk() -> Mapped[uuid.UUID]:
    return mapped_column(
        UUID(as_uuid=True), primary_key=True, server_default=func.gen_random_uuid()
    )


class OrganizationModel(Base):
    __tablename__ = "organizations"

    id: Mapped[uuid.UUID] = _uuid_pk()
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    plan: Mapped[str] = mapped_column(String(50), nullable=False, default="discovery")
    created_at: Mapped[datetime] = mapped_column(
        server_default=func.now(), nullable=False
    )
    retention_policy_days: Mapped[int] = mapped_column(Integer, nullable=False, default=365)


class UserModel(Base):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = _uuid_pk()
    organization_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("organizations.id", ondelete="CASCADE"), nullable=False
    )
    email: Mapped[str] = mapped_column(String(320), nullable=False)
    role: Mapped[str] = mapped_column(String(20), nullable=False, default="MEMBER")
    created_at: Mapped[datetime] = mapped_column(server_default=func.now(), nullable=False)
    deleted_at: Mapped[datetime | None] = mapped_column(nullable=True)

    __table_args__ = (
        UniqueConstraint("organization_id", "email", name="uq_users_org_email"),
        Index("ix_users_organization_id", "organization_id"),
    )


class IncidentModel(Base):
    __tablename__ = "incidents"

    id: Mapped[uuid.UUID] = _uuid_pk()
    organization_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("organizations.id", ondelete="CASCADE"), nullable=False
    )
    creator_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="RESTRICT"), nullable=False
    )
    status: Mapped[str] = mapped_column(String(30), nullable=False, default="draft_local")
    local_created_at: Mapped[datetime] = mapped_column(nullable=False)
    server_created_at: Mapped[datetime | None] = mapped_column(
        server_default=func.now(), nullable=True
    )
    occurred_at: Mapped[datetime] = mapped_column(nullable=False)
    supplier_name: Mapped[str | None] = mapped_column(String(200), nullable=True)
    carrier_name: Mapped[str | None] = mapped_column(String(200), nullable=True)
    delivery_ref: Mapped[str | None] = mapped_column(String(100), nullable=True)
    notes: Mapped[str | None] = mapped_column(String(2000), nullable=True)

    issues: Mapped[list[IssueModel]] = relationship(back_populates="incident")

    __table_args__ = (
        Index("ix_incidents_organization_id", "organization_id"),
        Index("ix_incidents_organization_status", "organization_id", "status"),
    )


class DeliveryDocumentModel(Base):
    __tablename__ = "delivery_documents"

    id: Mapped[uuid.UUID] = _uuid_pk()
    incident_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("incidents.id", ondelete="CASCADE"), nullable=False
    )
    document_type: Mapped[str] = mapped_column(String(50), nullable=False)
    ocr_status: Mapped[str] = mapped_column(String(30), nullable=False, default="pending")
    extracted_metadata_json: Mapped[dict] = mapped_column(JSONB, nullable=False, default=dict)
    confirmed_metadata_json: Mapped[dict | None] = mapped_column(JSONB, nullable=True)

    __table_args__ = (Index("ix_delivery_documents_incident_id", "incident_id"),)


class IssueModel(Base):
    __tablename__ = "issues"

    id: Mapped[uuid.UUID] = _uuid_pk()
    incident_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("incidents.id", ondelete="CASCADE"), nullable=False
    )
    issue_type: Mapped[str] = mapped_column(String(40), nullable=False)
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    status: Mapped[str] = mapped_column(String(30), nullable=False, default="OPEN")

    incident: Mapped[IncidentModel] = relationship(back_populates="issues")

    __table_args__ = (Index("ix_issues_incident_id", "incident_id"),)


class CandidateFactSetModel(Base):
    __tablename__ = "candidate_fact_sets"

    id: Mapped[uuid.UUID] = _uuid_pk()
    issue_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("issues.id", ondelete="CASCADE"), nullable=False
    )
    schema_version: Mapped[str] = mapped_column(String(60), nullable=False)
    prompt_version: Mapped[str] = mapped_column(String(60), nullable=False)
    model: Mapped[str] = mapped_column(String(100), nullable=False)
    raw_structured_json: Mapped[dict] = mapped_column(JSONB, nullable=False)
    created_at: Mapped[datetime] = mapped_column(server_default=func.now(), nullable=False)

    __table_args__ = (Index("ix_candidate_fact_sets_issue_id", "issue_id"),)


class ConfirmedFactSetModel(Base):
    __tablename__ = "confirmed_fact_sets"

    id: Mapped[uuid.UUID] = _uuid_pk()
    issue_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("issues.id", ondelete="CASCADE"), nullable=False
    )
    schema_version: Mapped[str] = mapped_column(String(60), nullable=False)
    confirmed_json: Mapped[dict] = mapped_column(JSONB, nullable=False)
    confirmed_by: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="RESTRICT"), nullable=False
    )
    confirmed_at: Mapped[datetime] = mapped_column(server_default=func.now(), nullable=False)
    revision: Mapped[int] = mapped_column(Integer, nullable=False)

    __table_args__ = (
        UniqueConstraint("issue_id", "revision", name="uq_confirmed_fact_sets_issue_revision"),
        Index("ix_confirmed_fact_sets_issue_id", "issue_id"),
    )


class EvidenceAssetModel(Base):
    __tablename__ = "evidence_assets"

    id: Mapped[uuid.UUID] = _uuid_pk()
    incident_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("incidents.id", ondelete="CASCADE"), nullable=False
    )
    issue_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("issues.id", ondelete="SET NULL"), nullable=True
    )
    type: Mapped[str] = mapped_column(String(40), nullable=False)
    original_object_key: Mapped[str] = mapped_column(String(500), nullable=False)
    preview_object_key: Mapped[str | None] = mapped_column(String(500), nullable=True)
    sha256: Mapped[str] = mapped_column(String(64), nullable=False)
    mime_type: Mapped[str] = mapped_column(String(100), nullable=False)
    bytes: Mapped[int] = mapped_column(Integer, nullable=False)
    captured_at_device: Mapped[datetime] = mapped_column(nullable=False)
    uploaded_at: Mapped[datetime | None] = mapped_column(nullable=True)
    sync_status: Mapped[str] = mapped_column(String(20), nullable=False, default="local")

    __table_args__ = (
        Index("ix_evidence_assets_incident_id", "incident_id"),
        # Immutabilité (invariant section 6.3) : un même original ne doit
        # jamais être réécrit ; une nouvelle capture crée toujours un nouvel
        # asset (nouvelle ligne), jamais un UPDATE de original_object_key.
        UniqueConstraint("original_object_key", name="uq_evidence_assets_original_key"),
    )


class ReserveTextModel(Base):
    __tablename__ = "reserve_texts"

    id: Mapped[uuid.UUID] = _uuid_pk()
    incident_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("incidents.id", ondelete="CASCADE"), nullable=False
    )
    template_version: Mapped[str] = mapped_column(String(30), nullable=False)
    confirmed_fact_revision: Mapped[int] = mapped_column(Integer, nullable=False)
    text: Mapped[str] = mapped_column(String, nullable=False)
    sha256: Mapped[str] = mapped_column(String(64), nullable=False)
    created_at: Mapped[datetime] = mapped_column(server_default=func.now(), nullable=False)

    __table_args__ = (Index("ix_reserve_texts_incident_id", "incident_id"),)


class ExportBundleModel(Base):
    __tablename__ = "export_bundles"

    id: Mapped[uuid.UUID] = _uuid_pk()
    incident_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("incidents.id", ondelete="CASCADE"), nullable=False
    )
    version: Mapped[int] = mapped_column(Integer, nullable=False)
    pdf_object_key: Mapped[str] = mapped_column(String(500), nullable=False)
    sha256: Mapped[str] = mapped_column(String(64), nullable=False)
    created_at: Mapped[datetime] = mapped_column(server_default=func.now(), nullable=False)
    superseded: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)

    __table_args__ = (
        UniqueConstraint("incident_id", "version", name="uq_export_bundles_incident_version"),
        Index("ix_export_bundles_incident_id", "incident_id"),
    )


class ReminderModel(Base):
    __tablename__ = "reminders"

    id: Mapped[uuid.UUID] = _uuid_pk()
    incident_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("incidents.id", ondelete="CASCADE"), nullable=False
    )
    rule_pack_id: Mapped[str | None] = mapped_column(String(100), nullable=True)
    due_at: Mapped[datetime] = mapped_column(nullable=False)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="pending")
    label: Mapped[str] = mapped_column(String(200), nullable=False)

    __table_args__ = (Index("ix_reminders_incident_id", "incident_id"),)


class AuditEventModel(Base):
    __tablename__ = "audit_events"

    id: Mapped[uuid.UUID] = _uuid_pk()
    organization_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("organizations.id", ondelete="CASCADE"), nullable=False
    )
    incident_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("incidents.id", ondelete="SET NULL"), nullable=True
    )
    actor_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    event_type: Mapped[str] = mapped_column(String(60), nullable=False)
    # Nom du champ rappelle explicitement l'exigence SEC-06 : jamais de
    # donnée métier brute (photo/audio/document/adresse/nom) ici.
    metadata_safe_json: Mapped[dict] = mapped_column(JSONB, nullable=False, default=dict)
    created_at: Mapped[datetime] = mapped_column(server_default=func.now(), nullable=False)

    __table_args__ = (
        Index("ix_audit_events_organization_id", "organization_id"),
        Index("ix_audit_events_incident_id", "incident_id"),
    )


class EntitlementModel(Base):
    __tablename__ = "entitlements"

    organization_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("organizations.id", ondelete="CASCADE"),
        primary_key=True,
    )
    source: Mapped[str] = mapped_column(String(30), primary_key=True)
    product_id: Mapped[str] = mapped_column(String(60), primary_key=True)
    status: Mapped[str] = mapped_column(String(20), nullable=False)
    valid_until: Mapped[datetime | None] = mapped_column(nullable=True)
