"""GET /config - "Remote config public/authentifié selon clé" (section 9.1).

R0 n'expose que des valeurs non sensibles (versions de template/schéma,
environnement). GATE secret : aucune clé API, aucun secret de storage/
paiement ne doit jamais transiter par cet endpoint, même authentifié."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends

from app.api.schemas import ConfigResponse
from app.config import Settings, get_settings

router = APIRouter(tags=["config"])


@router.get("/config", response_model=ConfigResponse)
def get_config(settings: Annotated[Settings, Depends(get_settings)]) -> ConfigResponse:
    return ConfigResponse(
        environment=settings.environment,
        reserve_template_version=settings.reserve_template_version,
        prompt_version=settings.prompt_version,
        schema_version_confirmed=settings.schema_version_confirmed,
        schema_version_candidate=settings.schema_version_candidate,
    )
