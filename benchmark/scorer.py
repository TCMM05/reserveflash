"""Scorer du corpus de qualification R2 (benchmark/corpus/r2_corpus_v1.json).

Volontairement DECOUPLE de tout provider IA concret : ce module ne fait
AUCUN appel reseau et ne sait rien d'OpenAI. Il prend en entree des
predictions deja produites (par n'importe quel pipeline - mock, OpenAI reel,
autre fournisseur) sous la forme JSON du schema candidate_fact_set.v1
(dict brut, pas un objet pydantic - benchmark/ n'importe pas les types
backend pour rester utilisable independamment du code applicatif) et calcule
les metriques (section "Metriques prioritaires" de la demande R2).

Seule exception a ce decouplage : la verification "aucun contenu interdit"
(categorie SAFETY) reutilise les motifs regex reels de
app.domain.liability_guard.FORBIDDEN_PATTERNS (backend/), pour eviter toute
divergence entre ce que le backend rejette reellement en production et ce
que le benchmark verifie - une seule source de verite pour "qu'est-ce qu'un
contenu interdit."

Usage typique (voir benchmark/run_scorer.py pour un exemple executable) :

    from benchmark.scorer import load_corpus, score_case, aggregate_by_category

    corpus = load_corpus()
    results = [score_case(case, predicted=my_pipeline(case)) for case in corpus]
    report = aggregate_by_category(results)
"""

from __future__ import annotations

import json
import sys
from dataclasses import dataclass, field
from pathlib import Path

_BENCHMARK_DIR = Path(__file__).resolve().parent
_REPO_ROOT = _BENCHMARK_DIR.parent
_BACKEND_DIR = _REPO_ROOT / "backend"
_DEFAULT_CORPUS_PATH = _BENCHMARK_DIR / "corpus" / "r2_corpus_v1.json"

if str(_BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(_BACKEND_DIR))

from app.domain.liability_guard import FORBIDDEN_PATTERNS  # noqa: E402

NUMERIC_TOLERANCE = 1e-6

# Categorie CORE isolee du reste (section "Metriques prioritaires" de la
# demande R2 : "Les métriques doivent distinguer clairement CORE et
# STRESS. Une bonne performance CORE avec une mauvaise généralisation
# STRESS doit être signalée comme telle et non masquée par une moyenne
# globale.").
STRESS_CATEGORIES: tuple[str, ...] = (
    "PARAPHRASE",
    "NEGATION",
    "AUDIO",
    "OCR",
    "UNKNOWN",
    "SAFETY",
)


def load_corpus(path: Path | str = _DEFAULT_CORPUS_PATH) -> list[dict]:
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    return data["cases"]


def contains_forbidden_content(fields: dict) -> bool:
    """Reutilise app.domain.liability_guard.FORBIDDEN_PATTERNS (source
    unique) pour verifier qu'AUCUNE valeur texte de `fields` (dict
    field_name -> {"value": ..., ...}, format candidate_fact_set.v1) ne
    contient un motif interdit."""
    for field_data in fields.values():
        value = field_data.get("value") if isinstance(field_data, dict) else field_data
        if not isinstance(value, str):
            continue
        for pattern in FORBIDDEN_PATTERNS.values():
            if pattern.search(value):
                return True
    return False


def _predicted_value(predicted_field: object) -> object:
    return predicted_field.get("value") if isinstance(predicted_field, dict) else None


def _values_match(expected: object, actual: object) -> bool:
    if isinstance(expected, bool) or isinstance(actual, bool):
        return expected == actual
    if isinstance(expected, (int, float)) and isinstance(actual, (int, float)):
        return abs(float(expected) - float(actual)) < NUMERIC_TOLERANCE
    if isinstance(expected, str) and isinstance(actual, str):
        return expected.strip().casefold() == actual.strip().casefold()
    return expected == actual


