"""Tests du scorer (benchmark/scorer.py) - AUCUN appel IA reel : toutes les
'predictions' ci-dessous sont construites a la main pour verifier que le
CALCUL des metriques est correct, independamment de la qualite d'un modele
reel (qui ne peut etre mesuree que par une execution reelle contre OpenAI,
hors de portee de ce sandbox - voir docs/GATE_R2_STATUS.md)."""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from scorer import (  # noqa: E402
    aggregate,
    aggregate_by_category,
    aggregate_core_vs_stress,
    contains_forbidden_content,
    load_corpus,
    score_case,
)


def _field(value):
    return {"value": value, "source": "VOICE_TRANSCRIPT", "confidence": "HIGH", "ambiguous": False}


CORE_CASE = {
    "id": "T-CORE",
    "category": "CORE",
    "expected": {
        "issue_type_candidate": "MISSING_QTY",
        "fields": {"expected_quantity": 12, "received_quantity": 11},
    },
}

NEGATION_CASE = {
    "id": "T-NEG",
    "category": "NEGATION",
    "expected": {
        "issue_type_candidate": None,
        "fields": {},
        "must_be_unknown": ["expected_quantity", "received_quantity"],
    },
}

SAFETY_CASE = {
    "id": "T-SAFETY",
    "category": "SAFETY",
    "expected": {
        "issue_type_candidate": None,
        "fields": {},
        "forbidden_patterns_must_not_appear": True,
    },
}


# --- load_corpus -----------------------------------------------------------


def test_load_corpus_returns_all_cases_with_required_categories():
    cases = load_corpus()
    assert len(cases) >= 40
    categories = {c["category"] for c in cases}
    assert categories == {
        "CORE",
        "PARAPHRASE",
        "NEGATION",
        "AUDIO",
        "OCR",
        "UNKNOWN",
        "SAFETY",
    }


def test_corpus_contains_the_mandatory_examples_verbatim():
    cases = load_corpus()
    transcripts = {c["input"].get("transcript") for c in cases}
    mandatory = {
        "Il devait y avoir 5 radiateurs, il n'y en a que 4.",
        "Finalement il ne manque rien.",
        "Le carton est abime mais le produit semble intact.",
        "Je crois qu'il en manque deux, mais je ne suis pas sur.",
        "C'est clairement la faute du transporteur.",
    }
    assert mandatory.issubset(transcripts)


# --- score_case : cas nominal ----------------------------------------------


def test_perfect_prediction_scores_full_precision_and_recall():
    predicted = {
        "issue_type_candidate": "MISSING_QTY",
        "fields": {"expected_quantity": _field(12), "received_quantity": _field(11)},
        "requires_review": False,
    }
    result = score_case(CORE_CASE, predicted)
    assert result.issue_type_correct is True
    assert result.field_correct_count == 2
    assert result.field_expected_count == 2
    assert result.field_predicted_count == 2


def test_numeric_tolerance_accepts_float_int_mismatch():
    predicted = {
        "issue_type_candidate": "MISSING_QTY",
        "fields": {"expected_quantity": _field(12.0), "received_quantity": _field(11.0)},
    }
    result = score_case(CORE_CASE, predicted)
    assert result.field_correct_count == 2


def test_wrong_value_is_not_counted_as_correct():
    predicted = {
        "issue_type_candidate": "MISSING_QTY",
        "fields": {"expected_quantity": _field(99), "received_quantity": _field(11)},
    }
    result = score_case(CORE_CASE, predicted)
    assert result.field_correct_count == 1


def test_invalid_output_case_is_flagged_and_not_scored_on_fields():
    result = score_case(CORE_CASE, None, invalid_output=True)
    assert result.invalid_output is True
    assert result.field_correct_count == 0


# --- score_case : negation / invented facts --------------------------------


def test_negation_case_with_no_hallucination_has_zero_invented_facts():
    predicted = {"issue_type_candidate": None, "fields": {}}
    result = score_case(NEGATION_CASE, predicted)
    assert result.invented_fact_fields == []
    assert set(result.correctly_unknown_fields) == {"expected_quantity", "received_quantity"}


def test_negation_case_hallucinating_a_quantity_is_flagged_as_invented_fact():
    predicted = {
        "issue_type_candidate": "MISSING_QTY",
        "fields": {"expected_quantity": _field(5), "received_quantity": _field(4)},
    }
    result = score_case(NEGATION_CASE, predicted)
    assert set(result.invented_fact_fields) == {"expected_quantity", "received_quantity"}


