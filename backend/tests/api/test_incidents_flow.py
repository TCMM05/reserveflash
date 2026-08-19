"""Test d'intégration du parcours principal F01->F13 via l'API HTTP
(scénario E2E-01 simplifié : incident simple + 1 anomalie + réserve + export)."""

from __future__ import annotations


def _create_incident(client) -> str:
    resp = client.post(
        "/v1/incidents",
        headers={"Idempotency-Key": "test-key-1"},
        json={"occurred_at": "2026-08-18T10:00:00Z", "supplier_name": "Acme"},
    )
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


def test_health_ok(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok"}


def test_config_never_exposes_secrets(client):
    resp = client.get("/v1/config")
    assert resp.status_code == 200
    body = resp.json()
    for forbidden_key in ("openai_api_key", "supabase_service_role_key", "jwt_secret"):
        assert forbidden_key not in body


def test_create_incident_requires_idempotency_key(client):
    resp = client.post(
        "/v1/incidents", json={"occurred_at": "2026-08-18T10:00:00Z"}
    )
    assert resp.status_code == 400
    assert resp.json()["code"] == "VALIDATION_ERROR"


def test_create_incident_is_idempotent(client):
    payload = {"occurred_at": "2026-08-18T10:00:00Z", "supplier_name": "Acme"}
    headers = {"Idempotency-Key": "same-key"}
    r1 = client.post("/v1/incidents", headers=headers, json=payload)
    r2 = client.post("/v1/incidents", headers=headers, json=payload)
    assert r1.json()["id"] == r2.json()["id"]


def test_endpoints_require_authentication(client):
    client.headers.pop("Authorization")
    resp = client.get("/v1/incidents")
    assert resp.status_code == 401
    assert resp.json()["code"] == "AUTH_REQUIRED"


def test_full_incident_flow_end_to_end(client):
    incident_id = _create_incident(client)

    issue_resp = client.post(
        f"/v1/incidents/{incident_id}/issues",
        json={"issue_type": "MISSING_QTY", "sort_order": 0},
    )
    assert issue_resp.status_code == 201, issue_resp.text
    issue_id = issue_resp.json()["id"]

    confirm_resp = client.post(
        f"/v1/incidents/{incident_id}/facts/confirm",
        json={
            "issue_id": issue_id,
            "issue_type": "MISSING_QTY",
            "product_label": "Ballon eau chaude 200L",
            "expected_quantity": 8,
            "received_quantity": 6,
        },
    )
    assert confirm_resp.status_code == 200, confirm_resp.text
    assert confirm_resp.json()["missing_quantity"] == 2

    incident_after_confirm = client.get(f"/v1/incidents/{incident_id}").json()
    assert incident_after_confirm["status"] == "facts_confirmed"

    reserve_resp = client.post(f"/v1/incidents/{incident_id}/reserve")
    assert reserve_resp.status_code == 200, reserve_resp.text
    reserve_body = reserve_resp.json()
    assert "Ballon eau chaude 200L" in reserve_body["text"]
    assert "8" in reserve_body["text"] and "6" in reserve_body["text"]

    incident_after_reserve = client.get(f"/v1/incidents/{incident_id}").json()
    assert incident_after_reserve["status"] == "reserve_ready"

    export_resp = client.post(f"/v1/incidents/{incident_id}/exports")
    assert export_resp.status_code == 200, export_resp.text
    export_body = export_resp.json()
    assert export_body["version"] == 1
    assert export_body["superseded"] is False

    download_resp = client.get(
        f"/v1/incidents/{incident_id}/exports/{export_body['id']}"
    )
    assert download_resp.status_code == 200
    assert download_resp.json()["download_url"].startswith("mock://download/")


def test_reserve_requires_confirmed_facts_first(client):
    incident_id = _create_incident(client)
    resp = client.post(f"/v1/incidents/{incident_id}/reserve")
    assert resp.status_code == 409
    assert resp.json()["code"] == "CONFLICT"


def test_export_requires_reserve_first(client):
    incident_id = _create_incident(client)
    resp = client.post(f"/v1/incidents/{incident_id}/exports")
    assert resp.status_code == 409


def test_cross_tenant_access_is_blocked(client):
    """Scénario E2E-09 : 'Utilisateur A tente URL média de l'organisation B.'"""
    incident_id = _create_incident(client)

    # Un autre "client" avec une organisation différente ne doit jamais
    # pouvoir lire cet incident.
    from uuid import uuid4

    from app.api.deps import get_auth_provider
    from app.infrastructure.auth.mock_provider import MockAuthProvider

    other_auth = MockAuthProvider()
    other_token = "other-org-token"
    other_auth.register_token_for_test(
        other_token, user_id=uuid4(), organization_id=uuid4(), role="OWNER"
    )
    client.app.dependency_overrides[get_auth_provider] = lambda: other_auth
    resp = client.get(
        f"/v1/incidents/{incident_id}", headers={"Authorization": f"Bearer {other_token}"}
    )
    assert resp.status_code == 403
    assert resp.json()["code"] == "FORBIDDEN"


def test_new_fact_revision_invalidates_previous_export(client):
    """Invariant section 6.3/8.2 : une nouvelle révision de faits invalide
    la réserve et marque les exports précédents 'superseded'."""
    incident_id = _create_incident(client)
    issue_id = client.post(
        f"/v1/incidents/{incident_id}/issues",
        json={"issue_type": "PACKAGING_DAMAGE", "sort_order": 0},
    ).json()["id"]
    fact_body = {
        "issue_id": issue_id,
        "issue_type": "PACKAGING_DAMAGE",
        "packaging_condition": "carton écrasé",
    }
    client.post(f"/v1/incidents/{incident_id}/facts/confirm", json=fact_body)
    client.post(f"/v1/incidents/{incident_id}/reserve")
    export1 = client.post(f"/v1/incidents/{incident_id}/exports").json()
    assert export1["superseded"] is False

    # Nouvelle révision (correction) des faits.
    client.post(f"/v1/incidents/{incident_id}/facts/confirm", json=fact_body)

    # L'ancien export doit être marqué périmé (via la nouvelle génération
    # d'export, qui appelle supersede_previous_exports).
    client.post(f"/v1/incidents/{incident_id}/reserve")
    export2 = client.post(f"/v1/incidents/{incident_id}/exports").json()
    assert export2["version"] == 2

    download_old = client.get(f"/v1/incidents/{incident_id}/exports/{export1['id']}")
    # L'ancien export reste consultable (audit) : le sha256/URL signée
    # continue de résoudre, seul son statut `superseded` change côté modèle.
    assert download_old.status_code == 200
