"""Test d'intégration ORM contre un vrai PostgreSQL (section 17.1 - "DB:
schéma, migrations, contraintes/index"). Ignoré si aucune base n'est
joignable (ex: poste de dev sans PostgreSQL local) ; exécuté en CI via le
service PostgreSQL défini dans .github/workflows/ci.yml.

Ne teste PAS le repository applicatif (InMemoryIncidentRepository, utilisé
par l'API en R0) mais valide que le mapping SQLAlchemy + les migrations
Alembic produisent bien un schéma cohérent et utilisable (contraintes FK,
UniqueConstraint, isolation multi-tenant par organization_id)."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

import pytest
from sqlalchemy import create_engine, select
from sqlalchemy.exc import IntegrityError, OperationalError
from sqlalchemy.orm import Session

from app.config import get_settings
from app.infrastructure.db.models import (
    ConfirmedFactSetModel,
    IncidentModel,
    IssueModel,
    OrganizationModel,
    UserModel,
)


def _engine_or_skip():
    url = get_settings().database_url
    engine = create_engine(url)
    try:
        with engine.connect():
            pass
    except OperationalError:
        pytest.skip("PostgreSQL non joignable localement - test exécuté en CI.")
    return engine


@pytest.fixture
def session():
    """Une session par test, jamais commitée : `session.close()` abandonne
    la transaction implicite et ne laisse aucune trace en base. On laisse la
    session gérer sa propre transaction plutôt que d'en superposer une au
    niveau connexion, pour rester robuste aux rollbacks explicites déclenchés
    par un IntegrityError attendu dans un test."""
    engine = _engine_or_skip()
    session = Session(bind=engine)
    yield session
    session.close()


def test_incident_requires_existing_organization(session):
    """FK - un incident ne peut pas exister sans organisation valide."""
    incident = IncidentModel(
        id=uuid.uuid4(),
        organization_id=uuid.uuid4(),  # organisation inexistante
        creator_id=uuid.uuid4(),
        status="draft_local",
        local_created_at=datetime.now(UTC),
        occurred_at=datetime.now(UTC),
    )
    session.add(incident)
    with pytest.raises(IntegrityError):
        session.flush()
    session.rollback()


def test_full_write_read_round_trip(session):
    org = OrganizationModel(
        id=uuid.uuid4(), name="Chauffage Dupont", plan="discovery", retention_policy_days=365
    )
    session.add(org)
    session.flush()

    user = UserModel(
        id=uuid.uuid4(), organization_id=org.id, email="marco@example.com", role="OWNER"
    )
    session.add(user)
    session.flush()

    incident = IncidentModel(
        id=uuid.uuid4(),
        organization_id=org.id,
        creator_id=user.id,
        status="draft_local",
        local_created_at=datetime.now(UTC),
        occurred_at=datetime.now(UTC),
        supplier_name="Acme",
    )
    session.add(incident)
    session.flush()

    issue = IssueModel(
        id=uuid.uuid4(),
        incident_id=incident.id,
        issue_type="MISSING_QTY",
        sort_order=0,
        status="OPEN",
    )
    session.add(issue)
    session.flush()

    fact_set = ConfirmedFactSetModel(
        id=uuid.uuid4(),
        issue_id=issue.id,
        schema_version="confirmed_fact_set.v1",
        confirmed_json={
            "issue_type": "MISSING_QTY",
            "expected_quantity": 8,
            "received_quantity": 6,
            "user_uncertainty": False,
            "unknown_fields": [],
            "user_confirmed": True,
        },
        confirmed_by=user.id,
        confirmed_at=datetime.now(UTC),
        revision=1,
    )
    session.add(fact_set)
    session.flush()

    fetched = session.scalars(
        select(ConfirmedFactSetModel).where(ConfirmedFactSetModel.issue_id == issue.id)
    ).one()
    assert fetched.confirmed_json["expected_quantity"] == 8
    assert fetched.revision == 1


def test_confirmed_fact_set_revision_is_unique_per_issue(session):
    """UniqueConstraint('issue_id', 'revision') - reflète l'invariant section
    6.3 (une révision de faits est un incrément strict, jamais dupliqué)."""
    org = OrganizationModel(
        id=uuid.uuid4(), name="Org", plan="discovery", retention_policy_days=365
    )
    session.add(org)
    session.flush()
    user = UserModel(id=uuid.uuid4(), organization_id=org.id, email="a@b.com", role="OWNER")
    session.add(user)
    session.flush()
    incident = IncidentModel(
        id=uuid.uuid4(),
        organization_id=org.id,
        creator_id=user.id,
        status="draft_local",
        local_created_at=datetime.now(UTC),
        occurred_at=datetime.now(UTC),
    )
    session.add(incident)
    session.flush()
    issue = IssueModel(
        id=uuid.uuid4(), incident_id=incident.id, issue_type="OTHER", sort_order=0, status="OPEN"
    )
    session.add(issue)
    session.flush()

    common = {
        "issue_id": issue.id,
        "schema_version": "confirmed_fact_set.v1",
        "confirmed_json": {"issue_type": "OTHER", "user_confirmed": True},
        "confirmed_by": user.id,
        "confirmed_at": datetime.now(UTC),
        "revision": 1,
    }
    session.add(ConfirmedFactSetModel(id=uuid.uuid4(), **common))
    session.flush()
    session.add(ConfirmedFactSetModel(id=uuid.uuid4(), **common))
    with pytest.raises(IntegrityError):
        session.flush()
    session.rollback()
