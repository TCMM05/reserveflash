# Changelog

Format inspiré de [Keep a Changelog](https://keepachangelog.com/fr/).

## [0.1.2] - R0.2 Clôture ciblée - 2026-08-19

Réponse point par point au retour de recette officiel sur `[0.1.1]` (verdict
"R0.1 : PASS TECHNIQUE SOUS RÉSERVES / GATE R0 : FAIL / NON VALIDÉ POUR LE
MOMENT"), qui demandait une "R0.2 de clôture extrêmement ciblée" sur 11
points précis. Voir `docs/GATE_R0.1_STATUS.md`, section "Mise à jour R0.2",
pour le tableau de statut complet point par point.

### Fait et vérifié dans cette session

- **API uniquement Local-First (point 10 du retour de recette)** :
  `/v1/incidents/*` (CRUD complet hérité de R0) n'est plus monté par défaut.
  Nouveau réglage `enable_legacy_cloud_incident_api` (`backend/app/config.py`,
  défaut `False`, activable via
  `RESERVEFLASH_ENABLE_LEGACY_CLOUD_INCIDENT_API`), lu une seule fois dans
  `create_app()` (`backend/app/main.py`) pour décider si le router legacy est
  inclus. Le code CRUD est conservé (chemin cloud optionnel/futur, section
  12 de la demande corrective R0.1) mais n'est plus exposé. Preuve :
  `backend/tests/api/test_legacy_api_disabled_by_default.py` (4 tests) +
  `backend/openapi.json` régénéré avec le réglage par défaut - la surface
  V1 exposée est exactement `/health`, `/v1/config`, `/v1/ai/transcribe`,
  `/v1/ai/extract`, comme demandé.
- **Durcissement de la sauvegarde (point 11 du retour de recette, sans
  déclarer R4 atteint)** : `mobile/lib/data/backup/backup_service.dart` -
  `importBackup()` vérifie désormais le SHA-256 de chaque pièce jointe
  (`local_evidence_assets`) déclarée dans `tables.json` AVANT toute
  `db.transaction(...)` destructrice, et lève `BackupIntegrityException`
  (aucune donnée locale modifiée) si un hash ne correspond pas - réponse
  directe à "l'import actuel commence à remplacer les données locales avant
  d'avoir effectué toutes les vérifications finales". Nouveau getter
  `BackupResult.isEncrypted` renvoyant explicitement `false` : le format
  reste un ZIP non chiffré, ce que `docs/security.md` (SEC-09) déclare
  maintenant noir sur blanc plutôt que de laisser sous-entendre une
  conformité R4 complète.
- **Traçabilité de la baseline contractuelle (point 1 du retour de recette,
  partiel)** : nouveau `docs/SPEC_BASELINE.md` enregistrant `SPEC_BASELINE`,
  `SPEC_DATE`, `SPEC_SHA256`. Voir "Limitation" ci-dessous : le "cahier
  v1.1" cité dans le retour de recette n'a été trouvé dans aucun
  emplacement accessible à ce développeur ; le SHA-256 enregistré est celui,
  réel, du cahier v1.0 fourni.
- **Tests d'intégration Drift réels (point 6 du retour de recette)** :
  `mobile/test/data/local_incident_repository_test.dart` - trois scénarios
  écrits contre une VRAIE base SQLite sur fichier temporaire (pas
  `NativeDatabase.memory()`) : (1) créer un incident, fermer la connexion,
  rouvrir une instance `AppDatabase` totalement nouvelle sur le même
  fichier, retrouver l'incident exact ; (2) le même scénario étendu à un
  fait confirmé + une pièce jointe (chemin photo) + une opération IA en
  attente (`AiOperationQueue`), tous relus après réouverture ; (3) le
  garde-fou anti-attribution de responsabilité rejette la tentative
  (`packagingCondition = "transporteur responsable"`) sans rien persister,
  y compris après réouverture. **Écrit avec la rigueur d'un test réellement
  exécutable, mais NON EXÉCUTÉ** - voir Limitation ci-dessous.

### Limitation connue (inchangée depuis R0.1, retentée pour R0.2)

Les points 2, 3, 4, 5, 7, 8 du retour de recette (dossiers `android/`/
`ios/`, `app_database.g.dart`, `flutter analyze`, `flutter test`,
`flutter build apk --debug`, APK) restent **bloqués** : le SDK Flutter/Dart a
été retenté dans les deux environnements disponibles pour cette session
(sandbox cloud - réseau bloqué vers `storage.googleapis.com`,
`github.com/flutter/flutter/releases`, `dart.dev` ; pont `device_bash` vers
l'ordinateur de l'utilisateur - VM isolée sans SDK installé et sans accès
réseau par construction) et reste inaccessible. Ceci ne peut être résolu que
par un développeur équipé exécutant `mobile/README.md` (section Bootstrap),
ou par un push vers un dépôt GitHub réel pour déclencher la CI existante
(`.github/workflows/ci.yml`, job `mobile`).

## [0.1.1] - R0.1 Local-First - 2026-08-18

Livraison corrective demandée explicitement par le Product Owner avant toute
poursuite de R1 ("Merci de ne pas commencer les fonctionnalités R1 tant que
le Gate R0.1 Local-First n'est pas validé"). Voir
`docs/adr/0002-local-first-pivot.md` pour la décision d'architecture
complète et `docs/architecture.md` pour l'état à jour des couches.

### Changé (pivot architectural)

- **Le téléphone devient la source de vérité canonique d'un dossier pour la
  V1**, plus le backend. Schéma Drift étendu de 3 à 9 tables
  (`mobile/lib/data/local/app_database.dart`, schémaVersion 1 -> 2) - voir
  `docs/local_storage_schema.md`.
- **Le Reserve Composer tourne désormais sur l'appareil**
  (`mobile/lib/domain/reserve_composer.dart` + `templates/fr_v1.dart`),
  portage fidèle de `backend/app/domain/reserve_composer.py`. Ceci renverse
  une décision de l'ADR 0001 ("le mobile ne duplique pas la logique de
  composition") - voir la justification et la mitigation du risque de
  divergence dans ADR 0002.
- **Le backend devient un proxy IA sans état** : nouvelles routes
  `POST /v1/ai/transcribe` et `POST /v1/ai/extract`
  (`backend/app/api/routes/ai.py`), sans authentification requise, sans
  dépendance à un `IncidentRepository`. `backend/app/api/routes/incidents.py`
  (CRUD complet hérité de R0) est conservé mais requalifié "chemin
  optionnel/futur", non appelé par l'app mobile V1.
- **PostgreSQL n'est plus une dépendance runtime** : prouvé par un test
  dédié (`backend/tests/api/test_postgres_not_required.py`) qui démarre
  l'app et appelle `/v1/ai/transcribe` avec une URL PostgreSQL
  volontairement injoignable.
- **Architecture repository côté mobile** (point 12) :
  `mobile/lib/domain/repositories/incident_repository.dart` (interface) +
  `mobile/lib/data/local/local_incident_repository.dart` (implémentation
  Drift, seule utilisée en V1).
- **File `AiOperationQueue`** remplace la `SyncOperations` générique de R0 :
  ne porte plus que les opérations IA (transcription/extraction), jamais la
  persistance de l'incident lui-même - garantit qu'aucune opération locale
  (créer un incident, confirmer des faits, composer une réserve) ne peut
  être bloquée par l'absence de réseau (point 6).
- **Aucune authentification requise pour créer un incident** (point 13) :
  `organization_id` nullable sur `LocalIncidents` ; le routeur mobile ne
  définit aucun `redirect` de garde vers `AuthScreen`.

### Corrigé (sécurité)

- **Bug d'attribution de responsabilité (point 8)** : un champ confirmé
  texte libre (ex: `packaging_condition`) pouvait contenir une attribution
  de responsabilité, une promesse d'indemnisation, une conclusion/
  qualification juridique ou un montant inventé, et ressortir tel quel dans
  la réserve finale - exemple cité explicitement : `packaging_condition =
  "transporteur responsable"`. Corrigé par un garde-fou déterministe
  (`backend/app/domain/liability_guard.py`,
  `mobile/lib/domain/liability_guard.dart`), appliqué DEUX fois : à la
  confirmation (retour immédiat) et juste avant la composition de réserve
  (défense en profondeur). Nouvelle exception
  `LiabilityAttributionError`/`LiabilityAttributionException`. Tests
  adversariaux dédiés des deux côtés
  (`backend/tests/domain/test_liability_guard.py`,
  `mobile/test/domain/liability_guard_test.dart`), rejouant explicitement le
  cas signalé.

### Ajouté

- **Sauvegarde utilisateur (point 9)** : `mobile/lib/data/backup/backup_service.dart`
  - export/import au format versionné `reserveflash_backup.v1` (documenté
    dans `docs/local_storage_schema.md`), bundle DB structurée (JSON) +
    fichiers de preuves, réécriture des chemins locaux à l'import (portable
    entre appareils), transparence sur les pièces manquantes.
- **Partage natif du PDF (point 10)** :
  `mobile/lib/data/share/reserve_share_service.dart` (feuille de partage OS
  via `share_plus`, aucune dépendance au serveur ReserveFlash).
- **Documentation de minimisation des données IA (point 14)** :
  `docs/security.md`, nouvelle section détaillant exactement ce qui est/n'est
  jamais envoyé aux routes `/v1/ai/*`.
- `docs/adr/0002-local-first-pivot.md`, `docs/local_storage_schema.md`.
- CI (`.github/workflows/ci.yml`, job `mobile`) : nouvelle étape
  `flutter build apk --debug` (Gate R0.1, point 1) + upload de l'APK en
  artefact CI.
- Backend : 8 nouveaux tests (`test_liability_guard.py`,
  `test_ai_routes.py`, `test_postgres_not_required.py`) - total 83 tests
  collectés, 80 passent, 3 skip (tests DB nécessitant un vrai PostgreSQL,
  comportement inchangé depuis R0). `python -m ruff check` sans erreur.
- Mobile : 2 nouveaux fichiers de tests adversariaux/domaine
  (`liability_guard_test.dart`, `reserve_composer_test.dart`), non exécutés
  faute de SDK Flutter disponible dans l'environnement de cette livraison
  (voir "Limitations connues" ci-dessous et `mobile/README.md`).

### Limitations connues (honnêteté de livraison - voir aussi
    `docs/architecture.md` section 7)

1. **Mobile Flutter non compilé/testé** dans l'environnement ayant produit
   cette livraison : le SDK Flutter est inaccessible à la fois dans le bac à
   sable cloud (réseau bloqué) et dans la VM isolée du pont vers
   l'ordinateur de l'utilisateur (`device_bash`, tentée pour cette
   livraison - également sans SDK Flutter installé). Vérification faite à la
   place : équilibrage syntaxique (accolades/parenthèses) sur tous les
   fichiers Dart modifiés/créés, résolution de tous les imports relatifs,
   cohérence des conventions de nommage Drift (row/companion classes)
   documentées dans le code. `flutter analyze`/`flutter test`/`flutter build
   apk --debug` restent donc À EXÉCUTER par un développeur équipé, ou au
   premier push vers un dépôt GitHub réel (la CI les exécute déjà - voir
   ci-dessus).
2. Duplication Backend/Mobile du Reserve Composer vérifiée par lecture
   humaine des deux suites de tests uniquement, pas encore par un corpus de
   vecteurs de test partagé (ROADMAP, voir ADR 0002).
3. `generate_export`/écran S13 : document placeholder, pas encore un PDF mis
   en page - inchangé depuis R0, prévu R3.
4. Pipeline IA réel (OpenAI) non implémenté - inchangé depuis R0, prévu R2.
5. Écrans d'export/import de sauvegarde non câblés dans l'UI (le service
   `BackupService` existe et est prêt, mais aucun écran S01-S20 ne l'appelle
   encore).
6. `LocalIncidentRepository` sans test d'intégration exécuté (nécessite le
   SDK Flutter - voir limitation 1).