@dataclass
class CaseResult:
    case_id: str
    category: str
    invalid_output: bool = False
    semantic_rejected: bool = False
    issue_type_correct: bool | None = None
    field_correct_count: int = 0
    field_expected_count: int = 0
    field_predicted_count: int = 0
    invented_fact_fields: list[str] = field(default_factory=list)
    correctly_unknown_fields: list[str] = field(default_factory=list)
    safety_checked: bool = False
    safety_violation: bool = False
    latency_ms: int | None = None
    # Point 9/10 (gouvernance cout/tokens IA, docs/GATE_R2_STATUS.md) -
    # renseignes depuis ExtractionResult (appel reussi) OU depuis
    # AIInvalidOutputError (appel finalement invalide - voir
    # app/domain/errors.py, ces attributs y existent precisement pour ce
    # cas : un cas invalid_output a quand meme un cout reel). None si le
    # pipeline utilise (ex: MockAIProvider) ne fournit aucune donnee
    # d'usage - jamais une valeur inventee.
    prompt_tokens: int | None = None
    completion_tokens: int | None = None
    total_tokens: int | None = None
    cached_tokens: int | None = None
    estimated_cost_usd: float | None = None
    retry_count: int = 0


def score_case(
    case: dict,
    predicted: dict | None,
    *,
    invalid_output: bool = False,
    semantic_rejected: bool = False,
    latency_ms: int | None = None,
    prompt_tokens: int | None = None,
    completion_tokens: int | None = None,
    total_tokens: int | None = None,
    cached_tokens: int | None = None,
    estimated_cost_usd: float | None = None,
    retry_count: int = 0,
) -> CaseResult:
    """Compare `predicted` (candidat FINAL, apres passage par
    candidate_guard - c'est ce que verrait reellement l'utilisateur) au gold
    du `case`. `invalid_output=True` si le pipeline a leve
    AIInvalidOutputError pour ce cas ; `semantic_rejected=True` si le
    candidat a ete entierement rejete par une validation semantique en amont
    (distinct d'un simple champ retire par candidate_guard, qui reste
    visible dans `predicted`).

    Les kwargs usage/cout (point 9/10) sont acceptes MEME si `invalid_output`
    est vrai - un appel dont la sortie est finalement invalide a quand meme
    consomme des tokens reels (voir AIInvalidOutputError,
    app/domain/errors.py)."""
    result = CaseResult(
        case_id=case["id"],
        category=case["category"],
        invalid_output=invalid_output,
        semantic_rejected=semantic_rejected,
        latency_ms=latency_ms,
        prompt_tokens=prompt_tokens,
        completion_tokens=completion_tokens,
        total_tokens=total_tokens,
        cached_tokens=cached_tokens,
        estimated_cost_usd=estimated_cost_usd,
        retry_count=retry_count,
    )
    if invalid_output or semantic_rejected or predicted is None:
        return result

    expected = case.get("expected", {})
    expected_fields: dict = expected.get("fields", {})
    must_be_unknown: set[str] = set(expected.get("must_be_unknown", []))
    predicted_fields: dict = predicted.get("fields", {})

    result.issue_type_correct = predicted.get("issue_type_candidate") == expected.get(
        "issue_type_candidate"
    )

    result.field_expected_count = len(expected_fields)
    result.field_predicted_count = sum(
        1
        for f in predicted_fields.values()
        if isinstance(f, dict) and f.get("value") is not None
    )
    for name, expected_value in expected_fields.items():
        predicted_value = _predicted_value(predicted_fields.get(name))
        if predicted_value is not None and _values_match(expected_value, predicted_value):
            result.field_correct_count += 1

    for name in must_be_unknown:
        predicted_value = _predicted_value(predicted_fields.get(name))
        if predicted_value is not None:
            result.invented_fact_fields.append(name)
        else:
            result.correctly_unknown_fields.append(name)

    if expected.get("forbidden_patterns_must_not_appear"):
        result.safety_checked = True
        result.safety_violation = contains_forbidden_content(predicted_fields)

    return result


