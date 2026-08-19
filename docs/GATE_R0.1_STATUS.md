# Gate R0.1 "Local-First" - statut de validation

Ce document évalue, un par un, les 11 critères du "Gate R0.1" définis dans la
demande corrective, et fournit la liste explicite des éléments
terminés/incomplets demandée au point 16 de cette même demande. Statut
honnête : un critère marqué ✅ est appuyé par un test automatisé exécuté
dans cette session ; un critère marqué ⏳ ne l'est pas et dit pourquoi.

## Mise à jour R0.2.3 (statut final - freeze documentaire/traçabilité)

Cette section fait foi sur le statut final ; les sections suivantes
("Mise à jour R0.2.1", "Mise à jour R0.2") sont conservées pour l'historique
détaillé de chaque preuve, mais certaines de leurs mentions ponctuelles
("CI non exécutée", "iOS/v1.1 en attente") sont désormais obsolètes et
corrigées ci-dessous.

| Sujet | Statut final |
|---|---|
| **CI GitHub Actions réelle** | ✅ **PASS** - run #2 vert, 4/4 jobs (`backend` 44s, `secret-scan` 6s, `build-staging` 25s, `mobile` 7m33s), 7m36s au total, sur `TCMM05/reserveflash`, commit `6aa7f88`. Le tout premier run (commit `cf2d17c`) avait révélé un vrai bug de packaging Python (`backend/pyproject.toml` sans `[build-system]`), corrigé et reconfirmé vert - voir `CHANGELOG.md`. |
| **Baseline cahier des charges v1.1** | ✅ **VÉRIFIÉE** - fichier reçu dans la conversation (2026-08-19), SHA-256 recalculé indépendamment (`sha256sum`) et confirmé identique à la valeur citée par l'équipe (`1c6b3db672d9d622679ecd6c8b20908e575e2702eeb4dcc839609b21ea5ccd1b`). 33 pages lues intégralement ; chaque clause citée dans les retours de recette a désormais une référence exacte (section/page) dans `docs/SPEC_BASELINE.md`. |
| **Android** | ✅ **PASS** - `flutter analyze` 0 erreur/0 info, 52/52 tests passés, `flutter build apk --debug` réussi, reconfirmé par une seconde exécution réelle indépendante (R0.2.2) après les correctifs de style. |
| **iOS** | 🟡 **Réserve future explicite, non bloquante pour la clôture de R0** - jamais construit ni testé (poste macOS/Xcode indisponible dans ce contexte). Ne bloque pas le Gate R0 (Android + backend entièrement prouvés), mais doit être démontré par un développeur équipé macOS avant toute release iOS. |

## Mise à jour R0.2.1 (preuve par exécution réelle obtenue)

