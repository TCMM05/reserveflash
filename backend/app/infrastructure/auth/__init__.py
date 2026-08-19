"""Factory du provider auth - point d'injection unique (section 5.3)."""

from __future__ import annotations

from app.application.ports import AuthProvider
from app.config import AuthProviderKind, Settings

_singleton_mock: AuthProvider | None = None


def build_auth_provider(settings: Settings) -> AuthProvider:
    global _singleton_mock
    if settings.auth_provider is AuthProviderKind.MOCK:
        from app.infrastructure.auth.mock_provider import MockAuthProvider

        # Singleton en mode mock : les tokens enregistrés pour les tests
        # doivent survivre entre l'appel qui les crée et la requête qui les
        # vérifie au sein d'un même process.
        if _singleton_mock is None:
            _singleton_mock = MockAuthProvider()
        return _singleton_mock
    raise NotImplementedError(
        f"Provider auth '{settings.auth_provider}' non encore implémenté "
        "(mocks choisis pour ce démarrage de projet, R0)."
    )
