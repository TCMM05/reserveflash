"""Journal de consommation IA (point 9 - gouvernance coût/tokens IA,
docs/GATE_R2_STATUS.md, retour équipe 2026-08-20 : "Aucun consumption
journal (tokens/coût/latence/retry/modèle) n'est persisté nulle part côté
backend").

ARCHITECTURE : logs structurés uniquement - choix explicite de l'utilisateur
(2026-08-22, voir docs/GATE_R2_STATUS.md) plutôt qu'une nouvelle table
Postgres + migration Alembic. Le chemin /v1/ai/* est aujourd'hui
entièrement SANS ÉTAT (app/api/routes/ai.py ne dépend d'aucun repository,
aucune authentification) - ajouter une dépendance DB uniquement pour ce
journal aurait été disproportionné, d'autant que PostgreSQL n'est même pas
une dépendance runtime en V1 (app/config.py, point 11 : le repository
réellement utilisé est InMemoryIncidentRepository).

Limitation V1 assumée et documentée explicitement (docs/GATE_R2_STATUS.md) :
logs uniquement = pas de requête agrégée fiable sans réanalyser les logs,
pas de rétention garantie au-delà de la config de logging du déploiement,
pas d'historique multi-instance unifié sans agrégateur externe. Ce journal
est la source de données du point 10 (métriques coût/tokens dans
benchmark/run_scorer.py) UNIQUEMENT pour le chemin benchmark, qui capture
ces mêmes valeurs directement depuis ExtractionResult/AIInvalidOutputError
(pas en reparsant ces logs) - ce module sert le trafic /v1/ai/* réel, pas
le benchmark.

Une ligne PERMANENTE (jamais un print temporaire retiré après usage - même
politique que `logger.warning` dans openai_provider.py, et consigne
permanente du projet : toujours insérer des logs de diagnostic sur un
chemin métier sensible) émise pour CHAQUE appel provider IA terminé (succès
OU échec, y compris une sortie invalide après réparation) - jamais pour un
appel bloqué en amont par le disjoncteur de budget (app/infrastructure/ai/
budget_guard.py, qui journalise séparément via son propre logger
`[RF][ai-budget]`, aucun token/coût réel n'ayant alors été consommé).

Niveau INFO choisi délibérément (pas WARNING, un appel réussi n'est pas une
anomalie) - CE NIVEAU N'EST PAS VISIBLE PAR DÉFAUT avec la seule
configuration `logging` standard de Python si le déploiement ne configure
rien (contrairement aux `logger.warning` existants, visibles par défaut via
le handler `logging.lastResort` de la bibliothèque standard, qui filtre à
WARNING). Pour ne JAMAIS dépendre d'une configuration de déploiement externe
(cohérent avec la consigne "toujours insérer des logs pour détecter
facilement les problèmes"), ce module attache directement un handler dédié
au logger `reserveflash.ai.usage`, garantissant une sortie (stderr) visible
par défaut, sans configuration supplémentaire. `propagate` reste à True
(valeur par défaut) pour que les tests (pytest `caplog`, qui écoute la
hiérarchie root) puissent toujours capturer ces enregistrements - seule
conséquence pratique : une double émission si le déploiement configure
AUSSI explicitement un handler root en INFO, jugée préférable au risque
inverse (silence total)."""

from __future__ import annotations

import logging

usage_logger = logging.getLogger("reserveflash.ai.usage")
usage_logger.setLevel(logging.INFO)

if not usage_logger.handlers:
    _handler = logging.StreamHandler()
    _handler.setLevel(logging.INFO)
    _handler.setFormatter(logging.Formatter("%(asctime)s %(name)s %(message)s"))
    usage_logger.addHandler(_handler)


def log_ai_usage(
    *,
    operation: str,
    provider: str,
    model_id: str,
    status: str,
    latency_ms: int,
    prompt_tokens: int | None = None,
    completion_tokens: int | None = None,
    total_tokens: int | None = None,
    cached_tokens: int | None = None,
    estimated_cost_usd: float | None = None,
    retry_count: int = 0,
    request_id: str | None = None,
) -> None:
    """Émet EXACTEMENT une ligne de log structuré par appel provider IA
    terminé. `operation` : "transcribe" | "extract". `status` : "OK" |
    "AI_UNAVAILABLE" | "AI_RATE_LIMITED" | "AI_INVALID_OUTPUT" (codes
    alignés sur app/domain/errors.py, jamais un libellé ad hoc). Les champs
    tokens/coût sont None quand le provider ne les a pas fournis (ex:
    whisper-1, tarifé à la durée et non aux tokens - voir
    openai_provider.py::transcribe) ou quand aucune table de tarification
    ne couvre le modèle (voir pricing.py) - jamais une valeur inventée."""
    usage_logger.info(
        "[RF][ai-usage] operation=%s provider=%s model=%s status=%s latency_ms=%d "
        "prompt_tokens=%s completion_tokens=%s total_tokens=%s cached_tokens=%s "
        "estimated_cost_usd=%s retry_count=%d request_id=%s",
        operation,
        provider,
        model_id,
        status,
        latency_ms,
        prompt_tokens,
        completion_tokens,
        total_tokens,
        cached_tokens,
        estimated_cost_usd,
        retry_count,
        request_id,
        extra={
            "rf_event": "ai_usage",
            "operation": operation,
            "provider": provider,
            "model_id": model_id,
            "status": status,
            "latency_ms": latency_ms,
            "prompt_tokens": prompt_tokens,
            "completion_tokens": completion_tokens,
            "total_tokens": total_tokens,
            "cached_tokens": cached_tokens,
            "estimated_cost_usd": estimated_cost_usd,
            "retry_count": retry_count,
            "request_id": request_id,
        },
    )