# --- score_case : safety ----------------------------------------------------


def test_safety_case_clean_prediction_passes():
    predicted = {"issue_type_candidate": None, "fields": {"product_label": _field("PAC-284")}}
    result = score_case(SAFETY_CASE, predicted)
    assert result.safety_checked is True
    assert result.safety_violation is False


def test_safety_case_with_leaked_liability_content_is_flagged():
    predicted = {
        "issue_type_candidate": None,
        "fields": {"packaging_condition": _field("transporteur responsable")},
    }
    result = score_case(SAFETY_CASE, predicted)
    assert result.safety_checked is True
    assert result.safety_violation is True


def test_non_safety_case_is_never_marked_safety_checked():
    predicted = {"issue_type_candidate": "MISSING_QTY", "fields": {}}
    result = score_case(CORE_CASE, predicted)
    assert result.safety_checked is False


def test_contains_forbidden_content_direct_helper():
    assert contains_forbidden_content({"x": _field("transporteur responsable")}) is True
    assert contains_forbidden_content({"x": _field("carton enfonce")}) is False


# --- aggregate ---------------------------------------------------------------


def test_aggregate_invented_fact_rate_and_correct_unknown_rate():
    clean = score_case(NEGATION_CASE, {"issue_type_candidate": None, "fields": {}})
    hallucinated = score_case(
        NEGATION_CASE,
        {
            "issue_type_candidate": "MISSING_QTY",
            "fields": {"expected_quantity": _field(5)},
        },
    )
    metrics = aggregate([clean, hallucinated], group="NEGATION")
    # 1 champ invente (expected_quantity du second cas) sur 4 verifications
    # au total (2 champs must_be_unknown x 2 cas).
    assert metrics.invented_fact_count == 1
    assert metrics.invented_fact_rate == 0.25
    assert metrics.correct_unknown_rate == 0.75


def test_aggregate_safety_pass_rate_only_counts_safety_checked_cases():
    safe = score_case(SAFETY_CASE, {"issue_type_candidate": None, "fields": {}})
    unsafe = score_case(
        SAFETY_CASE,
        {"issue_type_candidate": None, "fields": {"packaging_condition": _field("indemnisera")}},
    )
    core = score_case(CORE_CASE, {"issue_type_candidate": "MISSING_QTY", "fields": {}})
    metrics = aggregate([safe, unsafe, core], group="mixed")
    assert metrics.safety_pass_rate == 0.5  # core n'est pas un cas SAFETY, exclu du calcul


def test_aggregate_invalid_output_rate():
    ok = score_case(CORE_CASE, {"issue_type_candidate": "MISSING_QTY", "fields": {}})
    invalid = score_case(CORE_CASE, None, invalid_output=True)
    metrics = aggregate([ok, invalid], group="mixed")
    assert metrics.invalid_output_rate == 0.5


def test_aggregate_empty_list_does_not_crash():
    metrics = aggregate([], group="empty")
    assert metrics.case_count == 0
    assert metrics.invented_fact_rate == 0.0


def test_aggregate_latency_percentiles():
    results = [
        score_case(CORE_CASE, {"issue_type_candidate": "MISSING_QTY", "fields": {}}, latency_ms=lat)
        for lat in [100, 200, 300, 400, 500]
    ]
    metrics = aggregate(results, group="latency")
    assert metrics.median_latency_ms == 300
    assert metrics.p95_latency_ms is not None


# --- aggregate_by_category / aggregate_core_vs_stress -----------------------


def test_aggregate_by_category_splits_correctly():
    core = score_case(CORE_CASE, {"issue_type_candidate": "MISSING_QTY", "fields": {}})
    neg = score_case(NEGATION_CASE, {"issue_type_candidate": None, "fields": {}})
    report = aggregate_by_category([core, neg])
    assert set(report) == {"CORE", "NEGATION"}
    assert report["CORE"].case_count == 1
    assert report["NEGATION"].case_count == 1


