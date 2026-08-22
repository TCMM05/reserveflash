"""Taxonomie d'erreurs unifiée (section 9.3) - "Enveloppe erreur stable :
code, message utilisateur safe, trace_id, détails non sensibles" (section
9.2). Ce module est le SEUL endroit qui traduit une exception domaine/
application en réponse HTTP ; les routes ne construisent jamais elles-mêmes
un corps d'erreur brut.
"""

from __future__ import annotations

import uuid

from fastapi import FastAPI, HTTPException, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from pydantic import ValidationError

from app.application.use_cases.generate_export import NoReserveTextError
from app.application.use_cases.generate_reserve import NoConfirmedFactsError
from app.domain.errors import (
    AIBudgetExceededError,
    AIInvalidOutputError,
    AIRateLimitedError,
    AIUnavailableError,
    ConflictingRevisionError,
    CrossTenantAccessError,
    DomainError,
    InvalidStateTransitionError,
    LiabilityAttributionError,
    TemplateNotFoundError,
    UnconfirmedFactSetError,
    UnresolvedUnknownFieldError,
)
from app.infrastructure.auth.mock_provider import InvalidTokenError

_DOMAIN_ERROR_STATUS: dict[type[DomainError], int] = {
    UnconfirmedFactSetError: status.HTTP_400_BAD_REQUEST,
    UnresolvedUnknownFieldError: status.HTTP_400_BAD_REQUEST,
    InvalidStateTransitionError: status.HTTP_409_CONFLICT,
    TemplateNotFoundError: status.HTTP_500_INTERNAL_SERVER_ERROR,
    CrossTenantAccessError: status.HTTP_403_FORBIDDEN,
    ConflictingRevisionError: status.HTTP_409_CONFLICT,
    AIUnavailableError: status.HTTP_503_SERVICE_UNAVAILABLE,
    AIInvalidOutputError: status.HTTP_422_UNPROCESSABLE_ENTITY,
    AIRateLimitedError: status.HTTP_429_TOO_MANY_REQUESTS,
    # R0.1 (point 8) : contenu interdit dans un champ confirmé (attribution
    # de responsabilité, indemnisation, conclusion/qualification juridique,
    # montant inventé) -> 400, l'utilisateur doit reformuler le champ.
    LiabilityAttributionError: status.HTTP_400_BAD_REQUEST,
    # Point 12 (gouvernance coût/tokens IA) : 402 Payment Required - ni 429
    # (ce n'est pas un rate-limit provider) ni 503 (l'IA est disponible,
    # c'est une politique de dépense interne qui bloque l'appel). Note
    # honnête : le comportement du client mobile face à un 402 sur
    # /v1/ai/* n'a pas encore été vérifié en conditions réelles (aucun
    # budget configuré à ce jour) - à valider si un budget est un jour
    # activé en déploiement (voir docs/GATE_R2_STATUS.md).
    AIBudgetExceededError: status.HTTP_402_PAYMENT_REQUIRED,
}


def _envelope(request: Request, code: str, message: str, details: dict | None = None) -> dict:
    trace_id = getattr(request.state, "trace_id", None) or str(uuid.uuid4())
    return {"code": code, "message": message, "trace_id": trace_id, "details": details}


def install_error_handlers(app: FastAPI) -> None:
    @app.middleware("http")
    async def _assign_trace_id(request: Request, call_next):
        request.state.trace_id = str(uuid.uuid4())
        response = await call_next(request)
        response.headers["X-Trace-Id"] = request.state.trace_id
        return response

    @app.exception_handler(DomainError)
    async def _domain_error_handler(request: Request, exc: DomainError) -> JSONResponse:
        status_code = _DOMAIN_ERROR_STATUS.get(type(exc), status.HTTP_400_BAD_REQUEST)
        details: dict | None = None
        if isinstance(exc, LiabilityAttributionError):
            # Détails non sensibles (section 9.2) : permettent à l'UI mobile
            # de surligner précisément le champ à reformuler, sans exposer le
            # texte original refusé (qui reste uniquement dans `message`,
            # jamais loggé côté serveur en clair au-delà des logs applicatifs
            # standards).
            details = {"violation_code": exc.violation_code, "field_name": exc.field_name}
        return JSONResponse(
            status_code=status_code,
            content=_envelope(request, exc.code, exc.message, details=details),
        )

    @app.exception_handler(ValidationError)
    async def _pydantic_validation_handler(request: Request, exc: ValidationError) -> JSONResponse:
        # Erreurs de construction d'un ConfirmedFactData/CandidateFactData
        # (payload non conforme au schéma versionné) -> 400 VALIDATION_ERROR.
        return JSONResponse(
            status_code=status.HTTP_400_BAD_REQUEST,
            content=_envelope(
                request,
                "VALIDATION_ERROR",
                "Le corps de la requête ne respecte pas le schéma attendu.",
                details={"errors": exc.errors(include_url=False, include_context=False)},
            ),
        )

    @app.exception_handler(RequestValidationError)
    async def _fastapi_validation_handler(
        request: Request, exc: RequestValidationError
    ) -> JSONResponse:
        return JSONResponse(
            status_code=status.HTTP_400_BAD_REQUEST,
            content=_envelope(
                request,
                "VALIDATION_ERROR",
                "Requête invalide.",
                details={"errors": exc.errors()},
            ),
        )

    @app.exception_handler(InvalidTokenError)
    async def _invalid_token_handler(request: Request, exc: InvalidTokenError) -> JSONResponse:
        return JSONResponse(
            status_code=status.HTTP_401_UNAUTHORIZED,
            content=_envelope(request, "AUTH_REQUIRED", "Authentification requise."),
        )

    @app.exception_handler(HTTPException)
    async def _http_exception_handler(request: Request, exc: HTTPException) -> JSONResponse:
        # Les HTTPException levées explicitement (app/api/deps.py) portent déjà
        # {"code", "message"} dans `detail` ; on les passe dans la même
        # enveloppe stable que les autres erreurs plutôt que le format
        # {"detail": ...} par défaut de Starlette.
        if isinstance(exc.detail, dict) and "code" in exc.detail:
            code, message = exc.detail["code"], exc.detail.get("message", "Erreur.")
        else:
            code, message = "HTTP_ERROR", str(exc.detail)
        return JSONResponse(
            status_code=exc.status_code,
            content=_envelope(request, code, message),
            headers=exc.headers,
        )

    @app.exception_handler(KeyError)
    async def _not_found_handler(request: Request, exc: KeyError) -> JSONResponse:
        return JSONResponse(
            status_code=status.HTTP_404_NOT_FOUND,
            content=_envelope(request, "NOT_FOUND", "Ressource introuvable."),
        )

    @app.exception_handler(NoConfirmedFactsError)
    @app.exception_handler(NoReserveTextError)
    async def _precondition_handler(request: Request, exc: Exception) -> JSONResponse:
        return JSONResponse(
            status_code=status.HTTP_409_CONFLICT,
            content=_envelope(request, "CONFLICT", str(exc)),
        )

    @app.exception_handler(Exception)
    async def _fallback_handler(request: Request, exc: Exception) -> JSONResponse:
        # Ne jamais renvoyer de détail non sécurisé (section 9.3
        # INTERNAL_ERROR -> "Message générique + trace_id").
        return JSONResponse(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            content=_envelope(request, "INTERNAL_ERROR", "Une erreur inattendue est survenue."),
        )
