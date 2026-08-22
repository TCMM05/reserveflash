from __future__ import annotations

from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.api.deps import (
    get_ai_budget_guard,
    get_auth_provider,
    get_repository,
    get_storage_provider,
)
from app.config import get_settings
from app.infrastructure.auth.mock_provider import MockAuthProvider
from app.infrastructure.db.in_memory_repository import InMemoryIncidentRepository
from app.infrastructure.storage.mock_provider import MockStorageProvider
from app.main import create_app


@pytest.fixture
def org_id():
    return uuid4()


@pytest.fixture
def user_id():
    return uuid4()


@pytest.fixture
def client(org_id, user_id, monkeypatch):
    # R0.2 : `/v1/incidents/*` n'est plus monté par défaut (voir
    # app/main.py, app/config.py::enable_legacy_cloud_incident_api). Ce
    # fixture partagé sert à la fois les tests du chemin cloud optionnel/
    # futur (test_incidents_flow.py) et les tests du chemin V1 primaire
    # (test_ai_routes.py) : on l'active explicitement ICI, dans
    # l'environnement de test, pour continuer à couvrir ce code conservé -
    # jamais comme valeur par défaut de production (voir
    # tests/api/test_legacy_api_disabled_by_default.py pour la preuve que le
    # défaut réel reste désactivé).
    monkeypatch.setenv("RESERVEFLASH_ENABLE_LEGACY_CLOUD_INCIDENT_API", "true")
    get_settings.cache_clear()
    # Point 12 (gouvernance coût/tokens IA) : get_ai_budget_guard est aussi
    # @lru_cache (voir app/api/deps.py) - sans ce clear, un test qui
    # configure RESERVEFLASH_AI_DAILY_BUDGET_USD verrait un disjoncteur
    # construit avec la valeur d'un test précédent (compteur ET seuil
    # figés dans le cache lru).
    get_ai_budget_guard.cache_clear()
    app = create_app()

    repo = InMemoryIncidentRepository()
    auth_provider = MockAuthProvider()
    storage_provider = MockStorageProvider()
    token = "test-token"
    auth_provider.register_token_for_test(
        token, user_id=user_id, organization_id=org_id, role="OWNER"
    )

    # Une seule instance par test, réutilisée à chaque requête (une lambda
    # qui recréerait l'objet à chaque appel romprait la persistance en
    # mémoire attendue entre écriture et lecture d'un même objet).
    app.dependency_overrides[get_repository] = lambda: repo
    app.dependency_overrides[get_auth_provider] = lambda: auth_provider
    app.dependency_overrides[get_storage_provider] = lambda: storage_provider

    with TestClient(app) as test_client:
        test_client.headers.update({"Authorization": f"Bearer {token}"})
        yield test_client

    app.dependency_overrides.clear()
    get_settings.cache_clear()
    get_ai_budget_guard.cache_clear()
