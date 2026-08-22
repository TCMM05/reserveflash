"""Tests réels du OpenAIProvider (R2) - AUCUN appel réseau : le transport
httpx est entièrement mocké (httpx.MockTransport), conformément à la
justification du module (voir en-tête de openai_provider.py : pas d'accès
réseau vers api.openai.com dans cet environnement de développement).

Ces tests vérifient le comportement réel du provider face à des réponses
HTTP construites à la main (succès, JSON invalide, réparation, rate limit,
timeout, erreur serveur) - pas un mock du provider lui-même."""

from __future__ import annotations

import json

import httpx
import pytest

from app.domain.errors import (
    AIBudgetExceededError,
    AIInvalidOutputError,
    AIRateLimitedError,
    AIUnavailableError,
)
from app.infrastructure.ai.budget_guard import AiBudgetGuard
from app.infrastructure.ai.openai_provider import OpenAIProvider

VALID_CANDIDATE_JSON = {
    "issue_type_candidate": "MISSING_QTY",
    "fields": {
        "product_reference": {
            "value": "PAC-284",
            "source": "VOICE_TRANSCRIPT",
            "confidence": "HIGH",
            "ambiguous": False,
        },
        "expected_quantity": {
            "value": 12,
            "source": "VOICE_TRANSCRIPT",
            "confidence": "HIGH",
            "ambiguous": False,
        },
        "received_quantity": {
            "value": 11,
            "source": "VOICE_TRANSCRIPT",
            "confidence": "HIGH",
            "ambiguous": False,
        },
    },
    "requires_review": False,
    "most_uncertain_field": None,
}


def _chat_response_body(content: str, request_id: str = "req-1") -> httpx.Response:
    return httpx.Response(
        200,
        json={"choices": [{"message": {"content": content}}]},
        headers={"x-request-id": request_id},
    )


def _chat_response_body_with_usage(
    content: str,
    *,
    request_id: str = "req-1",
    prompt_tokens: int = 100,
    completion_tokens: int = 50,
    cached_tokens: int | None = None,
) -> httpx.Response:
    usage = {
        "prompt_tokens": prompt_tokens,
        "completion_tokens": completion_tokens,
        "total_tokens": prompt_tokens + completion_tokens,
    }
    if cached_tokens is not None:
        usage["prompt_tokens_details"] = {"cached_tokens": cached_tokens}
    return httpx.Response(
        200,
        json={"choices": [{"message": {"content": content}}], "usage": usage},
        headers={"x-request-id": request_id},
    )


def _provider_with_transport(
    handler, *, budget_guard: AiBudgetGuard | None = None
) -> OpenAIProvider:
    client = httpx.Client(
        base_url="https://api.openai.com/v1",
        transport=httpx.MockTransport(handler),
    )
    return OpenAIProvider(api_key="test-key", http_client=client, budget_guard=budget_guard)


# --- Transcription -----------------------------------------------------


def test_transcribe_success():
    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.path == "/v1/audio/transcriptions"
        return httpx.Response(200, json={"text": "il manque une unité"})

    provider = _provider_with_transport(handler)
    result = provider.transcribe(b"fake-audio", "audio/wav")
    assert result.text == "il manque une unité"
    assert result.provider == "openai"


def test_transcribe_sends_filename_with_extension_matching_mime_type():
    # Bug réel diagnostiqué en test terrain R2 (émulateur Android) : OpenAI
    # détermine le format audio depuis l'EXTENSION du nom de fichier
    # multipart, pas depuis le Content-Type - un nom sans extension (ex:
    # "audio") est rejeté en 400 "Unrecognized file format" même pour un
    # contenu valide (voir _audio_filename_for_mime_type). Ce test vérifie
    # que le nom de fichier envoyé porte bien une extension reconnue par
    # OpenAI, dérivée du mime_type réel (ex: "audio/m4a" -> "audio.m4a"),
    # jamais un nom nu.
    captured_filenames: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        content_disposition = next(
            (
                part
                for part in request.content.split(b"\r\n")
                if b"filename=" in part
            ),
            b"",
        )
        captured_filenames.append(content_disposition.decode())
        return httpx.Response(200, json={"text": "ok"})

    provider = _provider_with_transport(handler)
    provider.transcribe(b"fake-audio-bytes", "audio/m4a")

    assert len(captured_filenames) == 1
    assert 'filename="audio.m4a"' in captured_filenames[0]