### Décision Gate R0.1

Voir la section "Gate R0.1" de la conversation ayant produit cette livraison
(11 critères) - statut détaillé dans `docs/GATE_R0.1_STATUS.md` (livré avec
cette version). Les critères démontrables dans cet environnement (2, 3, 6-9,
11) sont satisfaits et prouvés par des tests automatisés exécutés. Les
critères 1, 4, 10 nécessitent le SDK Flutter (voir limitation 1 ci-dessus) et
ne sont donc PAS validés dans cette livraison - à valider par un développeur
équipé avant de considérer le Gate R0.1 entièrement franchi.

## [0.1.0] - R0 Fondation - 2026-08-18

### Ajouté

- Monorepo (`mobile/`, `backend/`, `schemas/`, `rulepacks/`, `infra/`,
  `docs/`, `scripts/`) conforme à la structure section 5.2 du cahier des
  charges.
- **Backend** : domaine (entités, value objects, machine à états
  `IncidentStatus`, `ConfirmedFactData` avec invariants section 6.3, Reserve
  Composer déterministe `app/domain/reserve_composer.py`), API FastAPI `/v1`
  couvrant la table d'endpoints section 9.1, adapters IA/storage/auth mockés
  derrière des interfaces (`app/application/ports.py`), taxonomie d'erreurs
  unifiée (section 9.3), modèles SQLAlchemy + migration Alembic initiale
  validée contre PostgreSQL 16.
