"""Factory du provider IA - point d'injection unique (section 5.3).

Aucun autre module ne doit instancier un provider IA directement : passer
par `build_ai_provider(settings)` garantit que le choix de provider reste
piloté par configuration, jamais codé en dur dans une route ou un cas
d'usage.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from app.application.ports import AIProvider
from app.config import AIProviderKind, Settings

if TYPE_CHECKING:
    from app.infrastructure.ai.budget_guard import AiBudgetGuard


def build_ai_provider(
    settings: Settings, *, budget_guard: AiBudgetGuard | None = None
) -> AIProvider:
    """`budget_guard` (point 12, gouvernance coût/tokens IA) optionnel :
    None par défaut = aucun disjoncteur appliqué (comportement historique
    inchangé pour tout appelant qui ne le fournit pas, ex:
    benchmark/run_scorer.py). Uniquement consommé par OpenAIProvider - le
    mock n'appelle jamais de provider réel, aucun coût réel à surveiller."""
    if settings.ai_provider is AIProviderKind.MOCK:
        from app.infrastructure.ai.mock_provider import MockAIProvider

        return MockAIProvider()
    if settings.ai_provider is AIProviderKind.OPENAI:
        # R2 : implémentation réelle (app/infrastructure/ai/openai_provider.py).
        # L'interface AIProvider n'a pas changé : brancher OpenAI n'a touché
        # ni le domaine ni les routes (section 5.3).
        from app.infrastructure.ai.openai_provider import OpenAIProvider

        return OpenAIProvider(
            api_key=settings.require_openai_key(),
            base_url=settings.openai_base_url,
            transcription_model=settings.openai_transcription_model,
            extraction_model=settings.openai_extraction_model,
            timeout_seconds=settings.openai_request_timeout_seconds,
            budget_guard=budget_guard,
        )
    raise ValueError(f"Provider IA inconnu : {settings.ai_provider}")
