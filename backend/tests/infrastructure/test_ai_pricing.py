"""Tests de app/infrastructure/ai/pricing.py (point 9/10 - gouvernance
coût/tokens IA)."""

from __future__ import annotations

from app.infrastructure.ai.pricing import estimate_chat_cost_usd


def test_estimate_chat_cost_usd_known_model():
    # gpt-4o-mini : 0.15$/1M input, 0.60$/1M output (voir pricing.py).
    cost = estimate_chat_cost_usd("gpt-4o-mini", prompt_tokens=1000, completion_tokens=500)
    expected = (1000 * 0.15 + 500 * 0.60) / 1_000_000
    assert cost is not None
    assert abs(cost - expected) < 1e-12


def test_estimate_chat_cost_usd_zero_tokens_is_zero_cost():
    assert estimate_chat_cost_usd("gpt-4o-mini", prompt_tokens=0, completion_tokens=0) == 0.0


def test_estimate_chat_cost_usd_unknown_model_returns_none():
    """GATE zéro invention appliqué au coût : un modèle absent de la table
    ne doit jamais renvoyer une estimation approximative."""
    cost = estimate_chat_cost_usd("some-future-model", prompt_tokens=100, completion_tokens=50)
    assert cost is None
