"""Factory du provider IA - point d'injection unique (section 5.3).

Aucun autre module ne doit instancier un provider IA directement : passer
par `build_ai_provider(settings)` garantit que le choix de provider reste
piloté par configuration, jamais codé en dur dans une route ou un cas
d'usage.
"""

from __future__ import annotations

from app.application.ports import AIProvider
from app.config import AIProviderKind, Settings


def build_ai_provider(settings: Settings) -> AIProvider:
    if settings.ai_provider is AIProviderKind.MOCK:
        from app.infrastructure.ai.mock_provider import MockAIProvider

        return MockAIProvider()
    if settings.ai_provider is AIProviderKind.OPENAI:
        # Implémentation réelle volontairement hors du périmètre R0 (mocks
        # choisis pour ce démarrage de projet). L'interface AIProvider est
        # stable : brancher OpenAI ne touche ni domaine ni API.
        raise NotImplementedError(
            "Provider OpenAI non encore implémenté. Fournir "
            "app/infrastructure/ai/openai_provider.py::OpenAIProvider avant "
            "d'activer RESERVEFLASH_AI_PROVIDER=openai."
        )
    raise ValueError(f"Provider IA inconnu : {settings.ai_provider}")
