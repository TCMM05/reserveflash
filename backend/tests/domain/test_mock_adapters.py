"""Vérifie que les adapters mock respectent les interfaces de
app.application.ports et le GATE de résilience (section 7.4)."""

from uuid import uuid4

import pytest

from app.domain.errors import AIUnavailableError
from app.infrastructure.ai.mock_provider import MockAIProvider
from app.infrastructure.auth.mock_provider import InvalidTokenError, MockAuthProvider
from app.infrastructure.storage.mock_provider import MockStorageProvider


def test_ai_provider_unavailable_never_loses_data_it_just_raises():
    provider = MockAIProvider(raise_unavailable=True)
    with pytest.raises(AIUnavailableError):
        provider.transcribe(b"...", "audio/wav")


def test_ai_provider_extraction_requires_review_by_default():
    provider = MockAIProvider()
    result = provider.extract_candidate_facts(
        document_text=None, transcript="colis abimé", prompt_version="extraction_fr_v1"
    )
    assert result.candidate.requires_review is True


def test_storage_round_trip_presign_upload_download():
    storage = MockStorageProvider()
    org_id, incident_id = uuid4(), uuid4()
    presigned = storage.create_presigned_upload(
        organization_id=org_id, incident_id=incident_id, content_type="image/jpeg"
    )
    assert str(org_id) in presigned.object_key

    storage.write_for_test(presigned.object_key, b"fake-jpeg-bytes")
    confirmation = storage.confirm_upload(presigned.object_key)
    assert confirmation.bytes == len(b"fake-jpeg-bytes")
    assert len(confirmation.sha256) == 64

    url = storage.create_signed_download(presigned.object_key)
    assert presigned.object_key in url


def test_storage_unknown_object_key_raises():
    storage = MockStorageProvider()
    with pytest.raises(KeyError):
        storage.confirm_upload("does-not-exist")


def test_auth_provider_rejects_unknown_token():
    auth = MockAuthProvider()
    with pytest.raises(InvalidTokenError):
        auth.verify_token("unknown-token")


def test_auth_provider_verifies_registered_token():
    auth = MockAuthProvider()
    user_id, org_id = uuid4(), uuid4()
    auth.register_token_for_test("tok-1", user_id=user_id, organization_id=org_id, role="OWNER")
    context = auth.verify_token("tok-1")
    assert context.user_id == user_id
    assert context.organization_id == org_id
    assert context.role == "OWNER"
