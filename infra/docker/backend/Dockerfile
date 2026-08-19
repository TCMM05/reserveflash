# Image backend ReserveFlash Incident (section 17.1 - "Backend: Dockerfile,
# dépendances lockées, migrations Alembic, seed minimal.").
#
# Contexte de build attendu : racine du monorepo (reserveflash/), pour que
# COPY backend/ fonctionne. Exemple :
#   docker build -f infra/docker/backend/Dockerfile -t reserveflash-backend .
#
# GATE secret (section 5.3) : aucune clé n'est ni ARG ni ENV en dur dans ce
# fichier ; toute valeur sensible est injectée au runtime (docker-compose,
# orchestrateur) via variables d'environnement RESERVEFLASH_*.

FROM python:3.12-slim AS base

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# Dépendances système minimales pour psycopg (binaire) et compilation native
# éventuelle des roues Python.
RUN apt-get update \
    && apt-get install -y --no-install-recommends libpq5 \
    && rm -rf /var/lib/apt/lists/*

COPY backend/pyproject.toml ./pyproject.toml
COPY backend/app ./app
COPY backend/alembic ./alembic
COPY backend/alembic.ini ./alembic.ini
COPY backend/scripts ./scripts
COPY rulepacks /rulepacks

# section 5.1 - "aucune migration manuelle production" : les dépendances
# sont installées depuis pyproject.toml (source unique de vérité), figées
# via le lockfile généré par le CI (voir .github/workflows/ci.yml) pour les
# builds reproductibles.
RUN pip install --no-cache-dir .

# Utilisateur non-root (SEC - défense en profondeur, non listé explicitement
# au cahier des charges mais cohérent avec section 10.1).
RUN useradd --create-home --uid 1000 reserveflash
USER reserveflash

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=3s CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" || exit 1

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
