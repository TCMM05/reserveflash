# ReserveFlash Incident

Application mobile B2B (France) pour constater et documenter les incidents de
réception de marchandise : photo, description orale/texte, faits validés par
l'utilisateur, réserve descriptive et dossier PDF. Voir
`ReserveFlash_Incident_Cahier_des_Charges_v1.0.pdf` pour la spécification
contractuelle complète, `docs/adr/0002-local-first-pivot.md` pour sa
modification officielle **R0.1 "Local-First"**, et `docs/SPEC_BASELINE.md`
pour la traçabilité exacte de la version du cahier utilisée (SHA-256 inclus)
- ce dépôt implémente désormais la baseline **R0.2** (clôture ciblée du
retour de recette R0.1), qui succède à R0.1 (Local-First) et R0 (Fondation,
section 18).

> Principe directeur (cahier des charges) : "L'IA comprend et structure.
> L'utilisateur valide la vérité. Le code déterministe compose la réserve et
> le dossier. Aucun fait non confirmé ne peut entrer dans le texte final."
>
> Principe ajouté en R0.1 : "Le téléphone est la source de vérité. L'absence
> de réseau ne doit jamais empêcher de constituer une preuve."

## État de cette baseline (R0.2 - clôture ciblée du retour de recette R0.1)

**Ne pas commencer les fonctionnalités R1 tant que le Gate R0 n'est pas
entièrement validé - voir `docs/GATE_R0.1_STATUS.md` (section "Mise à jour
R0.2") pour le détail exact, point par point du retour de recette, de ce qui
est prouvé et de ce qui reste bloqué.**

- ✅ **Pivot architectural** (R0.1) : le mobile (SQLite/Drift) est désormais
  la source de vérité d'un dossier - plus le backend. Voir
  `docs/adr/0002-local-first-pivot.md`.
- ✅ **Correctif de sécurité** (R0.1) : garde-fou déterministe
  anti-attribution de responsabilité (`liability_guard`), des deux côtés,
  avec tests adversariaux rejouant le cas signalé (`packaging_condition =
  "transporteur responsable"`).
- ✅ **API uniquement Local-First** (R0.2) : `/v1/incidents/*` (CRUD complet
  hérité de R0) n'est plus monté par défaut - la surface V1 réelle est
  exactement `/health`, `/v1/config`, `/v1/ai/transcribe`, `/v1/ai/extract`
  (voir `backend/app/config.py::enable_legacy_cloud_incident_api`,
  `backend/openapi.json`).
- ✅ **Backend** : proxy IA sans état, aucune clé OpenAI embarquée côté
  mobile, aucune dépendance PostgreSQL au runtime (prouvé par test). **87
  tests collectés, 84 verts, 3 skip** (DB, nécessitent un vrai PostgreSQL
  local). `ruff check` propre.
- ✅ **Mobile** : schéma Drift étendu (9 tables), Reserve Composer local,
  interface `IncidentRepository`/`LocalIncidentRepository`, file IA
  `pending`/retry, service de sauvegarde export/import (désormais avec
  vérification d'intégrité SHA-256 avant toute mutation locale, R0.2),
  service de partage natif du PDF. Code écrit et vérifié structurellement
  (imports, conventions de nommage, équilibrage syntaxique). Nouveau en
  R0.2 : tests d'intégration Drift réels écrits contre une vraie base
  SQLite fichier (`mobile/test/data/local_incident_repository_test.dart`),
  couvrant explicitement créer→fermer→rouvrir→retrouver.
- 🔴 **Mobile toujours non compilé/testé** dans cet environnement : SDK
  Flutter inaccessible (sandbox cloud ET pont vers l'ordinateur de
  l'utilisateur - les deux re-tentés pour R0.2, toujours bloqués).
  `flutter analyze`/`flutter test`/`flutter build apk --debug`, `android/`,
  `ios/`, `app_database.g.dart` et l'APK restent donc à produire par un
  développeur équipé - voir `mobile/README.md`. La CI
  (`.github/workflows/ci.yml`) les exécute déjà à chaque push, mais n'a pas
  encore tourné depuis ce bac à sable.
- 🟠 **Backup pas encore chiffré** : intégrité (SHA-256 par pièce, refus
  d'archive corrompue avant mutation locale) faite en R0.2, chiffrement pas
  fait - voir `docs/security.md` (SEC-09). Ne pas déclarer conforme R4.
- ✅ **CI GitHub Actions** (fichier présent, syntaxiquement validé) : lint,
  tests backend + PostgreSQL de service, migrations/OpenAPI, secret scan,
  build image Docker staging, build Android debug.

## Démarrage rapide (backend)

```bash
cd backend
pip install -e ".[dev]"
cp .env.example .env   # aucune valeur sensible dedans (GATE secret)

python -m ruff check app tests scripts alembic/env.py
python -m pytest tests -q          # 87 tests (84 verts, 3 skip sans PostgreSQL)
python scripts/generate_openapi.py

uvicorn app.main:app --reload
# -> http://localhost:8000/docs (Swagger UI généré depuis openapi.json)
```

PostgreSQL n'est PAS requis pour démarrer ou utiliser l'API en V1 (voir
`tests/api/test_postgres_not_required.py`) - `alembic upgrade head` reste
utile uniquement si vous travaillez sur le chemin cloud optionnel/futur
(`app/api/routes/incidents.py`, voir `docs/architecture.md`).

Avec Docker :

```bash
docker compose -f infra/docker/docker-compose.yml up --build
```

## Démarrage mobile

Voir `mobile/README.md` - une checklist "Premstrap" doit être exécutée une
fois par un développeur disposant du SDK Flutter avant tout travail sur
`mobile/` (génération des dossiers de plateforme, `build_runner`, puis
`flutter analyze && flutter test && flutter build apk --debug`).

## Structure du monorepo (section 5.2)

```
mobile/       Flutter - SOURCE DE VÉRITÉ V1 (Drift/SQLite local), capture,
              revue, composition de réserve, export, sauvegarde, partage
backend/      FastAPI - proxy IA sans état (/v1/ai/*, rôle primaire V1) +
              chemin CRUD incidents optionnel/futur (/v1/incidents/*)
schemas/      Contrats JSON versionnés (CandidateFactSet, ConfirmedFactSet)
prompts/      Prompts versionnés (peuplé en R2)
rulepacks/    Règles juridiques versionnées, désactivables
benchmark/    Corpus CORE/STRESS + scorer (peuplé en R6)
infra/        Docker, docker-compose, config déploiement
docs/         Architecture, ADR, runbooks, sécurité, schéma de stockage local
scripts/      Utilitaires transverses (voir aussi backend/scripts/)
```

## Documentation

- `docs/architecture.md` - frontières de couches, pivot Local-First,
  limitations connues.
- `docs/local_storage_schema.md` - schéma Drift complet, format de
  sauvegarde `reserveflash_backup.v1`.
- `docs/adr/0001-zero-invention-gate.md` - pourquoi le Reserve Composer est
  déterministe et séparé du LLM (amendé par ADR 0002 sur la question de la
  duplication mobile).
- `docs/adr/0002-local-first-pivot.md` - le pivot R0.1 : décision, raisons,
  conséquences, alternatives rejetées.
- `docs/security.md` - suivi des exigences GATE section 10.1 + minimisation
  des données envoyées à l'IA (R0.1, point 14).
- `docs/GATE_R0.1_STATUS.md` - statut détaillé, critère par critère, du Gate
  R0.1, et statut point par point de la clôture R0.2.
- `docs/SPEC_BASELINE.md` - traçabilité exacte du cahier des charges utilisé
  (SHA-256), et constat transparent sur l'absence d'un cahier v1.1 dans les
  emplacements accessibles à ce jour.
- `docs/runbooks/deploy_rollback.md` - procédure de déploiement.
- `CHANGELOG.md` - historique et limitations connues par version.
