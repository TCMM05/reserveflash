"""Tests de app/infrastructure/ai/budget_guard.py (point 12 - gouvernance
coût/tokens IA, disjoncteur en mémoire process)."""

from __future__ import annotations

import pytest

from app.domain.errors import AIBudgetExceededError
from app.infrastructure.ai.budget_guard import AiBudgetGuard


def test_no_budget_configured_never_raises():
    guard = AiBudgetGuard(daily_budget_usd=None)
    guard.record_spend(1_000_000.0)  # dépense énorme, sans effet si désactivé
    guard.check_budget_or_raise(operation="extract")  # ne doit pas lever


def test_under_budget_allows_call():
    guard = AiBudgetGuard(daily_budget_usd=1.0)
    guard.record_spend(0.5)
    guard.check_budget_or_raise(operation="extract")  # 0.5 < 1.0, ne doit pas lever


def test_at_or_over_budget_raises():
    guard = AiBudgetGuard(daily_budget_usd=1.0)
    guard.record_spend(1.0)
    with pytest.raises(AIBudgetExceededError):
        guard.check_budget_or_raise(operation="extract")


def test_over_budget_raises():
    guard = AiBudgetGuard(daily_budget_usd=1.0)
    guard.record_spend(0.6)
    guard.record_spend(0.6)
    with pytest.raises(AIBudgetExceededError):
        guard.check_budget_or_raise(operation="extract")


def test_record_spend_none_is_a_noop():
    guard = AiBudgetGuard(daily_budget_usd=0.0)
    guard.record_spend(None)
    assert guard.spent_usd() == 0.0
    # budget=0.0 et rien dépensé -> 0.0 >= 0.0 est vrai, donc ça lève quand
    # même (budget nul = tout bloqué) : ce test vérifie juste que
    # record_spend(None) n'a strictement rien changé au compteur.
    with pytest.raises(AIBudgetExceededError):
        guard.check_budget_or_raise(operation="transcribe")


def test_spent_usd_reflects_cumulative_recorded_spend():
    guard = AiBudgetGuard(daily_budget_usd=None)
    guard.record_spend(0.1)
    guard.record_spend(0.2)
    assert abs(guard.spent_usd() - 0.3) < 1e-12


def test_a_blocked_call_does_not_reduce_spend_already_recorded():
    """Un appel bloqué par le disjoncteur n'a par définition consommé aucun
    token/coût réel (bloqué EN AMONT de tout appel HTTP - voir docstring
    check_budget_or_raise) : le compteur ne doit pas bouger."""
    guard = AiBudgetGuard(daily_budget_usd=1.0)
    guard.record_spend(1.0)
    with pytest.raises(AIBudgetExceededError):
        guard.check_budget_or_raise(operation="extract")
    assert guard.spent_usd() == 1.0
