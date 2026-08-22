"""Dépendances FastAPI - point unique d'assemblage (injection) des adapters.

Aucune route ne doit importer directement un provider concret
(app.infrastructure.*) : tout passe par ces fonctions, elles-mêmes basées sur
les factories de app.infrastructure.*/__init__.py qui lisent la
configuration (section 5.3 - règle de dépendance)."""

from __future__ import annotations

from functools import lru_cache
from typing import Annotated

from fastapi import Depends, Header, HTTPException, status

from app.application.ports import (
    AIProvider,
    AuthContext,
    AuthProvider,
    IncidentRepository,
    StorageProvider,
)
from app.config import Settings, get_settings
from app.infrastructure.ai import build_ai_provider
from app.infrastructure.ai.budget_guard import AiBudgetGuard
from app.infrastructure.auth import build_auth_provider
from app.infrastructure.auth.mock_provider import InvalidTokenError
from app.infrastructure.db.in_memory_repository import InMemoryIncidentRepository
from app.infrastructure.storage import build_storage_provider


@lru_cache
def get_repository() -> IncidentRepository:
    """Singleton process : l'implémentation de référence R0 est en mémoire.
    Une future implémentation PostgreSQL (R4) sera fournie par requête
    (session par transaction HTTP) plutôt qu'en singleton - ce point
    d'injection changera alors, sans impact sur les routes (section 5.3)."""
    return InMemoryIncidentRepository()


@lru_cache
def get_ai_budget_guard() -> AiBudgetGuard:
    """Singleton process, comme get_repository/get_storage_provider ci-dessus
    - point 12 (gouvernance coût/tokens IA) : le compteur de dépense doit
    survivre entre requêtes HTTP, une nouvelle instance par requête rendrait
    le disjoncteur inopérant (voir docstring AiBudgetGuard). Lit
    `Settings.ai_daily_budget_usd` directement via get_settings() (pas par
    injection Depends) pour rester `@lru_cache`-compatible sans dépendre de
    l'hashabilité de Settings - même pattern que get_storage_provider
    ci-dessous. Les tests qui changent `RESERVEFLASH_AI_DAILY_BUDGET_USD`
    doivent appeler `get_ai_budget_guard.cache_clear()` en plus de
    `get_settings.cache_clear()` (voir tests/api/conftest.py)."""
    return AiBudgetGuard(daily_budget_usd=get_settings().ai_daily_budget_usd)


def get_ai_provider(
    settings: Annotated[Settings, Depends(get_settings)],
    budget_guard: Annotated[AiBudgetGuard, Depends(get_ai_budget_guard)],
) -> AIProvider:
    return build_ai_provider(settings, budget_guard=budget_guard)


@lru_cache
def get_storage_provider() -> StorageProvider:
    """Singleton process, comme get_repository ci-dessus : le mock storage
    garde ses objets en mémoire (voir mock_provider.py) et doit rester le
    même entre la requête qui écrit un objet et celle qui le relit."""
    return build_storage_provider(get_settings())


def get_auth_provider(settings: Annotated[Settings, Depends(get_settings)]) -> AuthProvider:
    return build_auth_provider(settings)


def get_auth_context(
    auth_provider: Annotated[AuthProvider, Depends(get_auth_provider)],
    authorization: Annotated[str | None, Header()] = None,
) -> AuthContext:
    """SEC-04/SEC-05 (section 10.1) : JWT toujours vérifié côté backend.
    Mappé en 401 AUTH_REQUIRED (section 9.3) si absent/invalide."""
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"code": "AUTH_REQUIRED", "message": "Authentification requise."},
        )
    token = authorization.split(" ", 1)[1].strip()
    try:
        return auth_provider.verify_token(token)
    except InvalidTokenError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"code": "AUTH_REQUIRED", "message": "Session invalide, reconnexion requise."},
        ) from exc


def get_idempotency_key(
    idempotency_key: Annotated[str | None, Header(alias="Idempotency-Key")] = None,
) -> str:
    """section 9.2 : "Idempotency-Key obligatoire sur créations critiques"."""
    if not idempotency_key:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={
                "code": "VALIDATION_ERROR",
                "message": "En-tête Idempotency-Key requis pour cette opération.",
            },
        )
    return idempotency_key
