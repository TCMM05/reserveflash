# Statut Gate R2 - "Voix + OCR + CandidateFacts"

**Statut : EN COURS. Aucune fonctionnalité R2 n'est déclarée terminée par ce
document.** Conformément à la consigne permanente du projet ("ne pas
déclarer une gate vous-même : livrer les preuves et laisser la recette
indépendante décider"), ce document se limite à consigner l'avancement réel
et les décisions de périmètre prises en cours de route - jamais un verdict.

## Rappel du principe R2 (verbatim de la demande de démarrage)

> "L'IA comprend et structure. Le code contrôle. L'utilisateur confirme la
> vérité. Une information proposée par l'IA n'est jamais une vérité métier
> avant validation explicite de l'utilisateur."

## Baseline

R2 démarre strictement depuis le freeze `r1-final` :

- Commit : `65287f71b17cef483187e3060bb00af1133f39dd`
- Tag : `r1-final`
- Gate R1 : PASS (verdict de la recette indépendante, voir `docs/GATE_R1_STATUS.md`)

## Décisions de périmètre prises en cours de route (transparence)

Ce projet n'a pas accès, dans cet environnement, au cahier des charges
externe `ReserveFlash_Incident_Cahier_des_Charges_v1.1_LocalFirst.pdf`
référencé par `docs/SPEC_BASELINE.md` (SHA-256 vérifié mais fichier non
versionné dans le dépôt git). Les décisions ci-dessous ont donc été prises
sur la base : des deux messages de démarrage R2 reçus de l'équipe, des ADR
déjà présents (`docs/adr/0001-zero-invention-gate.md`,
`docs/adr/0002-local-first-pivot.md`), et du code/schémas déjà existants
avant R2 (`schemas/candidate_fact_set.v1.schema.json`,
`app/domain/liability_guard.py`, tables Drift `LocalCandidateFactSets`/
`AiOperationQueue` déjà migrées). Si l'une de ces décisions s'avère en
contradiction avec une section précise du cahier des charges, elle doit être
corrigée.

1. **Fournisseur IA : OpenAI.** Le scaffolding déjà présent avant R2 était
   déjà nommé pour ça (`RESERVEFLASH_OPENAI_API_KEY`, `AIProviderKind.OPENAI`,
   `app/infrastructure/ai/__init__.py` référençait déjà explicitement
   `openai_provider.py` comme prochaine étape).
2. **OCR : Google ML Kit Text Recognition, on-device.** Conforme à "préférer
   un OCR local/on-device lorsque cela est raisonnable" ; câblé pour
   `document_capture_screen.dart` (bon de livraison) et pour
   `evidence_capture_screen.dart` (preuve photo "Étiquette / référence"
   uniquement, `extractFromPhoto`) - voir section "Avancement réel"
   ci-dessous. Les deux chemins sont désormais validés en conditions réelles
   (voir "Recette terrain").
3. **Benchmark avancé de R6 à R2** (voir `benchmark/README.md`, section
   "Changement de séquencement" pour le détail complet). Le dépôt assignait
   jusqu'ici le corpus de qualification (240 cas visés) au jalon "R6 -
   Qualification" ; la demande de démarrage R2 exige un corpus versionné +
   scorer "avant toute optimisation, dès R2". Corpus R2 réalisé :
   **50 cas** (`benchmark/corpus/r2_corpus_v1.json`), pas 240 - un socle réel
   et versionné, extensible en `v2` sans perdre la traçabilité, plutôt qu'un
   corpus de qualification exhaustif à ce stade.
4. **OCR du BL (fournisseur/transporteur/référence BL/date) traité
   séparément des `CandidateFacts` de l'incident.** Les "champs V1
   prioritaires" listés dans la demande R2 (`issue_type`, `product_label`,
   `product_reference`, `expected_quantity`, `received_quantity`,
   `affected_quantity`, `packaging_condition`, `product_condition`,
   `location_on_item`) correspondent exactement aux champs déjà couverts par
   `schemas/candidate_fact_set.v1.schema.json`. Les métadonnées d'en-tête du
   BL (fournisseur, transporteur, référence BL, date) n'y figurent pas et ne
   sont pas ajoutées à ce schéma v1 (une évolution de schéma versionné suit
   une politique de changement dédiée - voir `schemas/README.md`) : elles
   sont destinées à l'écran `S07`
   (`mobile/lib/features/document_capture/presentation/document_metadata_screen.dart`),
   distinct du flux `CandidateFactSet` de l'incident. Câblé (`[0.3.18]`,
   voir "Avancement réel" ci-dessous) - purement manuel (saisie/correction),
   AUCUNE extraction OCR/IA pour ces champs dans ce lot (décision confirmée
   par ce câblage, pas seulement en attente) : une OCR automatique de ces
   champs resterait une extension de périmètre distincte à confirmer
   explicitement avec l'équipe avant d'être entreprise (nouveau schéma,
   nouveau prompt IA backend, implications coût/benchmark).

## Avancement réel (vérifié par exécution, pas par relecture de code)

### Backend - vérifié dans le sandbox de développement (`pytest`, `ruff`)

- `app/infrastructure/ai/openai_provider.py` : provider réel (transcription
  + extraction), HTTP direct (`httpx`) vers l'API OpenAI - **jamais appelé
  contre le vrai service** (aucun accès réseau vers `api.openai.com` possible
  dans ce sandbox, vérifié). Testé contre un transport HTTP entièrement
  simulé (`httpx.MockTransport`) : succès, timeout, 429, 5xx, JSON invalide
  + 1 réparation contrôlée, échec après réparation.
- `app/domain/candidate_guard.py` + `app/domain/clarification_questions.py` :
  garde-fous déterministes sur les `CandidateFactData` (avant confirmation
  utilisateur), testés notamment sur l'exemple cité par l'équipe
  (`packaging_condition = "transporteur responsable"`).
