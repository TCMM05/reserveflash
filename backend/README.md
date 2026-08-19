# backend/ - ReserveFlash Incident API

FastAPI / Pydantic v2 / SQLAlchemy 2.0 / Alembic (section 5.1).

**Depuis R0.1 (pivot Local-First, voir `docs/adr/0002-local-first-pivot.md`)
: le rôle primaire de cette API est `app/api/routes/ai.py` (proxy IA sans
état - `/v1/ai/transcribe`, `/v1/ai/extract`). `app/api/routes/incidents.py`
(CRUD complet) est un chemin optionnel/futur, non appelé par l'app mobile V1
- voir sa docstring.**

## Commandes

```bash
pip install -e ".[dev]"
cp .env.example .env

python -m ruff check app tests scripts alembic/env.py
python -m pytest tests -q             # 83 tests collectés : 80 verts, 3 skip (DB, nécessitent PostgreSQL)
python scripts/generate_openapi.py    # régénère openapi.json, à committer si modifié
uvicorn app.main:app --reload
```

PostgreSQL n'est PAS requis pour démarrer le serveur ni pour utiliser
`/v1/ai/*` (preuve : `tests/api/test_postgres_not_required.py`). La commande
`alembic upgrade head` ci-dessous n'est utile QUE si vous travaillez sur le
chemin cloud optionnel/futur (`app/api/routes/incidents.py`,
`tests/db/`) :

```bash
python -m alembic upgrade head        # nécessite un PostgreSQL local (voir infra/docker/docker-compose.yml) - optionnel, voir ci-dessus
```

## Organisation (section 5.3 - règle de dépendance)

```
app/
  domain/           Entités, value objects, invariants, Reserve Composer,
                     liability_guard.py (garde-fou R0.1, point 8).
                     Aucune dépendance FastAPI/SQLAlchemy/SDK externe.
  application/
    ports.py         Interfaces (AIProvider, StorageProvider, AuthProvider,
                      IncidentRepository) - frontière stricte vers l'infra.
    use_cases/        Orchestration (confirm_facts, generate_reserve, ...).
  infrastructure/
    ai/, storage/, auth/   Adapters mock (R0) + factories par config.
    db/                     Modèles SQLAlchemy, migrations, repository
                             in-memory de référence - chemin optionnel/futur
                             depuis R0.1 (voir docs/architecture.md).
    rulepacks/              Chargeur/validateur de RulePack (section 11).
  api/
    routes/
      ai.py            RÔLE PRIMAIRE V1 (R0.1) - proxy IA sans état.
      incidents.py     Chemin optionnel/futur (R0.1) - CRUD complet hérité
                        de R0, non appelé par le mobile V1.
    deps.py           Injection de dépendances (settings, providers, auth).
    errors.py         Taxonomie d'erreurs unifiée (section 9.3).
    schemas.py        Contrats requête/réponse HTTP.
tests/
  domain/           Tests purs (invariants, composer, machine à états,
                     adapters mock, rule pack, liability_guard) - aucune
                     dépendance réseau.
  api/              Tests d'intégration HTTP (httpx TestClient), y compris
                     test_ai_routes.py et test_postgres_not_required.py (R0.1).
  db/               Tests ORM contre un vrai PostgreSQL (skip si indisponible).
alembic/            Migrations (section 5.1 - "aucune migration manuelle
                     production") - chemin optionnel/futur depuis R0.1.
```

## Providers (section 5.3)

Sélection via variables d'environnement (`.env`, voir `.env.example`) :

| Variable | Valeurs R0 | Notes |
|---|---|---|
| `RESERVEFLASH_AI_PROVIDER` | `mock` | `openai` lève `NotImplementedError` (R2). |
| `RESERVEFLASH_STORAGE_PROVIDER` | `mock` | `s3_compatible`/`supabase` non implémentés (R4). |
| `RESERVEFLASH_AUTH_PROVIDER` | `mock` | `supabase` non implémenté (R4). |

Le mode `mock` ne nécessite AUCUNE clé et fait tourner l'intégralité du
parcours F01-F13 (voir `tests/api/test_incidents_flow.py`).
