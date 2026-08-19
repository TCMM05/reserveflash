"""Adapter IA de développement/tests - aucun appel réseau, aucune clé requise.

Implémente app.application.ports.AIProvider avec un comportement déterministe
et contrôlable, pour permettre de développer et tester tout le pipeline
(section 7.2) sans dépendre d'OpenAI. À remplacer par
app/infrastructure/ai/openai_provider.py en changeant uniquement
RESERVEFLASH_AI_PROVIDER=openai (section 5.3 - le domaine ne change pas).
"""

from __future__ import annotations

from app.application.ports import AIProvider, ExtractionResult, TranscriptionResult
from app.domain.fact_set import CandidateFactData
from app.domain.value_objects import ConfidenceLevel, FactSource, IssueType

PROVIDER_NAME = "mock"
MODEL_ID = "mock-deterministic-v1"


class MockAIProvider(AIProvider):
    """Fournit des réponses déterministes et injectables pour les tests
    d'intégration et le développement local, sans jamais appeler de service
    externe (aucune clé requise, conforme GATE secret)."""

    def __init__(
        self,
        *,
        transcript: str = "",
        forced_extraction: CandidateFactData | None = None,
        raise_unavailable: bool = False,
    ) -> None:
        self._transcript = transcript
        self._forced_extraction = forced_extraction
        self._raise_unavailable = raise_unavailable

    def transcribe(self, audio_bytes: bytes, mime_type: str) -> TranscriptionResult:
        if self._raise_unavailable:
            from app.domain.errors import AIUnavailableError

            raise AIUnavailableError("Provider IA mock configuré pour simuler une indisponibilité.")
        return TranscriptionResult(
            text=self._transcript,
            provider=PROVIDER_NAME,
            model_id=MODEL_ID,
            latency_ms=1,
            request_id=None,
        )

    def extract_candidate_facts(
        self,
        *,
        document_text: str | None,
        transcript: str | None,
        prompt_version: str,
    ) -> ExtractionResult:
        if self._raise_unavailable:
            from app.domain.errors import AIUnavailableError

            raise AIUnavailableError("Provider IA mock configuré pour simuler une indisponibilité.")

        candidate = self._forced_extraction or CandidateFactData(
            issue_type_candidate=IssueType.OTHER,
            fields={
                "product_label": {
                    "value": None,
                    "source": FactSource.TEXT_INPUT,
                    "confidence": ConfidenceLevel.AMBIGUOUS,
                    "ambiguous": True,
                }
            },
            requires_review=True,
            clarification_question_id="Q_PRODUCT_LABEL_MISSING",
        )
        return ExtractionResult(
            candidate=candidate,
            provider=PROVIDER_NAME,
            model_id=MODEL_ID,
            prompt_version=prompt_version,
            schema_version="candidate_fact_set.v1",
            latency_ms=1,
            request_id=None,
        )
