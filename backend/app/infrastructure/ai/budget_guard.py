"""Disjoncteur de budget IA (point 12 - gouvernance coût/tokens IA,
docs/GATE_R2_STATUS.md, retour équipe 2026-08-20 : "Aucun plafond de
dépense, aucun disjoncteur nulle part dans backend/app/").

ARCHITECTURE (choix explicite de l'utilisateur, 2026-08-22, même décision
que usage_journal.py) : compteur EN MÉMOIRE PROCESSUS uniquement. PAS de
persistance, PAS de fenêtre "jour calendaire" au sens strict (repart à zéro
au redémarrage, pas à minuit), PAS de garantie multi-instance (chaque
instance backend déployée a son propre compteur, jamais partagé sans
coordination externe type Redis). Limitation V1 assumée et documentée
explicitement - cohérente avec le choix "logs structurés uniquement" pour
le journal de consommation : ajouter une dépendance DB/Redis uniquement
pour ce compteur aurait été disproportionné pour un chemin déjà sans état.

Désactivé PAR DÉFAUT (Settings.ai_daily_budget_usd = None, app/config.py) :
aucun déploiement existant ne voit son comportement changer sans
configuration explicite (RESERVEFLASH_AI_DAILY_BUDGET_USD) - même politique
que le reste de app/config.py (jamais de comportement modifié sans action
de déploiement explicite).

GATE de résilience (section 7.4) : ce disjoncteur bloque uniquement les
appels SUIVANTS une fois le budget dépassé - il n'interrompt jamais un
appel déjà en cours, et ne fait donc jamais perdre une preuve utilisateur
en cours de traitement."""

from __future__ import annotations

import logging
import threading

logger = logging.getLogger(__name__)


class AiBudgetGuard:
    """Instance SINGLETON PROCESSUS - voir app/api/deps.py::get_ai_budget_guard
    (`@lru_cache`, même pattern que get_repository/get_storage_provider).
    Ne JAMAIS instancier directement en dehors des tests : une nouvelle
    instance par requête viderait le compteur à chaque appel, rendant le
    disjoncteur inopérant."""

    def __init__(self, *, daily_budget_usd: float | None) -> None:
        self._daily_budget_usd = daily_budget_usd
        self._spent_usd = 0.0
        self._lock = threading.Lock()

    @property
    def daily_budget_usd(self) -> float | None:
        return self._daily_budget_usd

    def spent_usd(self) -> float:
        with self._lock:
            return self._spent_usd

    def check_budget_or_raise(self, *, operation: str) -> None:
        """À appeler AVANT tout appel provider payant (voir
        openai_provider.py::transcribe / _call_chat_completion). Lève
        AIBudgetExceededError (app/domain/errors.py) si le budget configuré
        est déjà dépassé. Aucun effet si aucun budget n'est configuré
        (daily_budget_usd is None - comportement par défaut, désactivé)."""
        if self._daily_budget_usd is None:
            return
        with self._lock:
            spent = self._spent_usd
        if spent >= self._daily_budget_usd:
            # Journalisé ICI (pas dans usage_journal.py) : aucun token/coût
            # réel n'a été consommé pour cet appel bloqué - le compter dans
            # le journal de consommation biaiserait les métriques point 10
            # (mean/median/p95 coût, tokens) avec des lignes à coût nul qui
            # n'y ont pas leur place.
            logger.warning(
                "[RF][ai-budget] budget IA process dépassé (%.4f$ >= %.4f$) - "
                "appel %s bloqué avant tout appel provider (aucune dépense "
                "supplémentaire engagée).",
                spent,
                self._daily_budget_usd,
                operation,
            )
            from app.domain.errors import AIBudgetExceededError

            raise AIBudgetExceededError(
                f"Budget IA quotidien dépassé ({spent:.4f}$ >= "
                f"{self._daily_budget_usd:.4f}$)."
            )

    def record_spend(self, cost_usd: float | None) -> None:
        """Appelé après un appel provider RÉUSSI (ou après une tentative
        infructueuse ayant tout de même consommé des tokens - ex: sortie
        invalide après réparation, voir openai_provider.py). `None` (coût
        inconnu - modèle hors table de tarification, ou whisper-1 tarifé à
        la durée) n'incrémente rien : GATE zéro invention appliqué au coût,
        jamais une estimation approximative comptée comme certaine."""
        if cost_usd is None:
            return
        with self._lock:
            self._spent_usd += cost_usd