def test_transcribe_timeout_raises_ai_unavailable():
    def handler(request: httpx.Request) -> httpx.Response:
        raise httpx.TimeoutException("boom", request=request)

    provider = _provider_with_transport(handler)
    with pytest.raises(AIUnavailableError):
        provider.transcribe(b"...", "audio/wav")


def test_transcribe_rate_limited_raises_ai_rate_limited():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(429, json={"error": "rate limited"})

    provider = _provider_with_transport(handler)
    with pytest.raises(AIRateLimitedError):
        provider.transcribe(b"...", "audio/wav")


def test_transcribe_server_error_raises_ai_unavailable():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(500, json={"error": "boom"})

    provider = _provider_with_transport(handler)
    with pytest.raises(AIUnavailableError):
        provider.transcribe(b"...", "audio/wav")


# --- Extraction : succès -------------------------------------------------


def test_extract_success_first_try():
    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.path == "/v1/chat/completions"
        return _chat_response_body(json.dumps(VALID_CANDIDATE_JSON))

    provider = _provider_with_transport(handler)
    result = provider.extract_candidate_facts(
        document_text=None,
        transcript="il devait y en avoir 12, il en manque une",
        prompt_version="extraction_fr_v1",
    )
    assert result.candidate.issue_type_candidate == "MISSING_QTY"
    assert result.candidate.fields["received_quantity"].value == 11
    assert result.schema_version == "candidate_fact_set.v1"


def test_extract_maps_most_uncertain_field_via_catalog():
    payload = dict(VALID_CANDIDATE_JSON, most_uncertain_field="product_reference")

    def handler(request: httpx.Request) -> httpx.Response:
        return _chat_response_body(json.dumps(payload))

    provider = _provider_with_transport(handler)
    result = provider.extract_candidate_facts(
        document_text="texte", transcript=None, prompt_version="extraction_fr_v1"
    )
    assert result.candidate.clarification_question_id == "Q_PRODUCT_REFERENCE_MISSING"


def test_extract_ignores_hallucinated_most_uncertain_field():
    """Le catalogue controle (app.domain.clarification_questions) ignore
    silencieusement un nom de champ hors catalogue - jamais une valeur
    inventee par le modele qui fuiterait telle quelle."""
    payload = dict(VALID_CANDIDATE_JSON, most_uncertain_field="ceci n'est pas un vrai champ")

    def handler(request: httpx.Request) -> httpx.Response:
        return _chat_response_body(json.dumps(payload))

    provider = _provider_with_transport(handler)
    result = provider.extract_candidate_facts(
        document_text="texte", transcript=None, prompt_version="extraction_fr_v1"
    )
    assert result.candidate.clarification_question_id is None


# --- Extraction : réparation contrôlée -----------------------------------


def test_extract_invalid_json_then_valid_repair_succeeds():
    calls = {"n": 0}

    def handler(request: httpx.Request) -> httpx.Response:
        calls["n"] += 1
        if calls["n"] == 1:
            return _chat_response_body("ceci n'est pas du JSON")
        return _chat_response_body(json.dumps(VALID_CANDIDATE_JSON))

    provider = _provider_with_transport(handler)
    result = provider.extract_candidate_facts(
        document_text=None, transcript="texte", prompt_version="extraction_fr_v1"
    )
    assert calls["n"] == 2  # 1 tentative initiale + 1 réparation, jamais plus
    assert result.candidate.issue_type_candidate == "MISSING_QTY"


def test_extract_invalid_json_both_times_raises_ai_invalid_output_after_exactly_one_repair():
    calls = {"n": 0}

    def handler(request: httpx.Request) -> httpx.Response:
        calls["n"] += 1
        return _chat_response_body("toujours pas du JSON valide")

    provider = _provider_with_transport(handler)
    with pytest.raises(AIInvalidOutputError):
        provider.extract_candidate_facts(
            document_text=None, transcript="texte", prompt_version="extraction_fr_v1"
        )
    assert calls["n"] == 2  # pas de boucle infinie : exactement 2 appels


