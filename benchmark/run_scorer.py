#!/usr/bin/env python3
"""Exécute le corpus R2 (benchmark/corpus/r2_corpus_v1.json) contre un
provider IA réel et écrit un rapport de métriques (benchmark/results/).

Usage :

    python3 benchmark/run_scorer.py --provider mock
    RESERVEFLASH_OPENAI_API_KEY=sk-... python3 benchmark/run_scorer.py --provider openai

--provider mock : sert de PREUVE D'INTÉGRATION (le pipeline complet corpus ->
  provider -> candidate_guard -> scorer tourne sans erreur de bout en bout) et
  de régression rapide en CI. Le MockAIProvider renvoie une sortie générique
  fixe (voir backend/app/infrastructure/ai/mock_provider.py) : les métriques
  de QUALITÉ obtenues avec ce provider ne mesurent PAS la capacité réelle
  d'extraction d'un LLM (issue_type_accuracy proche de 0 est attendu et
  normal ici) - seul le fait que le harnais tourne sans exception compte.

--provider openai : mesure réelle de qualité, nécessite une clé API valide
  (RESERVEFLASH_OPENAI_API_KEY) et un accès réseau vers api.openai.com,
  indisponibles dans le sandbox de développement où ce script a été écrit -
  à exécuter sur le poste de l'utilisateur (voir docs/GATE_R2_STATUS.md).
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

_BENCHMARK_DIR = Path(__file__).resolve().parent
_REPO_ROOT = _BENCHMARK_DIR.parent
_BACKEND_DIR = _REPO_ROOT / "backend"
if str(_BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(_BACKEND_DIR))
if str(_BENCHMARK_DIR) not in sys.path:
    sys.path.insert(0, str(_BENCHMARK_DIR))

from scorer import (  # noqa: E402
    aggregate_by_category,
    aggregate_core_vs_stress,
    load_corpus,
    score_case,
)

from app.domain.candidate_guard import screen_candidate_fact_data  # noqa: E402
from app.domain.errors import (  # noqa: E402
    AIInvalidOutputError,
    AIRateLimitedError,
    AIUnavailableError,
)


def _build_provider(kind: str):
    if kind == "mock":
        from app.infrastructure.ai.mock_provider import MockAIProvider

        return MockAIProvider()
    if kind == "openai":
        from app.config import get_settings
        from app.infrastructure.ai import build_ai_provider

        return build_ai_provider(get_settings())
    raise ValueError(f"Provider inconnu : {kind!r} (attendu: mock, openai)")


def run(*, provider_kind: str, prompt_version: str = "extraction_fr_v1") -> dict:
    provider = _build_provider(provider_kind)
    cases = load_corpus()
    results = []
    raw_records = []

    for case in cases:
        input_data = case["input"]
        try:
            extraction = provider.extract_candidate_facts(
                document_text=input_data.get("document_text"),
                transcript=input_data.get("transcript"),
                prompt_version=prompt_version,
            )
        except AIInvalidOutputError as exc:
            # Point 9/10 (gouvernance cout/tokens IA) : une sortie invalide
            # a quand meme un cout reel deja consomme - AIInvalidOutputError
            # (app/domain/errors.py) porte ces attributs precisement pour ce
            # cas, capture ici plutot que de les perdre.
            results.append(
                score_case(
                    case,
                    None,
                    invalid_output=True,
                    prompt_tokens=exc.prompt_tokens,
                    completion_tokens=exc.completion_tokens,
                    total_tokens=exc.total_tokens,
                    estimated_cost_usd=exc.estimated_cost_usd,
                    retry_count=exc.retry_count,
                )
            )
            raw_records.append(
                {
                    "case_id": case["id"],
                    "status": "AI_INVALID_OUTPUT",
                    "prompt_tokens": exc.prompt_tokens,
                    "completion_tokens": exc.completion_tokens,
                    "estimated_cost_usd": exc.estimated_cost_usd,
                    "retry_count": exc.retry_count,
                }
            )
            continue
        except (AIUnavailableError, AIRateLimitedError) as exc:
            # Panne infrastructure, pas un jugement sur la qualite du modele
            # - on l'enregistre a part et on ne compte pas ce cas dans le
            # denominateur qualite (voir docstring de score_case). Aucune
            # donnee d'usage fiable ici (l'appel peut avoir echoue avant
            # toute reponse provider).
            raw_records.append(
                {"case_id": case["id"], "status": "PROVIDER_ERROR", "detail": str(exc)}
            )
            continue

        screened = screen_candidate_fact_data(extraction.candidate)
        predicted_dict = screened.model_dump(mode="json")
        results.append(
            score_case(
                case,
                predicted_dict,
                latency_ms=extraction.latency_ms,
                prompt_tokens=extraction.prompt_tokens,
                completion_tokens=extraction.completion_tokens,
                total_tokens=extraction.total_tokens,
                cached_tokens=extraction.cached_tokens,
                estimated_cost_usd=extraction.estimated_cost_usd,
                retry_count=extraction.retry_count,
            )
        )
        raw_records.append(
            {
                "case_id": case["id"],
                "status": "OK",
                "predicted": predicted_dict,
                "latency_ms": extraction.latency_ms,
                "prompt_tokens": extraction.prompt_tokens,
                "completion_tokens": extraction.completion_tokens,
                "total_tokens": extraction.total_tokens,
                "cached_tokens": extraction.cached_tokens,
                "estimated_cost_usd": extraction.estimated_cost_usd,
                "retry_count": extraction.retry_count,
            }
        )

    by_category = {cat: m.to_dict() for cat, m in aggregate_by_category(results).items()}
    core_vs_stress = {grp: m.to_dict() for grp, m in aggregate_core_vs_stress(results).items()}

    return {
        "provider": provider_kind,
        "corpus_version": "r2_corpus_v1",
        "case_count": len(cases),
        "scored_case_count": len(results),
        "by_category": by_category,
        "core_vs_stress": core_vs_stress,
        "raw_records": raw_records,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--provider", choices=["mock", "openai"], default="mock")
    parser.add_argument("--prompt-version", default="extraction_fr_v1")
    parser.add_argument(
        "--out",
        default=None,
        help="Chemin du rapport JSON (défaut: benchmark/results/report_<provider>.json)",
    )
    args = parser.parse_args()

    report = run(provider_kind=args.provider, prompt_version=args.prompt_version)

    if args.out:
        out_path = Path(args.out)
    else:
        out_path = _BENCHMARK_DIR / "results" / f"report_{args.provider}.json"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")

    print(f"Rapport écrit dans {out_path}")
    print(f"Cas total : {report['case_count']} | scorés : {report['scored_case_count']}")
    for group, metrics in report["core_vs_stress"].items():
        print(
            f"[{group}] n={metrics['case_count']} "
            f"invented_fact_rate={metrics['invented_fact_rate']:.3f} "
            f"issue_type_accuracy={metrics['issue_type_accuracy']} "
            f"safety_pass_rate={metrics['safety_pass_rate']} "
            f"invalid_output_rate={metrics['invalid_output_rate']:.3f}"
        )
        # Point 10 (gouvernance coût/tokens IA) - None pour --provider mock
        # (aucune donnée d'usage réelle, voir mock_provider.py) : affiché
        # tel quel, jamais masqué par une valeur par défaut trompeuse.
        mean_cost = metrics["mean_cost_usd"]
        mean_cost_str = f"{mean_cost:.6f}$" if mean_cost is not None else "None"
        print(
            f"    coût moyen/cas={mean_cost_str} "
            f"p95_coût={metrics['p95_cost_usd']} "
            f"tokens_moyen/cas={metrics['mean_total_tokens']} "
            f"cache_rate={metrics['cache_rate']} "
            f"appels_moyen/cas={metrics['mean_calls_per_case']}"
        )


if __name__ == "__main__":
    main()