- **Schemas** : `confirmed_fact_set.v1.schema.json`,
  `candidate_fact_set.v1.schema.json` (section 6.2).
- **Rule pack** d'exemple `FR_ROAD_DOMESTIC_GENERAL_2026_01`, statut
  `DISABLED_PENDING_LEGAL_REVIEW` (section 11.2).
- **Mobile** : design system (couleurs/typographie/spacing, section 4),
  navigation go_router pour les 20 écrans (section 3.2), domaine Dart miroir
  du backend, schéma Drift offline (section 8.1).
- **CI** : `.github/workflows/ci.yml` (lint, tests + PostgreSQL de service,
  vérification migrations/OpenAPI, secret scan gitleaks, build image Docker
  staging).
- **Docs** : `docs/architecture.md`, `docs/adr/0001-zero-invention-gate.md`,
  `docs/security.md`, `docs/runbooks/deploy_rollback.md`.

### Limitations connues

Voir `docs/architecture.md` section 4 pour le détail complet. En résumé :

1. Persistence runtime backend en mémoire (PostgreSQL testé mais non encore
   branché) - prévu R4.
2. Export PDF = placeholder texte, pas encore de mise en page - prévu R3.
3. Pipeline IA réel (OpenAI) non implémenté - prévu R2.
4. Mobile Flutter non compilé/testé dans l'environnement de cette baseline
   (SDK Flutter inaccessible) - voir `mobile/README.md`.

### Décision Gate

Non applicable à ce stade (baseline de développement interne, pas une
livraison candidate à la recette section 16). La checklist section 19 sera
appliquée à la fin de R6 - Qualification.
