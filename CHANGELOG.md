# Changelog

Format inspiré de [Keep a Changelog](https://keepachangelog.com/fr/).

## [0.2.0] - R1 "Capture Offline" (candidate) - 2026-08-19

Développée en partant strictement de la baseline gelée `r0-final` (voir
`docs/GATE_R0.1_STATUS.md`). Objectif R1 (demande corrective) : "permettre à
un utilisateur, sans connexion Internet, de créer un incident réel de
livraison et de conserver durablement toutes les preuves sur son téléphone."

**Conformément à la demande, cette version n'est PAS déclarée PASS ici** -
voir `docs/GATE_R1_STATUS.md` pour les preuves livrées et la recette
indépendante à mener. Aucune fonctionnalité R2 n'a été développée.

### Architecture / persistance

1. **`IncidentRepository`** (interface) : 3 nouvelles méthodes -
   `updateIncidentMetadata` (correction des champs saisis, point 7),
   `deleteEvidenceAsset` et `deleteIncident` (suppression avec confirmation
   côté UI, cascade transactionnelle pour l'incident - issues, faits
   candidats/confirmés, réserve(s), preuves, opérations IA). Les deux
   méthodes de suppression ne touchent QUE les métadonnées Drift ; les
   fichiers binaires sont supprimés séparément par l'appelant via le
   nouveau service ci-dessous (frontière stricte préservée).
2. **`lib/data/local/evidence_storage.dart`** (nouveau) : couche d'I/O
   fichier dédiée aux preuves - écriture ATOMIQUE (fichier temporaire même
   répertoire puis `rename`, jamais un fichier final partiel visible),
   calcul SHA-256 à la capture, suppression de fichier, et **vérification
   d'intégrité réelle** (`missing` si absent, `corrupted` si le hash
   recalculé diffère). `documentsDirectoryProvider` injectable uniquement
   pour les tests (voir plus bas), `path_provider` réel par défaut.
3. **`LocalIncidentRepository.verifyEvidenceAssetsIntegrity`** : n'est plus
   un stub (retournait simplement `listEvidenceAssets` depuis R0.1) -
   relit maintenant chaque fichier via `EvidenceStorageService.verify` et
   met à jour `availabilityStatus` en base si l'état a changé.
4. **`lib/core/providers/app_providers.dart`** (nouveau) : premier câblage
   Riverpod réel du projet (`ProviderScope` n'avait aucun override jusqu'ici)
   - `AppDatabase` (Drift/SQLite réel via `path_provider` +
   `NativeDatabase.createInBackground`, jamais `.memory()`),
   `IncidentRepository`, `EvidenceStorageService`, et des `FutureProvider`
   de lecture (liste/détail/issues/preuves) invalidés explicitement après
   chaque mutation locale via `notifyDataChanged`.

### Navigation

5. **`SplashScreen`** : corrigé - cet écran n'avait AUCUNE navigation avant
   R1 (l'app ne pouvait jamais atteindre l'accueil par elle-même). Navigue
   maintenant directement vers `AppRoutes.home`, sans jamais passer par
   `auth` ni requérir de réseau.