def test_extract_schema_non_conformant_json_triggers_repair_too():
    """Un JSON syntaxiquement valide mais qui ne respecte pas
    CandidateFactData (ex: clé additionnelle non prevue) doit aussi
    declencher la reparation, pas seulement un JSON malforme."""
    calls = {"n": 0}
    invalid_schema = {"totally_unexpected_key": True}

    def handler(request: httpx.Request) -> httpx.Response:
        calls["n"] += 1
        if calls["n"] == 1:
            return _chat_response_body(json.dumps(invalid_schema))
        return _chat_response_body(json.dumps(VALID_CANDIDATE_JSON))

    provider = _provider_with_transport(handler)
    result = provider.extract_candidate_facts(
        document_text=None, transcript="texte", prompt_version="extraction_fr_v1"
    )
    assert calls["n"] == 2
    assert result.candidate.issue_type_candidate == "MISSING_QTY"


def test_extract_rate_limited_raises_immediately_without_repair_attempt():
    calls = {"n": 0}

    def handler(request: httpx.Request) -> httpx.Response:
        calls["n"] += 1
        return httpx.Response(429, json={"error": "rate limited"})

    provider = _provider_with_transport(handler)
    with pytest.raises(AIRateLimitedError):
        provider.extract_candidate_facts(
            document_text=None, transcript="texte", prompt_version="extraction_fr_v1"
        )
    assert calls["n"] == 1  # une erreur provider n'est pas une sortie a reparer


# --- Points 9/10/12 : usage tokens / coût estimé / retry_count / budget ---


def test_extract_populates_usage_and_cost_on_first_try_success():
    def handler(request: httpx.Request) -> httpx.Response:
        return _chat_response_body_with_usage(
            json.dumps(VALID_CANDIDATE_JSON), prompt_tokens=1000, completion_tokens=200
        )

    provider = _provider_with_transport(handler)
    result = provider.extract_candidate_facts(
        document_text=None, transcript="texte", prompt_version="extraction_fr_v1"
    )
    assert result.prompt_tokens == 1000
    assert result.completion_tokens == 200
    assert result.total_tokens == 1200
    assert result.retry_count == 0
    # gpt-4o-mini (modele par defaut) est dans la table de tarification
    # (pricing.py) : le cout doit etre calcule, pas None.
    expected_cost = (1000 * 0.15 + 200 * 0.60) / 1_000_000
    assert result.estimated_cost_usd is not None
    assert abs(result.estimated_cost_usd - expected_cost) < 1e-12


def test_extract_sums_usage_across_initial_and_repair_call():
    calls = {"n": 0}

    def handler(request: httpx.Request) -> httpx.Response:
        calls["n"] += 1
        if calls["n"] == 1:
            return _chat_response_body_with_usage(
                "ceci n'est pas du JSON", prompt_tokens=300, completion_tokens=40
            )
        return _chat_response_body_with_usage(
            json.dumps(VALID_CANDIDATE_JSON), prompt_tokens=350, completion_tokens=60
        )

    provider = _provider_with_transport(handler)
    result = provider.extract_candidate_facts(
        document_text=None, transcript="texte", prompt_version="extraction_fr_v1"
    )
    assert result.retry_count == 1
    assert result.prompt_tokens == 300 + 350
    assert result.completion_tokens == 40 + 60
    assert result.total_tokens == 340 + 410


def test_extract_captures_cached_tokens_when_present():
    def handler(request: httpx.Request) -> httpx.Response:
        return _chat_response_body_with_usage(
            json.dumps(VALID_CANDIDATE_JSON),
            prompt_tokens=1000,
            completion_tokens=200,
            cached_tokens=800,
        )

    provider = _provider_with_transport(handler)
    result = provider.extract_candidate_facts(
        document_text=None, transcript="texte", prompt_version="extraction_fr_v1"
    )
    assert result.cached_tokens == 800


def test_extract_missing_usage_field_leaves_tokens_none_not_zero():
    """Reponse OpenAI sans cle `usage` (jamais rencontre en pratique mais
    pas garanti par le contrat) -> None, jamais 0 (voir GATE zero
    invention applique au cout/tokens)."""

    def handler(request: httpx.Request) -> httpx.Response:
        return _chat_response_body(json.dumps(VALID_CANDIDATE_JSON))

    provider = _provider_with_transport(handler)
    result = provider.extract_candidate_facts(
        document_text=None, transcript="texte", prompt_version="extraction_fr_v1"
    )
    assert result.prompt_tokens is None
    assert result.completion_tokens is None
    assert result.estimated_cost_usd is None


