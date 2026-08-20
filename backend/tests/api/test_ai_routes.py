"""Tests des routes /v1/ai/* (R0.1, points 4/5) - le backend comme proxy IA
sans état. Vérifie explicitement : pas d'authentification requise (point 13),
aucune notion d'incident/organisation dans le contrat, sortie structurée
conforme au schéma candidate_fact_set (validation de structure, point 4)."""

from __future__ import annotations

import base64

from app.api.deps import get_ai_provider
from app.domain.fact_set import CandidateFactData
from app.domain.value_objects import ConfidenceLevel, FactSource, IssueType
from app.infrastructure.ai.mock_provider import MockAIProvider


def test_transcribe_requires_no_authentication(client):
    """Point 13 : aucune création de compte cloud requise. Aucun header
    Authorization n'est envoyé ici, contrairement aux tests de
    test_incidents_flow.py."""
    payload = {"audio_base64": base64.b64encode(b"fake-audio").decode(), "mime_type": "audio/wav"}
    response = client.post("/v1/ai/transcribe", json=payload)
    assert response.status_code == 200
    body = response.json()
    assert body["provider"] == "mock"
    assert "text" in body


def test_transcribe_rejects_unexpected_fields(client):
    payload = {
        "audio_base64": base64.b64encode(b"x").decode(),
        "mime_type": "audio/wav",
        "incident_id": "should-not-be-accepted",
    }
    response = client.post("/v1/ai/transcribe", json=payload)
    assert response.status_code == 400
    assert response.json()["code"] == "VALIDATION_ERROR"


def test_extract_returns_structurally_valid_candidate(client):
    payload = {"document_text": "carton abîmé", "prompt_version": "v1"}
    response = client.post("/v1/ai/extract", json=payload)
    assert response.status_code == 200
    body = response.json()
    assert body["schema_version"] == "candidate_fact_set.v1"
    # La structure de CandidateFactData (extra="forbid") est déjà la
    # validation de structure exigée par le point 4 - une réponse provider
    # non conforme lèverait une erreur de validation pydantic AVANT d'arriver
    # ici (voir app/infrastructure/ai/mock_provider.py).
    assert "candidate" in body
    assert "requires_review" in body["candidate"]


def test_extract_rejects_extra_fields(client):
    payload = {"document_text": "x", "prompt_version": "v1", "unexpected_field": "nope"}
    response = client.post("/v1/ai/extract", json=payload)
    assert response.status_code == 400
    assert response.json()["code"] == "VALIDATION_ERROR"


def test_extract_screens_out_forbidden_content_even_from_a_compliant_provider(client):
    """R2 - "Validation sémantique obligatoire" : même si le provider IA
    (ici forcé via un mock injecté) renvoie un candidat structurellement
    valide mais contenant le cas nommément cité par l'équipe
    (packaging_condition = "transporteur responsable"), la route /v1/ai/extract
    ne doit jamais le laisser passer tel quel."""
    forced = CandidateFactData(
        issue_type_candidate=IssueType.PACKAGING_DAMAGE,
        fields={
            "packaging_condition": {
                "value": "transporteur responsable",
                "source": FactSource.VOICE_TRANSCRIPT,
                "confidence": ConfidenceLevel.HIGH,
                "ambiguous": False,
            },
            "product_label": {
                "value": "PAC-284",
                "source": FactSource.VOICE_TRANSCRIPT,
                "confidence": ConfidenceLevel.HIGH,
                "ambiguous": False,
            },
        },
        requires_review=False,
    )
    client.app.dependency_overrides[get_ai_provider] = lambda: MockAIProvider(
        forced_extraction=forced
    )
    try:
        payload = {
            "transcript": "c'est clairement la faute du transporteur",
            "prompt_version": "v1",
        }
        response = client.post("/v1/ai/extract", json=payload)
    finally:
        del client.app.dependency_overrides[get_ai_provider]

    assert response.status_code == 200
    body = response.json()["candidate"]
    assert "packaging_condition" not in body["fields"]
    assert "product_label" in body["fields"]
    assert body["requires_review"] is True


def test_extract_provider_unavailable_maps_to_503(client):
    """R2 - "Échec IA" : une indisponibilité provider ne doit jamais faire
    perdre de preuve ni renvoyer une erreur 500 opaque - 503 AI_UNAVAILABLE,
    conforme à la taxonomie d'erreurs existante (app/api/errors.py)."""
    client.app.dependency_overrides[get_ai_provider] = lambda: MockAIProvider(
        raise_unavailable=True
    )
    try:
        response = client.post(
            "/v1/ai/extract", json={"document_text": "x", "prompt_version": "v1"}
        )
    finally:
        del client.app.dependency_overrides[get_ai_provider]

    assert response.status_code == 503
    assert response.json()["code"] == "AI_UNAVAILABLE"


def test_transcribe_provider_unavailable_maps_to_503(client):
    client.app.dependency_overrides[get_ai_provider] = lambda: MockAIProvider(
        raise_unavailable=True
    )
    try:
        payload = {"audio_base64": base64.b64encode(b"x").decode(), "mime_type": "audio/wav"}
        response = client.post("/v1/ai/transcribe", json=payload)
    finally:
        del client.app.dependency_overrides[get_ai_provider]

    assert response.status_code == 503
    assert response.json()["code"] == "AI_UNAVAILABLE"


def test_ai_routes_do_not_expose_incident_or_organization_concepts(client):
    """Point 4 : le backend ne doit plus être la base centrale des incidents.
    Vérifié structurellement ici : le contrat des routes /v1/ai/* ne contient
    aucun champ incident_id/organization_id, contrairement à
    /v1/incidents/*."""
    openapi = client.get("/openapi.json").json()
    ai_paths = {path: spec for path, spec in openapi["paths"].items() if path.startswith("/v1/ai/")}
    assert ai_paths, "les routes /v1/ai/* doivent être présentes dans l'OpenAPI"
    for spec in ai_paths.values():
        as_text = str(spec)
        assert "incident_id" not in as_text
        assert "organization_id" not in as_text
