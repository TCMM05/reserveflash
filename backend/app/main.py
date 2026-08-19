"""Point d'entrée FastAPI - assemble routers, gestion d'erreurs, config.

section 9.2 : "OpenAPI commité/généré et utilisé pour tests contractuels."
Toutes les routes métier vivent sous le préfixe /v1 (section 9.1).

Depuis R0.1 (pivot Local-First, voir docs/adr/0002-local-first-pivot.md) :
`ai_routes` (app/api/routes/ai.py) est le chemin PRIMAIRE utilisé par l'app
mobile V1 (transcription/extraction sans état).

Depuis R0.2 (retour de recette R0.1) : `incidents_routes` (CRUD complet,
chemin optionnel/futur - point 11) N'EST PLUS MONTÉ PAR DÉFAUT. Le monter
inconditionnellement en V1 augmentait la surface d'attaque et l'ambiguïté
sur la source de vérité pour aucun bénéfice (le mobile V1 ne l'appelle
jamais). Contrôlé par `RESERVEFLASH_ENABLE_LEGACY_CLOUD_INCIDENT_API`
(défaut `false`, voir app/config.py) - à activer explicitement uniquement
pour développer/tester ce chemin cloud futur, jamais en déploiement V1."""

from __future__ import annotations

from fastapi import FastAPI

from app.api.errors import install_error_handlers
from app.api.routes import ai as ai_routes
from app.api.routes import config as config_routes
from app.api.routes import health as health_routes
from app.api.routes import incidents as incidents_routes
from app.config import get_settings


def create_app() -> FastAPI:
    settings = get_settings()
    app = FastAPI(
        title="ReserveFlash Incident API",
        version="0.1.0",
        description=(
            "API backend de ReserveFlash Incident (cahier des charges v1.1 "
            "Local-First - REFERENCE CONTRACTUELLE, remplace v1.0 - voir "
            "docs/SPEC_BASELINE.md pour le SHA-256 verifie et "
            "docs/adr/0002-local-first-pivot.md pour l'historique du pivot). "
            f"Environnement: {settings.environment}. "
            "Le rôle primaire de cette API est app/api/routes/ai.py (proxy "
            "IA sans état). app/api/routes/incidents.py est un chemin "
            "optionnel/futur (usage cloud), non requis pour l'app mobile V1, "
            "et non monté par défaut depuis R0.2 "
            f"(enable_legacy_cloud_incident_api={settings.enable_legacy_cloud_incident_api})."
        ),
    )

    install_error_handlers(app)

    app.include_router(health_routes.router)
    app.include_router(config_routes.router, prefix="/v1")
    app.include_router(ai_routes.router, prefix="/v1")
    if settings.enable_legacy_cloud_incident_api:
        app.include_router(incidents_routes.router, prefix="/v1")

    return app


app = create_app()
