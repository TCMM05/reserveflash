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

from app.domain.errors import AIInvalidOutputError, AIRateLimitedError, AIUnavailableError
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


def _provider_with_transport(handler) -> OpenAIProvider:
    client = httpx.Client(
        base_url="https://api.openai.com/v1",
        transport=httpx.MockTransport(handler),
    )
    return OpenAIProvider(api_key="test-key", http_client=client)


# --- Transcription -----------------------------------------------------


def test_transcribe_success():
    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.path == "/v1/audio/transcriptions"
        return httpx.Response(200, json={"text": "il manque une unité"})

    provider = _provider_with_transport(handler)
    result = provider.transcribe(b"fake-audio", "audio/wav")
    assert result.text == "il manque une unité"
    assert result.provider == "openai"


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
