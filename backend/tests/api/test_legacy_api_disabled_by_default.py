"""R0.2 (retour de recette R0.1, point "API uniquement Local-First") :
`/v1/incidents/*` (CRUD complet, chemin optionnel/futur) ne doit PAS être
exposé par défaut - seuls `/health`, `/v1/config`, `/v1/ai/transcribe` et
`/v1/ai/extract` (le rôle primaire V1) doivent l'être.

Ce fichier construit sa PROPRE app (comme test_postgres_not_required.py),
sans passer par le fixture `client` de conftest.py, qui active
volontairement le flag legacy pour continuer à tester ce code conservé
(voir sa docstring)."""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from app.config import get_settings


@pytest.fixture
def default_app(monkeypatch):
    # Aucune variable d'environnement positionnée ici : on veut le
    # comportement de configuration RÉEL par défaut, pas un override de test.
    monkeypatch.delenv("RESERVEFLASH_ENABLE_LEGACY_CLOUD_INCIDENT_API", raising=False)
    get_settings.cache_clear()
    from app.main import create_app

    app = create_app()
    yield app
    get_settings.cache_clear()


def test_incidents_routes_are_not_mounted_by_default(default_app):
    client = TestClient(default_app)
    response = client.get("/v1/incidents")
    # 404 (route inexistante), jamais 401/403 (qui prouveraient que la route
    # existe mais est protégée) - la route n'existe tout simplement pas.
    assert response.status_code == 404


def test_openapi_does_not_list_incidents_paths_by_default(default_app):
    client = TestClient(default_app)
    openapi = client.get("/openapi.json").json()
    incident_paths = [p for p in openapi["paths"] if p.startswith("/v1/incidents")]
    assert incident_paths == []


def test_v1_ai_and_config_remain_mounted_by_default(default_app):
    """Le chemin V1 primaire, lui, reste bien présent."""
    client = TestClient(default_app)
    openapi = client.get("/openapi.json").json()
    assert "/v1/config" in openapi["paths"]
    assert "/v1/ai/transcribe" in openapi["paths"]
    assert "/v1/ai/extract" in openapi["paths"]


def test_enabling_the_flag_explicitly_remounts_incidents_routes(monkeypatch):
    """Contre-preuve : le chemin reste accessible si explicitement activé
    (usage dev/test du chemin cloud futur, jamais un déploiement V1)."""
    monkeypatch.setenv("RESERVEFLASH_ENABLE_LEGACY_CLOUD_INCIDENT_API", "true")
    get_settings.cache_clear()
    from app.main import create_app

    app = create_app()
    client = TestClient(app)
    openapi = client.get("/openapi.json").json()
    assert "/v1/incidents" in openapi["paths"]
    get_settings.cache_clear()
