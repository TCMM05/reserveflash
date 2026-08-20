# mobile/ - ReserveFlash Incident (Flutter)

Application mobile B2B France (section 1.3). Stack de référence : Flutter/Dart,
Riverpod, go_router, Drift, Dio (section 5.1).

**Depuis R0.1 (pivot Local-First, voir `docs/adr/0002-local-first-pivot.md`) :
ce module N'EST PLUS un simple client d'un backend qui ferait autorité.**
`lib/data/local/` (SQLite/Drift) est la source de vérité canonique d'un
dossier ReserveFlash pour la V1 - incidents, faits, réserve composée,
preuves, exports, tout y vit. Le backend n'est appelé que pour deux
opérations ponctuelles et optionnelles (transcription/extraction IA, voir
`backend/app/api/routes/ai.py`), jamais pour lire/écrire un incident.

## Limitation connue de cet environnement (important)

Ce code a été écrit/étendu dans un bac à sable cloud qui n'a **pas accès au
SDK Flutter/Dart** (téléchargement bloqué par la politique réseau de
l'environnement) - la même limitation existait déjà en R0 et reste
non-résolue en R0.1 **et en R0.2** (retentée explicitement à la demande du
retour de recette R0.1, qui refusait à raison une simple ré-affirmation).
Une deuxième voie a été explorée (exécuter `flutter`/`dart` via le pont vers
l'ordinateur de l'utilisateur, `device_bash`) : elle tourne dans une VM
isolée qui n'a, elle non plus, pas le SDK Flutter installé et n'a par
construction aucun accès réseau - donc pas de solution de contournement
trouvée à ce jour. Concrètement :

- **Priorité absolue dès que le SDK est disponible** : exécuter
  `flutter test test/data/local_incident_repository_test.dart` en premier -
  ce fichier (ajouté en R0.2) contient la preuve par test, explicitement
  demandée par la recette, que `LocalIncidentRepository` persiste réellement
  sur disque (créer → fermer la connexion → rouvrir une base neuve sur le
  même fichier → retrouver l'incident, les faits confirmés, une pièce jointe
  et une opération IA en attente).

- Tout le code sous `lib/` et `test/` est écrit à la main, syntaxiquement
  vérifié au meilleur effort (équilibrage d'accolades/parenthèses, cohérence
  des imports et des noms de classes générées par Drift selon ses
  conventions documentées), mais **n'a pas pu être compilé, analysé
  (`flutter analyze`) ni testé (`flutter test`) dans cette session**.
- Les fichiers générés par `build_runner` (`*.g.dart`, notamment
  `app_database.g.dart` pour Drift) n'existent pas encore : ils sont produits
  au premier `dart run build_runner build --delete-conflicting-outputs`.
- Les dossiers de plateforme (`android/`, `ios/`, ...) n'existent pas encore :
  ils sont générés par `flutter create .` (voir ci-dessous).
- `.github/workflows/ci.yml` (job `mobile`) exécute déjà l'intégralité de
  cette checklist sur un vrai runner GitHub Actions (avec accès réseau) à
  chaque push/PR, y compris un `flutter build apk --debug` (Gate R0.1, point
  1) - mais cette CI n'a **pas encore tourné** au moment de cette livraison
  (aucun push vers un dépôt GitHub réel n'a été effectué depuis ce bac à
  sable). Voir CHANGELOG.md pour le statut exact "livré vs. vérifié".

**Avant tout travail sur le mobile, un développeur disposant du SDK Flutter
doit exécuter la checklist "Premstrap" ci-dessous.**

## Premstrap (à faire une fois, avec Flutter installé)

```bash
cd mobile
flutter --version   # vérifier Flutter stable, canal correspondant à section 5.1
flutter create . --org com.reserveflash --platforms=android,ios
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
flutter build apk --debug   # Gate R0.1, point 1 - "application Flutter compilable"
```

Si une de ces commandes échoue à cause d'une erreur de syntaxe dans le code
écrit ici, c'est un bug de cette baseline à corriger en priorité (Gate R0.1 -
voir la liste des 11 critères dans le CHANGELOG.md).

## Structure

