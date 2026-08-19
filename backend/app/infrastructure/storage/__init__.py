"""Factory du provider storage - point d'injection unique (section 5.3)."""

from __future__ import annotations

from app.application.ports import StorageProvider
from app.config import Settings, StorageProviderKind


def build_storage_provider(settings: Settings) -> StorageProvider:
    if settings.storage_provider is StorageProviderKind.MOCK:
        from app.infrastructure.storage.mock_provider import MockStorageProvider

        return MockStorageProvider()
    raise NotImplementedError(
        f"Provider storage '{settings.storage_provider}' non encore implémenté "
        "(mocks choisis pour ce démarrage de projet, R0)."
    )
