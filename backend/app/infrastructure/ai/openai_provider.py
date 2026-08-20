"""Provider IA réel (R2) - implémente app.application.ports.AIProvider en
appelant l'API HTTP d'OpenAI directement via `httpx`, plutôt que le SDK
`openai`.

Choix délibéré et documenté : ce sandbox de développement n'a pas d'accès
réseau vers api.openai.com (vérifié - toute requête sortante échoue), donc
aucune vérification réelle contre le SDK `openai` installé n'est possible
ici, et sa version exacte disponible en production n'est pas garantie
identique. L'API HTTP REST d'OpenAI (endpoints `/audio/transcriptions` et
`/chat/completions`) est un contrat stable, documenté, et permet un test
unitaire précis en mockant le transport `httpx` - sans dépendre d'une
surface d'API de SDK tierce non vérifiable depuis cet environnement. Ce
choix pourra être révisé une fois testé en conditions réelles (poste
utilisateur, voir docs/GATE_R2_STATUS.md).

Comportement conforme à la demande de démarrage R2, section "Échec IA" :
  - Timeout / erreur réseau / erreur serveur OpenAI (5xx) -> AIUnavailableError.
  - 429 -> AIRateLimitedError.
  - Sortie JSON structurée invalide (JSON malformé OU non conforme au schéma
    CandidateFactData) -> EXACTEMENT une tentative de réparation contrôlée
    (un second appel modèle avec le JSON invalide + l'erreur de validation),
    puis AIInvalidOutputError si toujours invalide. Jamais de boucle.
  - `most_uncertain_field` (métadonnée hors-schéma produite par le modèle,
    voir prompts/extraction_fr_v1.txt) est traduit en
    `clarification_question_id` UNIQUEMENT via le catalogue contrôlé
    (app.domain.clarification_questions) - jamais une valeur produite
    directement par le modèle.
"""

from __future__ import annotations

import json
import time
from pathlib import Path

import httpx
from pydantic import ValidationError

from app.application.ports import AIProvider, ExtractionResult, TranscriptionResult
from app.domain.clarification_questions import clarification_question_id_for_field
from app.domain.errors import AIInvalidOutputError, AIRateLimitedError, AIUnavailableError
from app.domain.fact_set import CandidateFactData

PROVIDER_NAME = "openai"

# prompts/ est au niveau racine du dépôt, backend/ est un sous-dossier -
# voir prompts/README.md : "fichiers nommés <usage>_<langue>_v<N>.txt".
_PROMPTS_DIR = Path(__file__).resolve().parents[4] / "prompts"

_OUTPUT_KEYS = {"issue_type_candidate", "fields", "requires_review", "most_uncertain_field"}


def _load_prompt(prompt_version: str) -> str:
    path = _PROMPTS_DIR / f"{prompt_version}.txt"
    try:
        return path.read_text(encoding="utf-8")
    except FileNotFoundError as exc:
        # Un prompt_version inconnu est une erreur de configuration, pas une
        # indisponibilité IA - on ne la masque pas en AIUnavailableError.
        raise ValueError(f"Prompt version inconnue : {prompt_version!r} ({path})") from exc