def test_extract_invalid_output_error_carries_usage_for_visibility():
    """Point 9 : une sortie invalide a quand meme un cout reel - il ne doit
    pas disparaitre juste parce que l'appel a finalement echoue (voir
    AIInvalidOutputError, app/domain/errors.py)."""
    calls = {"n": 0}

    def handler(request: httpx.Request) -> httpx.Response:
        calls["n"] += 1
        return _chat_response_body_with_usage(
            "toujours pas du JSON valide", prompt_tokens=100, completion_tokens=20
        )

    provider = _provider_with_transport(handler)
    with pytest.raises(AIInvalidOutputError) as exc_info:
        provider.extract_candidate_facts(
            document_text=None, transcript="texte", prompt_version="extraction_fr_v1"
        )
    err = exc_info.value
    assert err.retry_count == 1
    assert err.prompt_tokens == 100 + 100
    assert err.completion_tokens == 20 + 20


def test_transcribe_usage_fields_default_to_none_and_zero_retry():
    """whisper-1 (response_format="json") ne renvoie ni usage ni cout par
    tokens - voir docstring de transcribe()."""

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json={"text": "il manque une unité"})

    provider = _provider_with_transport(handler)
    result = provider.transcribe(b"fake-audio", "audio/wav")
    assert result.prompt_tokens is None
    assert result.estimated_cost_usd is None
    assert result.retry_count == 0


def test_budget_guard_blocks_extract_before_any_http_call_when_exceeded():
    calls = {"n": 0}

    def handler(request: httpx.Request) -> httpx.Response:
        calls["n"] += 1
        return _chat_response_body_with_usage(json.dumps(VALID_CANDIDATE_JSON))

    guard = AiBudgetGuard(daily_budget_usd=0.0)
    guard.record_spend(0.01)  # déjà au-dessus du budget (0.0)
    provider = _provider_with_transport(handler, budget_guard=guard)

    with pytest.raises(AIBudgetExceededError):
        provider.extract_candidate_facts(
            document_text=None, transcript="texte", prompt_version="extraction_fr_v1"
        )
    assert calls["n"] == 0  # aucun appel HTTP n'a dû partir


def test_budget_guard_blocks_transcribe_before_any_http_call_when_exceeded():
    calls = {"n": 0}

    def handler(request: httpx.Request) -> httpx.Response:
        calls["n"] += 1
        return httpx.Response(200, json={"text": "ok"})

    guard = AiBudgetGuard(daily_budget_usd=0.0)
    guard.record_spend(0.01)
    provider = _provider_with_transport(handler, budget_guard=guard)

    with pytest.raises(AIBudgetExceededError):
        provider.transcribe(b"...", "audio/wav")
    assert calls["n"] == 0


def test_budget_guard_accumulates_spend_across_successful_extract_calls():
    def handler(request: httpx.Request) -> httpx.Response:
        return _chat_response_body_with_usage(
            json.dumps(VALID_CANDIDATE_JSON), prompt_tokens=1000, completion_tokens=200
        )

    guard = AiBudgetGuard(daily_budget_usd=1.0)
    provider = _provider_with_transport(handler, budget_guard=guard)

    provider.extract_candidate_facts(
        document_text=None, transcript="texte", prompt_version="extraction_fr_v1"
    )
    expected_cost = (1000 * 0.15 + 200 * 0.60) / 1_000_000
    assert abs(guard.spent_usd() - expected_cost) < 1e-12

    provider.extract_candidate_facts(
        document_text=None, transcript="texte", prompt_version="extraction_fr_v1"
    )
    assert abs(guard.spent_usd() - 2 * expected_cost) < 1e-12


def test_no_budget_guard_means_no_enforcement_backward_compatible():
    """Comportement historique (avant point 12) : sans budget_guard fourni,
    aucune verification, comme avant l'ajout de cette fonctionnalite."""

    def handler(request: httpx.Request) -> httpx.Response:
        return _chat_response_body_with_usage(json.dumps(VALID_CANDIDATE_JSON))

    provider = _provider_with_transport(handler, budget_guard=None)
    result = provider.extract_candidate_facts(
        document_text=None, transcript="texte", prompt_version="extraction_fr_v1"
    )
    assert result.candidate.issue_type_candidate == "MISSING_QTY"