@dataclass
class AggregateMetrics:
    group: str
    case_count: int
    invalid_output_rate: float
    semantic_rejected_rate: float
    issue_type_accuracy: float | None
    field_precision: float | None
    field_recall: float | None
    invented_fact_rate: float
    invented_fact_count: int
    correct_unknown_rate: float | None
    safety_pass_rate: float | None
    median_latency_ms: float | None
    p95_latency_ms: float | None
    # Point 10 (gouvernance cout/tokens IA, docs/GATE_R2_STATUS.md, retour
    # equipe 2026-08-20 : "mean/median/p95 cost, tokens, cache rate, calls
    # per dossier"). None quand aucun cas de ce groupe n'a de donnee d'usage
    # (ex: --provider mock, voir run_scorer.py) - jamais une valeur
    # inventee. "dossier" ~= un cas du corpus ici (le benchmark n'a pas la
    # notion d'incident/dossier a plusieurs issues, voir docstring module).
    mean_cost_usd: float | None
    median_cost_usd: float | None
    p95_cost_usd: float | None
    mean_total_tokens: float | None
    median_total_tokens: float | None
    p95_total_tokens: float | None
    cache_rate: float | None
    mean_calls_per_case: float | None

    def to_dict(self) -> dict:
        return {
            "group": self.group,
            "case_count": self.case_count,
            "invalid_output_rate": self.invalid_output_rate,
            "semantic_rejected_rate": self.semantic_rejected_rate,
            "issue_type_accuracy": self.issue_type_accuracy,
            "field_precision": self.field_precision,
            "field_recall": self.field_recall,
            "invented_fact_rate": self.invented_fact_rate,
            "invented_fact_count": self.invented_fact_count,
            "correct_unknown_rate": self.correct_unknown_rate,
            "safety_pass_rate": self.safety_pass_rate,
            "median_latency_ms": self.median_latency_ms,
            "p95_latency_ms": self.p95_latency_ms,
            "mean_cost_usd": self.mean_cost_usd,
            "median_cost_usd": self.median_cost_usd,
            "p95_cost_usd": self.p95_cost_usd,
            "mean_total_tokens": self.mean_total_tokens,
            "median_total_tokens": self.median_total_tokens,
            "p95_total_tokens": self.p95_total_tokens,
            "cache_rate": self.cache_rate,
            "mean_calls_per_case": self.mean_calls_per_case,
        }


def _percentile(sorted_values: list[float], pct: float) -> float:
    if not sorted_values:
        return 0.0
    if len(sorted_values) == 1:
        return sorted_values[0]
    k = (len(sorted_values) - 1) * pct
    lower = int(k)
    upper = min(lower + 1, len(sorted_values) - 1)
    if lower == upper:
        return sorted_values[lower]
    return sorted_values[lower] + (sorted_values[upper] - sorted_values[lower]) * (k - lower)


def _mean(values: list[float]) -> float | None:
    return (sum(values) / len(values)) if values else None


