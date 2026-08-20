"""Endpoints /v1/ai/* - LE rôle primaire du backend depuis R0.1 (pivot
Local-First, points 4/5 de la demande corrective, voir
docs/adr/0002-local-first-pivot.md).

"Le backend devient minimal et sans état. Rôle limité à : protéger la clé
API OpenAI ; recevoir strictement les données nécessaires au traitement IA ;
appeler le provider IA ; valider la structure de la réponse ; renvoyer les
CandidateFacts au téléphone. Il ne doit PAS devenir la base de données
centrale des incidents."

Ces routes :
  - ne dépendent d'AUCUN repository (pas d'IncidentRepository injecté) : le
    backend ne sait rien d'un incident, ne le lit ni ne l'écrit ;
  - ne dépendent d'AUCUN provider de stockage : aucun média n'est persisté
    ici (voir docs/security.md - "pas de stockage durable de photos/BL/audio
    hors nécessité technique documentée", point 4) ;
  - valident la structure de la réponse IA via les types pydantic
    eux-mêmes (`CandidateFactData`, `extra="forbid"`) - une sortie provider
    non conforme lève AIInvalidOutputError (app/domain/errors.py), mappée en
    422 (app/api/errors.py), AVANT de quitter ce module ;
  - n'exigent PAS d'authentification utilisateur (point 13 - aucun compte
    cloud requis pour utiliser l'app). ROADMAP avant exposition publique :
    clé API par installation pour l'anti-abus/rate-limiting (distincte d'un
    compte utilisateur) - voir docs/security.md.

Flux imposé par le point 5 de la demande corrective : Flutter -> Backend
ReserveFlash -> OpenAI -> Backend -> Flutter. L'app mobile n'appelle JAMAIS
OpenAI directement (aucune clé OpenAI n'est ni ne doit être embarquée dans
l'app - voir mobile/README.md et docs/security.md, GATE secret)."""

from __future__ import annotations

import base64
from typing import Annotated

from fastapi import APIRouter, Depends

from app.api.deps import get_ai_provider
from app.api.schemas import (
    ExtractCandidateFactsRequest,
    ExtractCandidateFactsResponse,
    TranscribeAudioRequest,
    TranscribeAudioResponse,
)
from app.application.ports import AIProvider
from app.domain.candidate_guard import screen_candidate_fact_data

router = APIRouter(prefix="/ai", tags=["ai"])

Provider = Annotated[AIProvider, Depends(get_ai_provider)]


@router.post("/transcribe", response_model=TranscribeAudioResponse)
def transcribe_audio(
    payload: TranscribeAudioRequest, ai_provider: Provider
) -> TranscribeAudioResponse:
    """F06/F11 (section 2.1) - transcrit un extrait audio. Ne persiste rien :
    l'app mobile est responsable de conserver le résultat localement (Drift,
    voir LocalCandidateFactSets)."""
    audio_bytes = base64.b64decode(payload.audio_base64)
    result = ai_provider.transcribe(audio_bytes, payload.mime_type)
    # DEBUG TEMPORAIRE (diagnostic terrain R2 - vérifier que le micro de
    # l'émulateur Android capte réellement la voix, pas du silence) :
    # affiche le transcript UNIQUEMENT dans la console uvicorn locale,
    # jamais renvoyé nulle part ailleurs. A retirer une fois le test terrain
    # confirmé concluant.
    print(f"[DEBUG transcript] {len(audio_bytes)} octets audio -> {result.text!r}")
    return TranscribeAudioResponse(
        text=result.text,
        provider=result.provider,
        model_id=result.model_id,
        latency_ms=result.latency_ms,
        request_id=result.request_id,
    )


@router.post("/extract", response_model=ExtractCandidateFactsResponse)
def extract_candidate_facts(
    payload: ExtractCandidateFactsRequest, ai_provider: Provider
) -> ExtractCandidateFactsResponse:
    """F07/F08 (section 2.1) - extrait un `CandidateFactData` structuré à
    partir d'un texte déjà transcrit/OCRisé. Le résultat DOIT ensuite passer
    par la revue utilisateur (F09) puis
    `lib/domain/liability_guard.dart`/`app/domain/liability_guard.py` avant
    de pouvoir devenir un `ConfirmedFactData` - jamais directement utilisable
    par un Reserve Composer (GATE zéro invention, ADR 0001).

    R2 (section "Validation sémantique obligatoire") : avant de renvoyer le
    candidat, `screen_candidate_fact_data` (app/domain/candidate_guard.py)
    retire tout champ contenant une attribution de responsabilité, une
    conclusion/qualification juridique, une promesse d'indemnisation, un
    montant inventé, ou une quantité négative - appliqué ICI, au point
    d'entrée unique des candidats côté backend, pour couvrir tout provider
    (mock ou réel) sans dépendre de sa discipline interne."""
    result = ai_provider.extract_candidate_facts(
        document_text=payload.document_text,
        transcript=payload.transcript,
        prompt_version=payload.prompt_version,
    )
    screened_candidate = screen_candidate_fact_data(result.candidate)
    return ExtractCandidateFactsResponse(
        candidate=screened_candidate,
        provider=result.provider,
        model_id=result.model_id,
        prompt_version=result.prompt_version,
        schema_version=result.schema_version,
        latency_ms=result.latency_ms,
        request_id=result.request_id,
    )