class OpenAIProvider(AIProvider):
    def __init__(
        self,
        *,
        api_key: str,
        base_url: str = "https://api.openai.com/v1",
        transcription_model: str = "whisper-1",
        extraction_model: str = "gpt-4o-mini",
        timeout_seconds: float = 30.0,
        http_client: httpx.Client | None = None,
    ) -> None:
        self._transcription_model = transcription_model
        self._extraction_model = extraction_model
        # http_client injectable : les tests fournissent un client construit
        # avec `transport=httpx.MockTransport(...)`, sans jamais toucher au
        # réseau réel (voir tests/infrastructure/test_openai_provider.py).
        self._client = http_client or httpx.Client(
            base_url=base_url,
            headers={"Authorization": f"Bearer {api_key}"},
            timeout=timeout_seconds,
        )

    # ------------------------------------------------------------------
    # Transcription
    # ------------------------------------------------------------------

    def transcribe(self, audio_bytes: bytes, mime_type: str) -> TranscriptionResult:
        started = time.monotonic()
        try:
            response = self._client.post(
                "/audio/transcriptions",
                data={"model": self._transcription_model, "response_format": "json"},
                files={"file": ("audio", audio_bytes, mime_type)},
            )
        except httpx.TimeoutException as exc:
            raise AIUnavailableError("Timeout OpenAI (transcription).") from exc
        except httpx.TransportError as exc:
            raise AIUnavailableError("Erreur réseau OpenAI (transcription).") from exc

        self._raise_for_provider_errors(response, context="transcription")

        body = response.json()
        latency_ms = int((time.monotonic() - started) * 1000)
        return TranscriptionResult(
            text=body.get("text", ""),
            provider=PROVIDER_NAME,
            model_id=self._transcription_model,
            latency_ms=latency_ms,
            request_id=response.headers.get("x-request-id"),
        )

    # ------------------------------------------------------------------
    # Extraction
    # ------------------------------------------------------------------

    def extract_candidate_facts(
        self,
        *,
        document_text: str | None,
        transcript: str | None,
        prompt_version: str,
    ) -> ExtractionResult:
        system_prompt = _load_prompt(prompt_version)
        user_content = self._build_user_content(document_text=document_text, transcript=transcript)

        started = time.monotonic()
        raw_text, request_id = self._call_chat_completion(system_prompt, user_content)

        candidate, error_for_repair = self._try_parse_candidate(raw_text)
        if candidate is None:
            # Exactement UNE tentative de réparation contrôlée (section
            # "Échec IA" de la demande R2) - jamais de boucle.
            repaired_text, request_id = self._call_chat_completion(
                system_prompt,
                user_content,
                repair_of=raw_text,
                repair_error=error_for_repair,
            )
            candidate, error_for_repair = self._try_parse_candidate(repaired_text)
            if candidate is None:
                raise AIInvalidOutputError(
                    "Sortie IA non conforme au schéma CandidateFactData après "
                    f"une tentative de réparation contrôlée : {error_for_repair}"
                )

        latency_ms = int((time.monotonic() - started) * 1000)
        return ExtractionResult(
            candidate=candidate,
            provider=PROVIDER_NAME,
            model_id=self._extraction_model,
            prompt_version=prompt_version,
            schema_version="candidate_fact_set.v1",
            latency_ms=latency_ms,
            request_id=request_id,
        )

    # ------------------------------------------------------------------
    # Internes
    # ------------------------------------------------------------------

    @staticmethod
    def _build_user_content(*, document_text: str | None, transcript: str | None) -> str:
        parts: list[str] = []
        if transcript:
            parts.append(f"TRANSCRIPTION AUDIO :\n{transcript}")
        if document_text:
            parts.append(f"TEXTE OCR DU DOCUMENT :\n{document_text}")
        if not parts:
            parts.append("(aucun texte fourni)")
        return "\n\n".join(parts)

    def _call_chat_completion(
        self,
        system_prompt: str,
        user_content: str,
        *,
        repair_of: str | None = None,
        repair_error: str | None = None,
    ) -> tuple[str, str | None]:
        messages = [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_content},
        ]
        if repair_of is not None:
            messages.append(
                {
                    "role": "user",
                    "content": (
                        "Ta réponse précédente n'était pas un JSON valide pour le "
                        f"format demandé : {repair_error}\n\nRéponse précédente :\n"
                        f"{repair_of}\n\nRenvoie UNIQUEMENT le JSON corrigé, rien d'autre."
                    ),
                }
            )
        try:
            response = self._client.post(
                "/chat/completions",
                json={
                    "model": self._extraction_model,
                    "messages": messages,
                    "response_format": {"type": "json_object"},
                    "temperature": 0,
                },
            )
        except httpx.TimeoutException as exc:
            raise AIUnavailableError("Timeout OpenAI (extraction).") from exc
        except httpx.TransportError as exc:
            raise AIUnavailableError("Erreur réseau OpenAI (extraction).") from exc

        self._raise_for_provider_errors(response, context="extraction")

        body = response.json()
        try:
            content = body["choices"][0]["message"]["content"]
        except (KeyError, IndexError) as exc:
            raise AIInvalidOutputError(
                "Réponse OpenAI sans contenu exploitable (structure inattendue)."
            ) from exc
        return content, response.headers.get("x-request-id")

    @staticmethod
    def _try_parse_candidate(raw_text: str) -> tuple[CandidateFactData | None, str | None]:
        try:
            data = json.loads(raw_text)
        except json.JSONDecodeError as exc:
            return None, f"JSON invalide : {exc}"

        if not isinstance(data, dict):
            return None, "La réponse JSON n'est pas un objet."

        unexpected_keys = set(data) - _OUTPUT_KEYS
        if unexpected_keys:
            return None, f"Clé(s) non attendue(s) dans la réponse : {sorted(unexpected_keys)}"

        most_uncertain_field = data.get("most_uncertain_field")
        clarification_question_id = clarification_question_id_for_field(most_uncertain_field)

        candidate_payload = {
            "issue_type_candidate": data.get("issue_type_candidate"),
            "fields": data.get("fields", {}),
            "requires_review": data.get("requires_review", True),
            "clarification_question_id": clarification_question_id,
        }
        try:
            return CandidateFactData(**candidate_payload), None
        except ValidationError as exc:
            return None, str(exc)

    @staticmethod
    def _raise_for_provider_errors(response: httpx.Response, *, context: str) -> None:
        if response.status_code == httpx.codes.TOO_MANY_REQUESTS:
            raise AIRateLimitedError(f"OpenAI a limité le débit ({context}).")
        if response.status_code >= 400:
            # DEBUG TEMPORAIRE (diagnostic terrain R2, à retirer une fois la
            # cause du 403/503 observé identifiée avec certitude) : affiche
            # le corps d'erreur OpenAI complet UNIQUEMENT dans les logs
            # serveur locaux (console uvicorn) - jamais renvoyé au client
            # mobile, qui reçoit toujours le message générique ci-dessous
            # (aucune fuite de détail sensible côté app).
            print(
                f"[DEBUG OpenAI {context}] status={response.status_code} "
                f"body={response.text[:2000]!r}"
            )
        if response.status_code >= 500:
            raise AIUnavailableError(
                f"OpenAI indisponible ({context}), statut {response.status_code}."
            )
        if response.status_code >= 400:
            # 4xx hors 429 = erreur de requête (mauvaise clé, payload
            # invalide côté nous) - traitée comme indisponibilité côté
            # utilisateur final (jamais de détail de clé/API exposé), mais
            # distincte d'un JSON de sortie invalide.
            raise AIUnavailableError(
                f"OpenAI a rejeté la requête ({context}), statut {response.status_code}."
            )