def aggregate(results: list[CaseResult], *, group: str) -> AggregateMetrics:
    n = len(results)
    if n == 0:
        return AggregateMetrics(
            group, 0, 0.0, 0.0, None, None, None, 0.0, 0, None, None, None, None,
            None, None, None, None, None, None, None, None,
        )

    invalid_count = sum(1 for r in results if r.invalid_output)
    rejected_count = sum(1 for r in results if r.semantic_rejected)
    valid = [r for r in results if not r.invalid_output and not r.semantic_rejected]

    issue_type_checks = [r.issue_type_correct for r in valid if r.issue_type_correct is not None]
    issue_type_accuracy = (
        sum(issue_type_checks) / len(issue_type_checks) if issue_type_checks else None
    )

    total_predicted = sum(r.field_predicted_count for r in valid)
    total_correct = sum(r.field_correct_count for r in valid)
    total_expected = sum(r.field_expected_count for r in valid)
    field_precision = (total_correct / total_predicted) if total_predicted else None
    field_recall = (total_correct / total_expected) if total_expected else None

    total_invented = sum(len(r.invented_fact_fields) for r in valid)
    total_correctly_unknown = sum(len(r.correctly_unknown_fields) for r in valid)
    total_must_be_unknown = total_invented + total_correctly_unknown
    invented_fact_rate = (total_invented / total_must_be_unknown) if total_must_be_unknown else 0.0
    correct_unknown_rate = (
        (total_correctly_unknown / total_must_be_unknown) if total_must_be_unknown else None
    )

    safety_checked = [r for r in valid if r.safety_checked]
    safety_pass_rate = (
        sum(1 for r in safety_checked if not r.safety_violation) / len(safety_checked)
        if safety_checked
        else None
    )

    latencies = sorted(r.latency_ms for r in results if r.latency_ms is not None)
    median_latency = _percentile(latencies, 0.5) if latencies else None
    p95_latency = _percentile(latencies, 0.95) if latencies else None

    # Point 10 : delibmerement calcule sur TOUS les `results` (pas
    # seulement `valid`) - un cas invalid_output a quand meme un cout reel
    # consomme (voir AIInvalidOutputError, app/domain/errors.py, et
    # docstring de score_case ci-dessus). `cost_bearing` = les cas pour
    # lesquels une donnee d'usage existe du tout (exclut --provider mock,
    # qui ne renvoie jamais de tokens - voir run_scorer.py).
    cost_bearing = [r for r in results if r.total_tokens is not None]
    costs = sorted(r.estimated_cost_usd for r in cost_bearing if r.estimated_cost_usd is not None)
    total_tokens_values = sorted(float(r.total_tokens) for r in cost_bearing)
    mean_cost = _mean(costs)
    median_cost = _percentile(costs, 0.5) if costs else None
    p95_cost = _percentile(costs, 0.95) if costs else None
    mean_total_tokens = _mean(total_tokens_values)
    median_total_tokens = _percentile(total_tokens_values, 0.5) if total_tokens_values else None
    p95_total_tokens = _percentile(total_tokens_values, 0.95) if total_tokens_values else None

    cacheable = [r for r in cost_bearing if r.cached_tokens is not None and r.prompt_tokens]
    total_cached = sum(r.cached_tokens for r in cacheable)
    total_cacheable_prompt = sum(r.prompt_tokens for r in cacheable)
    cache_rate = (total_cached / total_cacheable_prompt) if total_cacheable_prompt else None

    mean_calls_per_case = _mean([1 + r.retry_count for r in cost_bearing])

    return AggregateMetrics(
        group=group,
        case_count=n,
        invalid_output_rate=invalid_count / n,
        semantic_rejected_rate=rejected_count / n,
        issue_type_accuracy=issue_type_accuracy,
        field_precision=field_precision,
        field_recall=field_recall,
        invented_fact_rate=invented_fact_rate,
        invented_fact_count=total_invented,
        correct_unknown_rate=correct_unknown_rate,
        safety_pass_rate=safety_pass_rate,
        median_latency_ms=median_latency,
        p95_latency_ms=p95_latency,
        mean_cost_usd=mean_cost,
        median_cost_usd=median_cost,
        p95_cost_usd=p95_cost,
        mean_total_tokens=mean_total_tokens,
        median_total_tokens=median_total_tokens,
        p95_total_tokens=p95_total_tokens,
        cache_rate=cache_rate,
        mean_calls_per_case=mean_calls_per_case,
    )


def aggregate_by_category(results: list[CaseResult]) -> dict[str, AggregateMetrics]:
    categories = sorted({r.category for r in results})
    return {
        cat: aggregate([r for r in results if r.category == cat], group=cat) for cat in categories
    }


def aggregate_core_vs_stress(results: list[CaseResult]) -> dict[str, AggregateMetrics]:
    core = [r for r in results if r.category == "CORE"]
    stress = [r for r in results if r.category in STRESS_CATEGORIES]
    return {
        "CORE": aggregate(core, group="CORE"),
        "STRESS": aggregate(stress, group="STRESS"),
        "ALL": aggregate(results, group="ALL"),
    }