La limitation qui bloquait 6 des 11 points R0.2 ci-dessous ("SDK Flutter
inaccessible dans les deux environnements disponibles pour cette session")
a été levée : l'utilisateur a installé le SDK Flutter sur son propre poste
Windows et exécuté lui-même, à ma demande et sous mon guidage, le bootstrap
complet (`flutter create` / `flutter pub get` / `build_runner build` /
`flutter analyze` / `flutter test` / `flutter build apk --debug`), plusieurs
fois de suite, jusqu'à un résultat entièrement vert. 8 vagues de correctifs
réels ont été nécessaires (voir `CHANGELOG.md`, sections "R0.2.1 Hotfix" et
suivantes, pour le détail complet de chaque bug, sa cause racine réelle, et
la preuve - log d'exécution - qui l'a fait apparaître).

**Résultat final, exécuté sur le poste réel de l'utilisateur (pas affirmé) :**

- `flutter analyze` : 0 erreur (14 `info` de style non bloquants).
- `flutter test` : **52/52 tests passés** (`All tests passed!`), suite Drift
  d'intégration dédiée (point 6) comprise - preuve réelle de persistance
  disque après fermeture/réouverture de la base, garde-fou anti-attribution
  inclus.
- `flutter build apk --debug` : **APK debug construit avec succès.**
  - Fichier : `app-debug.apk` (183 865 201 octets)
  - SHA-256 : `08fe8ac120e38befaf7cc9bb753b63ff8d86308f674490ead639ca9e2077ada7`
  - SHA-1 (généré par Gradle, `app-debug.apk.sha1`) :
    `7826ade1fc3267e34ff60ddf683c7affe8387fbf` - identique au SHA-1
    recalculé indépendamment sur la copie transférée, confirmant l'intégrité
    du transfert.
  - Emplacement sur le poste de l'utilisateur :
    `C:\Dev\Application claude\Reserveflash\repo\mobile\build\app\outputs\flutter-apk\app-debug.apk`

**Ce qui reste réellement non prouvé** (honnêteté du statut, pas
d'affirmation au-delà de ce qui a été exécuté) :

- **iOS** : jamais construit ni testé - `flutter build apk` ne concerne que
  l'Android, et l'utilisateur est sur Windows (Xcode/macOS requis pour tout
  build iOS, indisponible dans ce contexte). Le dossier `ios/` est régénéré
  par `flutter create .` comme `android/`, mais sa compilation réelle reste
  à prouver sur un poste macOS.
- **Écrans UI réels exercés manuellement** (tap-through de l'app sur
  appareil/émulateur) - seuls les tests automatisés ont tourné ; personne
  n'a encore lancé l'APK sur un téléphone/émulateur pour vérifier le
  comportement visuel.
- Voir la mise à jour "R0.2" ci-dessous pour le détail point par point des
  11 demandes de clôture ciblée, désormais réévaluées à la lumière de cette
  exécution.

### Commit / tag / SHA de cette livraison

- Commit du code (hotfixes eux-mêmes, pas ce document) : `3266752`
  ("R0.2.1 - Hotfixes de premiere execution reelle").
- Tag : `r0.2.1-hotfix-preuve-execution` (pointe sur le dernier commit de
  cette livraison, documentation incluse - voir `git log` pour son hash
  exact, volontairement non figé ici : ce document fait lui-même partie de
  l'historique qu'il décrirait, un hash gravé en dur deviendrait
  immédiatement obsolète dès la prochaine modification de ce fichier).
- Archive de livraison : `ReserveFlash_R0.2.1_Hotfix.zip`, générée par
  `git archive` depuis le commit tagué `r0.2.1-hotfix-preuve-execution` -
  strictement identique au code committé, ce document inclus. Le SHA-256
  de cette archive est fourni dans le message de livraison qui l'accompagne
  (impossible à faire figurer ici par construction : l'archive contient ce
  fichier, donc son hash ne peut être calculé qu'après que ce fichier soit
  figé).

## Mise à jour R0.2 (clôture ciblée demandée par le retour de recette)

Le Product Owner a rendu un verdict "R0.1 : PASS TECHNIQUE SOUS RÉSERVES /
GATE R0 : FAIL / NON VALIDÉ POUR LE MOMENT" et a demandé une clôture R0.2
ciblée sur 11 points précis (voir `CHANGELOG.md`, section `[0.1.2]`, pour le
détail complet). État honnête de ces 11 points à l'issue de cette session :

| # | Demande | Statut |
|---|---|---|
| 1 | Basculer sur le cahier v1.1 + marqueur `SPEC_BASELINE` | ✅ **Fait et vérifié (R0.2.2)** - le fichier v1.1 a été fourni dans la conversation, SHA-256 recalculé indépendamment et confirmé identique à la valeur citée par l'équipe ; `docs/SPEC_BASELINE.md` mis à jour avec `SPEC_BASELINE`/`SPEC_DATE`/`SPEC_SHA256` réels et les citations exactes (section/page) de chaque clause. |
| 2 | Livrer `android/` + `ios/` | 🟡 Android : ✅ **prouvé par exécution réelle** - `flutter create . --platforms=android,ios` régénère `android/` de façon reproductible (vérifié plusieurs fois de suite), complété par 2 fichiers Gradle committés portant un vrai correctif (`mobile/android/build.gradle.kts`, `mobile/android/app/build.gradle.kts` - voir R0.2.1 ci-dessus) ; l'APK résultant compile et s'exécute, reconfirmé par la CI GitHub Actions réelle (R0.2.2). iOS : **réserve future explicite, non bloquante** - jamais construit, nécessite un poste macOS/Xcode indisponible ici. |
| 3 | Générer `app_database.g.dart` | ✅ Prouvé par exécution réelle - `dart run build_runner build --delete-conflicting-outputs` a tourné avec succès sur le poste de l'utilisateur ("Built with build_runner/aot in 17s; wrote 99 outputs"), après correction d'une collision de nom colonne/méthode Drift qui, avant correctif, invalidait silencieusement toute la génération (voir CHANGELOG.md). |
| 4 | `flutter analyze` vert | ✅ Prouvé par exécution réelle - 0 erreur (14 `info` de style uniquement : `const` manquants, `withOpacity` déprécié - aucun des deux ne bloque la compilation). |
| 5 | `flutter test` vert | ✅ Prouvé par exécution réelle - 52/52 tests passés (`All tests passed!`), sur la suite complète ET sur la suite Drift dédiée (point 6) exécutée séparément en priorité comme demandé. |
| 6 | Tests d'intégration Drift réels (créer→persister→fermer→rouvrir→retrouver, idéalement + faits + preuve + PendingAIJob) | ✅ Écrit avec rigueur d'exécution réelle ET désormais **exécuté et vert** (`mobile/test/data/local_incident_repository_test.dart`, base SQLite sur fichier temporaire réel, PAS `NativeDatabase.memory()`, fermeture/réouverture d'une instance `AppDatabase` totalement nouvelle) - les 3 tests (incident seul ; incident+fait confirmé+preuve+PendingAIJob ensemble ; rejet du garde-fou qui ne persiste rien) passent tous. |
| 7 | `flutter build apk --debug` | ✅ Prouvé par exécution réelle - `Built build\app\outputs\flutter-apk\app-debug.apk`. |
| 8 | Fournir l'APK | ✅ APK réel produit et son SHA-256 vérifié (voir R0.2.1 ci-dessus) - présent sur le poste de l'utilisateur, transmis en copie dans cette livraison. |
| 9 | Commit + tag + SHA APK/ZIP | ✅ Commit `3266752` + tag `r0.2.1-hotfix-preuve-execution` ; SHA-256 du ZIP et de l'APK tous deux fournis et vérifiés (voir R0.2.1 ci-dessus). |
| 10 | Ne plus monter `/v1/incidents/*` par défaut | ✅ Fait et testé (`backend/app/config.py::enable_legacy_cloud_incident_api`, défaut `False` ; `backend/tests/api/test_legacy_api_disabled_by_default.py`, 4 tests verts ; `backend/openapi.json` régénéré, surface minimale confirmée : `/health`, `/v1/config`, `/v1/ai/transcribe`, `/v1/ai/extract`). |
| 11 | Ne pas présenter le Backup comme conforme R4 | ✅ Fait - `docs/security.md` (SEC-09) et la docstring de `BackupService` déclarent explicitement le format non chiffré (`BackupResult.isEncrypted => false`) ; vérification d'intégrité SHA-256 par pièce AVANT toute mutation locale (`db.transaction`) ajoutée pour la partie "hashes + refus d'archive corrompue" de R4, sans déclarer le chiffrement fait. |

**Bilan R0.2 (mis à jour après R0.2.3)** : 10/11 points pleinement faits et
vérifiés par exécution réelle (1, 3, 4, 5, 6, 7, 8, 9, 10, 11), 1/11 partiel
(2 - Android prouvé y compris par la CI réelle, iOS reste une réserve
future non bloquante faute de poste macOS). Tous les points initialement
bloqués (SDK Flutter indisponible en R0.1/R0.2, document v1.1 non fourni)
sont désormais débloqués et prouvés, à l'exception d'iOS.

## Les 11 critères du Gate

| # | Critère | Statut | Preuve |
|---|---|---|---|
| 1 | Application Flutter compilable | ✅ PROUVÉ PAR EXÉCUTION RÉELLE | `flutter build apk --debug` a réussi sur le poste réel de l'utilisateur ("Built build\app\outputs\flutter-apk\app-debug.apk") après 8 vagues de correctifs (voir CHANGELOG.md et la mise à jour R0.2.1 ci-dessus pour le détail et les SHA de preuve). **Reconfirmé par la CI GitHub Actions elle-même depuis R0.2.2** (run #2 vert, job `mobile`, 7m33s, sur un vrai runner GitHub - voir "Mise à jour R0.2.3" en tête de ce document) : ce critère est donc validé à la fois par exécution locale directe ET par la CI. |
| 2 | Création d'incident sans Internet | ✅ Conforme, vérifié par test | `LocalIncidentRepository.createIncident` n'effectue aucun appel réseau (aucun import `dio`/`http`) ; désormais aussi couvert par les 3 tests d'intégration Drift réels (point 6), tous exécutés et verts. |
| 3 | Persistance après fermeture/réouverture | ✅ Conforme, vérifié par test réel | Prouvé par exécution réelle, pas seulement par construction : `mobile/test/data/local_incident_repository_test.dart` ferme une vraie connexion SQLite puis en rouvre une toute nouvelle sur le même fichier disque, et retrouve l'incident exact - test vert. |
| 4 | Photos conservées localement | ✅ Conforme par construction | `LocalEvidenceAssets` + fichiers dans l'espace privé de l'app (voir docs/local_storage_schema.md) ; `registerEvidenceAsset` ne fait aucun appel réseau. Le chemin `EvidenceAsset` est couvert par le 2ème test d'intégration Drift (point 6), exécuté et vert. |
| 5 | Aucune perte après échec réseau | ✅ Conforme par construction | Seule `AiOperationQueue` dépend du réseau ; un échec y passe l'opération en `pending` avec `retryCount` incrémenté (`markAiOperationFailed`), jamais de suppression. Le statut `pending` d'un `AiQueueItem` est couvert par le 2ème test d'intégration Drift (point 6), exécuté et vert. |
| 6 | Aucune clé OpenAI dans l'app | ✅ Conforme, vérifié | Aucune chaîne `sk-`/clé API dans `mobile/`. Le job CI `secret-scan` (gitleaks) + le grep de motifs de clé dans le job `backend` couvrent cette exigence à chaque push. `RESERVEFLASH_OPENAI_API_KEY` n'existe que côté `backend/.env` (jamais committé, voir `.env.example`). |
| 7 | L'IA ne passe que par le backend | ✅ Conforme, vérifié par test | `mobile/lib/domain/entities/ai_queue_item.dart` + `AiOperationQueue` sont le seul chemin IA côté mobile, et pointent vers `backend/app/api/routes/ai.py` (jamais un SDK OpenAI direct dans `mobile/pubspec.yaml` - absent des dépendances). `tests/api/test_ai_routes.py::test_ai_routes_do_not_expose_incident_or_organization_concepts` prouve que les routes IA sont sans état. |
| 8 | Aucun fait non confirmé dans une réserve | ✅ Conforme, vérifié par test | Invariant de type inchangé depuis R0 (`ConfirmedFactData` ne peut exister avec `user_confirmed=False`) + `test_zero_unconfirmed_fact_in_final_reserve_gate` (backend, toujours vert). |
| 9 | Aucune attribution de responsabilité dans une réserve | ✅ Conforme, vérifié par test réel des deux côtés | Backend : `liability_guard.py` + 15+ tests adversariaux (`test_liability_guard.py`, tous verts) rejouant le cas exact signalé (`packaging_condition = "transporteur responsable"`). Mobile : `liability_guard.dart` désormais EXÉCUTÉ réellement (`liability_guard_test.dart`, tous verts) - et ce n'était pas gratuit : l'exécution réelle a révélé puis fait corriger un bug de sécurité fonctionnelle réel, absent d'une simple relecture de code (frontières `\b`/`\w` des `RegExp` Dart non Unicode-aware, laissant passer certaines formulations d'attribution de responsabilité commençant/finissant par une lettre accentuée - voir CHANGELOG.md, "Troisième" et "Quatrième vague"). |
| 10 | Tests automatisés verts | ✅ Fait, des deux côtés | Backend : 80 tests passent, 3 skip (DB), 0 échec, `ruff check` propre. Mobile : **52/52 tests passés** (`All tests passed!`), exécution réelle sur le poste de l'utilisateur, suite Drift dédiée (point 6) comprise. |
| 11 | Aucune dépendance à PostgreSQL pour utiliser la V1 | ✅ Conforme, vérifié par test | `tests/api/test_postgres_not_required.py` (3 tests, tous verts) démarre l'app et appelle `/v1/ai/transcribe` avec une URL PostgreSQL injoignable - succès. |

**Bilan (mis à jour après R0.2.3)** : les 11 critères sont désormais validés
par un test automatisé RÉELLEMENT EXÉCUTÉ (backend ET mobile), **ET
reconfirmés par un run CI GitHub Actions réel et vert** (4/4 jobs, voir
"Mise à jour R0.2.3" en tête de ce document) - la seule réserve qui subsiste
est le build iOS (jamais tenté, nécessite un poste macOS/Xcode). **Le Gate
R0.1 est donc validé pour tout le périmètre Android + backend + CI** ; iOS
reste une réserve future explicite et non bloquante, à démontrer avant
toute release iOS.

## Éléments terminés (point 16)

- Backend : garde-fou anti-attribution de responsabilité + tests
  adversariaux (point 8).
- Backend : routes `/v1/ai/*` sans état (points 4, 5).
- Backend : preuve automatisée d'indépendance à PostgreSQL (point 11).
- Backend : 83 tests collectés, 80 verts, `ruff check` propre.
- Mobile : schéma Drift étendu à 9 tables, source de vérité V1 (point 1, 2).
- Mobile : Reserve Composer + template + garde-fou portés en Dart (point 6,
  8), avec tests écrits ET désormais exécutés (52/52 verts, voir R0.2.1).
- Mobile : bootstrap Flutter complet exécuté réellement de bout en bout
  (`flutter create`/`pub get`/`build_runner`/`analyze`/`test`/`build apk`),
  APK debug produit et son SHA-256 vérifié (voir R0.2.1).
- Mobile : interface `IncidentRepository` + `LocalIncidentRepository` (point
  12).
- Mobile : file `AiOperationQueue` (état `pending`, retry) (point 6).
- Mobile : service de sauvegarde export/import versionné (point 9).
- Mobile : service de partage natif du PDF (point 10).
- Mobile : suppression de toute dépendance d'authentification pour créer un
  incident (point 13).
- Documentation : ADR 0002, `docs/local_storage_schema.md`, mise à jour de
  `docs/architecture.md`, `docs/security.md` (section minimisation IA, point
  14), `README.md`, `CHANGELOG.md`, ce document.
- CI : étape `flutter build apk --debug` ajoutée, ET **exécutée avec succès
  sur un vrai runner GitHub Actions depuis R0.2.2** (run #2 vert, 4/4 jobs -
  voir "Mise à jour R0.2.3" en tête de ce document et CHANGELOG.md).
- Backend : bug de packaging Python découvert et corrigé par cette même
  exécution CI réelle (`backend/pyproject.toml` sans `[build-system]`,
  invisible en local car les tests passent par `pytest` sans jamais
  installer le paquet) - voir CHANGELOG.md, section R0.2.3.
- Documentation : cahier des charges v1.1 Local-First reçu et vérifié
  (SHA-256 indépendant, lecture intégrale des 33 pages), `SPEC_BASELINE.md`
  mis à jour en conséquence (R0.2.2).

## Éléments incomplets / non vérifiés (point 16)

- **Build/test iOS** - jamais tenté, nécessite un poste macOS/Xcode
  indisponible dans ce contexte (Android, en revanche, est désormais
  entièrement prouvé par exécution réelle - voir R0.2.1 ci-dessus).
- **Exécution manuelle de l'app sur appareil/émulateur** - l'APK compile et
  les tests automatisés passent, mais personne n'a encore lancé l'app pour
  vérifier visuellement le comportement des écrans.
- **Écrans UI d'export/import de sauvegarde** - le service existe, aucun
  écran ne l'appelle encore (tous les écrans S01-S20 restent des stubs
  hérités de R0, pas de régression introduite mais pas d'avancement non plus
  sur ce point précis dans cette livraison).
- **Corpus de vecteurs de test partagé** entre les deux implémentations du
  Reserve Composer (backend/mobile) - ROADMAP documentée dans ADR 0002, pas
  fait dans cette livraison.
- **Provider OpenAI réel** (`openai_provider.py`) - toujours non implémenté,
  inchangé depuis R0, prévu R2 (hors scope R0.1).
- **PDF avec mise en page réelle** - toujours un placeholder texte, inchangé
  depuis R0, prévu R3 (hors scope R0.1).
