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

Points 9/10/12 (gouvernance coût/tokens IA, docs/GATE_R2_STATUS.md, retour
équipe 2026-08-20) - ajoutés à ce fichier :
  - chaque appel /chat/completions ou /audio/transcriptions lit
    `body["usage"]` quand présent (jamais inventé s'il est absent) et le
    propage dans TranscriptionResult/ExtractionResult (app/application/ports.py) ;
  - un coût estimé est calculé via une table de tarification codée en dur
    (app/infrastructure/ai/pricing.py, None si le modèle n'y figure pas) ;
  - CHAQUE appel terminé (succès ou échec) émet une ligne de log structuré
    PERMANENTE via app/infrastructure/ai/usage_journal.py (point 9) ;
  - un disjoncteur de budget optionnel (app/infrastructure/ai/budget_guard.py,
    point 12) est consulté avant tout appel HTTP payant, et alimenté après
    chaque appel dont le coût est connu.
"""

from __future__ import annotations

import json
import logging
import time
from pathlib import Path
from typing import TYPE_CHECKING

import httpx
from pydantic import ValidationError

from app.application.ports import AIProvider, ExtractionResult, TranscriptionResult
from app.domain.clarification_questions import clarification_question_id_for_field
from app.domain.errors import AIInvalidOutputError, AIRateLimitedError, AIUnavailableError
from app.domain.fact_set import CandidateFactData
from app.infrastructure.ai.pricing import estimate_chat_cost_usd
from app.infrastructure.ai.usage_journal import log_ai_usage

if TYPE_CHECKING:
    from app.infrastructure.ai.budget_guard import AiBudgetGuard

PROVIDER_NAME = "openai"

# Journalisation PERMANENTE (pas un print temporaire retiré après usage) -
# retour d'expérience terrain (R2, 2026-08) : plusieurs diagnostics
# (filename Whisper, 429 quota vs rate-limit) ont nécessité d'ajouter puis
# retirer un print() à chaque fois. `logger.warning` ci-dessous couvre tous
# les statuts d'erreur OpenAI une fois pour toutes - visible par défaut dans
# les logs `uvicorn` (configuration standard `logging`, niveau WARNING),
# jamais la clé API (le corps de réponse OpenAI ne la contient jamais).
#
# Distinct du logger dédié `reserveflash.ai.usage` (usage_journal.py,
# point 9) : celui-ci diagnostique une erreur provider (corps de réponse
# brut), l'autre journalise systématiquement la CONSOMMATION (tokens/coût/
# latence/retry) de chaque appel terminé, succès compris.
logger = logging.getLogger(__name__)

# prompts/ est au niveau racine du dépôt, backend/ est un sous-dossier -
# voir prompts/README.md : "fichiers nommés <usage>_<langue>_v<N>.txt".
_PROMPTS_DIR = Path(__file__).resolve().parents[4] / "prompts"

_OUTPUT_KEYS = {"issue_type_candidate", "fields", "requires_review", "most_uncertain_field"}

# Bug réel diagnostiqué en test terrain R2 (émulateur Android, GATE R2) :
# OpenAI détermine le format audio de `/v1/audio/transcriptions` à partir de
# l'EXTENSION du nom de fichier envoyé en multipart, jamais du `Content-Type`
# - un nom de fichier sans extension (ex: "audio") est systématiquement
# rejeté en 400 "Unrecognized file format", MÊME pour un contenu audio
# parfaitement valide (constaté avec un vrai .m4a enregistré par l'app).
# Formats supportés par l'API (message d'erreur OpenAI observé) : flac, m4a,
# mp3, mp4, mpeg, mpga, oga, ogg, wav, webm.
_MIME_TYPE_TO_EXTENSION = {
    "audio/flac": "flac",
    "audio/x-flac": "flac",
    "audio/m4a": "m4a",
    "audio/x-m4a": "m4a",
    "audio/mp3": "mp3",
    "audio/mpeg": "mp3",
    "audio/mp4": "mp4",
    "audio/mpga": "mpga",
    "audio/oga": "oga",
    "audio/ogg": "ogg",
    "audio/wav": "wav",
    "audio/x-wav": "wav",
    "audio/webm": "webm",
}


def _audio_filename_for_mime_type(mime_type: str) -> str:
    """Nom de fichier multipart avec extension, dérivé de [mime_type] -
    voir la note ci-dessus (_MIME_TYPE_TO_EXTENSION) : OpenAI a besoin d'une
    extension reconnue dans le nom, pas seulement du Content-Type. Repli sur
    le sous-type MIME tel quel (ex: "audio/aac" -> "audio.aac") si absent de
    la table - jamais un nom sans extension, qui échoue à coup sûr."""
    extension = _MIME_TYPE_TO_EXTENSION.get(mime_type.lower())
    if extension is None:
        _, _, subtype = mime_type.partition("/")
        extension = subtype.strip().lower() or "bin"
    return f"audio.{extension}"


def _load_prompt(prompt_version: str) -> str:
    path = _PROMPTS_DIR / f"{prompt_version}.txt"
    try:
        return path.read_text(encoding="utf-8")
    except FileNotFoundError as exc:
        # Un prompt_version inconnu est une erreur de configuration, pas une
        # indisponibilité IA - on ne la masque pas en AIUnavailableError.
        raise ValueError(f"Prompt version inconnue : {prompt_version!r} ({path})") from exc


def _sum_optional_ints(a: int | None, b: int | None) -> int | None:
    """Somme deux compteurs de tokens optionnels (point 9) - None seulement
    si LES DEUX sont None (aucune donnée d'usage disponible pour aucun des
    deux appels), jamais un 0 qui laisserait croire à une mesure réelle."""
    if a is None and b is None:
        return None
    return (a or 0) + (b or 0)


def _usage_ints(usage: dict) -> tuple[int | None, int | None, int | None, int | None]:
    """Extrait (prompt_tokens, completion_tokens, total_tokens, cached_tokens)
    du champ `usage` d'une réponse OpenAI - `cached_tokens` vient de
    `usage.prompt_tokens_details.cached_tokens` (prompt caching automatique
    OpenAI, point 10 "cache rate"). Toutes les clés sont absentes -> None,
    jamais 0 par défaut (0 affirmerait "aucun token utilisé", ce qui serait
    faux, on ne SAIT simplement pas)."""
    prompt_tokens = usage.get("prompt_tokens")
    completion_tokens = usage.get("completion_tokens")
    total_tokens = usage.get("total_tokens")
    cached_tokens = None
    details = usage.get("prompt_tokens_details")
    if isinstance(details, dict):
        cached_tokens = details.get("cached_tokens")
    return prompt_tokens, completion_tokens, total_tokens, cached_tokens


def _status_for_error(exc: Exception) -> str:
    if isinstance(exc, AIRateLimitedError):
        return "AI_RATE_LIMITED"
    if isinstance(exc, AIInvalidOutputError):
        return "AI_INVALID_OUTPUT"
    return "AI_UNAVAILABLE"


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
        budget_guard: AiBudgetGuard | None = None,
    ) -> None:
        self._transcription_model = transcription_model
        self._extraction_model = extraction_model
        # Point 12 (gouvernance coût/tokens IA) : None = aucun disjoncteur
        # (comportement historique, voir app/infrastructure/ai/__init__.py).
        self._budget_guard = budget_guard
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
        if self._budget_guard is not None:
            self._budget_guard.check_budget_or_raise(operation="transcribe")

        started = time.monotonic()
        try:
            response = self._client.post(
                "/audio/transcriptions",
                data={"model": self._transcription_model, "response_format": "json"},
                files={
                    "file": (
                        _audio_filename_for_mime_type(mime_type),
                        audio_bytes,
                        mime_type,
                    )
                },
            )
        except httpx.TimeoutException as exc:
            self._log_transcribe_outcome(started, "AI_UNAVAILABLE", None)
            raise AIUnavailableError("Timeout OpenAI (transcription).") from exc
        except httpx.TransportError as exc:
            self._log_transcribe_outcome(started, "AI_UNAVAILABLE", None)
            raise AIUnavailableError("Erreur réseau OpenAI (transcription).") from exc

        request_id = response.headers.get("x-request-id")
        try:
            self._raise_for_provider_errors(response, context="transcription")
        except (AIRateLimitedError, AIUnavailableError) as exc:
            self._log_transcribe_outcome(started, _status_for_error(exc), request_id)
            raise

        body = response.json()
        # whisper-1 (modèle par défaut, app/config.py) est tarifé à la DURÉE
        # audio, pas aux tokens, et `response_format="json"` utilisé ici ne
        # renvoie ni `usage` ni `duration` - estimated_cost_usd reste donc
        # None pour ce modèle (jamais une valeur inventée, voir pricing.py).
        # Les modèles de transcription plus récents (ex: gpt-4o-transcribe)
        # renvoient bien `usage` : ces champs se peupleront automatiquement
        # le jour où RESERVEFLASH_OPENAI_TRANSCRIPTION_MODEL change, sans
        # modification de ce fichier.
        usage = body.get("usage") or {}
        prompt_tokens, completion_tokens, total_tokens, cached_tokens = _usage_ints(usage)
        estimated_cost_usd: float | None = None
        if self._budget_guard is not None:
            self._budget_guard.record_spend(estimated_cost_usd)

        latency_ms = int((time.monotonic() - started) * 1000)
        log_ai_usage(
            operation="transcribe",
            provider=PROVIDER_NAME,
            model_id=self._transcription_model,
            status="OK",
            latency_ms=latency_ms,
            prompt_tokens=prompt_tokens,
            completion_tokens=completion_tokens,
            total_tokens=total_tokens,
            cached_tokens=cached_tokens,
            estimated_cost_usd=estimated_cost_usd,
            retry_count=0,
            request_id=request_id,
        )
        return TranscriptionResult(
            text=body.get("text", ""),
            provider=PROVIDER_NAME,
            model_id=self._transcription_model,
            latency_ms=latency_ms,
            request_id=request_id,
            prompt_tokens=prompt_tokens,
            completion_tokens=completion_tokens,
            total_tokens=total_tokens,
            cached_tokens=cached_tokens,
            estimated_cost_usd=estimated_cost_usd,
            retry_count=0,
        )

    def _log_transcribe_outcome(
        self, started: float, status: str, request_id: str | None
    ) -> None:
        latency_ms = int((time.monotonic() - started) * 1000)
        log_ai_usage(
            operation="transcribe",
            provider=PROVIDER_NAME,
            model_id=self._transcription_model,
            status=status,
            latency_ms=latency_ms,
            retry_count=0,
            request_id=request_id,
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
        retry_count = 0
        prompt_tokens: int | None = None
        completion_tokens: int | None = None
        total_tokens: int | None = None
        cached_tokens: int | None = None

        try:
            raw_text, request_id, usage = self._call_chat_completion(system_prompt, user_content)
        except (AIRateLimitedError, AIUnavailableError, AIInvalidOutputError) as exc:
            self._log_extract_outcome(started, retry_count, None, None, None, None, exc, None)
            raise
        prompt_tokens, completion_tokens, total_tokens, cached_tokens = _usage_ints(usage)

        candidate, error_for_repair = self._try_parse_candidate(raw_text)
        if candidate is None:
            # Exactement UNE tentative de réparation contrôlée (section
            # "Échec IA" de la demande R2) - jamais de boucle.
            retry_count = 1
            try:
                repaired_text, request_id, repair_usage = self._call_chat_completion(
                    system_prompt,
                    user_content,
                    repair_of=raw_text,
                    repair_error=error_for_repair,
                )
            except (AIRateLimitedError, AIUnavailableError, AIInvalidOutputError) as exc:
                self._log_extract_outcome(
                    started, retry_count, prompt_tokens, completion_tokens, total_tokens,
                    cached_tokens, exc, request_id,
                )
                raise
            r_prompt, r_completion, r_total, r_cached = _usage_ints(repair_usage)
            prompt_tokens = _sum_optional_ints(prompt_tokens, r_prompt)
            completion_tokens = _sum_optional_ints(completion_tokens, r_completion)
            total_tokens = _sum_optional_ints(total_tokens, r_total)
            cached_tokens = _sum_optional_ints(cached_tokens, r_cached)

            candidate, error_for_repair = self._try_parse_candidate(repaired_text)
            if candidate is None:
                estimated_cost_usd = self._estimate_and_record_cost(
                    prompt_tokens, completion_tokens
                )
                latency_ms = int((time.monotonic() - started) * 1000)
                log_ai_usage(
                    operation="extract",
                    provider=PROVIDER_NAME,
                    model_id=self._extraction_model,
                    status="AI_INVALID_OUTPUT",
                    latency_ms=latency_ms,
                    prompt_tokens=prompt_tokens,
                    completion_tokens=completion_tokens,
                    total_tokens=total_tokens,
                    cached_tokens=cached_tokens,
                    estimated_cost_usd=estimated_cost_usd,
                    retry_count=retry_count,
                    request_id=request_id,
                )
                raise AIInvalidOutputError(
                    "Sortie IA non conforme au schéma CandidateFactData après "
                    f"une tentative de réparation contrôlée : {error_for_repair}",
                    prompt_tokens=prompt_tokens,
                    completion_tokens=completion_tokens,
                    total_tokens=total_tokens,
                    estimated_cost_usd=estimated_cost_usd,
                    retry_count=retry_count,
                )

        estimated_cost_usd = self._estimate_and_record_cost(prompt_tokens, completion_tokens)
        latency_ms = int((time.monotonic() - started) * 1000)
        log_ai_usage(
            operation="extract",
            provider=PROVIDER_NAME,
            model_id=self._extraction_model,
            status="OK",
            latency_ms=latency_ms,
            prompt_tokens=prompt_tokens,
            completion_tokens=completion_tokens,
            total_tokens=total_tokens,
            cached_tokens=cached_tokens,
            estimated_cost_usd=estimated_cost_usd,
            retry_count=retry_count,
            request_id=request_id,
        )
        return ExtractionResult(
            candidate=candidate,
            provider=PROVIDER_NAME,
            model_id=self._extraction_model,
            prompt_version=prompt_version,
            schema_version="candidate_fact_set.v1",
            latency_ms=latency_ms,
            request_id=request_id,
            prompt_tokens=prompt_tokens,
            completion_tokens=completion_tokens,
            total_tokens=total_tokens,
            cached_tokens=cached_tokens,
            estimated_cost_usd=estimated_cost_usd,
            retry_count=retry_count,
        )

    def _log_extract_outcome(
        self,
        started: float,
        retry_count: int,
        prompt_tokens: int | None,
        completion_tokens: int | None,
        total_tokens: int | None,
        cached_tokens: int | None,
        exc: Exception,
        request_id: str | None,
    ) -> None:
        estimated_cost_usd = self._estimate_and_record_cost(prompt_tokens, completion_tokens)
        latency_ms = int((time.monotonic() - started) * 1000)
        log_ai_usage(
            operation="extract",
            provider=PROVIDER_NAME,
            model_id=self._extraction_model,
            status=_status_for_error(exc),
            latency_ms=latency_ms,
            prompt_tokens=prompt_tokens,
            completion_tokens=completion_tokens,
            total_tokens=total_tokens,
            cached_tokens=cached_tokens,
            estimated_cost_usd=estimated_cost_usd,
            retry_count=retry_count,
            request_id=request_id,
        )

    def _estimate_and_record_cost(
        self, prompt_tokens: int | None, completion_tokens: int | None
    ) -> float | None:
        estimated_cost_usd: float | None = None
        if prompt_tokens is not None and completion_tokens is not None:
            estimated_cost_usd = estimate_chat_cost_usd(
                self._extraction_model,
                prompt_tokens=prompt_tokens,
                completion_tokens=completion_tokens,
            )
        if self._budget_guard is not None:
            self._budget_guard.record_spend(estimated_cost_usd)
        return estimated_cost_usd

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
    ) -> tuple[str, str | None, dict]:
        if self._budget_guard is not None:
            self._budget_guard.check_budget_or_raise(operation="extract")

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
        return content, response.headers.get("x-request-id"), body.get("usage") or {}

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
            logger.warning(
                "OpenAI 429 (%s) - rate-limit OU quota/spend-limit, corps : %s",
                context,
                response.text,
            )
            raise AIRateLimitedError(f"OpenAI a limité le débit ({context}).")
        if response.status_code >= 500:
            logger.warning(
                "OpenAI %s indisponible (%s), corps : %s",
                response.status_code,
                context,
                response.text,
            )
            raise AIUnavailableError(
                f"OpenAI indisponible ({context}), statut {response.status_code}."
            )
        if response.status_code >= 400:
            # 4xx hors 429 = erreur de requête (mauvaise clé, payload
            # invalide côté nous) - traitée comme indisponibilité côté
            # utilisateur final (jamais de détail de clé/API exposé côté
            # exception levée), mais distincte d'un JSON de sortie invalide.
            # Le corps de réponse OpenAI est journalisé (jamais la clé
            # elle-même) pour permettre un diagnostic sans avoir à ajouter un
            # print temporaire à chaque fois.
            logger.warning(
                "OpenAI %s rejeté (%s), corps : %s",
                response.status_code,
                context,
                response.text,
            )
            raise AIUnavailableError(
                f"OpenAI a rejeté la requête ({context}), statut {response.status_code}."
            )
