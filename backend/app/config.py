"""Configuration applicative.

GATE secret (section 5.3) : "Aucune clé OpenAI, service-role Supabase, clé de
stockage privée ou secret de paiement ne doit exister dans l'APK/IPA, le
dépôt Git ou les variables publiques du mobile." Toutes les valeurs
sensibles ici viennent EXCLUSIVEMENT de variables d'environnement (backend
uniquement), jamais d'une valeur par défaut en dur dans le code, et jamais
exposées via GET /config sans filtrage (voir app/api/routes/config.py).
"""

from __future__ import annotations

from enum import StrEnum
from functools import lru_cache

from pydantic import Field, SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict


class AIProviderKind(StrEnum):
    MOCK = "mock"
    OPENAI = "openai"


class StorageProviderKind(StrEnum):
    MOCK = "mock"
    S3_COMPATIBLE = "s3_compatible"
    SUPABASE = "supabase"


class AuthProviderKind(StrEnum):
    MOCK = "mock"
    SUPABASE = "supabase"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="RESERVEFLASH_", env_file=".env", extra="ignore")

    environment: str = "development"

    # Sélection de provider - section 5.3 "le provider IA est derrière une
    # interface ; remplacement possible sans modifier le domaine."
    ai_provider: AIProviderKind = AIProviderKind.MOCK
    storage_provider: StorageProviderKind = StorageProviderKind.MOCK
    auth_provider: AuthProviderKind = AuthProviderKind.MOCK

    # Secrets - toujours optionnels par défaut (None), jamais de valeur en
    # dur. Requis uniquement quand le provider correspondant est activé.
    openai_api_key: SecretStr | None = None

    # R2 (app/infrastructure/ai/openai_provider.py) : noms de modèles et
    # réglages réseau, tous surchargeables par variable d'environnement -
    # jamais de comportement figé qui obligerait un déploiement de code pour
    # changer de modèle (section 7.3 : "tout changement de
    # prompt/schéma/modèle déclenche un nouveau run benchmark").
    openai_base_url: str = "https://api.openai.com/v1"
    openai_transcription_model: str = "whisper-1"
    openai_extraction_model: str = "gpt-4o-mini"
    openai_request_timeout_seconds: float = 30.0

    supabase_service_role_key: SecretStr | None = None
    supabase_url: str | None = None
    storage_bucket: str = "reserveflash-evidence"
    jwt_secret: SecretStr | None = None

    # R0.1 (point 11) : PostgreSQL n'est PAS une dépendance runtime pour la
    # V1 - cette URL n'est utilisée QUE par `alembic upgrade head` (migration
    # manuelle, hors démarrage serveur) et par `pytest tests/db` (skip
    # explicite si indisponible). Aucun composant du chemin HTTP normal
    # (app/api/*, app/application/*) n'ouvre de connexion PostgreSQL - le
    # repository runtime est `InMemoryIncidentRepository`
    # (app/infrastructure/db/in_memory_repository.py) côté "chemin cloud
    # optionnel/futur" (voir app/api/routes/incidents.py), et n'est de toute
    # façon pas appelé par l'app mobile V1 (voir docs/adr/0002-local-first-
    # pivot.md). Voir tests/api/test_postgres_not_required.py pour la preuve
    # exécutable de cette propriété.
    database_url: str = Field(
        default="postgresql+psycopg://reserveflash:reserveflash@localhost:5432/reserveflash"
    )

    reserve_template_version: str = "fr_v1"
    prompt_version: str = "extraction_fr_v1"
    schema_version_confirmed: str = "confirmed_fact_set.v1"
    schema_version_candidate: str = "candidate_fact_set.v1"

    signed_url_ttl_seconds: int = 300

    # R0.2 (retour de recette R0.1, point "API uniquement Local-First") :
    # `/v1/incidents/*` (app/api/routes/incidents.py) reste un CRUD complet
    # hérité de R0, conservé en code pour un usage cloud futur (point 11 de
    # la demande corrective), mais ne doit PAS être exposé par défaut en V1 -
    # ni surface d'attaque inutile, ni ambiguïté sur la source de vérité
    # (le mobile V1 ne l'appelle jamais). Défaut = False : le router n'est
    # tout simplement pas monté (voir app/main.py::create_app). Positionner
    # à True est un choix explicite (dev local du chemin cloud futur, tests
    # de non-régression de ce chemin) - jamais la configuration par défaut
    # d'un déploiement V1.
    enable_legacy_cloud_incident_api: bool = False

    def require_openai_key(self) -> str:
        if self.openai_api_key is None:
            raise RuntimeError(
                "RESERVEFLASH_OPENAI_API_KEY manquant : requis quand "
                "RESERVEFLASH_AI_PROVIDER=openai (GATE secret, section 5.3)."
            )
        return self.openai_api_key.get_secret_value()


@lru_cache
def get_settings() -> Settings:
    return Settings()
