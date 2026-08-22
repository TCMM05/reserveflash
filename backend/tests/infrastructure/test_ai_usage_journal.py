"""Tests de app/infrastructure/ai/usage_journal.py (point 9 - journal de
consommation IA, logs structurés). Vérifie qu'une ligne PERMANENTE est bien
émise avec les champs attendus - via `caplog`, qui capture les
enregistrements propagés à la hiérarchie root (voir docstring du module :
`propagate` reste à True précisément pour permettre ceci)."""

from __future__ import annotations

import logging

from app.infrastructure.ai.usage_journal import log_ai_usage, usage_logger


def test_log_ai_usage_emits_one_info_record_with_expected_fields(caplog):
    with caplog.at_level(logging.INFO, logger="reserveflash.ai.usage"):
        log_ai_usage(
            operation="extract",
            provider="openai",
            model_id="gpt-4o-mini",
            status="OK",
            latency_ms=123,
            prompt_tokens=100,
            completion_tokens=50,
            total_tokens=150,
            cached_tokens=10,
            estimated_cost_usd=0.000045,
            retry_count=0,
            request_id="req-abc",
        )

    records = [r for r in caplog.records if r.name == "reserveflash.ai.usage"]
    assert len(records) == 1
    record = records[0]
    assert record.levelno == logging.INFO
    assert record.rf_event == "ai_usage"
    assert record.operation == "extract"
    assert record.provider == "openai"
    assert record.model_id == "gpt-4o-mini"
    assert record.status == "OK"
    assert record.latency_ms == 123
    assert record.prompt_tokens == 100
    assert record.completion_tokens == 50
    assert record.total_tokens == 150
    assert record.cached_tokens == 10
    assert record.estimated_cost_usd == 0.000045
    assert record.retry_count == 0
    assert record.request_id == "req-abc"
    # Le message formaté doit rester grep-able sans dépendre du champ
    # `extra` (voir docstring : préfixe [RF] permanent, même convention que
    # le reste du projet).
    assert "[RF][ai-usage]" in record.getMessage()


def test_log_ai_usage_defaults_are_none_not_zero_when_omitted(caplog):
    """Un appel sans données d'usage (ex: whisper-1, échec avant réponse)
    doit journaliser None, jamais 0 (0 affirmerait faussement "aucun
    token")."""
    with caplog.at_level(logging.INFO, logger="reserveflash.ai.usage"):
        log_ai_usage(
            operation="transcribe",
            provider="openai",
            model_id="whisper-1",
            status="AI_UNAVAILABLE",
            latency_ms=42,
        )

    records = [r for r in caplog.records if r.name == "reserveflash.ai.usage"]
    assert len(records) == 1
    record = records[0]
    assert record.prompt_tokens is None
    assert record.completion_tokens is None
    assert record.total_tokens is None
    assert record.cached_tokens is None
    assert record.estimated_cost_usd is None
    assert record.retry_count == 0


def test_usage_logger_has_a_dedicated_handler_for_default_visibility():
    """Voir docstring du module : un handler est attaché directement au
    logger pour garantir une sortie visible sans configuration de
    déploiement supplémentaire (le niveau INFO n'est pas visible par défaut
    via `logging.lastResort`, contrairement à WARNING)."""
    assert usage_logger.level == logging.INFO
    assert len(usage_logger.handlers) >= 1