6. **`app_router.dart`** : `incidentId` transmis via `extra` à chaque étape
   du parcours de capture (S06-S15), pour que chaque écran sache sur quel
   dossier écrire - absent avant R1 (aucun écran, hors détail, ne recevait
   d'identifiant).

### Écrans (remplacement des stubs par une logique réelle)

7. **`CreateIncidentScreen`** (S05) : n'utilise plus de données fictives -
   ajoute les champs référence BL/commentaire (manquants), et "Continuer"
   crée réellement l'incident en local (R1-T01) avant toute navigation.
8. **`DocumentCaptureScreen`** (S06) : caméra réelle (plugin `camera`,
   permission demandée au point d'usage), preuve `delivery_document`
   enregistrée (id, incident, type, date/heure, chemin, taille, SHA-256)
   AVANT toute autre opération. Aucun OCR/IA.
9. **`IssueTypeScreen`** (S08) : sélection multiple réelle des 7 catégories
   V1, persistée via `addIssue` (plusieurs anomalies par incident).
10. **`EvidenceCaptureScreen`** (S09) : capture guidée (Photo 1 vue
    générale, Photo 2 étiquette/référence, Photo 3 vue rapprochée du
    dommage, photos supplémentaires facultatives), suppression avec
    confirmation par photo, compteur de progression.
11. **`VoiceDescriptionScreen`** (S10) : saisie texte toujours disponible
    (sortie de secours) + note vocale locale au mieux-effort via `record`
    (voir section "Risque documenté" ci-dessous). Aucune transcription IA.
12. **`ChecklistScreen`** (S14) : complétude de la CAPTURE (document BL,
    type(s) de problème, ≥3 photos preuves) en vert/orange, actionnable.
13. **`DossierCompleteScreen`** (S15) : confirme la sauvegarde 100% locale ;
    export PDF/partage restent hors périmètre R1 (voir demande corrective).
14. **`IncidentDetailScreen`** (S17) : réel - informations, type(s) de
    problème, photos BL/preuves, note texte/audio ; correction des
    métadonnées, suppression de photo/incident avec confirmation
    explicite, reprise d'un dossier commencé précédemment. Revérifie
    l'intégrité disque de chaque preuve à chaque ouverture (R1-T07).
15. **`HomeScreen`** / **`HistoryScreen`** : listes réelles
    (`listIncidents()`), plus de texte fictif "Aucun incident" figé.

### Dépendances

16. **`record: ^7.1.1`** ré-ajouté (retiré temporairement en R0.2, voir
    entrée `[0.1.3]`) - utilisé UNIQUEMENT par `VoiceDescriptionScreen`, en
    best-effort complet (try/catch, jamais bloquant). Version choisie après
    recherche (changelog pub.dev) pour son alignement AGP 9.x/Kotlin Gradle
    DSL avec le toolchain déjà prouvé de ce projet - **seul ajout de plugin
    natif de ce lot, donc le point de risque le plus élevé, à vérifier en
    priorité lors du premier `flutter build apk --debug` réel**.
17. **Aucun sélecteur de galerie** (`image_picker`) : décision de périmètre
    volontaire pour minimiser le risque d'un nouveau plugin natif
    supplémentaire non testable localement - "prise photo caméra" (exigée)
    est couverte, "choix image existante" (`si pertinent`) est différé.

### Tests

18. **`mobile/test/data/r1_capture_offline_test.dart`** (nouveau) : couvre
    R1-T01, T02, T03, T04, T05, T07, T08 par exécution réelle (vraie base
    SQLite sur fichier temporaire + vrais fichiers sur disque, jamais de
    mock mémoire) - mêmes garanties de preuve que
    `local_incident_repository_test.dart` (R0). R1-T10 (aucun appel réseau)
    est garanti par construction (aucune dépendance HTTP dans le chemin de
    code exercé) et documenté comme tel en tête du fichier. R1-T06 (refus
    de permission) et R1-T09 (mode avion) nécessitent un vrai canal de
    plateforme - à vérifier manuellement sur appareil (voir
    `docs/GATE_R1_STATUS.md`).
19. Tous les tests R0 existants sont conservés inchangés (non-régression).

### Limitations connues / simplifications assumées (R1)

- Les libellés "Photo 1/2/3" de la capture guidée sont déterminés par
  ORDRE de capture, pas par un champ stocké (`LocalEvidenceAssets` n'a pas
  de colonne dédiée) - purement un affichage, sans conséquence sur
  l'intégrité des preuves elles-mêmes.
- `HistoryScreen` : liste complète sans recherche/filtres avancés (mention
  du critère de conception d'origine S16, hors périmètre fonctionnel R1
  explicite).
- Risque audio (`record`) documenté explicitement ci-dessus et dans
  `docs/GATE_R1_STATUS.md`, conformément à la demande : "si l'intégration
  audio ajoute un risque important au Gate R1, documenter clairement le
  point mais ne pas compromettre caméra, fichiers et persistance."
- Aucune exécution réelle (`flutter analyze`/`flutter test`/
  `flutter build apk --debug`) n'a encore eu lieu au moment de la rédaction
  de cette entrée - le SDK Flutter reste indisponible dans ce contexte de
  développement (même limitation que R0, résolue à chaque fois par un
  bootstrap réel sur le poste de l'utilisateur, voir `mobile/README.md`).
  **Ne pas considérer R1 validée avant ce bootstrap réel.**

## [0.1.5] - R0.2.3 Freeze documentaire/traçabilité - 2026-08-19

R0.2.2 étant techniquement validée (CI GitHub Actions réelle et verte,
cahier v1.1 vérifié), cette version clôt la traçabilité documentaire finale
de R0, **sans aucun changement métier ou architectural** :

1. **Références actives v1.0 -> v1.1 Local-First** : `README.md`,
   `docs/architecture.md` (nom de fichier du cahier cité),
   `backend/pyproject.toml`, `backend/app/main.py` (description FastAPI),
   `mobile/pubspec.yaml`. Les mentions historiques légitimes (ADR 0002,
   qui documente une décision datée du 2026-08-18 quand seul le cahier
   v1.0 était connu ; `docs/SPEC_BASELINE.md`, qui archive le SHA-256 v1.0
   à des fins de traçabilité) sont volontairement laissées inchangées.
2. **`backend/openapi.json` régénéré** après la modification de la
   description FastAPI ci-dessus - seul le champ `info.description`
   change dans le diff, confirmé stable (même SHA-256 sur deux générations
   consécutives) dans un environnement Python 3.12 propre.
3. **`docs/GATE_R0.1_STATUS.md` au statut final** : nouvelle section "Mise
   à jour R0.2.3" en tête de document (CI GitHub réelle = PASS, baseline
   v1.1 = vérifiée, Android = PASS, iOS = réserve future explicite non
   bloquante), et toutes les mentions ponctuelles contradictoires dans les
   sections historiques ("CI jamais déclenchée", "v1.1 jamais fourni")
   corrigées pour ne plus se contredire avec ce statut final.
4. **Phrase obsolète retirée du CHANGELOG** : la section "Explicitement PAS
   fait dans cette clôture" de `[0.1.4]` affirmant que la CI n'avait pas
   été exécutée a été supprimée - elle était directement contredite par le
   paragraphe qui la précédait (run CI #2 vert, documenté juste au-dessus).
5. **`README.md`/`docs/architecture.md` nettoyés** des limitations R0
   désormais résolues : "mobile non compilé/testé" et "test d'intégration
   Drift non exécuté" (toutes deux résolues depuis R0.2.1/R0.2.2, barrées
   et marquées RÉSOLU plutôt que supprimées, pour garder la trace de la
   recette). Les réserves toujours réelles (iOS, backup non chiffré) sont
   conservées telles quelles.
6. **Commit final + tag final R0** : voir `git log`/`git tag -n1` pour le
   commit et le tag exacts de cette clôture (volontairement non figés en
   dur ici, même raison que dans `docs/GATE_R0.1_STATUS.md` - ce document
   fait partie de l'historique qu'il décrirait).
7. **Poussé sur GitHub** (`TCMM05/reserveflash`, historique + tags complets
   via `git bundle`, comme pour R0.2.2).
8. **CI relancée sur ce commit exact** - voir la section suivante pour le
   résultat.

## [0.1.4] - R0.2.2 Clôture documentaire/build (revue équipe post-R0.2.1) - 2026-08-19

Réponse à la revue de l'équipe sur R0.2.1 (verdict "R0.2.1 : PASS
TECHNIQUE Android + backend / Gate R0 global : PASS SOUS RÉSERVES de
livraison/traçabilité"), qui demandait une clôture documentaire/build
sans nouveau chantier architectural, sur 8 points précis.

### Fait dans cette clôture

1. **CI alignée sur l'environnement réellement prouvé** :
   `.github/workflows/ci.yml`, `FLUTTER_VERSION` passé de `3.24.5`
   (jamais exécuté ni prouvé dans ce dépôt) à `3.47.0` (version exacte du
   build réel qui a produit 52/52 tests verts et l'APK debug).
2. **`pubspec.lock` committé** : retiré de `mobile/.gitignore` (qui suivait
   par défaut la convention "bibliothèque Flutter", inadaptée à une
   application) et committé tel que résolu par le `flutter pub get` du
   build réellement validé (même horodatage que l'exécution qui a produit
   l'APK : 2026-08-19T14:59:43+02:00) - fige les versions qui ont
   effectivement fonctionné, après toutes les difficultés de dépendances
   rencontrées en R0.2.1.
3. **Les 14 `info` de `flutter analyze` corrigés** (viser 0 issue) :
   - `mobile/lib/core/design_system/rf_theme.dart` : `const` ajouté sur
     `BottomSheetThemeData` (4 occurrences imbriquées résolues par
     propagation du contexte const).
   - `mobile/lib/features/facts_review/presentation/facts_review_screen.dart` :
     `color.withOpacity(0.12)` → `color.withValues(alpha: 0.12)` (API de
     remplacement suggérée par le message de dépréciation lui-même).
   - `mobile/lib/features/home/presentation/home_screen.dart` : `const`
     ajouté sur le `Padding` racine du corps d'écran (4 occurrences
     imbriquées résolues par propagation).
   - `mobile/lib/features/incident_create/presentation/create_incident_screen.dart` :
     `const` ajouté sur un `Text` isolé (le reste de l'arbre contient un
     `TextField` avec contrôleur, non const-compatible).
   - `mobile/lib/features/reserve/presentation/reserve_screen.dart` :
     `const` ajouté sur `Card`/`Text` (les deux champs affichés,
     `_sampleReserveText`/`_prudenceMention`, sont déjà des
     `static const String`).
   - **Reconfirmé par une nouvelle exécution réelle le 2026-08-19** (voir
     section "Reconfirmation par exécution réelle" ci-dessous) :
     `flutter analyze` -> `No issues found! (ran in 13.9s)`.
4. **APK transmis** pour vérification indépendante du SHA-256 annoncé en
   R0.2.1 - **limitation découverte à cette occasion** : le fichier
   (175,3 MiB) dépasse la limite de taille des pièces jointes de cette
   conversation (30 MiB) et n'a donc pas pu être transmis par ce canal.
   Reste disponible sur le poste de l'utilisateur ; son SHA-1 (généré par
   Gradle) a été recalculé indépendamment sur la copie transférée dans cet
   environnement et correspond exactement, ce qui prouve l'intégrité du
   transfert vers CET environnement, mais pas encore une vérification par
   l'équipe elle-même (qui ne l'a pas reçu).
5. **Manifeste de livraison séparé** : `docs/DELIVERY_MANIFEST_R0.2.2.md`,
   rassemblant environnement de build, commit/tag, SHA du ZIP et de l'APK,
   statut `pubspec.lock`/`flutter analyze`/cahier de référence/CI GitHub en
   un seul endroit.
6. **Cahier des charges v1.1 reçu et vérifié** (point 1 de la revue,
   résolu après la clôture initiale de ce cycle) : le fichier
   `ReserveFlash_Incident_Cahier_des_Charges_v1.1_LocalFirst.pdf` a été
   déposé dans la conversation le 2026-08-19. `sha256sum` recalculé
   indépendamment sur le fichier reçu ->
   `1c6b3db672d9d622679ecd6c8b20908e575e2702eeb4dcc839609b21ea5ccd1b` -
   identique au hash cité par l'équipe, confirmant l'authenticité du
   fichier plutôt que de la supposer. Les 33 pages ont été lues
   intégralement ; `docs/SPEC_BASELINE.md` mis à jour avec `SPEC_BASELINE`/
   `SPEC_DATE`/`SPEC_SHA256` réels, et chaque clause précédemment "traitée
   sans source numérotée" a désormais sa référence exacte (section/page) :
   endpoint d'historique métier (section 9.2, p.19), chiffrement de
   sauvegarde SEC-08 (p.20), formulation du Gate de sortie R0 (section 18,
   p.29), exigences R4 intégrité/hashes/refus d'archive corrompue
   (sections 8.2 et 18, p.17-18 et p.29).

### Reconfirmation par exécution réelle (2026-08-19, rebuild post-commit `f4106b2`)

Nouveau bootstrap complet relancé par l'utilisateur sur son poste Windows
après le commit documentaire du cahier v1.1 (aucun changement de code
mobile depuis) - `bootstrap_log.txt` relu intégralement (décodé, comme les
fois précédentes, depuis un mélange UTF-8/UTF-16LE produit par PowerShell) :

- `flutter analyze` -> **`No issues found! (ran in 13.9s)`** - confirme
  bien les 5 correctifs `const`/`withValues` du point 3 ci-dessus.
- Tests -> **52/52 verts** (`All tests passed!`), y compris les tests
  Drift de persistance disque réelle et les tests `liability_guard`/
  `reserve_composer`.
- `flutter build apk --debug` -> APK reconstruit avec succès,
  `183 865 201` octets (taille identique à l'APK R0.2.1).
- **Constat honnête, non demandé mais découvert par cette ré-exécution** :
  le SHA-1 de ce nouvel APK (`1ddb0ade10198eb0e8d8232e6be14c7a350f1809`) est
  **différent** de celui de l'APK R0.2.1 (`7826ade1fc3267e34ff60ddf683c7affe8387fbf`)
  alors que la taille est identique et qu'aucun code mobile n'a changé
  entre les deux builds. Ceci indique que le build APK debug (signé avec
  le keystore de debug, horodatage/metadata de signature embarqués) n'est
  **pas reproductible bit-à-bit** d'une exécution à l'autre sur ce poste -
  à distinguer de "build reproductible" au sens du Gate R0 du cahier v1.1
  (section 18, page 29), qui porte sur la capacité à reconstruire un build
  qui fonctionne et passe les tests, non sur une identité binaire stricte
  (non exigée explicitement ailleurs dans le cahier). Consigné ici par
  souci de transparence plutôt que passé sous silence.

### CI GitHub Actions - premier run réel, bug trouvé et corrigé (2026-08-19)

Le dépôt a été poussé vers un dépôt GitHub réel (`TCMM05/reserveflash`,
historique et tags complets préservés via `git bundle`) pour la toute
première exécution de `.github/workflows/ci.yml` sur un vrai runner - le
seul point de la revue R0.2.2 qui ne pouvait pas être prouvé depuis ce bac
à sable.

Cette première exécution réelle a immédiatement révélé un bug invisible
jusqu'ici : le job `backend` échouait dès l'étape `pip install -e
".[dev]"` avec `error: Multiple top-level packages discovered in a
flat-layout: ['app', 'alembic']`. Root cause : `backend/pyproject.toml` ne
déclarait aucune section `[build-system]`/`[tool.setuptools.packages.find]`
; setuptools scanne alors tout `backend/` et trouve DEUX répertoires
Python de premier niveau (`app/` et `alembic/`), et refuse de construire
sans instruction explicite. Ce bug n'était jamais apparu localement car
les tests tournent via `pytest` (qui utilise `pythonpath = ["."]` et
n'installe jamais le paquet), jamais via une installation `pip` réelle -
exactement le type de bug que seule une vraie CI peut révéler.

Corrigé dans `backend/pyproject.toml` : ajout de `[build-system]`
(`setuptools>=68`) et de `[tool.setuptools.packages.find]` avec `include =
["app*"]` pour ne déclarer que le paquet applicatif `app` (ni `alembic/`,
invoqué via sa CLI et non importé, ni `tests/`/`scripts/`). Reproduit et
vérifié dans cet environnement cloud, dans un environnement Python 3.12
propre créé pour l'occasion : échec identique reproduit AVANT le correctif
(`Getting requirements to build editable` échoue), puis succès confirmé
APRÈS (`Successfully installed ... reserveflash-backend-0.1.0`, `import
app` fonctionne, `ruff check` toujours vert). `backend/.gitignore` complété
avec `*.egg-info/` (artefact généré localement par cette installation).

Le correctif a été repoussé vers `TCMM05/reserveflash` (commit `6aa7f88`,
run CI #2) - **résultat : run complet vert, 4/4 jobs, 7m36s au total** :
`backend` (44s), `secret-scan`/gitleaks (6s), `build-staging`, dépendant du
succès de `backend` (25s), et `mobile` - analyze/tests/build APK debug, le
plus long (7m33s). Capture d'écran du run fournie par l'utilisateur,
consultable sur `https://github.com/TCMM05/reserveflash/actions` (run #2,
commit `6aa7f88`).

**C'est la première fois que ce dépôt obtient une exécution complète et
verte sur un vrai runner GitHub Actions** - le dernier point resté ouvert
de la revue R0.2.2 est donc clos, avec la même exigence de preuve par
exécution que le reste du projet (le bug ci-dessus n'aurait justement
jamais été détecté sans cette exécution réelle).

## [0.1.3] - R0.2.1 Hotfix (première exécution réelle) - 2026-08-19

### Livraison finale de cette version

- Tag Git : `r0.2.1-hotfix-preuve-execution`.
- Archive : `ReserveFlash_R0.2.1_Hotfix.zip`, générée par `git archive`
  depuis ce tag (contenu strictement identique à l'historique Git, aucune
  dérive possible entre l'archive livrée et le code committé).
  SHA-256 : `1147994981558dea49b961b6032dd8cf977b1dee69d5035f88798a6efec8c1f3`
- APK debug Android construit sur le poste réel de l'utilisateur :
  `app-debug.apk`, 183 865 201 octets.
  SHA-256 : `08fe8ac120e38befaf7cc9bb753b63ff8d86308f674490ead639ca9e2077ada7`
  SHA-1 (généré par Gradle) : `7826ade1fc3267e34ff60ddf683c7affe8387fbf`
- Voir `docs/GATE_R0.1_STATUS.md` pour l'évaluation point par point, mise à
  jour, des 11 critères du Gate R0.1 et des 11 points de clôture R0.2 à la
  lumière de cette exécution réelle.

Premiers correctifs issus d'une VRAIE exécution de `flutter create` /
`flutter pub get` / `dart run build_runner build` sur un poste équipé du SDK
Flutter (3.47.0, Dart 3.13.0) - exactement ce que le retour de recette
demandait ("nous voulons la preuve par test/exécution, pas l'affirmation").
Deux problèmes réels, invisibles à la seule lecture du code, sont apparus
dès la première tentative :

- **`mobile/lib/data/local/app_database.dart`** : la directive `library;`
  était placée APRÈS `import`/`part`, ce qui est invalide en Dart (la
  directive `library`, si présente, doit être la toute première du fichier)
  - `build_runner` levait `The library directive must appear before all
  other directives.` Corrigé en replaçant `library;` (et le commentaire de
  documentation associé) en tête de fichier.
- **`mobile/pubspec.yaml`** : `riverpod_generator`, `freezed` et
  `json_serializable` (dev_dependencies) embarquaient un `analyzer` trop
  ancien (langue Dart 3.9) pour le SDK Dart 3.13 réellement installé -
  `build_runner build` plantait avec `Exception: Missing implementation of
  visitDotShorthandPropertyAccess` en tentant d'analyser le SDK Flutter
  lui-même (pas notre code). Vérifié avant suppression : aucun fichier de ce
  dépôt n'utilise `@riverpod`, `@freezed` ni `@JsonSerializable` (grep sur
  `lib/`, zéro résultat) - ces trois générateurs étaient présents par
  anticipation mais totalement inutilisés. Retirés pour l'instant ; à
  ré-ajouter avec des versions à jour le jour où du code annoté est
  réellement introduit (probable en R1+).

### Deuxième vague (après ré-exécution avec les 2 correctifs ci-dessus)

`build_runner` a ensuite tourné sans planter, mais a produit un
`app_database.g.dart` VIDE (`allSchemaEntities => []`, aucune des 9 tables).
`flutter analyze` a révélé la cause racine, ainsi que 3 autres bugs réels
indépendants, tous confirmés par une VRAIE exécution :

- **`mobile/lib/data/local/app_database.dart`** : la table
  `LocalReserveTexts` définissait une colonne nommée `text`
  (`TextColumn get text => text()();`), qui entre en collision avec la
  méthode `Table.text()` héritée (le builder utilisé pour DÉFINIR une
  colonne texte) - `flutter analyze` le confirme littéralement : `Class
  'LocalReserveTexts' can't define field 'text' and have method 'Table.text'
  with the same name.` Cette collision faisait planter `drift_dev` sur cette
  seule table, ce qui invalidait la génération de TOUT le fichier
  (`allSchemaEntities => []`), ce qui à son tour cassait en cascade des
  dizaines de références dans `local_incident_repository.dart` et
  `backup_service.dart` (classes `LocalIncident`, `LocalIncidentsCompanion`,
  etc. "introuvables"), et empêchait toute compilation - `flutter build apk
  --debug` échouait avec `Target kernel_snapshot_program failed: Exception`
  pour cette même raison. Corrigé en renommant la colonne `text` ->
  `reserveText` (répercuté dans `local_incident_repository.dart` et
  `backup_service.dart`, 4 sites d'appel).
- **`mobile/lib/domain/liability_guard.dart`** (bug de correction, PAS de
  compilation) : 3 tests du garde-fou échouaient réellement -
  `"carton à la charge du fournisseur"` (LIABILITY_ATTRIBUTION),
  `"remboursement dû au client"` (INDEMNIFICATION_PROMISE),
  `"vice caché constaté"` (LEGAL_CONCLUSION) - le garde-fou laissait passer
  SILENCIEUSEMENT ces formulations au lieu de les bloquer. Cause : les
  `RegExp` Dart n'utilisent PAS un `\b`/`\w` Unicode par défaut
  (contrairement au module `re` de Python utilisé côté backend, Unicode par
  défaut) - une frontière `\b` juste avant/après une lettre accentuée ("à",
  "dû", "caché") ne correspond alors JAMAIS à une frontière de mot. C'est
  exactement le type de divergence Python/Dart qu'une simple relecture de
  code ne peut pas détecter. **Premier correctif tenté ici (ajout de
  `unicode: true` aux 5 `RegExp`) INSUFFISANT** - voir "Troisième vague"
  ci-dessous pour le correctif réel, découvert par une RE-exécution des
  tests qui a échoué de façon identique après ce premier correctif.
- **`mobile/test/widget_test.dart`** : fichier généré par `flutter create .`
  avec son boilerplate par défaut (`MyApp`, compteur), qui ne correspond à
  rien dans notre app (`ReserveFlashApp`, voir `lib/main.dart`) -
  `flutter analyze`/`flutter test` échouaient avec `The name 'MyApp' isn't a
  class.` Remplacé par un smoke test minimal réel (`pumpWidget` de
  `ReserveFlashApp`, vérifie qu'un `MaterialApp` est bien construit).
- **`mobile/test/data/local_incident_repository_test.dart`** (bug dans le
  test ajouté en R0.2, point 6 de la demande corrective) : import inutile de
  `package:drift/drift.dart` (en plus de `package:drift/native.dart`, le
  seul réellement nécessaire) - le premier ré-exporte `isNotNull`/`isNull`,
  qui entrent en collision avec les matchers de même nom de
  `package:flutter_test` (`ambiguous_import`). Corrigé en retirant l'import
  inutile.
- **`mobile/pubspec.yaml`** : `flutter build apk --debug` échouait
  séparément (après le correctif `text`/`reserveText`) sur
  `record_linux-0.7.2`, qui n'implémente pas l'interface
  `record_platform_interface-1.6.0` résolue (`startStream` manquant,
  signature de `hasPermission` incompatible) - Dart refuse de compiler le
  kernel snapshot de l'app, même pour une cible Android, dès qu'un paquet de
  plateforme du graphe de dépendances ne compile pas. Vérifié avant retrait
  : `record` n'est utilisé nulle part dans `lib/` (grep, zéro résultat) - la
  capture audio (F06/F07/F11) n'est pas encore implémentée. Retiré
  temporairement (commenté, avec justification) ; à ré-ajouter avec une
  version laissant `pub` résoudre un jeu cohérent de sous-paquets (ou un
  `dependency_overrides` explicite) le jour où la capture audio est
  réellement codée.

Après ces correctifs, `flutter create`/`flutter pub get` avaient déjà
réussi sur le poste de l'utilisateur avant le hotfix ; `build_runner build`
(génération de `app_database.g.dart`), `flutter analyze`, `flutter test` et
`flutter build apk --debug` restent à re-tenter avec ce correctif - voir
`docs/GATE_R0.1_STATUS.md` pour le statut mis à jour une fois le résultat
connu.

### Troisième vague (après ré-exécution avec les correctifs de la deuxième vague)

La ré-exécution a confirmé que 3 des 4 bugs de la deuxième vague étaient
bien corrigés (plus d'erreur `text`/`MyApp`/`ambiguous_import`), mais a
révélé que le correctif du garde-fou anti-attribution était INSUFFISANT,
plus 2 bugs supplémentaires non vus jusqu'ici :

- **`mobile/lib/domain/liability_guard.dart`** (correctif réel du bug
  décrit en deuxième vague) : les 3 mêmes tests échouaient encore, à
  l'identique, APRÈS le premier correctif (`unicode: true` seul). Vérifié
  que ce correctif était bien déployé (pas un problème de synchronisation)
  avant de ré-investiguer. Cause réelle : le flag `unicode: true` d'un
  `RegExp` Dart NE rend PAS `\b`/`\w` sensibles à l'Unicode (ce
  comportement est hérité de la sémantique JavaScript/ECMAScript, où le
  flag `u` ne change pas non plus `\w`) - il active uniquement les échappes
  de propriété Unicode `\p{...}`/`\P{...}`. Correctif réel : remplacement
  des frontières `\b` par des lookaround explicites sur la catégorie
  Unicode "Lettre" + chiffre/underscore - `(?<![\p{L}\p{N}_])` (non précédé
  d'un caractère de mot Unicode) et `(?![\p{L}\p{N}_])` (non suivi) -, qui
  EUX exploitent réellement `unicode: true`. Appliqué aux 4 motifs
  concernés (LIABILITY_ATTRIBUTION, INDEMNIFICATION_PROMISE,
  LEGAL_CONCLUSION, LEGAL_QUALIFICATION) ; INVENTED_AMOUNT inchangé (son
  usage interne de `eur\b` n'a pas ce problème de frontière accentuée).
  **Bug de sécurité fonctionnelle réel** : entre les deux correctifs, le
  garde-fou aurait laissé passer silencieusement des formulations
  d'attribution de responsabilité se terminant/commençant par une lettre
  accentuée - exactement le type de contenu qu'il existe pour bloquer.
- **`mobile/lib/data/share/reserve_share_service.dart`** : `flutter
  analyze` échouait avec `Undefined name 'SharePlus'` et `The method
  'ShareParams' isn't defined for the type 'ReserveShareService'`. Cause :
  `pubspec.yaml` déclarait `share_plus: ^10.0.2`, qui autorise uniquement
  des versions `10.x.x` - or la classe unifiée `SharePlus` et son paramètre
  `ShareParams` n'ont été introduits qu'en version 11.0.0 du paquet
  (confirmé via le changelog officiel `share_plus` sur pub.dev). `pub get`
  résolvait donc la dernière version 10.x compatible (10.1.4), qui
  n'expose pas ces symboles, alors que le code du fichier utilisait déjà
  l'API 11.0.0+. Corrigé en relevant la contrainte à `share_plus: ^11.0.0`
  (borné à `<12.0.0` volontairement, pour ne pas importer en même temps les
  nouvelles exigences Android Gradle Plugin/Gradle wrapper des versions
  12.0.0+, non testées et hors périmètre de ce hotfix - dernière version
  stable constatée au moment du correctif : 13.3.0).
- **`mobile/test/data/local_incident_repository_test.dart`** (bug
  d'infrastructure de test, spécifique à Windows) : les 3 tests de
  persistance disque (point 6 de la demande corrective) échouaient en fin
  d'exécution avec `PathAccessException` sur `tempDir.delete(recursive:
  true)` dans `tearDown` - `"...ce fichier est utilisé par un autre
  processus", errno = 32`. Cause : sur Windows, le verrou OS sur le fichier
  SQLite ouvert par `NativeDatabase` n'est pas toujours libéré de façon
  synchrone au retour de `db.close()` (le driver natif le relâche de façon
  asynchrone), donc la suppression immédiate du dossier temporaire pouvait
  s'exécuter avant la libération effective du handle - un problème
  spécifique à Windows, absent sur les systèmes de type Unix. Les
  assertions métier elles-mêmes (preuve de persistance) réussissaient
  toutes ; seul le nettoyage échouait, faisant néanmoins échouer le test
  dans son ensemble. Corrigé en retentant la suppression jusqu'à 5 fois
  avec un court délai entre chaque tentative, et en abandonnant
  silencieusement (sans faire échouer le test) si le nettoyage échoue
  malgré tout - un résidu de dossier temporaire est sans conséquence
  fonctionnelle, contrairement à un faux échec de la preuve de persistance
  elle-même.

`flutter build apk --debug` échouait aussi lors de cette troisième
exécution ; la cause exacte n'a pas encore été confirmée indépendamment
mais est vraisemblablement entièrement expliquée par les erreurs de
compilation `SharePlus`/`ShareParams` ci-dessus (un échec de compilation
Dart, où qu'il survienne dans le graphe de l'app, bloque le kernel
snapshot pour toute la cible, comme déjà observé avec le bug
`record_linux` en deuxième vague) - à confirmer par la prochaine
exécution réelle.

### Quatrième vague (après ré-exécution avec les correctifs de la troisième vague)

Cette hypothèse ci-dessus était **fausse** : la ré-exécution a confirmé que
`SharePlus`/`ShareParams` compilaient bien, et a révélé la vraie cause du
`flutter build apk --debug` (indépendante), plus 2 bugs réels
supplémentaires non vus jusqu'ici - toujours des bugs qu'une relecture de
code n'aurait pas détectés :

- **`mobile/lib/domain/liability_guard.dart`** (même bug racine que la
  troisième vague, mais À L'INTÉRIEUR d'un motif cette fois) : le test
  `"sera indemnisé intégralement" est bloqué (INDEMNIFICATION_PROMISE)`
  échouait - `screenConfirmedFact` ne levait plus l'exception attendue
  (`Actual: returned <null>`). Cause : `indemnis\w*` utilise `\w`, LUI
  AUSSI ASCII-only en Dart (`[A-Za-z0-9_]`, `unicode: true` ne change rien
  ici non plus) - sur `"indemnisé"`, `\w*` s'arrêtait juste avant le "é",
  puis le lookahead Unicode-aware `(?![\p{L}\p{N}_])` (corrigé en
  troisième vague) refusait la position car "é" EST un caractère de mot
  Unicode - contradiction entre un `\w*` ASCII à l'intérieur du motif et
  une frontière vérifiée en Unicode juste après. Corrigé en remplaçant
  `indemnis\w*`/`dédommag\w*` par `indemnis[\p{L}\p{N}_]*`/
  `dédommag[\p{L}\p{N}_]*`.
- **Persistance des `DateTime` (Drift)** : le test de persistance disque
  réelle (point 6 de la demande corrective) échouait sur
  `expect(reopened.occurredAt, equals(occurredAt))` -
  `Expected: DateTime:<2026-08-19 10:30:00.000Z>` /
  `Actual: DateTime:<2026-08-19 12:30:00.000>`. Root cause (confirmée via
  la documentation officielle Drift, guide "DateTime Storage") : en mode
  de stockage par défaut (entier unix timestamp), Drift NE PRÉSERVE PAS le
  flag UTC/local d'un `DateTime` - "drift always returns a non-UTC value.
  So even when UTC date times are stored, this information is lost when
  retrieving rows." `occurredAt` est créé via `DateTime.utc(...)`, mais
  après fermeture/réouverture de la connexion (exactement le scénario que
  ce test doit prouver), Drift le retourne en heure locale. Même INSTANT
  (12:30 heure d'été Paris == 10:30 UTC), mais l'opérateur `==` de
  `DateTime` compare l'instant ET le flag UTC/local (documentation
  officielle `dart:core`) - deux `DateTime` au même instant avec un flag
  différent sont donc INÉGAUX. Un vrai bug de fidélité des données :
  `occurredAt` glissait silencieusement d'UTC vers l'heure locale de
  l'appareil après un redémarrage de l'app. Corrigé en ajoutant
  `mobile/build.yaml` avec l'option de génération `drift_dev` :
  `store_date_time_values_as_text: true`, qui stocke les `DateTime` en
  TEXT ISO 8601 et préserve explicitement le flag UTC/local. Sans
  conséquence de migration : aucune base utilisateur réelle n'existe
  encore (Gate R0 toujours en cours de validation).
- **`flutter build apk --debug`** (cause réelle, indépendante de
  `SharePlus`) : `BUILD FAILED` sur la tâche Gradle
  `:camera_android_camerax:compileDebugJavaWithJavac` -
  `error: Cannot attach type annotations @org.jspecify.annotations.NonNull
  to SurfaceRequest.mSurfaceRecreationCompleter: class file for
  androidx.concurrent.futures.CallbackToFutureAdapter not found`. Root
  cause (confirmée via le fil officiel Google camerax-developers, "CameraX
  1.5.0 fails to build") : `androidx.camera:camera-core` 1.5.x (utilisé en
  transitif par le plugin `camera_android_camerax`) utilise
  `CallbackToFutureAdapter` (de `androidx.concurrent:concurrent-futures`)
  pour ses `ListenableFuture`, mais cette dépendance n'est plus résolue
  automatiquement sur le classpath de compilation Java depuis cette
  version - réponse officielle Google sur ce fil : "It might need to add
  this dependency manually." PAS un bug de notre code Dart/Kotlin - ajouté
  un bloc `dependencies { implementation("androidx.concurrent:concurrent-
  futures:1.1.0") }` dans `mobile/android/app/build.gradle.kts` (fichier
  généré par `flutter create .`, désormais versionné dans le dépôt avec ce
  correctif pour que `flutter create .` le préserve tel quel - voir
  commentaire dans le fichier - au lieu de régénérer une version sans le
  correctif sur un poste n'ayant jamais eu de `repo/android/` existant).

### Cinquième vague (après ré-exécution avec les correctifs de la quatrième vague)

Les 52 tests Dart passent tous ("All tests passed!", suite complète + suite
Drift dédiée) - les 4 vagues précédentes de correctifs Dart sont donc
confirmées bonnes. `flutter analyze` : 0 erreur (14 `info` de style
uniquement - `const` manquants, `withOpacity` déprécié ; PowerShell les
affiche comme `NativeCommandError` uniquement parce que `flutter analyze`
sort avec un code de retour non-nul dès qu'il trouve ne serait-ce qu'un
`info`, ce n'est PAS un vrai échec). Seul `flutter build apk --debug`
échouait encore, à l'IDENTIQUE de la vague précédente :

- **`mobile/android/app/build.gradle.kts`** (correctif de la quatrième
  vague, INSUFFISANT - prouvé par une ré-exécution identique) : ajouter la
  dépendance manquante `androidx.concurrent:concurrent-futures` dans le
  module `:app` n'avait aucun effet, car l'erreur de compilation Java
  (`CallbackToFutureAdapter not found`) survient dans un SOUS-PROJET
  Gradle DIFFÉRENT et distinct - `:camera_android_camerax` (le plugin
  lui-même, généré par le "plugin loader" de Flutter à partir du paquet
  pub, avec son propre classpath de compilation). Une dépendance déclarée
  côté `:app` ne remonte jamais vers le classpath de compilation d'un
  sous-projet dont `:app` dépend - seul l'inverse est vrai. Retiré (le
  fichier redevient celui généré par `flutter create .`, avec un
  commentaire renvoyant vers le vrai correctif).
- **`mobile/android/build.gradle.kts`** (fichier RACINE du build multi-
  projet Gradle - correctif réel) : root cause confirmée via le dépôt de
  reproduction officiel du bug
  (`github.com/justshowcode/flutter_packages_camerax_repro`) :
  `androidx.camera:camera-core:1.5.3` déclare sa dépendance vers
  `androidx.concurrent:concurrent-futures` avec la portée "runtime" dans
  son POM. Jusqu'à Gradle 8.x, Gradle promouvait silencieusement cette
  dépendance runtime vers le classpath de COMPILATION des consommateurs ;
  Gradle 9.x (utilisé ici - `gradle-9.3.1`, visible dans les logs de
  build) applique un isolement de classpath strict et ne fait plus cette
  promotion, rendant la classe invisible au compilateur Java. Corrigé en
  injectant la dépendance manquante dans TOUS les sous-projets Android
  (donc `:camera_android_camerax` y compris) depuis ce fichier racine, via
  un bloc `subprojects { afterEvaluate { ... dependencies.add(...) } }` -
  sans éditer aucun fichier du cache pub (qui serait de toute façon écrasé
  au prochain `flutter pub get`, sur cette machine comme sur n'importe
  quelle autre - un correctif non reproductible sur un autre poste n'a
  aucune valeur pour ce projet).

À confirmer par la prochaine exécution réelle : c'est, à ce stade, le
DERNIER échec connu du bootstrap complet (`flutter create` /
`flutter pub get` / `build_runner` / `flutter analyze` / `flutter test` /
`flutter build apk --debug`).

### Sixième vague (après ré-exécution avec le correctif de la cinquième vague)

Les tests Dart et `flutter analyze` restent bons (aucune régression). Le
correctif Gradle racine de la cinquième vague a introduit un NOUVEAU bug,
distinct du bug qu'il essayait de corriger :

- **`mobile/android/build.gradle.kts`** : `flutter build apk --debug`
  échouait immédiatement (5s, avant même la compilation) avec
  `Cannot run Project.afterEvaluate(Action) when the project is already
  evaluated.` (le message Gradle ne nomme PAS le sous-projet fautif - la
  cause ci-dessous, "précisément sur `:app`", était une supposition NON
  VÉRIFIÉE au moment d'écrire cette entrée ; elle s'est révélée fausse,
  voir "Septième vague"). Hypothèse (partiellement correcte) : le bloc
  `subprojects { project.evaluationDependsOn(":app") }` (déjà présent
  dans le template Flutter par défaut, jamais modifié ici) force
  l'évaluation anticipée de `:app`. Corrigé en ne ciblant plus `:app`
  (il n'a d'ailleurs jamais été le module fautif du bug
  `CallbackToFutureAdapter` - voir cinquième vague) : seul
  `com.android.library` visé. **Ce correctif s'est révélé INSUFFISANT**
  - voir "Septième vague" ci-dessous, qui a rejoué le même échec à
  l'identique sur un sous-projet library cette fois, invalidant
  l'hypothèse ci-dessus.

### Septième vague (après ré-exécution avec le correctif de la sixième vague)

Le correctif de la sixième vague (limiter la cible à `com.android.library`)
échouait EXACTEMENT PAREIL - `Cannot run Project.afterEvaluate(Action)
when the project is already evaluated.`, toujours sans nom de sous-projet
dans le message Gradle. Ceci invalide l'hypothèse de la sixième vague
("seul `:app` est déjà évalué à ce stade") : en réalité, TOUS les sous-
projets (modules de plugins compris) sont déjà évalués au moment où un
bloc `subprojects { ... }` placé APRÈS `subprojects {
project.evaluationDependsOn(":app") }` s'exécute - quel que soit le
sous-projet ciblé. Confirmé par un ticket officiel du dépôt
`flutter/flutter` rapportant le même message d'erreur exact : en
appliquant `dev.flutter.flutter-gradle-plugin`, l'évaluation de `:app`
déclenchée par `evaluationDependsOn(":app")` force EN CASCADE
l'évaluation de TOUS les sous-projets de plugins Flutter (le "plugin
loader" doit inspecter la configuration AGP de chacun) - donc n'importe
quel bloc placé après ce point trouve déjà tout le monde évalué, peu
importe le filtre de plugin appliqué.

Correctif réel : enregistrer le hook `afterEvaluate` (avec le même filtre
`com.android.library` déjà en place) DANS LE PREMIER bloc `subprojects {
... }` du fichier (celui qui relocalise `buildDirectory`, déjà présent
dans le template par défaut et qui n'a jamais posé de problème sur les 6
vagues précédentes), c'est-à-dire AVANT que `evaluationDependsOn(":app")`
n'ait la moindre chance de s'exécuter pour quiconque. Les deux blocs
`subprojects { ... }` d'origine sont fusionnés en un seul pour ce fichier
racine (voir le fichier lui-même pour le détail commenté de ces trois
tentatives successives, gardé intact pour ne pas reproduire deux fois la
même hypothèse non vérifiée).

### Huitième vague - premier bootstrap complet 100% vert (preuve par test obtenue)

Ré-exécution avec le correctif de la septième vague : **succès complet, de
bout en bout**, sur le poste réel de l'utilisateur -

- `flutter create .` / `flutter pub get` / `build_runner build` : OK.
- `flutter analyze` : 0 erreur (14 `info` de style, non bloquants).
- `flutter test` (suite Drift dédiée + suite complète) : **52/52 tests
  passés**, `All tests passed!` sur les deux commandes.
- `flutter build apk --debug` : **`Built build\app\outputs\flutter-apk\
  app-debug.apk`** - premier build APK réussi de tout ce cycle de
  correctifs.

C'est la première exécution réelle, de bout en bout, sans aucun échec -
la preuve par test explicitement demandée par la recette ("Nous voulons
la preuve par test, pas l'affirmation") est désormais obtenue, pas
seulement affirmée. Au total, 8 vagues de correctifs ont été nécessaires
pour passer d'un projet qui n'avait jamais tourné à ce résultat -
récapitulatif des bugs réels trouvés UNIQUEMENT par exécution (aucun
n'aurait été détecté par une simple relecture de code) :
`library;` mal placé, générateurs de code incompatibles avec le SDK
installé, collision de nom colonne/méthode Drift, boilerplate
`flutter create` obsolète, import ambigu, dépendance `record` cassée,
frontières Unicode `\b`/`\w` non gérées par Dart (bug de sécurité
fonctionnelle réel sur le garde-fou anti-attribution), API `share_plus`
non disponible dans la version résolue, verrou fichier Windows au
nettoyage des tests, perte du flag UTC/local par Drift au redémarrage de
l'app, et enfin une dépendance Gradle manquante dans un plugin tiers
combinée à un ordre d'évaluation Gradle particulièrement retors.

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