- `app/api/routes/ai.py` : screening appliqué au point d'entrée unique des
  candidats côté backend (tout provider, mock ou réel).
- `prompts/extraction_fr_v1.txt` : prompt versionné, règles d'or explicites.
- **`pytest` : 116/116 tests verts (3 skips préexistants, indépendants de
  PostgreSQL), `ruff check` propre.** Chiffres obtenus par exécution réelle
  dans ce sandbox, reproductibles (voir CI dès que ce commit sera poussé).

### Benchmark - vérifié dans le sandbox de développement

- `benchmark/corpus/r2_corpus_v1.json` : 50 cas réels, 7 catégories, les 5
  exemples obligatoires de l'équipe repris verbatim.
- `benchmark/scorer.py` : 20 tests verts (prédictions construites à la main,
  aucun appel IA).
- `benchmark/run_scorer.py --provider mock` : **exécuté réellement**,
  pipeline complet corpus -> provider -> `candidate_guard` -> scorer -> rapport
  JSON, sans exception, sur les 50 cas (`benchmark/results/report_mock.json`).
  Les métriques de qualité obtenues avec le mock (ex: `issue_type_accuracy
  = 0.0`) sont **attendues et sans signification qualité** - seul le fait que
  le harnais tourne de bout en bout sans erreur est une preuve à ce stade.
  Un run `--provider openai` avec une vraie clé, produisant des métriques de
  qualité réelles, reste à faire (poste utilisateur).

### Mobile - EN COURS (persistance CandidateFacts posée, reste tout le câblage)

