"""Machine à états métier d'un incident (section 2.2)."""

from datetime import UTC, datetime
from uuid import uuid4

import pytest

from app.domain.entities import Incident
from app.domain.errors import InvalidStateTransitionError
from app.domain.value_objects import IncidentStatus


def _incident(status: IncidentStatus) -> Incident:
    now = datetime.now(UTC)
    return Incident(
        id=uuid4(),
        organization_id=uuid4(),
        creator_id=uuid4(),
        status=status,
        local_created_at=now,
        occurred_at=now,
    )


def test_draft_local_can_move_to_syncing():
    incident = _incident(IncidentStatus.DRAFT_LOCAL)
    updated = incident.transition_to(IncidentStatus.SYNCING)
    assert updated.status == IncidentStatus.SYNCING


def test_cannot_skip_review_required_to_go_straight_to_reserve_ready():
    incident = _incident(IncidentStatus.EXTRACTION_PENDING)
    with pytest.raises(InvalidStateTransitionError):
        incident.transition_to(IncidentStatus.RESERVE_READY)


def test_exported_can_be_reopened_manually():
    """'archived -> réouverture manuelle' et 'exported -> archived ou
    réouverture' (section 2.2, F15 réouverture)."""
    incident = _incident(IncidentStatus.EXPORTED)
    reopened = incident.transition_to(IncidentStatus.REVIEW_REQUIRED)
    assert reopened.status == IncidentStatus.REVIEW_REQUIRED


def test_transition_is_immutable_original_untouched():
    incident = _incident(IncidentStatus.DRAFT_LOCAL)
    incident.transition_to(IncidentStatus.SYNCING)
    assert incident.status == IncidentStatus.DRAFT_LOCAL
