"""Table de tarification OpenAI (point 9/10 - gouvernance coût/tokens IA,
docs/GATE_R2_STATUS.md, retour équipe 2026-08-20).

Tarifs par MILLION de tokens, en USD, saisis À LA MAIN depuis la page de
pricing OpenAI (https://openai.com/api/pricing/) à la date d'écriture de ce
module (2026-08-22) - VALEURS CODÉES EN DUR, il n'existe aucune API
OpenAI permettant de les récupérer dynamiquement. Limitation V1 assumée et
documentée (docs/GATE_R2_STATUS.md, points 6/9/10) : ces valeurs peuvent
devenir périmées sans avertissement automatique si OpenAI change ses
tarifs - à réviser manuellement (voir CHANGELOG à chaque révision).

N'inclut QUE les modèles réellement utilisables par ce projet
(app/config.py::openai_extraction_model, valeur par défaut "gpt-4o-mini")
- volontairement PAS une table exhaustive de tout le catalogue OpenAI.

GATE zéro invention (section 2.4) appliqué ICI au coût, pas seulement aux
faits métier : un modèle absent de cette table renvoie None (jamais un
montant inventé/extrapolé) - voir estimate_chat_cost_usd.
"""

from __future__ import annotations

# model_id -> (prix input $/1M tokens, prix output $/1M tokens)
_CHAT_MODEL_PRICING_USD_PER_MILLION_TOKENS: dict[str, tuple[float, float]] = {
    "gpt-4o-mini": (0.15, 0.60),
    "gpt-4o-mini-2024-07-18": (0.15, 0.60),
    "gpt-4o": (2.50, 10.00),
    "gpt-4o-2024-08-06": (2.50, 10.00),
}


def estimate_chat_cost_usd(
    model_id: str, *, prompt_tokens: int, completion_tokens: int
) -> float | None:
    """Coût estimé (USD) d'un appel /chat/completions, à partir de
    `usage.prompt_tokens`/`usage.completion_tokens` (réponse OpenAI réelle -
    voir openai_provider.py). Retourne None si [model_id] n'est pas dans la
    table ci-dessus, plutôt qu'une estimation approximative qui serait
    présentée comme un fait alors que ce n'en est pas un."""
    pricing = _CHAT_MODEL_PRICING_USD_PER_MILLION_TOKENS.get(model_id)
    if pricing is None:
        return None
    input_price_per_million, output_price_per_million = pricing
    return (
        prompt_tokens * input_price_per_million + completion_tokens * output_price_per_million
    ) / 1_000_000
