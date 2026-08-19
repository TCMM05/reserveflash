"""Tests des routes /v1/ai/* (R0.1, points 4/5) - le backend comme proxy IA
sans état. Vérifie explicitement : pas d'authentification requise (point 13),
aucune notion d'incident/organisation dans le contrat, sortie structurée
conforme au schéma candidate_fact_set (validation de structure, point 4)."""

from __future__ import annotations

import base64


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
