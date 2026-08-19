"""R0.1 (point 11) : "PostgreSQL n'est plus une dépendance runtime
obligatoire pour la V1 [...] la V1 doit démarrer et fonctionner
correctement SANS PostgreSQL."

Ce test prouve, plutôt que de l'affirmer dans la documentation seule, que
`create_app()` et le parcours HTTP de base ne touchent JAMAIS PostgreSQL :
`RESERVEFLASH_DATABASE_URL` pointe ici vers un hôte inexistant, et l'API
répond quand même normalement. Seuls `alembic upgrade head` (migration
manuelle, hors runtime) et `pytest tests/db` (skip explicite si PostgreSQL
indisponible, voir tests/db/test_models_smoke.py) touchent réellement une
base PostgreSQL - jamais le serveur applicatif lui-même."""

from __future__ import annotations

import base64

import pytest
from fastapi.testclient import TestClient

from app.config import get_settings


@pytest.fixture
def app_without_reachable_postgres(monkeypatch):
    # Hôte volontairement inexistant : si quoi que ce soit dans le chemin de
    # démarrage ou d'appel HTTP tentait une connexion réseau vers Postgres,
    # ce test échouerait par timeout/erreur de connexion plutôt que de
    # réussir.
    monkeypatch.setenv(
        "RESERVEFLASH_DATABASE_URL",
        "postgresql+psycopg://nope:nope@postgres-does-not-exist.invalid:5432/nope",
    )
    get_settings.cache_clear()
    from app.main import create_app

    app = create_app()
    yield app
    get_settings.cache_clear()


def test_app_starts_without_reachable_postgres(app_without_reachable_postgres):
    assert len(app_without_reachable_postgres.routes) > 0


def test_health_endpoint_works_without_postgres(app_without_reachable_postgres):
    client = TestClient(app_without_reachable_postgres)
    response = client.get("/health")
    assert response.status_code == 200


def test_ai_proxy_endpoint_works_without_postgres(app_without_reachable_postgres):
    """Le chemin primaire V1 (points 4/11) : un appel IA de bout en bout ne
    doit jamais dépendre de PostgreSQL."""
    client = TestClient(app_without_reachable_postgres)
    payload = {"audio_base64": base64.b64encode(b"x").decode(), "mime_type": "audio/wav"}
    response = client.post("/v1/ai/transcribe", json=payload)
    assert response.status_code == 200