```
lib/
  core/
    design_system/   # section 4 - couleurs, typographie, spacing, thème
    router/           # go_router, une route par écran S01-S20 (section 3.2)
                       # - AUCUN redirect d'auth obligatoire (R0.1, point 13)
    widgets/          # composants partagés (RfScreenStub, ...)
    config/
      backend_config.dart  # R2 - URL du backend ReserveFlash (jamais de clé
                            # OpenAI ici, voir docs/security.md, GATE secret)
    providers/
      app_providers.dart   # câblage Riverpod - SEUL point de construction de
                            # AppDatabase/IncidentRepository/Dio/AiApiClient
  domain/
    value_objects/     # miroirs Dart de backend/app/domain/value_objects.py
    fact_set/           # ConfirmedFactData, CandidateFactData (GATE zéro
                        # invention, section 2.4 - candidat vs confirmé)
    entities/           # Incident, Issue, ConfirmedFactSet, CandidateFactSet,
                        # ReserveText, EvidenceAsset, AiQueueItem (section 2.2)
    errors/             # DomainException + sous-classes (LiabilityAttribution,
                        # R2 : AiUnavailable/AiInvalidOutput/AiRateLimited/
                        # AiRequestFailed - miroir de backend/app/domain/errors.py)
    repositories/        # IncidentRepository (interface, R0.1 point 12) -
                         # la logique métier ne dépend QUE de ce fichier,
                         # jamais de Drift directement.
    liability_guard.dart      # garde-fou anti-attribution de responsabilité
                               # (R0.1 point 8 - correctif de sécurité)
    candidate_guard.dart       # R2 - même garde-fou appliqué AVANT revue
                               # utilisateur, sur les CandidateFactData
    clarification_questions.dart  # R2 - catalogue contrôlé de questions
    reserve_composer.dart     # Reserve Composer LOCAL (R0.1 point 6 - tourne
                               # désormais sur l'appareil, voir ADR 0002)
    templates/fr_v1.dart      # template déterministe (miroir du backend)
  data/
    local/
      app_database.dart              # schéma Drift - SOURCE DE VÉRITÉ V1
      local_incident_repository.dart # seule implémentation V1 de IncidentRepository
    remote/
      ai_api_client.dart   # R2 - client vers /v1/ai/transcribe et /v1/ai/extract,
                            # SEUL appel réseau optionnel de l'app (jamais requis
                            # pour la capture locale, section 8.1) ; n'appelle
                            # JAMAIS OpenAI directement (flux Flutter -> Backend
                            # ReserveFlash -> OpenAI -> Backend -> Flutter)
    backup/
      backup_service.dart    # "Export mes données / Sauvegarde" (R0.1 point 9)
    share/
      reserve_share_service.dart  # partage natif du PDF (R0.1 point 10)
  features/<feature>/presentation/  # un dossier par écran/flux (section 3.2)
test/
  domain/               # tests purement Dart, aucune dépendance Flutter SDK
                        # nécessaire au-delà de flutter_test (package:test) -
                        # inclut les tests adversariaux liability_guard_test.dart
                        # (rejoue le bug "packagingCondition = 'transporteur
                        # responsable'" signalé dans la demande corrective R0.1)
                        # et reserve_composer_test.dart (E2E-01 à E2E-07).
  data/
    remote/
      ai_api_client_test.dart  # R2 - teste AiApiClient contre un
                                # AiHttpTransport factice fait à la main (pas
                                # de mock package:dio - voir docstring de
                                # ai_api_client.dart pour la justification)
```

## Pourquoi le Reserve Composer EST dupliqué ici (changement R0.1)

**Ce choix a changé depuis R0.** ADR 0001 ("GATE zéro invention") énonçait
initialement que le mobile ne dupliquerait pas la logique de composition,
pour éviter tout risque de divergence entre deux implémentations d'un
composant dont l'exigence centrale est l'unicité déterministe.

R0.1 (pivot Local-First, point 6 de la demande corrective) renverse
explicitement ce choix : "générer un dossier à partir des données locales
quand l'IA n'est pas nécessaire" est impossible à tenir si le composeur ne
vit que côté backend, dès que l'appareil est hors ligne - le scénario
central visé par ce pivot. Voir `docs/adr/0002-local-first-pivot.md`,
section "Conséquences sur ADR 0001", pour le détail complet du raisonnement
et de la mitigation du risque de divergence (tests adversariaux miroirs des
deux côtés, ROADMAP d'un corpus de vecteurs de test partagé).

`lib/domain/fact_set/confirmed_fact_data.dart::missingQuantity` reste
calculé par code uniquement (jamais saisi), désormais utilisé DIRECTEMENT
par le Reserve Composer local (et non plus seulement pour un feedback
visuel, comme c'était le cas en R0).