- **Fait, non vérifié par exécution** (aucun SDK Flutter/Dart dans ce
  sandbox - voir `mobile/README.md` ; à valider par `flutter analyze`/
  `flutter test` côté utilisateur, comme pour tout le code Dart de ce
  projet) :
  - `app/domain/fact_set/candidate_fact_data.dart` : miroir Dart de
    `CandidateFactData`/`CandidateField` (`schemas/candidate_fact_set.v1.schema.json`).
  - `app/domain/entities/candidate_fact_set.dart` : entité `CandidateFactSet`.
  - `app/domain/candidate_guard.dart` : miroir Dart de
    `backend/app/domain/candidate_guard.py` (`screenCandidateFactData`),
    réutilise les motifs de `liability_guard.dart` (désormais publics,
    même renommage que le backend R2).
  - `app/domain/clarification_questions.dart` : miroir Dart du catalogue
    contrôlé backend.
  - `IncidentRepository`/`LocalIncidentRepository` : nouvelles méthodes
    `saveCandidateFactSet`/`latestCandidateFactSet` (table
    `LocalCandidateFactSets`, déjà migrée mais jusqu'ici jamais utilisée
    par aucun repository) ; `saveCandidateFactSet` applique
    `screenCandidateFactData` avant toute écriture, même principe que
    `confirmFacts`/`liability_guard.dart`.
  - `app/data/remote/ai_api_client.dart` : `AiApiClient`, miroir de
    `backend/app/api/routes/ai.py` (`/v1/ai/transcribe`, `/v1/ai/extract`),
    au-dessus d'une frontière `AiHttpTransport` testée sans dépendre des
    mécanismes de mock internes à `package:dio` (voir CHANGELOG `[0.3.3]`).
    Retraduit l'enveloppe d'erreur backend en `AiUnavailableException`/
    `AiInvalidOutputException`/`AiRateLimitedException`/
    `AiRequestFailedException` (`app/domain/errors/domain_errors.dart`).
  - `app/core/config/backend_config.dart` + câblage `dioProvider`/
    `aiApiClientProvider` dans `app_providers.dart`.
  - `app/data/local/evidence_storage.dart::readBytes` - relit les octets
    d'une preuve déjà capturée (nécessaire pour transmettre un audio à
    `AiApiClient.transcribe`), frontière stricte disque préservée.
  - `app/data/ai_queue_processor.dart` (`AiQueueProcessor`) - traite les
    items `pending` de `AiOperationQueue`, en DEUX opérations distinctes et
    retentables indépendamment (optimisation coût IA - un échec
    d'extraction ne refait JAMAIS une transcription déjà payée en tokens) :
    `AiOperationKind.transcribeAudio` (transcription seule) met en file
    `AiOperationKind.extractFromTranscript` (extraction + `saveCandidateFactSet`,
    payload = le transcript déjà obtenu). `processPendingOperations` boucle
    sur plusieurs "rounds" pour que la chaîne complète progresse en un seul
    appel côté écran. Disjoncteur de retry uniforme (2 tentatives par
    défaut, volontairement bas - voir section "Exigences coût/tokens IA"
    ci-dessous, point 7) - au-delà, un item reste `pending` en base sans
    être retenté automatiquement, rien n'est supprimé. `extractFromDocument`
    (bon de livraison) et `extractFromPhoto` (preuve photo générique, lot
    suivant) sont câblés (voir ci-dessous) : contrairement à l'audio, l'OCR
    ML Kit tourne SUR L'APPAREIL (gratuit, aucun réseau) directement dans
    `_runExtractFromDocument`/`_runExtractFromPhoto`, sans étape
    intermédiaire mise en file - seul l'appel réseau d'extraction
    (`/v1/ai/extract`, payant) a besoin d'être
    retenté indépendamment, et il l'est déjà via le retry de cet item
    unique. `IncidentRepository.enqueueAiOperation`
    est idempotent par clé `incident_id + operation_type + source_hash +
    pipeline_version` (une mise en file en double ne crée jamais un doublon
    qui déclencherait un appel IA payant superflu).
  - `voice_description_screen.dart` (S10) - SEUL point de déclenchement
    câblé à ce stade : après l'enregistrement d'une note vocale, met en
    file une opération `transcribeAudio` (rattachée à la première anomalie
    de l'incident - limitation V1, cet écran est incident-scope et non
    issue-scope) puis déclenche le traitement au mieux-effort. Entièrement
    best-effort : aucune erreur de cette étape optionnelle n'est jamais
    affichée à l'utilisateur (la note vocale est déjà sauvegardée avec
    succès avant cette étape).
  - `document_capture_screen.dart` (S06) - deuxième point de déclenchement
    câblé (avant ce lot : AUCUN, la photo du BL restait sans traitement IA
    quel qu'il soit). Après l'enregistrement de la photo, met en file une
    opération `extractFromDocument` (rattachée à la première anomalie de
    l'incident - même limitation V1 incident-scope que la note vocale) puis
    déclenche le traitement au mieux-effort - même politique "jamais
    d'erreur affichée pour cette étape optionnelle" que
    `voice_description_screen.dart`. `lib/data/local/ocr_service.dart`
    (nouveau) : interface `OcrService` + implémentation `MlKitOcrService`
    (`google_mlkit_text_recognition`, script Latin) - reconnaissance de
    texte SUR L'APPAREIL, aucun appel réseau, aucun coût IA. Le texte
    reconnu est transmis à `/v1/ai/extract` via le champ `document_text`
    (déjà supporté côté backend et par `AiApiClient.extractCandidateFacts`
    depuis l'origine de R2 - aucun changement backend nécessaire pour ce
    lot). Preuve par test :
    `test/data/ai_queue_processor_test.dart` (2 nouveaux tests - succès
    avec un `OcrService` factice, et échec OCR proprement requeue).
  - `evidence_capture_screen.dart` (S09) - `AiOperationKind.extractFromPhoto`
    câblé (`_runExtractFromPhoto`, même principe qu'`_runExtractFromDocument` -
    item unique, OCR gratuit on-device, voir docstring d'`ExtractFromPhotoPayload`).
    Deux garde-fous spécifiques à ce lot (S09 capture PLUSIEURS photos,
    contrairement au BL qui n'en a qu'une) : (1) SEULE la photo "Étiquette /
    référence" (2e photo guidée) déclenche la mise en file - pas les 3+
    photos capturées, pour ne pas multiplier les appels IA payants sur des
    photos peu susceptibles de contenir du texte (vue générale, gros plan de
    dommage) ; (2) la mise en file est sautée si un `CandidateFactSet`
    existe déjà pour l'anomalie (ex : déjà obtenu depuis le BL à S06/S08),
    pour ne jamais écraser silencieusement un résultat déjà bon par un
    résultat potentiellement moins bon. Preuve par test :
    `test/data/ai_queue_processor_test.dart` (2 nouveaux tests, même forme
    que pour `extractFromDocument`). **Validé en conditions réelles avec un
    résultat correctement rempli** (`[0.3.16]`, voir "Recette terrain"
    ci-dessous) - y compris le cas réel où le garde-fou (2) a dû laisser
    passer une deuxième tentative après un `CandidateFactSet` vide issu du
    BL.
  - `facts_review_screen.dart` (S11) - câblage réel (avant : stub à champs
    codés en dur, jamais branché). Une section par anomalie de l'incident ;
    lit `latestCandidateFactSet`/`latestConfirmedFactSet` via 4 nouveaux
    providers Riverpod (`app_providers.dart`). Fonctionne intégralement
    SANS extraction IA préalable (tous les champs démarrent "non détecté",
    modifiables/marquables UNKNOWN comme n'importe quel champ candidat) :
    c'est la vraie bascule "saisie manuelle/UNKNOWN" exigée par le retour
    d'équipe (exigence coût IA, point 7 - voir section dédiée ci-dessous),
    et elle fonctionne aussi bien "IA jamais lancée" qu'"IA bloquée par le
    disjoncteur de retry", sans distinction nécessaire côté UI. "Valider les
    faits de cette anomalie" appelle réellement `IncidentRepository.confirmFacts`
    (persistance vérifiée par re-lecture directe du repository dans les
    tests, pas seulement par l'affichage écran - voir
    `test/features/facts_review_screen_test.dart`). "Générer la réserve"
    appelle `composeAndSaveReserve` puis navigue vers `reserve_screen.dart`
    (désormais activé également, pousse `incidentId` via `extra`
    go_router). Affiche un bandeau informatif si un item de la file IA est
    encore en cours ou bloqué par le disjoncteur pour cette anomalie
    (`pendingAiOperationsProvider`), avec un bouton de rafraîchissement
    manuel dans l'AppBar. Rendu désormais accessible depuis
    `checklist_screen.dart` (item optionnel "Revue des faits (IA) et
    réserve", SANS incidence sur `canFinish`/"Terminer le dossier" - critère
    R1 inchangé).
  - `reserve_screen.dart` (S12) - câblage réel (avant : texte d'exemple
    codé en dur, `_sampleReserveText`). Affiche désormais
    `latestReserveText(incidentId)` (nouveau provider) tel quel, ou un
    message explicite si aucune réserve n'a encore été composée pour ce
    dossier - jamais de texte factice. "Modifier les faits"/"Continuer"
    inchangés (retour à l'écran précédent / vers `final_document_screen.dart`,
    toujours un stub, hors périmètre - voir demande corrective R1).
  - Déclenchement automatique de la file au retour réseau (`[0.3.17]`) -
    `mobile/lib/core/network/connectivity_watcher.dart` (interface
    `ConnectivityWatcher` + implémentation `ConnectivityPlusWatcher`,
    nouvelle dépendance `connectivity_plus`) et
    `mobile/lib/data/ai_queue_connectivity_listener.dart`
    (`AiQueueConnectivityListener`, une seule instance pour toute la durée
    de vie de l'app, voir câblage `lib/main.dart`/`app_providers.dart`) :
    `AiQueueProcessor.processPendingOperations` est désormais relancé
    automatiquement à chaque transition hors-ligne -> en ligne détectée, en
    plus des déclenchements existants (juste après une capture, ou
    manuellement depuis `facts_review_screen.dart`). Correctif `[0.3.20]`
    trouvé en préparant le test terrain (avant tout retest utilisateur) :
    le traitement automatique ne prévenait jamais l'UI de son résultat
    (`notifyDataChanged` manquant) - un écran déjà ouvert au moment du
    retour réseau n'aurait affiché le résultat qu'après une action
    explicite. Preuve par test :
    `test/data/ai_queue_connectivity_listener_test.dart` (10 tests, watcher
    fait à la main). **Validé en conditions réelles** (2026-08-22, voir
    "Recette terrain" ci-dessous).
- **Limites documentées de ce câblage (V1, pas des bugs)** :
  - TOUS les champs V1 prioritaires doivent être résolus pour valider une
    anomalie - pas de distinction "champ critique pour CE type d'anomalie"
    vs "champ secondaire" (même simplification que le disjoncteur de retry
    uniforme de `ai_queue_processor.dart`).
  - Le type d'anomalie confirmé reste TOUJOURS celui choisi à l'étape S08
    (`IssueTypeScreen`) : si `issueTypeCandidate` de l'IA diverge, l'écran
    l'affiche à titre informatif mais ne le substitue jamais silencieusement
    (GATE zéro invention) - changer le type nécessite de revenir à S08.
  - `CandidateField.confidence`/`.ambiguous` (reçus du backend) ne sont pas
    encore affichés dans l'UI (seule la distinction "compris par l'IA" vs
    "confirmé"/"corrigé"/"inconnu" l'est) - raffinement possible non
    nécessaire pour ce premier câblage bout en bout.
  - Le bouton "Générer la réserve" (navigation go_router vers
    `reserve_screen.dart`) n'est PAS couvert par un test automatisé dans ce
    sandbox (ce fichier n'installe pas de vrai `GoRouter` - hors scope de ce
    câblage) ; `reserve_screen_test.dart` couvre séparément l'affichage réel
    de `ReserveScreen` en l'atteignant directement, sans navigation - même
    limite déjà documentée pour l'audio dans `evidence_viewer_test.dart`.
  - `document_metadata_screen.dart` (S07, `[0.3.18]`) - écran réel
    (fournisseur/transporteur/référence BL/date du BL, tous optionnels),
    câblé entre S06 et S08 dans le parcours nominal (avant ce lot :
    orphelin, jamais atteint par aucune navigation). `deliveryDate`
    (nouveau champ, migration `v2 -> v3` additive) répercuté aussi dans
    `incident_detail_screen.dart` (S17) pour rester corrigeable après
    coup. Preuve par test : `test/data/local_incident_repository_test.dart`
    (persistance de `deliveryDate`, et nouveau test dédié pour
    `updateIncidentMetadata` - jusqu'ici sans aucune couverture malgré 3
    écrans appelants). Pas de widget test dédié pour cet écran (même
    précédent que `create_incident_screen.dart`/`incident_detail_screen.dart`).
    **Validé en conditions réelles** (2026-08-22, voir "Recette terrain"
    ci-dessous) : l'écran apparaît bien juste après la photo du BL, avant le
    type de problème, et les 4 champs (dont `deliveryDate`, nouveau)
    persistent correctement et restent corrigeables depuis S17.
- **Reste à faire** :
  - `final_document_screen.dart` (S13, photo du document complété) - reste
    un `RfScreenStub`, explicitement hors périmètre R1 (F13/F14).

## Exigences coût/tokens IA (retour équipe, 2026-08-20)

L'équipe a fait remonter 14 exigences explicites de maîtrise des coûts/
tokens IA pour R2. Inventaire honnête, point par point, vérifié par lecture
de code (pas une auto-évaluation optimiste) - "présent" signifie vérifié
dans le code cité, jamais "je pense que c'est fait".

1. **Aucun retraitement inutile (empreinte/hash, jamais sur simple
   réaffichage).** ⚠️ Partiel. Ouvrir/fermer un écran, redémarrer l'app ou
   rouvrir un dossier ne déclenche AUCUN appel IA (l'enqueue n'existe que
   dans `voice_description_screen.dart::_stopAndSaveRecording`, jamais dans
   `build()`/`initState()`) - **conforme**. En revanche, il n'existe PAS
   encore de vérification "un `CandidateFactSet` valide existe déjà pour
   cette empreinte source, ne pas rappeler l'IA" avant l'enqueue lui-même -
   seule la déduplication EN FILE (point 8) existe. Pas commencé : la
   logique "source inchangée + résultat déjà valide -> skip silencieux".
2. **Transcription séparée de l'extraction.** ✅ Fait (`[0.3.5]`) -
   `AiQueueProcessor` : `transcribeAudio` puis `extractFromTranscript`,
   deux opérations distinctes et retentables indépendamment. Backend :
   `/v1/ai/transcribe` et `/v1/ai/extract` étaient déjà deux routes
   séparées depuis l'origine.
3. **OCR local prioritaire (ML Kit).** ✅ Fait, pour le BL ET pour la preuve
   photo générique - `document_capture_screen.dart` (chaque photo de bon de
   livraison) et `evidence_capture_screen.dart` (photo "Étiquette /
   référence" uniquement, voir garde-fous ci-dessus) mettent désormais en
   file une extraction OCR (`lib/data/local/ocr_service.dart`, ML Kit
   on-device, aucun coût IA). Test terrain réel effectué pour le BL ET pour
   la preuve photo générique (voir "Recette terrain").
4. **Prompt minimal (pas d'historique, pas de dump complet).** ✅ Fait côté
   backend (vérifié) - `openai_provider.py` : le message utilisateur ne
   contient QUE le transcript et/ou le texte OCR, jamais l'historique de
   l'incident ni les faits déjà confirmés. Mobile : `AiApiClient`/`AiQueueProcessor`
   n'envoient que `transcript`/`document_text` + `prompt_version`, jamais un
   dossier complet (cohérent avec le payload minimal de `AiOperationQueue`,
   point 14 de la demande R1/R2).
5. **Sortie courte, structurée, limite de tokens.** ⚠️ Partiel. Le backend
   utilise déjà le mode JSON (`response_format: json_object`) mais PAS le
   mode "JSON Schema strict" d'OpenAI, et n'impose aucun `max_tokens`/limite
   de sortie explicite. Pas commencé : plafond de tokens de sortie, passage
   en mode schema strict.
6. **Modèle le moins cher qui franchit le benchmark.** ⚠️ Partiel. `gpt-4o-mini`
   (déjà un choix économique) est configuré par défaut, mais AUCUNE
   comparaison multi-modèles n'existe dans `benchmark/run_scorer.py`
   (`--provider` ne distingue que `mock`/`openai`, jamais entre plusieurs
   modèles OpenAI) - le choix n'est donc pas encore justifié empiriquement
   par le benchmark, seulement par défaut de configuration. Pas commencé :
   harnais de comparaison multi-modèles.
7. **Retry strictement limité (1 appel + 1 réparation, jamais de boucle
   automatique, bascule vers saisie manuelle/UNKNOWN sur erreur
   persistante).** ✅ Fait, aux deux niveaux. Backend (niveau "un appel
   modèle") : `openai_provider.py` fait 1 appel, et EXACTEMENT 1 tentative
   de réparation si la sortie est invalide, sans boucle (voir docstring du
   module) - conforme depuis avant ce retour d'équipe. Mobile (niveau "file
   d'attente dans le temps") : le disjoncteur de `AiQueueProcessor` est à 2
   tentatives (`[0.3.5]`), ET `facts_review_screen.dart` (`[0.3.6]`) offre
   désormais réellement la bascule "saisie manuelle/UNKNOWN" - chaque champ
   V1 prioritaire est éditable/marquable UNKNOWN indépendamment de l'état de
   la file IA (jamais bloquant), que l'IA n'ait jamais tourné, soit encore
   en cours, ou ait atteint le disjoncteur. Persistance de cette bascule
   vérifiée par test (`test/features/facts_review_screen_test.dart`, groupe
   "bascule manuelle/UNKNOWN"), pas seulement par relecture de code. **Point
   ouvert inchangé** : la valeur "2" reste un choix par défaut prudent, pas
   une valeur confirmée par l'équipe - à ajuster si vous avez une préférence
   précise. **Nuance non couverte** : l'écran ne distingue pas visuellement
   "IA jamais tentée" de "disjoncteur épuisé après 2 échecs" (les deux
   affichent le même formulaire manuel fonctionnel) - un bandeau informatif
   distinct existe uniquement pour "en cours"/"bloqué après échecs" via
   `pendingAiOperationsProvider`, pas pour "jamais lancé".
8. **Déduplication des jobs (`incident_id + operation_type + source_hash +
   pipeline_version`).** ✅ Fait (`[0.3.5]`), composition EXACTE demandée -
   `aiOperationIdempotencyKey`/`aiPipelineVersion` dans `ai_queue_processor.dart`,
   `IncidentRepository.enqueueAiOperation` vérifie l'existence avant toute
   insertion.
9. **Journal de consommation obligatoire (tokens, coût, latence, retry,
   modèle...).** ✅ Fait (`[0.3.22]`), architecture **logs structurés
   uniquement** décidée explicitement avec l'utilisateur (pas de nouvelle
   table Postgres/migration - le chemin `/v1/ai/*` reste sans état, voir
   point 11). `OpenAIProvider.transcribe()`/`extract_candidate_facts()`
   (`backend/app/infrastructure/ai/openai_provider.py`) lisent
   `usage.prompt_tokens`/`completion_tokens`/`total_tokens`/`cached_tokens`
   de chaque réponse OpenAI quand présents ; `TranscriptionResult`/
   `ExtractionResult` (`app/application/ports.py`) les portent, ainsi que
   `estimated_cost_usd` (table de tarification codée en dur,
   `app/infrastructure/ai/pricing.py`) et `retry_count`. Une ligne de log
   structuré PERMANENTE (`app/infrastructure/ai/usage_journal.py`,
   `[RF][ai-usage]`) est émise pour chaque appel terminé, succès OU échec -
   y compris une sortie invalide après réparation (`AIInvalidOutputError`
   étendue pour porter les tokens/coût déjà consommés). **✅ Validé en
   conditions réelles (2026-08-22)** - test terrain via l'app mobile, deux
   vraies lignes `[RF][ai-usage]` observées dans la console `uvicorn`, coût
   vérifié à la main (`(1455×0.15 + 34×0.60)/1e6 = 0.00023865$`, exact) -
   voir "Recette terrain" ci-dessous. **Limitation assumée** : logs
   uniquement = pas de requête agrégée fiable côté backend sans réanalyser
   les logs, pas de rétention garantie au-delà de la config de logging du
   déploiement, pas d'historique multi-instance unifié.
10. **Métriques coût dans le benchmark (coût moyen/médian/p95, tokens,
    cache, appels par dossier).** ✅ Fait (`[0.3.22]`) - `benchmark/scorer.py`
    (`AggregateMetrics`) calcule désormais coût moyen/médian/p95, tokens
    moyen/médian/p95, `cache_rate` (depuis les tokens cachés OpenAI) et
    `mean_calls_per_case` (reflète les tentatives de réparation), sur tous
    les cas ayant une donnée d'usage (y compris les sorties invalides -
    coût réel même en cas d'échec). `run_scorer.py` capture ces champs
    depuis `ExtractionResult`/`AIInvalidOutputError` et les affiche. `None`
    (jamais 0) pour `--provider mock`, qui ne fournit aucune donnée
    d'usage. **Le mécanisme sous-jacent (capture des tokens/coût par appel,
    point 9) est validé en conditions réelles** (voir ci-dessus), mais
    l'agrégation elle-même (moyenne/médiane/p95 sur les 50 cas du corpus)
    n'a toujours pas tourné avec un vrai run `--provider openai` - le
    premier essai a tourné par erreur en mode `mock` (voir "Recette
    terrain" ci-dessous), à refaire.
11. **Protection environnement TEST (clé séparée, quotas configurables).**
    ❌ Pas commencé - une seule variable `RESERVEFLASH_OPENAI_API_KEY`,
    aucune distinction DEV/TEST/PROD, aucun quota applicatif. Note : la
    provision réelle d'un projet/clé OpenAI séparé pour TEST reste de toute
    façon un geste utilisateur (aucune clé OpenAI n'est jamais manipulée
    dans ce sandbox, contrainte permanente du projet) - ce qui PEUT être
    fait ici est la plomberie de config (lecture de variables d'env
    séparées, quotas applicatifs), pas la clé elle-même. Non traité dans le
    lot `[0.3.22]` (hors périmètre demandé - le retour équipe ciblait le
    trio 9/10/12).
12. **Circuit breaker budgétaire production.** ✅ Fait (`[0.3.22]`) - nouveau
    `AIBudgetExceededError` (`app/domain/errors.py`) mappé en **402
    AI_BUDGET_EXCEEDED** (`app/api/errors.py`). `AiBudgetGuard`
    (`app/infrastructure/ai/budget_guard.py`) : compteur de dépense EN
    MÉMOIRE PROCESSUS (singleton `@lru_cache`, `app/api/deps.py::get_ai_budget_guard`),
    consulté avant tout appel HTTP payant, alimenté après chaque appel dont
    le coût est connu. Nouveau `Settings.ai_daily_budget_usd`
    (`RESERVEFLASH_AI_DAILY_BUDGET_USD`), **désactivé par défaut**.
    L'enregistrement de la dépense (`record_spend`) est **validé en
    conditions réelles** (les deux appels du 2026-08-22 ont bien alimenté le
    compteur, voir point 9 ci-dessus) - mais le BLOCAGE effectif
    (`check_budget_or_raise` levant `AIBudgetExceededError` une fois un
    plafond dépassé) n'a lui **pas encore** été testé en conditions réelles
    (aucun `RESERVEFLASH_AI_DAILY_BUDGET_USD` n'était configuré pendant ce
    test) - test simple et peu coûteux à faire : configurer un plafond très
    bas (ex: `0.0001`) et vérifier qu'un appel suivant est bien refusé en
    402. **Limitations assumées** : repart à zéro à chaque redémarrage du
    process (pas de fenêtre "jour calendaire" au sens strict malgré le
    nom), pas partagé entre instances déployées, et le comportement du
    client mobile face à un 402 sur `/v1/ai/*` n'a **pas** été vérifié.
13. **Prompt caching (préfixe stable avant données variables).** ✅ Fait,
    déjà conforme par construction - `openai_provider.py` charge le prompt
    système (`prompts/extraction_fr_v1.txt`) tel quel comme préfixe fixe, le
    contenu variable (transcript/OCR) n'arrive qu'ensuite dans le message
    utilisateur. **✅ Validé en conditions réelles (2026-08-22)** : sur le
    second appel `[RF][ai-usage]` observé en test terrain, OpenAI a
    effectivement réutilisé `cached_tokens=1408` sur `prompt_tokens=1487`
    (~95%) - le cache fonctionne réellement, pas seulement par construction
    du prompt.
14. **Aucun traitement IA automatique au simple affichage (jamais dans
    `build()`/`initState()`/navigation/polling).** ✅ Fait, vérifié - le seul
    point d'enqueue mobile (`voice_description_screen.dart`) est déclenché
    UNIQUEMENT par l'action explicite "arrêter l'enregistrement", jamais par
    le cycle de vie du widget. Les routes backend `/v1/ai/*` sont de simples
    endpoints HTTP, appelés uniquement par une action explicite du client -
    aucun polling ni déclenchement automatique côté serveur.

**Synthèse (mise à jour `[0.3.22]`, puis test terrain 2026-08-22)** : 9
points désormais conformes (2, 3, 4, 7, 9, 10, 12, 13, 14), 3 partiellement
conformes avec du travail réel restant (1, 5, 6), 1 pas commencé (11 - hors
périmètre du lot `[0.3.22]`, volontairement non traité, voir sa fiche
ci-dessus). Les points 9/10/12 (le trio explicitement signalé "à traiter
comme un lot dédié") ont été implémentés et testés (`pytest`/`ruff`
exécutés dans ce sandbox) via l'architecture "logs structurés uniquement"
décidée avec l'utilisateur, PUIS le point 9 (journal) et le point 13 (cache)
ont été **validés en conditions réelles** le jour même (test terrain via
l'app mobile, vraies lignes `[RF][ai-usage]` avec de vrais tokens/coût
OpenAI - voir "Recette terrain" ci-dessous). Ce qui reste non validé en
conditions réelles : le blocage effectif du disjoncteur de budget (point
12 - la mesure de dépense, elle, est validée réelle) et l'agrégation
benchmark sur les 50 cas (point 10 - le premier essai a tourné par erreur
en mode `mock`). Voir `CHANGELOG.md [0.3.22]` pour le détail complet et les
limitations assumées (disjoncteur non persistant/non multi-instance,
journal non requêtable sans réanalyser les logs, comportement mobile face
à un 402 non vérifié). Les points 5/6
nécessitent toujours des runs `--provider openai` réels avec une vraie clé
(poste utilisateur, aucun accès réseau `api.openai.com` dans ce sandbox)
pour être validés empiriquement, pas seulement codés - et bénéficieront
désormais des métriques coût/tokens du point 10 une fois ce run effectué.

### Recette terrain - PREMIÈRE VALIDATION RÉELLE (émulateur, PAS encore appareil physique ni recette indépendante)

Mise à jour 2026-08-20 : première exécution réelle de la chaîne complète R2
(capture -> transcription IA -> extraction IA -> revue -> confirmation ->
génération de réserve) sur un **émulateur** Android (Android Studio AVD),
backend local (`uvicorn`) et une vraie clé OpenAI fournie et configurée par
l'utilisateur lui-même (jamais transmise/manipulée par l'assistant, voir
`docs/security.md`, GATE secret). Voir `CHANGELOG.md [0.3.8]` pour le détail
complet (bugs trouvés/corrigés pendant ce diagnostic, dont [0.3.7]).

Observé et conforme : extraction correcte des champs V1 prioritaires depuis
une note vocale réelle, et **GATE zéro invention confirmé en conditions
réelles** - une suggestion de type d'anomalie de l'IA différente du type
confirmé par l'utilisateur à S08 n'a jamais écrasé ce dernier, affichée
uniquement en bandeau informationnel.

**Mise à jour 2026-08-20 (suite) - OCR BL testé en conditions réelles** :
chaîne complète confirmée fonctionnelle de bout en bout (capture -> mise en
file -> OCR ML Kit on-device -> `/v1/ai/extract` -> GATE zéro invention ->
revue des faits) - voir `CHANGELOG.md [0.3.10]`/`[0.3.11]` pour le détail
complet (un vrai bug de séquencement trouvé et corrigé au passage : la mise
en file OCR ne se déclenchait jamais dans le parcours nominal avant S08).
Sur ce premier essai, texte manuscrit + bruit webcam d'émulateur -> OCR a
reconnu un texte erroné ("Kolorena PRC 4SO" au lieu de "Perceuse ... PRC
450") -> "Non détecté" à raison (GATE zéro invention, pas un bug). Limite
ML Kit/manuscrit documentée dans `mobile/README.md` et la docstring de
`MlKitOcrService`.

**Mise à jour 2026-08-20 (suite, résultat positif) - texte imprimé testé** :
même parcours refait avec le même texte affiché en gros (imprimé, non
manuscrit) sur un écran de téléphone plutôt qu'écrit à la main. Résultat
conforme à l'attendu : `facts_review_screen.dart` affiche "Produit :
perceuse", "Référence produit : PRC 450", "Quantité attendue : 10" (badge
"Compris par l'IA" sur chaque champ). **OCR confirmé fonctionnel de bout en
bout avec un résultat correctement rempli**, pas seulement le câblage - au
même niveau de validation terrain que la note vocale (`[0.3.8]`). Voir
`CHANGELOG.md [0.3.12]`.

**Mise à jour 2026-08-22 - bug `extractFromPhoto` trouvé et corrigé via les
logs `[RF]`, puis validé en conditions réelles** : premier test terrain
d'`extractFromPhoto` (`[0.3.13]`) resté sans effet visible côté écran - le
garde-fou anti-écrasement bloquait à tort sur un `CandidateFactSet` VIDE
(OCR du BL n'ayant rien reconnu), diagnostiqué immédiatement grâce aux logs
`[RF]` (`[0.3.14]`, adoptés sur consigne explicite de l'utilisateur : "pour
faire des tests il faut toujours insérer des logs pour facilement détecter
les problèmes"). Corrigé en `[0.3.15]`. Un retest a d'abord montré le même
log qu'avant le correctif ; vérification du commit `7c4d48f` sur `master`
dans ce sandbox a confirmé que le correctif était bien présent et correct
côté livraison - le retest suivant, avec le correctif effectivement actif,
a confirmé le bon fonctionnement : le BL a de nouveau produit un OCR
inexploitable ("BIF"), le garde-fou corrigé a laissé passer une deuxième
tentative sur la photo d'étiquette, et celle-ci a produit un résultat
correct (Produit = perceuse, Référence = PRC 450, Quantité attendue = 10).
**`extractFromPhoto` est désormais validé en conditions réelles avec un
résultat correctement rempli**, au même niveau que le BL et la note vocale.
Voir `CHANGELOG.md [0.3.15]`/`[0.3.16]`.

**Mise à jour 2026-08-22 (suite) - S07 "Vérifier les informations" validé
en conditions réelles** : après régénération du code Drift
(`dart run build_runner build --delete-conflicting-outputs`, nécessaire
suite à l'ajout de `deliveryDate` à `LocalIncidents` - `flutter analyze`
propre, 119/119 tests passés), test terrain confirmé : l'écran S07
apparaît bien juste après la photo du bon de livraison, avant l'écran du
type de problème (le parcours ne saute plus directement de S06 à S08).
Fournisseur/transporteur/référence BL/date du BL saisis à S07 persistent
correctement et restent visibles/corrigeables depuis le détail du dossier
(S17, capture d'écran de la fenêtre "Corriger les informations" avec les 4
champs pré-remplis, dont "Date du BL : 11/09/2023"). Voir
`CHANGELOG.md [0.3.18]`.

**Mise à jour 2026-08-22 (suite) - déclenchement au retour réseau validé
en conditions réelles** : un bug (`notifyDataChanged` manquant, voir
`CHANGELOG.md [0.3.20]`) a été trouvé et corrigé en préparant ce test,
AVANT que l'utilisateur ne le tente - sans ce correctif, le test aurait
semblé échoué (donnée bien enregistrée en base mais jamais montrée à
l'écran sans action manuelle). Une fois corrigé : réseau coupé avant la
capture de la photo "Étiquette / référence" (item resté `pending`), photo
prise, réseau rétabli SANS fermer l'app entre-temps (condition nécessaire
au déclenchement - voir docstring `ConnectivityPlusWatcher`), résultat
confirmé : le champ se remplit automatiquement, sans aucune action
utilisateur après la reconnexion. **Déclenchement automatique au retour
réseau validé en conditions réelles.** Voir `CHANGELOG.md [0.3.17]`/
`[0.3.20]`.

**Mise à jour 2026-08-22 (suite) - gouvernance coût/tokens IA (points
9/10/12) implémentée côté backend** : journal de consommation (logs
structurés), coût estimé par appel, disjoncteur de budget en mémoire
process - voir `CHANGELOG.md [0.3.22]` et la section "Exigences coût/tokens
IA" ci-dessus pour le détail complet. Testé (`pytest`/`ruff`) dans ce
sandbox, backend Python disponible ici.

**Mise à jour 2026-08-22 (suite) - point 9 (journal de consommation) et
point 13 (prompt caching) validés en conditions réelles** : test terrain
via l'app mobile (photos capturées, `extractFromDocument`/`extractFromPhoto`),
backend local avec `RESERVEFLASH_AI_PROVIDER=openai` et une vraie clé.
Deux lignes `[RF][ai-usage]` réelles observées dans la console `uvicorn`,
avec de vrais tokens OpenAI (1455/1487 prompt, 34/184 completion) et un
coût calculé correctement (`0.00023865$`, `0.00033345$` - vérifié à la main :
`(1455×0.15 + 34×0.60)/1e6 = 0.00023865`, exact). Le deuxième appel montre
`cached_tokens=1408` : le prompt caching OpenAI (point 13) fonctionne bien
en pratique, pas seulement par construction du prompt. **Nuances qui
restent ouvertes** : le disjoncteur de budget (point 12) a bien enregistré
la dépense (`record_spend` appelé) mais son comportement de BLOCAGE
(`check_budget_or_raise` levant réellement une erreur une fois un plafond
dépassé) n'a pas encore été testé en conditions réelles - aucun
`RESERVEFLASH_AI_DAILY_BUDGET_USD` n'était configuré pendant ce test. Le
benchmark complet (point 10, agrégation sur les 50 cas du corpus) n'a lui
toujours pas tourné en conditions réelles - le premier essai a tourné par
erreur en mode `mock` (variables d'environnement PowerShell perdues entre
deux fenêtres), sans appel OpenAI réel.

Ce qui N'EST PAS encore fait, à ne pas confondre avec ce qui précède :
- Test sur un **appareil Android physique réel** (celui-ci était un
  émulateur) - networking/latence/micro/caméra réels peuvent différer.
- Test avec un **vrai bon de livraison papier réel** (celui-ci était un
  texte imprimé affiché sur un écran, pas du papier photographié) - à faire
  idéalement avant appareil physique.
- Exigences coût/tokens IA, points 9/10/12 : point 9 (journal) et point 13
  (cache) **validés en conditions réelles** (voir ci-dessus). Point 12
  (disjoncteur) : la mesure de dépense est validée réelle, mais pas encore
  le blocage effectif à un plafond. Point 10 (métriques benchmark) : code
  testé en sandbox uniquement, pas encore exécuté avec un vrai run
  `--provider openai` (voir section "Avancement réel" ci-dessus pour le
  détail des limitations assumées).
- **La recette indépendante elle-même** : cette session de test a été menée
  par l'utilisateur avec l'assistant en accompagnement, ce n'est PAS la
  recette indépendante prévue par le processus GATE. Aucun verdict "GATE R2
  PASS" n'est déclaré ici ni ailleurs par ce document ou son auteur.

## Prochaines étapes

1. Mobile : `document_metadata_screen.dart` (S07) : FAIT et **validé en
   conditions réelles** (`[0.3.18]`, voir "Recette terrain" ci-dessus).
   Déclenchement de la file au retour réseau : FAIT et **validé en
   conditions réelles** (`[0.3.17]`/`[0.3.20]`, voir "Recette terrain"
   ci-dessus - un bug d'UI trouvé et corrigé au passage, `[0.3.20]`). Ces
   deux points de "câblage mobile manquant" (voir échange précédent) sont
   désormais entièrement traités. Écran de revue réel et bascule
   manuelle/UNKNOWN sur disjoncteur de retry : FAIT (`[0.3.6]`, voir section
   "Avancement réel" ci-dessus). OCR (ML Kit) sur le BL : FAIT et **validé en
   conditions réelles avec un résultat correctement rempli** (`[0.3.9]` à
   `[0.3.12]`, voir "Recette terrain" ci-dessus). OCR sur preuve photo
   générique (`extractFromPhoto`) : FAIT (`[0.3.13]`) et **validé en
   conditions réelles avec un résultat correctement rempli** (`[0.3.16]`,
   voir "Recette terrain" ci-dessus). Reste un test avec un vrai bon de
   livraison papier (pas un écran) pour le BL.
2. Exigences coût/tokens IA (retour équipe, voir section dédiée) : journal
   de consommation backend (point 9), métriques coût benchmark (point 10),
   circuit breaker budgétaire (point 12) - **implémentées et testées en
   sandbox** (`[0.3.22]`), **pas encore validées en conditions réelles**
   (voir "Recette terrain" ci-dessus). Point 11 (séparation DEV/TEST/PROD
   des clés) reste non traité, hors périmètre de ce lot.
3. Recette terrain avec clé OpenAI réelle sur appareil Android réel
   (protocole fourni par l'équipe, section "Test terrain obligatoire") - à
   l'occasion de ce run, vérifier aussi que le journal `[RF][ai-usage]`
   s'affiche bien côté serveur réel (pas seulement dans les tests).
4. Run `benchmark/run_scorer.py --provider openai` réel (+ comparaison
   multi-modèles, point 6 de la section coût/tokens), rapport versionné -
   inclura désormais les métriques coût/tokens réelles du point 10.
5. Livraison `r2-candidate` (ZIP, commit, tag, APK CI, SHA-256, ce document
   mis à jour, `R2_BENCHMARK_REPORT.md`, captures, preuve du test terrain) -
   soumission à la recette indépendante. **Aucun verdict "GATE R2 PASS" ne
   sera déclaré par ce document ni par son auteur.**
6. R3 : aucun développement avant validation du Gate R2 par la recette
   indépendante.