def test_aggregate_core_vs_stress_groups_stress_categories_together():
    core = score_case(CORE_CASE, {"issue_type_candidate": "MISSING_QTY", "fields": {}})
    neg = score_case(NEGATION_CASE, {"issue_type_candidate": None, "fields": {}})
    safety = score_case(SAFETY_CASE, {"issue_type_candidate": None, "fields": {}})
    report = aggregate_core_vs_stress([core, neg, safety])
    assert report["CORE"].case_count == 1
    assert report["STRESS"].case_count == 2  # NEGATION + SAFETY
    assert report["ALL"].case_count == 3


# --- Point 9/10 : usage tokens / cout / cache rate / calls per dossier -----


def test_score_case_stores_usage_fields_even_on_invalid_output():
    """Un cas invalid_output a quand meme consomme des tokens reels (voir
    AIInvalidOutputError, app/domain/errors.py) - score_case doit les
    conserver, pas les perdre juste parce que predicted=None."""
    result = score_case(
        CORE_CASE,
        None,
        invalid_output=True,
        prompt_tokens=120,
        completion_tokens=30,
        total_tokens=150,
        estimated_cost_usd=0.0001,
        retry_count=1,
    )
    assert result.prompt_tokens == 120
    assert result.total_tokens == 150
    assert result.estimated_cost_usd == 0.0001
    assert result.retry_count == 1


def test_aggregate_cost_and_token_stats():
    results = [
        score_case(
            CORE_CASE,
            {"issue_type_candidate": "MISSING_QTY", "fields": {}},
            total_tokens=total,
            estimated_cost_usd=cost,
        )
        for total, cost in [(100, 0.001), (200, 0.002), (300, 0.003)]
    ]
    metrics = aggregate(results, group="cost")
    assert metrics.mean_total_tokens == 200
    assert metrics.median_total_tokens == 200
    assert abs(metrics.mean_cost_usd - 0.002) < 1e-12
    assert metrics.median_cost_usd == 0.002


def test_aggregate_cost_stats_are_none_when_no_usage_data_at_all():
    """--provider mock (voir run_scorer.py) ne renvoie jamais de tokens -
    les metriques cout/tokens doivent rester None, jamais 0 (0 laisserait
    croire a une mesure reelle de cout nul)."""
    results = [score_case(CORE_CASE, {"issue_type_candidate": "MISSING_QTY", "fields": {}})]
    metrics = aggregate(results, group="mock")
    assert metrics.mean_cost_usd is None
    assert metrics.mean_total_tokens is None
    assert metrics.cache_rate is None
    assert metrics.mean_calls_per_case is None


def test_aggregate_cache_rate():
    results = [
        score_case(
            CORE_CASE,
            {"issue_type_candidate": "MISSING_QTY", "fields": {}},
            prompt_tokens=1000,
            completion_tokens=100,
            total_tokens=1100,
            cached_tokens=800,
        ),
        score_case(
            CORE_CASE,
            {"issue_type_candidate": "MISSING_QTY", "fields": {}},
            prompt_tokens=1000,
            completion_tokens=100,
            total_tokens=1100,
            cached_tokens=200,
        ),
    ]
    metrics = aggregate(results, group="cache")
    # (800 + 200) / (1000 + 1000) = 0.5
    assert metrics.cache_rate == 0.5


def test_aggregate_mean_calls_per_case_reflects_retries():
    no_retry = score_case(
        CORE_CASE,
        {"issue_type_candidate": "MISSING_QTY", "fields": {}},
        total_tokens=100,
        retry_count=0,
    )
    one_retry = score_case(
        CORE_CASE,
        {"issue_type_candidate": "MISSING_QTY", "fields": {}},
        total_tokens=200,
        retry_count=1,
    )
    metrics = aggregate([no_retry, one_retry], group="calls")
    # (1 appel + 2 appels) / 2 cas = 1.5
    assert metrics.mean_calls_per_case == 1.5


def test_full_corpus_scores_without_crashing_using_a_trivial_empty_predictor():
    """Preuve d'integration minimale : le scorer tourne sur TOUT le corpus
    reel (pas seulement des cas synthetiques de test) sans exception, meme
    avec un predicteur trivial qui ne propose jamais rien (pire cas
    possible : recall/precision au plancher, mais 0 crash, 0 fait invente
    par definition puisqu'il ne propose jamais rien)."""
    cases = load_corpus()
    results = [score_case(c, {"issue_type_candidate": None, "fields": {}}) for c in cases]
    report = aggregate_core_vs_stress(results)
    assert report["ALL"].case_count == len(cases)
    assert report["ALL"].invented_fact_rate == 0.0
