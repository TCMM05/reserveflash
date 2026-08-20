# Changelog

Format inspiré de [Keep a Changelog](https://keepachangelog.com/fr/).

## [0.3.13] - R2 - OCR on-device (ML Kit) sur preuve photo générique (mobile) - 2026-08-20

Septième lot mobile de R2. Étend le lot OCR BL (`[0.3.9]`, validé terrain en
`[0.3.12]`) à `AiOperationKind.extractFromPhoto` (preuve photo générique,
S09 `evidence_capture_screen.dart`), jusqu'ici non câblé
(`_isSupported` retournait `false`).

1. **`mobile/lib/data/ai_queue_processor.dart`** - `extractFromPhoto` passe
   de "non supporté" à câblé (`_runExtractFromPhoto`), en tout point
   identique à `_runExtractFromDocument` (OCR gratuit on-device, un seul
   item, même raisonnement que `[0.3.9]`). Nouveau
   `ExtractFromPhotoPayload` (même forme qu'`ExtractFromDocumentPayload` -
   référence vers l'`EvidenceAsset`, jamais le texte OCR - classe distincte
   car `AiOperationKind` reste la source de vérité du type d'opération, pas
   le nom de la classe payload).
2. **`mobile/lib/features/evidence_capture/presentation/evidence_capture_screen.dart`** -
   après l'écriture d'une photo sur disque, met en file `extractFromPhoto`
   au mieux-effort - MAIS avec deux garde-fous spécifiques à cet écran
   (contrairement au BL, S09 capture plusieurs photos guidées) :
   - **SEULE la photo "Photo 2 - Étiquette / référence"** déclenche la mise
     en file, pas les 3+ photos capturées (vue générale, gros plan de
     dommage) - la plus susceptible de contenir du texte utile, pour ne pas
     multiplier les appels IA payants sur des photos qui n'en contiennent
     probablement pas.
   - **Sautée si un `CandidateFactSet` existe déjà** pour l'anomalie (ex :
     déjà obtenu depuis le BL à S06/S08) - `CandidateFactSet` étant
     append-only (`latestCandidateFactSet` renvoie le plus récent), enqueue
     sans cette vérification aurait pu écraser silencieusement dans l'UI un
     résultat déjà bon par un résultat moins bon issu d'une simple photo
     d'étiquette.
   Contrairement à S06 (voir le bug corrigé en `[0.3.10]`), cette anomalie
   existe FORCÉMENT à ce stade : S08 (`issueType`) la crée, S09
   (`evidenceCapture`) vient après dans le parcours nominal - aucun risque
   de no-op silencieux équivalent ici.
3. **Backend : AUCUN changement** (même raison qu'en `[0.3.9]` -
   `/v1/ai/extract` acceptait déjà `document_text` depuis l'origine de R2).
4. **`mobile/test/data/ai_queue_processor_test.dart`** - 2 nouveaux tests
   (même forme que pour `extractFromDocument` en `[0.3.9]`) : succès
   OCR+extraction en un seul item, et échec OCR propre (requeue pending,
   jamais de perte). Le test `extractFromPhoto (OCR pas encore câblé) ->
   skipped` (obsolète, l'opération est maintenant supportée) a été
   remplacé par ce nouveau groupe.

Non testé en conditions réelles à ce stade (contrairement au BL, validé
terrain en `[0.3.12]`) - à faire au prochain test terrain (voir
`docs/GATE_R2_STATUS.md`, "Reste à faire").

## [0.3.12] - R2 - OCR validé en conditions réelles avec un résultat correctement rempli - 2026-08-20

Suite immédiate de `[0.3.11]`. Même parcours de test refait avec le même
texte (produit/référence/quantités), cette fois affiché en gros IMPRIMÉ sur
un écran de téléphone plutôt qu'écrit à la main, photographié via la webcam
de l'émulateur (toujours en mode Webcam0 + cold boot, voir
`mobile/README.md`).

Résultat conforme à l'attendu sur `facts_review_screen.dart` : "Produit :
perceuse", "Référence produit : PRC 450", "Quantité attendue : 10", chaque
champ avec le badge "Compris par l'IA". **OCR (ML Kit) confirmé fonctionnel
de bout en bout avec un résultat correctement rempli** - capture -> mise en
file (`[0.3.10]`) -> OCR on-device -> `/v1/ai/extract` -> GATE zéro
invention -> revue des faits. Même niveau de validation terrain que la note
vocale (`[0.3.8]`) : première preuve réelle, pas encore appareil physique ni
recette indépendante (voir `docs/GATE_R2_STATUS.md`, aucun verdict "GATE R2
PASS" déclaré).

Aucun changement de code dans ce lot - uniquement la confirmation terrain et
la mise à jour de `docs/GATE_R2_STATUS.md` (section "Recette terrain").

## [0.3.11] - R2 - OCR confirmé fonctionnel de bout en bout ; limite manuscrit/bruit identifiée - 2026-08-20

Suite immédiate de `[0.3.10]`. Après correctif de mise en file et
relèvement de la limite de dépenses OpenAI (voir plus bas, hors code), le
test terrain butait encore sur "Non détecté" malgré un `POST
/v1/ai/extract` en `200 OK`. Un log temporaire du texte reconnu par ML Kit
(`mobile/lib/data/local/ocr_service.dart`, ajouté puis retiré dans la
foulée - même discipline que les diagnostics précédents) a confirmé la
cause : sur la photo de test (texte manuscrit cursif, webcam d'émulateur
bruitée), ML Kit a reconnu **"Kolorena PRC 4SO"** au lieu de "Perceuse ...
PRC 450" - un texte réel mais largement erroné. L'extraction IA en aval a
donc, à raison, trouvé aucun champ fiable dans ce texte : **le "Non détecté"
observé est le GATE zéro invention qui fonctionne comme prévu, pas un bug**.

**Chaîne confirmée fonctionnelle de bout en bout par ce test** : capture
photo -> mise en file (correctif `[0.3.10]`) -> OCR ML Kit on-device ->
`POST /v1/ai/extract` -> réponse IA -> GATE zéro invention -> écran de
revue des faits. Seule la QUALITÉ du texte reconnu par l'OCR sur ce cas
précis (manuscrit + bruit) était en cause.

**Limite documentée** (docstring `MlKitOcrService`, `mobile/README.md`) :
ML Kit (script Latin) est conçu pour du texte imprimé - performance dégradée
attendue sur de l'écriture manuscrite cursive, a fortiori bruitée. Un bon de
livraison réel est en général tapé/imprimé (cas nominal), donc ce point ne
devrait pas bloquer un usage réel, mais reste à confirmer sur un vrai bon de
livraison papier photographié au téléphone (pas webcam d'émulateur) avant de
le considérer clos - inscrit dans "Reste à faire" de
`docs/GATE_R2_STATUS.md`.

Fichiers modifiés : `mobile/lib/data/local/ocr_service.dart` (docstring
uniquement - le log de debug ajouté pour ce diagnostic a été retiré),
`backend/app/infrastructure/ai/openai_provider.py` (idem, log de debug 429
retiré une fois la cause - `insufficient_quota` / limite de dépenses du
projet OpenAI côté compte utilisateur, hors code - confirmée).

## [0.3.10] - R2 - correctif : mise en file OCR jamais déclenchée dans le parcours nominal - 2026-08-20

Premier test terrain de `[0.3.9]` (OCR) : écran "Vérifiez les faits" affichant
"Non détecté" sur tous les champs, sans erreur visible. Diagnostic (avant
toute hypothèse webcam/qualité photo) : bug réel de séquencement, pas un
problème d'OCR ni de réseau.

**Cause** : `document_capture_screen.dart::_enqueueOcrExtractionBestEffort`
ne met en file l'extraction OCR+IA que s'il existe déjà au moins une `Issue`
pour l'incident (un `CandidateFactSet` est toujours rattaché à une anomalie).
Or dans le parcours NOMINAL, l'ordre des écrans est S06 `documentCapture` ->
S08 `issueType` -> ... : `Issue` n'est créée qu'à S08, donc au moment de la
capture du document (S06) `listIssues` renvoie toujours une liste vide.
L'appel était donc un no-op silencieux systématique dans le cas normal
(erreur avalée par le `catch` best-effort, comme prévu) - l'opération n'était
tout simplement jamais créée en base, jamais retentée par
`facts_review_screen.dart` (qui ne fait que rejouer les items déjà en file,
n'en crée aucun).

**Correctif** : la mise en file réelle est déplacée dans
`issue_type_screen.dart::_continue()`, juste après la création (ou la
confirmation) du premier type de problème - à ce moment, une `Issue` existe
forcément. Le code recherche la preuve `EvidenceAsset` de type bon de
livraison de l'incident et met en file `extractFromDocument` pour elle.
L'appel resté dans `document_capture_screen.dart` est conservé tel quel (utile
pour "Reprendre la photo" sur un dossier qui a déjà une anomalie, ex. depuis
`incident_detail_screen.dart`) : `enqueueAiOperation` étant idempotent par
clé, les deux points d'appel ne créent jamais de doublon ni de double coût
IA.

Fichiers modifiés : `mobile/lib/features/issue_type/presentation/issue_type_screen.dart`
(nouvelle méthode `_enqueueOcrExtractionBestEffort`, appelée depuis
`_continue()`), `mobile/lib/features/document_capture/presentation/document_capture_screen.dart`
(docstrings corrigées uniquement, aucun changement de comportement).

Aucun test automatisé nouveau dans ce lot (le bug était dans le câblage
écran, hors du périmètre couvert par `ai_queue_processor_test.dart`, qui
teste le processeur en isolation et n'a jamais été affecté). À valider par un
nouveau test terrain : nouvelle photo de document (nouveau `sourceHash`,
l'ancien item resterait sinon bloqué au même titre que les incidents connus
de disjoncteur de retry documentés en `[0.3.8]`).

**Correctif confirmé par un nouveau test terrain immédiat** : après
application, `POST /v1/ai/extract` part bien désormais dès la validation du
type de problème (S08) - preuve que la chaîne câblage/OCR/appel réseau
fonctionne de bout en bout. Le test s'est ensuite heurté à un `429` distinct
et sans rapport avec le code : `insufficient_quota` /
`project_spend_limit_exceeded` - limite de dépenses du projet OpenAI
atteinte (réglage `https://platform.openai.com/settings/<project>/limits`,
côté compte de l'utilisateur, hors périmètre de ce dépôt). Corps JSON
confirmé via un log temporaire (ajouté puis retiré dans la foulée, même
discipline que `[0.3.7]`/`[0.3.8]`) - aucune ambiguïté restante entre
rate-limit et quota épuisé.

## [0.3.9] - R2 - OCR on-device (ML Kit) sur le bon de livraison (mobile) - 2026-08-20

Sixième lot mobile de R2. Jusqu'ici, `document_capture_screen.dart` (S06) ne
déclenchait AUCUN traitement IA après la photo du bon de livraison - seule la
note vocale (`voice_description_screen.dart`) était câblée à l'extraction IA.
Ce lot corrige ce trou fonctionnel (le plus matériel restant après la
validation terrain de `[0.3.8]`).

1. **`mobile/lib/data/local/ocr_service.dart`** (nouveau) - interface
   `OcrService` + implémentation `MlKitOcrService`
   (`google_mlkit_text_recognition`, script Latin, entièrement sur
   l'appareil, aucun appel réseau, aucun coût IA). Ne lève jamais pour un
   texte absent/illisible (retourne une chaîne vide, même philosophie "ne
   jamais bloquer l'utilisateur" que le reste du pipeline IA).
2. **`mobile/lib/data/ai_queue_processor.dart`** - `AiOperationKind.extractFromDocument`
   passe de "non supporté" à câblé (`_runExtractFromDocument`). Choix
   architectural explicite : contrairement à `transcribeAudio`/
   `extractFromTranscript` (séparés car la transcription audio est PAYANTE
   et ne doit jamais être refaite après un échec d'extraction), l'OCR ML Kit
   est gratuit - `extractFromDocument` reste donc un item UNIQUE : l'OCR est
   relancé à chaque tentative, seul l'appel réseau d'extraction (payant) a
   besoin d'un retry indépendant, et il l'a déjà via le retry normal de cet
   item. Nouveau `ExtractFromDocumentPayload` (référence vers l'`EvidenceAsset`
   photo, jamais le texte OCR lui-même - payload minimal, point 14).
   `ocrService` : paramètre optionnel du constructeur (repli
   `_UnconfiguredOcrService` qui lève si jamais utilisé sans être fourni) -
   choix délibéré pour ne casser aucun appelant existant (tous les tests déjà
   écrits construisaient `AiQueueProcessor` sans lui).
3. **`mobile/lib/features/document_capture/presentation/document_capture_screen.dart`** -
   après l'écriture de la photo sur disque (déjà point 4 - AVANT toute
   opération réseau/IA), met en file `extractFromDocument` (rattaché à la
   première anomalie de l'incident, même limitation V1 incident-scope que la
   note vocale) et déclenche le traitement au mieux-effort - même politique
   "jamais d'erreur affichée pour cette étape optionnelle" que
   `voice_description_screen.dart`.
4. **`mobile/lib/core/providers/app_providers.dart`** - nouveau
   `ocrServiceProvider` (construit `MlKitOcrService`), injecté dans
   `aiQueueProcessorProvider`.
5. **Backend : AUCUN changement.** `/v1/ai/extract` acceptait déjà
   `document_text` depuis l'origine de R2 (même endpoint, même schéma
   `CandidateFactData` que pour un transcript audio - seule la source du
   texte diffère) : ce lot est purement mobile.
6. **`mobile/pubspec.yaml`** - nouvelle dépendance
   `google_mlkit_text_recognition: ^0.17.1` (version vérifiée sur pub.dev au
   moment de ce lot ; exige `minSdkVersion: 21` côté Android, déjà largement
   couvert par la cible Android 10+ de ce projet - aucun conflit attendu).
7. **`mobile/test/data/ai_queue_processor_test.dart`** - 2 nouveaux tests
   (`OcrService` factice, même philosophie que `_FakeAiHttpTransport`) :
   succès OCR+extraction en un seul item, et échec OCR propre (requeue
   pending, jamais de perte).

Non testé en conditions réelles à ce stade (contrairement à la note vocale,
validée terrain en `[0.3.8]`) - à faire au prochain test terrain, priorité
haute vu que c'est un chemin de code entièrement neuf (plugin natif ML Kit
jamais exercé jusqu'ici dans ce projet).

## [0.3.8] - R2 - première validation terrain réelle bout en bout (émulateur Android) - 2026-08-20

Première exécution réelle de la chaîne complète R2 sur un appareil (émulateur
Android via Android Studio) avec un vrai backend local et une vraie clé
OpenAI : capture (photos + note vocale) → transcription IA → extraction IA
→ écran de revue des faits (`facts_review_screen.dart`) → confirmation
utilisateur → génération de la réserve. Résultat conforme à l'attendu sur
tous les points observables :

- Champs correctement extraits de la note vocale (produit, référence,
  quantités attendue/reçue) avec badge "Compris par l'IA".
- **GATE zéro invention confirmé en conditions réelles** : l'IA a suggéré un
  type d'anomalie différent (quantité manquante, cohérent avec 10 attendues/
  8 reçues) du type confirmé par l'utilisateur à l'étape S08 (produit
  endommagé) - le bandeau informationnel `_IssueFactsSectionState` l'affiche
  sans jamais écraser silencieusement le type confirmé (section 2.4).
- Réserve générée reflétant les faits confirmés.

Deux bugs réels trouvés et corrigés pendant ce diagnostic (voir aussi
0.3.7) :
1. Clé OpenAI restreinte + accès modèles du projet limité côté compte
   OpenAI (config utilisateur, hors dépôt) - pas un bug de code, mais a
   nécessité un diagnostic serveur temporaire (`GET /v1/models` en direct)
   pour distinguer permission de clé vs accès modèle de projet, deux
   réglages distincts sur platform.openai.com.
2. Nom de fichier multipart sans extension rejeté par OpenAI (0.3.7).

Voir `mobile/README.md`, section "Test sur émulateur Android - note micro" :
le micro virtuel de l'AVD nécessite un redémarrage à froid après activation,
sinon l'audio capté reste silencieux sans erreur explicite (facilement
confondu avec un bug IA/réseau).

Aucun changement de code dans ce lot au-delà du nettoyage d'un log de
diagnostic temporaire (`backend/app/api/routes/ai.py`) ajouté puis retiré
pendant ce diagnostic - voir 0.3.7 pour le correctif de code réel.

## [0.3.7] - R2 - correctif transcription OpenAI : nom de fichier sans extension (backend) - 2026-08-20

Corrigé lors du premier test terrain réel (émulateur Android + backend
local + vraie clé OpenAI, GATE R2) : `OpenAIProvider.transcribe`
(`backend/app/infrastructure/ai/openai_provider.py`) envoyait à
`/v1/audio/transcriptions` un fichier multipart nommé littéralement
`"audio"`, sans extension. OpenAI détermine le format audio depuis
l'EXTENSION du nom de fichier, jamais depuis le `Content-Type` - un nom
sans extension est systématiquement rejeté (`400 Unrecognized file
format`), y compris pour un contenu audio parfaitement valide (constaté
avec un vrai `.m4a` enregistré par l'app mobile). Ce bug était masqué côté
app par le message générique `AIUnavailableError` (GATE secret - jamais de
détail de statut/erreur provider exposé au client mobile), rendant le
diagnostic à distance nécessaire (log temporaire côté serveur, retiré une
fois la cause confirmée).

Correction : `_audio_filename_for_mime_type` dérive un nom de fichier avec
extension reconnue (`audio.m4a`, `audio.wav`, ...) depuis le `mime_type`
réel de la preuve capturée, avec repli sur le sous-type MIME si absent de
la table plutôt qu'un nom nu. Nouveau test
`test_transcribe_sends_filename_with_extension_matching_mime_type`
(`backend/tests/infrastructure/test_openai_provider.py`) vérifie que le nom
de fichier envoyé porte bien l'extension attendue - garde contre une
régression silencieuse (ce bug ne se voyait dans AUCUN test existant,
puisqu'ils mockent le transport sans jamais inspecter le nom de fichier
multipart).

Aucun changement mobile - uniquement le provider backend.

## [0.3.6] - R2 - câblage réel écran de revue des faits + réserve (mobile) - 2026-08-20

Cinquième lot mobile de R2. Jusqu'ici, `facts_review_screen.dart` (S11) et
`reserve_screen.dart` (S12) étaient tous deux des stubs à contenu codé en
dur, jamais branchés sur `IncidentRepository`, et `facts_review_screen.dart`
n'était atteignable depuis AUCUN parcours réel (`pushFactsReview()` n'avait
aucun appelant) - le principe R2 ("l'IA propose, le code contrôle,
l'utilisateur confirme") n'était donc démontrable nulle part de bout en
bout. Ce lot corrige les trois à la fois : câblage réel des deux écrans, et
reachability depuis `checklist_screen.dart`.

1. **`mobile/lib/features/facts_review/presentation/facts_review_screen.dart`**
   - réécriture complète. Une section par anomalie (`Issue`) de l'incident ;
   lit la dernière extraction candidate (`latestCandidateFactSet`) et la
   dernière confirmation (`latestConfirmedFactSet`) via 4 nouveaux providers
   Riverpod. Fonctionne intégralement SANS extraction IA préalable (champs
   "non détecté", éditables/marquables UNKNOWN comme n'importe quel champ
   candidat) - la vraie bascule "saisie manuelle/UNKNOWN" exigée par le
   retour d'équipe (exigence coût IA, point 7), qui n'existait pas encore
   (voir `[0.3.5]`, limitation documentée). "Valider les faits de cette
   anomalie" appelle réellement `IncidentRepository.confirmFacts`. "Générer
   la réserve" appelle `composeAndSaveReserve` puis navigue vers
   `reserve_screen.dart`. Bandeau informatif si la file IA a un item encore
   en cours ou bloqué par le disjoncteur pour cette anomalie, avec
   rafraîchissement manuel (AppBar).
2. **`mobile/lib/features/reserve/presentation/reserve_screen.dart`** -
   affiche désormais `latestReserveText(incidentId)` réel (nouveau
   provider), ou un message explicite si aucune réserve n'a encore été
   composée - suppression du texte d'exemple codé en dur
   (`_sampleReserveText`).
3. **`mobile/lib/core/providers/app_providers.dart`** - 5 nouveaux
   providers : `latestCandidateFactSetProvider`, `latestConfirmedFactSetProvider`,
   `incidentConfirmedFactSetsProvider`, `pendingAiOperationsProvider`,
   `latestReserveTextProvider`.
4. **`mobile/lib/core/router/app_router.dart`** - `FactsReviewScreen`/
   `ReserveScreen` reçoivent désormais `incidentId` via `extra` (même
   mécanisme que les autres écrans du parcours de capture) ;
   `pushFactsReview`/`pushReserve` prennent maintenant ce paramètre.
5. **`mobile/lib/features/checklist/presentation/checklist_screen.dart`** -
   nouvel item optionnel "Revue des faits (IA) et réserve" -> `pushFactsReview`.
   Sans incidence sur `canFinish`/"Terminer le dossier" (critère de
   complétude R1 inchangé) : la checklist R1 continue de fonctionner à
   l'identique même si cette étape R2 n'est jamais utilisée.
6. **Tests** - `mobile/test/features/facts_review_screen_test.dart` (3 tests :
   affichage d'un candidat partiel + désactivation du bouton tant que non
   résolu ; bascule manuelle complète sans aucun `CandidateFactSet`,
   `confirmFacts` vérifié par relecture directe du repository ; acceptation
   intégrale d'un candidat à 8 champs, valeurs persistées vérifiées une par
   une) et `mobile/test/features/reserve_screen_test.dart` (2 tests :
   absence de réserve -> message clair sans texte factice ; réserve réelle
   composée -> texte affiché identique à celui retourné par
   `composeAndSaveReserve`, jamais un texte codé en dur).

**Limites documentées, pas des bugs** (détail complet dans
`docs/GATE_R2_STATUS.md`) : tous les champs V1 prioritaires doivent être
résolus pour valider une anomalie (pas de distinction champ critique par
type d'anomalie) ; le type d'anomalie confirmé reste toujours celui choisi
à l'étape S08, jamais substitué silencieusement même si l'IA suggère
autre chose ; `CandidateField.confidence`/`.ambiguous` ne sont pas encore
affichés ; le bouton "Générer la réserve" (navigation go_router) n'est pas
couvert par un test automatisé dans ce sandbox, seul l'affichage réel de
`ReserveScreen` l'est (même limite déjà actée pour l'audio dans
`evidence_viewer_test.dart`).

## [0.3.5] - R2 - optimisation coût IA (mobile) + inventaire exigences équipe - 2026-08-20

Quatrième lot mobile de R2, en réponse directe au retour d'équipe "Exigences
R2 - maîtrise des coûts et tokens IA" (14 points, voir
`docs/GATE_R2_STATUS.md` section dédiée pour l'inventaire complet point par
point). Corrige/complète `[0.3.4]` sur deux axes précis, et documente
honnêtement tout ce qui reste à faire côté backend/benchmark.

1. **`mobile/lib/data/ai_queue_processor.dart`** - `AiOperationKind.transcribeAudio`
   ne fait plus QUE transcrire : l'extraction est désormais une opération
   séparée et retentable indépendamment (`AiOperationKind.extractFromTranscript`,
   payload = transcript déjà obtenu). Avant ce changement, un échec
   d'extraction APRÈS une transcription réussie faisait retenter les DEUX
   appels au prochain passage - la transcription déjà payée en tokens était
   regaspillée à chaque tentative. `processPendingOperations` boucle
   désormais sur plusieurs "rounds" bornés (`maxRoundsPerCall`, défaut 5)
   pour que la chaîne complète progresse en un seul appel côté écran.
2. **Idempotence conforme à la composition exigée par l'équipe** (point 8 -
   `incident_id + operation_type + source_hash + pipeline_version`) : nouvelle
   fonction `aiOperationIdempotencyKey` + `aiPipelineVersion`, utilisées par
   TOUS les points de mise en file. `sourceHash` = SHA-256 déjà calculé de
   l'audio (jamais un id généré aléatoirement) pour `transcribeAudio`, SHA-256
   du transcript pour `extractFromTranscript`. `IncidentRepository.enqueueAiOperation`
   (`local_incident_repository.dart`) vérifie désormais l'existence d'un item
   avec la même clé AVANT toute insertion - une mise en file en double ne
   crée jamais de doublon.
3. **Disjoncteur de retry abaissé de 5 à 2 tentatives par défaut**
   (`defaultAiQueueMaxRetryCount`) - alignement avec le point 7 de l'équipe
   ("jamais de boucle automatique", "une erreur persistante doit basculer
   vers saisie manuelle/UNKNOWN"). Alignement partiel seulement : la vraie
   bascule vers saisie manuelle/UNKNOWN nécessite `facts_review_screen.dart`
   (pas encore connecté à la file), voir limitation documentée dans le code.
4. **`mobile/lib/domain/entities/ai_queue_item.dart`** - nouvelle valeur
   `AiOperationKind.extractFromTranscript` (mapping wire ajouté dans
   `local_incident_repository.dart`, aucune migration Drift nécessaire -
   colonne texte libre côté schéma).
5. Tests mis à jour/ajoutés dans `ai_queue_processor_test.dart` : preuve
   explicite qu'un échec d'extraction après transcription réussie ne
   rappelle JAMAIS `/v1/ai/transcribe` au retry, et qu'une mise en file en
   double (même `incidentId`/`operationKind`/`sourceHash`) ne crée jamais de
   doublon.

**Ce lot NE couvre PAS** les 12 autres points du retour d'équipe (OCR local,
journal de consommation backend, métriques coût benchmark, circuit breaker
budgétaire production, séparation clés DEV/TEST vs PROD, limite de tokens de
sortie/schema strict, sélection du modèle le moins cher par benchmark,
détection "source inchangée -> ne pas rappeler" au-delà de la simple
déduplication de mise en file) - voir `docs/GATE_R2_STATUS.md`, nouvelle
section "Exigences coût/tokens IA (retour équipe)" pour l'inventaire complet,
honnête et non filtré, de ce qui est fait vs pas commencé.

## [0.3.4] - R2 - câblage AiOperationQueue (mobile) - 2026-08-20

Troisième lot mobile de R2 : la pièce qui relie enfin `AiApiClient`
(`[0.3.3]`) et `saveCandidateFactSet` (`[0.3.2]`) - jusqu'ici posés mais
jamais appelés l'un après l'autre. Un seul point de déclenchement est câblé
à ce stade (note vocale, voir "Reste à faire" pour l'OCR/photo).

1. **`mobile/lib/data/local/evidence_storage.dart`** - nouvelle méthode
   `readBytes(EvidenceAsset)` : relit les octets bruts d'une preuve déjà
   capturée (nécessaire pour transmettre un audio à
   `AiApiClient.transcribe`), en conservant la frontière stricte de ce
   fichier (seule partie de l'app qui lit/écrit des octets pour les
   preuves). Contrairement à `verify()`, lève une exception explicite si le
   fichier est absent - un appelant qui a besoin du CONTENU d'une preuve
   doit être informé immédiatement, jamais recevoir un résultat vide
   silencieux.
2. **`mobile/lib/data/ai_queue_processor.dart`** (nouveau) - `AiQueueProcessor`,
   traite les items `pending` de `AiOperationQueue` un par un :
   transcription (`AiApiClient.transcribe`) puis extraction
   (`AiApiClient.extractCandidateFacts`) puis persistance
   (`saveCandidateFactSet`), pour `AiOperationKind.transcribeAudio`.
   `extractFromPhoto`/`extractFromDocument` (OCR non câblé) sont laissés
   `pending` intacts, jamais consommés pour un échec certain. Disjoncteur de
   retry uniforme (`maxRetryCount`, défaut 5) : au-delà, un item n'est plus
   retenté automatiquement mais reste en base (rien n'est perdu, pas encore
   d'écran pour réarmer manuellement - voir `docs/GATE_R2_STATUS.md`).
   Expose aussi `TranscribeAudioPayload`, le contrat JSON minimal
   (référence vers un `EvidenceAsset`, jamais un dump complet du dossier -
   point 14) partagé entre l'écran qui met en file et ce processeur.
3. **`mobile/lib/core/providers/app_providers.dart`** - `aiQueueProcessorProvider`,
   même principe de frontière que les autres providers de ce fichier.
4. **`mobile/lib/features/voice_description/presentation/voice_description_screen.dart`**
   (S10) - après l'enregistrement réussi d'une note vocale, met en file une
   opération `transcribeAudio` (rattachée à la première `Issue` de
   l'incident - limitation V1 documentée, cet écran est aujourd'hui
   incident-scope et non issue-scope) puis déclenche immédiatement le
   traitement de la file au mieux-effort. Entièrement best-effort : la note
   vocale est déjà sauvegardée avec succès avant cette étape, aucune erreur
   n'est jamais affichée à l'utilisateur pour cette partie optionnelle -
   "ne jamais bloquer l'utilisateur" (section "Échec IA" de la demande R2).
5. **Tests écrits (non exécutés, voir `mobile/README.md`)** :
   `mobile/test/data/ai_queue_processor_test.dart` - même philosophie que
   `local_incident_repository_test.dart` (vraie base Drift sur fichier
   temporaire, vrai `EvidenceStorageService` sur vrai dossier temporaire,
   seul le transport réseau est simulé) : succès bout en bout (transcription
   + extraction + `CandidateFactSet` persisté), panne réseau -> requeue
   pending avec retry incrémenté, disjoncteur de retry, opération non
   supportée (OCR) -> skipped sans être consommée, erreurs de cohérence
   interne (`issueId` manquant, preuve introuvable).

**Reste à faire (R2, mobile)** : déclenchement de la file au retour réseau
(listener de connectivité - à ce stade uniquement déclenché juste après une
capture) ; OCR on-device (ML Kit) et enqueue `extractFromPhoto`/
`extractFromDocument` depuis `document_capture_screen.dart` ; écran de
revue réel `facts_review_screen.dart` ; écran pour réarmer manuellement un
item bloqué par le disjoncteur de retry.

## [0.3.3] - R2 - client HTTP mobile vers /v1/ai/* - 2026-08-20

Deuxième lot mobile de R2 : le client HTTP qui relie l'app au pipeline IA
backend déjà livré (`[0.3.0]`) - pièce manquante entre "un fichier audio/un
texte OCRisé sur l'appareil" et "un `CandidateFactSet` sauvegardé"
(`[0.3.2]`). Le câblage de la file `AiOperationQueue` (déclenchement online/
offline, retry) et l'OCR on-device restent à faire (voir "Reste à faire").

1. **`mobile/lib/domain/errors/domain_errors.dart`** - ajout de
   `AiUnavailableException`/`AiInvalidOutputException`/
   `AiRateLimitedException`/`AiRequestFailedException`, mêmes `code` que
   `backend/app/domain/errors.py::AIUnavailableError`/`AIInvalidOutputError`/
   `AIRateLimitedError`, pour que l'enveloppe d'erreur JSON du backend
   (`{"code", "message", "trace_id"}`, voir `backend/app/api/errors.py`) se
   retraduise directement en exception typée côté mobile.
2. **`mobile/lib/data/remote/ai_api_client.dart`** (nouveau) - `AiApiClient`,
   miroir de `backend/app/api/routes/ai.py` (`/v1/ai/transcribe`,
   `/v1/ai/extract`). Construit au-dessus d'une frontière volontairement
   minimale, `AiHttpTransport` (implémentation réelle `DioAiHttpTransport`
   au-dessus de `package:dio`) plutôt que directement sur `Dio` : ce sandbox
   ne pouvant vérifier par exécution aucun mécanisme de mock spécifique à
   `dio`, les tests passent par une implémentation entièrement faite à la
   main de cette frontière - même logique que le choix de `httpx` brut
   (plutôt que le SDK `openai`) pour `openai_provider.py` (`[0.3.0]`).
   `candidate` reçu est déjà filtré côté backend
   (`screen_candidate_fact_data`) mais reste soumis à
   `candidate_guard.dart::screenCandidateFactData` avant toute persistance
   (défense en profondeur, déjà en place depuis `[0.3.2]`).
3. **`mobile/lib/core/config/backend_config.dart`** (nouveau) - URL de base
   du backend, surchargeable via `--dart-define=RESERVEFLASH_BACKEND_BASE_URL=...`
   (défaut `http://10.0.2.2:8000`, alias standard émulateur Android ->
   hôte ; documenté comme inadapté à un simulateur iOS/appareil physique).
4. **`mobile/lib/core/providers/app_providers.dart`** - `dioProvider`/
   `aiApiClientProvider`, seul point de construction du client HTTP de
   l'app (même principe que `incidentRepositoryProvider`).
5. **Tests écrits (non exécutés, voir `mobile/README.md`)** :
   `mobile/test/data/remote/ai_api_client_test.dart` - succès transcribe/
   extract, panne de transport -> `AiUnavailableException`, mapping complet
   des codes d'erreur backend (`AI_UNAVAILABLE`/`AI_INVALID_OUTPUT`/
   `RATE_LIMITED`/`VALIDATION_ERROR`/`INTERNAL_ERROR` non catégorisé), corps
   2xx non-JSON.

**Reste à faire (R2, mobile)** : câblage `AiOperationQueue`/`PendingAIJob`
(déclenchement online, file offline, rejeu au retour réseau) consommant
`AiApiClient` + `saveCandidateFactSet` ; OCR on-device (ML Kit) ; écran de
revue réel `facts_review_screen.dart`.

## [0.3.2] - R2 - CandidateFactSet côté mobile (entité + garde-fous + repository) - 2026-08-20

Premier lot mobile de R2 (voir `docs/GATE_R2_STATUS.md`, section "Mobile" -
jusqu'ici "PAS COMMENCÉ"). Portée volontairement limitée à la persistance
locale des candidats IA - l'OCR on-device, le câblage `AiOperationQueue` et
l'écran de revue réel restent à faire (voir "Reste à faire" ci-dessous).

**Non vérifié par exécution dans ce sandbox** (contrairement au travail
backend de `[0.3.0]`/`[0.3.1]`, testé via `pytest` réel) : ce sandbox ne
dispose d'aucun SDK Flutter/Dart (voir `mobile/README.md`). Ce lot a été
écrit par calque strict sur les fichiers Dart existants déjà validés côté
utilisateur (mêmes conventions d'import, de nommage, de sérialisation JSON,
de structure de fichier - y compris la contrainte `library;` avant tout
`import`/`part`, réapprise à la dure lors du hotfix R0.2 documenté dans
`app_database.dart`). Reste à exécuter côté utilisateur : `flutter pub get`,
`flutter analyze`, puis les tests une fois écrits.

1. **`mobile/lib/domain/fact_set/candidate_fact_data.dart`** (nouveau) -
   miroir Dart de `schemas/candidate_fact_set.v1.schema.json` /
   `backend/app/domain/fact_set.py::CandidateField`/`CandidateFactData`
   (classes `CandidateField`, `CandidateFactData`, sérialisation
   `fromJson`/`toJson`, `copyWith`). Clés du `Map fields` en snake_case
   (wire JSON), pas camelCase, pour un round-trip JSON fidèle et un
   alignement direct avec `clarification_questions.dart`.
2. **`mobile/lib/domain/entities/candidate_fact_set.dart`** (nouveau) -
   entité `CandidateFactSet` (pendant candidat de `ConfirmedFactSet`),
   miroir mobile de `backend/app/domain/entities.py`.
3. **`mobile/lib/domain/liability_guard.dart`** - `_ForbiddenPattern`/
   `_forbiddenPatterns` rendus publics (`ForbiddenPattern`/
   `forbiddenPatterns`), même renommage que le backend
   (`_FORBIDDEN_PATTERNS` -> `FORBIDDEN_PATTERNS`, voir `[0.3.0]`) : source
   unique de vérité réutilisée par le nouveau `candidate_guard.dart`.
   Comportement inchangé.
4. **`mobile/lib/domain/candidate_guard.dart`** (nouveau) - miroir Dart de
   `backend/app/domain/candidate_guard.py` : `screenCandidateFactData`
   retire silencieusement (jamais de mutation en place, jamais
   d'exception) tout champ candidat contenant un motif interdit ou une
   quantité négative, force `requiresReview = true` si un champ a été
   retiré.
5. **`mobile/lib/domain/clarification_questions.dart`** (nouveau) - miroir
   Dart de `backend/app/domain/clarification_questions.py` : catalogue
   contrôlé `clarificationQuestionCatalog` + `clarificationQuestionIdForField`
   (nom de champ hors catalogue -> `null`, jamais un identifiant inventé).
6. **`mobile/lib/domain/repositories/incident_repository.dart`** - ajout de
   `saveCandidateFactSet`/`latestCandidateFactSet` à l'interface
   `IncidentRepository` (absents jusqu'ici malgré la table Drift
   `LocalCandidateFactSets` déjà migrée - lacune confirmée par lecture
   complète du fichier avant ce commit).
7. **`mobile/lib/data/local/local_incident_repository.dart`** -
   implémentation Drift des deux méthodes ci-dessus. `saveCandidateFactSet`
   applique `screenCandidateFactData` AVANT toute écriture (même principe
   que `confirmFacts`/`liability_guard.dart` : point d'entrée unique de
   persistance, défense en profondeur).
8. **Tests écrits (non exécutés, même statut que `test/data/
   local_incident_repository_test.dart` existant avant ce commit - voir
   `mobile/README.md`, section "Limitation connue de cet environnement")** :
   `mobile/test/domain/candidate_guard_test.dart` (miroir de
   `backend/tests/domain/test_candidate_guard.py`, rejoue l'exemple
   "transporteur responsable" et les cas de quantité négative),
   `mobile/test/domain/clarification_questions_test.dart` (miroir de
   `backend/tests/domain/test_clarification_questions.py`), et une nouvelle
   `group` ajoutée à `test/data/local_incident_repository_test.dart`
   (persistance réelle disque de `saveCandidateFactSet`/
   `latestCandidateFactSet`, y compris la preuve que le champ interdit
   n'atteint jamais `rawStructuredJson` sur disque).

**Reste à faire (R2, mobile)** : OCR on-device (ML Kit) sur la photo du BL,
câblage `AiOperationQueue`/`PendingAIJob` (déclenchement online, file
offline, rejeu au retour réseau) consommant ces nouvelles méthodes, écran de
revue réel `facts_review_screen.dart` (aujourd'hui un stub à champs codés en
dur) branché sur `latestCandidateFactSet`/confirmation vers
`ConfirmedFactSet`.

## [0.3.1] - R2 - corpus de benchmark versionné + scorer + GATE_R2_STATUS.md - 2026-08-20

1. **`benchmark/corpus/r2_corpus_v1.json`** (nouveau, dossier vide jusqu'ici) -
   50 cas réels et versionnés couvrant les 7 catégories demandées (CORE 8,
   PARAPHRASE 8, NEGATION 8, AUDIO 6, OCR 6, UNKNOWN 6, SAFETY 8), incluant
   verbatim les 5 exemples obligatoires fournis par l'équipe. Périmètre
   volontairement réduit par rapport aux 240 cas assignés à "R6 -
   Qualification" avant ce commit - voir `benchmark/README.md` section
   "Changement de séquencement" et `docs/GATE_R2_STATUS.md` pour la
   justification complète de ce choix non tranché silencieusement.
2. **`benchmark/scorer.py`** (nouveau) - calcule précision/recall/exactitude
   issue_type/taux de faits inventés/taux de UNKNOWN corrects/taux de
   sorties invalides/latence médiane-p95/taux de réussite SAFETY, séparément
   par catégorie et CORE vs STRESS. Réutilise
   `app.domain.liability_guard.FORBIDDEN_PATTERNS` (backend) comme source
   unique pour la vérification SAFETY. Décorrélé de tout provider IA
   concret (opère sur des dicts JSON `candidate_fact_set.v1`, aucun appel
   réseau). 20 tests (`benchmark/tests/test_scorer.py`), prédictions
   construites à la main.
3. **`benchmark/run_scorer.py`** (nouveau) - exécute le corpus contre un
   provider réel (`--provider openai`, nécessite une clé + réseau non
   disponibles dans ce sandbox) ou le mock (`--provider mock`, preuve
   d'intégration bout-en-bout, pas une mesure de qualité). **Exécuté
   réellement** avec `--provider mock` sur les 50 cas, sans exception -
   rapport `benchmark/results/report_mock.json`.
4. **`docs/GATE_R2_STATUS.md`** (nouveau) - document vivant de suivi R2,
   même format que `GATE_R1_STATUS.md` : baseline, décisions de périmètre
   documentées explicitement (fournisseur IA, OCR, benchmark R2 vs R6,
   séparation métadonnées BL/CandidateFacts), avancement réel par domaine
   (backend vérifié, mobile pas commencé, recette terrain pas commencée).
   Aucun verdict "GATE R2 PASS" déclaré.

Non-régression : `pytest` (backend 116/116 + benchmark 20/20) et
`ruff check` toujours propres après ce commit.

## [0.3.0] - R2 (démarrage) - pipeline IA backend réel (voix/OCR -> CandidateFacts) - 2026-08-20

**R2 démarré à partir du freeze `r1-final` (commit `65287f7`), architecture
Local-First strictement conservée.** Ce sont les toutes premières briques de
R2 - uniquement le backend, vérifié réellement (`pytest`, 116/116 verts,
`ruff check` propre) dans cet environnement. Le mobile (OCR on-device,
câblage `AiOperationQueue`, écran de revue réel) reste à faire et devra être
vérifié sur poste/téléphone utilisateur comme pour R0/R1.

1. **`backend/app/infrastructure/ai/openai_provider.py`** (nouveau) -
   implémentation réelle de `AIProvider` (`transcribe`, `extract_candidate_facts`)
   via l'API HTTP d'OpenAI directement (`httpx`), pas le SDK `openai` - ce
   sandbox de développement n'a aucun accès réseau vers `api.openai.com`
   (vérifié), donc aucune vérification réelle contre le SDK n'était possible ;
   l'API HTTP REST est un contrat stable et permet un test unitaire précis
   via `httpx.MockTransport` (11 tests, `tests/infrastructure/test_openai_provider.py`),
   sans jamais toucher au réseau réel. Gère : timeout/erreur réseau/5xx ->
   `AIUnavailableError`, 429 -> `AIRateLimitedError`, JSON de sortie invalide
   -> **exactement une** tentative de réparation contrôlée puis
   `AIInvalidOutputError` (jamais de boucle, section "Échec IA" de la
   demande R2).
2. **`app/infrastructure/ai/__init__.py`** - la factory instancie désormais
   réellement `OpenAIProvider` quand `RESERVEFLASH_AI_PROVIDER=openai` (ne
   lève plus `NotImplementedError`).
3. **`app/domain/candidate_guard.py`** (nouveau) - garde-fou déterministe
   appliqué aux `CandidateFactData` (sortie brute IA, avant confirmation
   utilisateur), en complément de `liability_guard.py` (qui protège les
   `ConfirmedFactData`, après confirmation). Retire silencieusement (sans
   jamais lever d'exception ni bloquer le dossier) tout champ contenant une
   attribution de responsabilité, une conclusion/qualification juridique,
   une promesse d'indemnisation, un montant inventé (mêmes motifs que
   `liability_guard`, désormais publics et partagés via
   `liability_guard.FORBIDDEN_PATTERNS` - une seule source de vérité), ou
   une quantité négative (`expected_quantity`/`received_quantity`/
   `affected_quantity`). Rejoue explicitement le cas cité par l'équipe :
   `packaging_condition = "transporteur responsable"` ne doit jamais
   atteindre l'écran de revue. 14 tests (`tests/domain/test_candidate_guard.py`).
   Appliqué au point d'entrée unique des candidats côté backend
   (`app/api/routes/ai.py::extract_candidate_facts`), donc actif pour tout
   provider (mock ou réel), sans dépendre de sa discipline interne.
4. **`app/domain/clarification_questions.py`** (nouveau) - catalogue
   contrôlé des `clarification_question_id` (schéma `candidate_fact_set.v1` :
   "jamais une question générée librement par le LLM"). Le modèle ne peut
   indiquer qu'un NOM de champ candidat (`most_uncertain_field`, métadonnée
   hors-schéma) ; c'est le code, jamais le modèle, qui traduit ce nom en
   identifiant catalogue - un nom halluciné/hors catalogue est ignoré. 4 tests.
5. **`prompts/extraction_fr_v1.txt`** (nouveau, premier fichier du dossier -
   jusqu'ici vide en R0/R1) - prompt système versionné de l'extraction :
   liste fermée des 8 champs V1 prioritaires, règles d'or explicites
   (UNKNOWN plutôt qu'invention, négations, incertitude non résolue
   arbitrairement, aucune attribution de responsabilité/conclusion
   juridique/montant, quantités jamais négatives).
6. **`app/config.py`** - nouveaux réglages `openai_base_url`,
   `openai_transcription_model` (défaut `whisper-1`),
   `openai_extraction_model` (défaut `gpt-4o-mini`),
   `openai_request_timeout_seconds`, tous surchargeables par variable
   d'environnement.
7. **`app/domain/liability_guard.py`** - `_FORBIDDEN_PATTERNS` renommé en
   `FORBIDDEN_PATTERNS` (public) pour être partagé avec `candidate_guard.py` :
   comportement strictement inchangé (27 tests existants toujours verts),
   seule la visibilité change.
8. **`app/api/routes/ai.py`** - `extract_candidate_facts` applique désormais
   `screen_candidate_fact_data` avant de renvoyer la réponse (voir point 3).
   1 nouveau test dédié + 2 tests de mapping d'erreur (`AIUnavailableError`
   -> 503, sur `/extract` et `/transcribe`).

**Non-régression** : les 84 tests backend R0/R1 existants restent verts,
inchangés, plus les 32 nouveaux tests ci-dessus = 116/116 (3 skips
préexistants, indépendants de PostgreSQL, inchangés). `ruff check` propre.

**Reste à faire avant toute candidate `r2-candidate`** : côté mobile - OCR
on-device (ML Kit), entité Dart `CandidateFactSet` (absente malgré les
tables Drift déjà prêtes), câblage `AiOperationQueue`/`PendingAIJob`
online/offline, écran de revue réel (`facts_review_screen.dart` est
aujourd'hui un stub à champs codés en dur) ; côté qualification - corpus de
benchmark versionné (CORE/PARAPHRASE/NEGATION/AUDIO/OCR/UNKNOWN/SAFETY) et
scorer ; recette terrain réelle sur Android avec une clé OpenAI réelle
(aucun appel réseau réel vers OpenAI n'a été possible dans cet
environnement de développement - à vérifier en conditions réelles). Cette
entrée ne déclare aucune fonctionnalité R2 "terminée" au sens du Gate R2.

## [0.2.1] - R1 correction ciblée post-recette terrain (photo/audio) - 2026-08-19

**Vérifié par exécution réelle sur le poste de l'utilisateur** :
`flutter analyze` (0/0), `flutter test` (67/67), `flutter build apk
--debug` (réussi) - voir `docs/GATE_R1_STATUS.md`, section "Correction
ciblée post-recette terrain (photo/audio)", pour le détail complet
(y compris les bugs réels de test trouvés et corrigés au passage). CI et
nouvelle recette terrain sur appareil restent à faire avant tout nouveau
tag.

Origine : la recette terrain indépendante, en déroulant le parcours réel
sur un Samsung Galaxy A51, a signalé qu'une fois les photos et la note
vocale enregistrées dans un dossier, il était impossible de les relire/
écouter depuis l'app. Vérifié dans le code : exact -
`EvidenceThumbnailTile` n'avait aucun `onTap`, et le projet n'avait aucun
package de lecture audio (seulement `record`, pour l'enregistrement).
Aucune perte de données ni crash - un trou d'usage réel. Correctif
strictement ciblé sur ce point (aucun changement Drift, architecture
Local-First ou backend, comme demandé) :

1. **`EvidencePhotoViewerScreen`** (nouveau,
   `lib/features/common/presentation/evidence_photo_viewer_screen.dart`) -
   visionneuse plein écran (photo/BL) : zoom/pan (`InteractiveViewer`),
   bouton retour explicite, reprendre (remplacement explicite ancien ->
   nouveau, jamais d'état intermédiaire sans preuve), supprimer (avec
   confirmation), état contrôlé "introuvable"/"corrompu" sans crash
   (étend l'invariant R1-T07 au rendu plein écran).
2. **`EvidenceAudioPlayerScreen`** (nouveau,
   `lib/features/common/presentation/evidence_audio_player_screen.dart`) -
   lecteur plein écran (note vocale) : lecture/pause, durée/progression,
   arrêter/recommencer, supprimer, état contrôlé "introuvable"/"corrompu"
   sans même tenter d'ouvrir le lecteur natif dans ce cas.
3. **`just_audio: ^0.10.6`** (nouveau, `mobile/pubspec.yaml`) - lecture
   audio 100% locale (fichier sur disque uniquement, jamais de réseau/
   streaming). Choisi après recherche du changelog officiel (pub.dev) :
   "Support AGP 9" + migration Android vers `.kts`, alignée sur le même
   toolchain déjà prouvé pour `record` (AGP 9.x/Kotlin Gradle DSL, Flutter
   3.47.0/Dart 3.13.0). Seul nouveau plugin natif de ce correctif, donc le
   point de risque de build le plus élevé - à vérifier en priorité lors du
   prochain `flutter build apk --debug` réel (même méthode que `record` en
   R1 initial).
4. **`lib/core/utils/duration_format.dart`** (nouveau) - formatage `mm:ss`
   partagé par le timer d'enregistrement et la progression de lecture.
5. **`voice_description_screen.dart`** - ajoute un chronomètre affiché
   pendant l'enregistrement ("Enregistrement en cours : mm:ss"), absent
   avant ce correctif.
6. **`EvidenceThumbnailTile`** - nouveau paramètre `onTap`, câblé depuis
   `document_capture_screen.dart` (S06), `evidence_capture_screen.dart`
   (S09), `voice_description_screen.dart` (S10) et
   `incident_detail_screen.dart` (S17, qui route vers la visionneuse photo
   ou le lecteur audio selon `documentType`) pour ouvrir la visionneuse/le
   lecteur correspondant.
7. **Tests** (`mobile/test/features/evidence_viewer_test.dart`, nouveau) -
   formatage `mm:ss`, ouverture plein écran d'une photo au tap, photo
   consultable après fermeture/réouverture, photo manquante/corrompue sans
   crash, suppression réelle depuis la visionneuse. **La lecture audio
   réelle n'est PAS testée automatiquement** : `just_audio`, comme
   `record`/`camera`, n'a aucun canal de plateforme disponible en `flutter
   test` pur - `EvidenceAudioPlayerScreen` reste "manuel requis" sur un
   vrai appareil pour son comportement complet (voir
   `docs/GATE_R1_STATUS.md`).
8. **Bugs réels trouvés et corrigés par le bootstrap réel** (aucun n'aurait
   été détecté par simple relecture de code) : import manquant de la
   classe `Incident` dans le nouveau fichier de test (`flutter analyze`) ;
   tests `Image.file` restés bloqués indéfiniment (dart:io réellement
   asynchrone dans `testWidgets()` nécessite `tester.runAsync()`, y compris
   avant le premier `pumpWidget` - diagnostiqué par une trace disque
   synchrone) ; test de suppression bloqué (`pumpAndSettle timed out`,
   corrigé par plusieurs petits aller-retours temps réel/temps simulé au
   lieu d'un délai fixe unique). Détail complet dans l'historique git de ce
   correctif.

~~**Reste à faire avant tout nouveau tag** : pousser ce commit et confirmer
la CI GitHub Actions verte dessus, puis nouvelle recette terrain manuelle
sur appareil ciblée sur ce correctif (la recette indépendante précédente ne
le couvre pas) - cette entrée ne déclare PAS ce correctif validé.~~ **FAIT** :
CI GitHub Actions verte (run #10, commit `b7b6fc2`, 4 jobs, 9m47s) et
parcours manuel sur Samsung Galaxy A51 confirmé ("tout marche bien !") -
voir `docs/GATE_R1_STATUS.md`. Verdict de la recette indépendante sur ce
correctif : voir entrée `[0.2.2]` ci-dessous.

## [0.2.2] - Freeze R1 final - GATE R1 PASS - 2026-08-20

**La recette indépendante a validé le correctif photo/audio et prononcé
GATE R1 PASS.** Verdict transmis par l'utilisateur le 2026-08-20, verbatim :
"La recette indépendante valide le correctif photo/audio et prononce GATE
R1 PASS." Ce verdict couvre à la fois le parcours métier/offline de R1
initial et le correctif ciblé photo/audio (entrée `[0.2.1]` ci-dessus).

Ce commit est le **freeze documentaire R1 final**, conforme à la consigne
reçue avec ce verdict : **"ne modifier aucune fonctionnalité"**. Seuls
`docs/GATE_R1_STATUS.md` et `CHANGELOG.md` sont modifiés dans ce commit -
aucun fichier `mobile/lib/**` n'est touché.

Séquence de freeze restant à exécuter après ce commit (voir
`docs/GATE_R1_STATUS.md`, "Prochaines étapes", point 7) : push sur `main`,
CI complète sur ce commit exact, tag `r1-final` si verte, génération de
`ReserveFlash_R1_FINAL.zip` depuis le tag, APK issue de cette même CI,
`R1_FINAL_SHA256.txt` (commit, tag, SHA ZIP, SHA APK, run CI). R2 ne
commence qu'après livraison complète de ce freeze.

**Correction annexe découverte juste avant le push (commit séparé,
immédiatement après celui-ci)** : `mobile/pubspec.lock` ne contenait pas
`just_audio`/`audio_session` alors que `pubspec.yaml` les déclare depuis le
correctif `[0.2.1]` - le lockfile régénéré n'avait jamais été committé (la
CI s'en sortait car elle relance `flutter pub get`). Corrigé avec le
contenu réel produit par `flutter pub get` sur le poste de l'utilisateur
(pas une régénération devinée) : ajout de `just_audio` (direct),
`audio_session`, `just_audio_platform_interface`, `just_audio_web`,
`rxdart`, `synchronized` (transitives), aucune version modifiée par
ailleurs. Aucun changement fonctionnel - uniquement le fichier de
verrouillage des dépendances.

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

### Mise à jour - bootstrap réel effectué (même jour)

Le bootstrap ci-dessus a été réalisé pour de vrai sur le poste Windows de
l'utilisateur, avec 3 bugs réels trouvés et corrigés (méthode "vagues"
identique à R0) :

- Import manquant `package:drift/drift.dart` (`LazyDatabase` n'est pas
  exporté par `package:drift/native.dart`) - commit `cd1be3b`.
- Lint `prefer_const_constructors` - même commit.
- `flutter build apk --debug` : "Build failed due to use of deleted
  Android v1 embedding" - causé par un dossier `android/` incomplet sur ce
  poste (`AndroidManifest.xml`/`MainActivity` absents), pas par le code R1
  lui-même. Corrigé par `flutter create . --org com.reserveflash
  --platforms=android,ios` puis restauration ciblée des deux fichiers
  Gradle protégés du correctif CameraX R0.2
  (`git checkout -- android/app/build.gradle.kts
  android/build.gradle.kts`, vérifiés non modifiés par `flutter create`).

Résultat final, confirmé deux fois (poste utilisateur + CI GitHub Actions
sur runner Ubuntu propre, commits `cd1be3b` et `e18980c`, CI #5/#6 vertes) :
`flutter analyze` 0 erreur/0 info, `flutter test` **61/61 verts** (dont
l'intégralité de `r1_capture_offline_test.dart`), APK debug construit
(185 591 137 octets, SHA-256
`f353d6e1cc2e8c751574769f19d789274c22747d7aadf68cd8df2a79f9f7dea5`). Le
risque documenté du plugin `record: ^7.1.1` ne s'est PAS matérialisé.

### Mise à jour - parcours manuel réel sur appareil Android effectué (même jour)

Le parcours manuel sur un vrai téléphone (seul point restant après le
bootstrap ci-dessus) a été déroulé pour de vrai sur un Samsung Galaxy A51
(`SM-A515F`), mode avion actif de bout en bout : installation de l'APK,
création d'un incident réel, photo du BL, sélection du type de problème,
capture guidée de 3 photos de preuve, description texte + note vocale,
écran de clôture du dossier ("Dossier terminé"), fermeture complète de
l'application puis réouverture avec le dossier et toutes ses preuves
intacts (BL, 3 photos, note vocale, commentaire, type de problème),
refus de permission caméra affichant l'écran contrôlé prévu (aucun
crash, aucune perte de dossier), suppression avec dialogue de
confirmation ("Supprimer tout le dossier ?"), et correction des
informations via le formulaire dédié. Détail complet, écran par écran,
dans `docs/GATE_R1_STATUS.md` (section "Parcours manuel réel sur appareil
Android - preuve obtenue").

Deux points environnementaux (non liés au code livré) ont retardé ce
diagnostic et sont documentés par souci de traçabilité dans
`docs/GATE_R1_STATUS.md` : un dossier de projet dupliqué non suivi par git
sur le poste de l'utilisateur (contenant du code R0 obsolète) a été testé
par erreur avant identification du bon dépôt, et la gestion de batterie
Samsung ("Optimisé"/veille des apps récemment installées) retardait le
premier lancement à froid par l'icône - résolu en passant l'app en "Non
restreint" dans les réglages de batterie.

**Toutes les preuves attendues pour le Gate R1 sont désormais réunies.
Conformément à la demande corrective, cette entrée ne déclare PAS R1
PASS : la décision revient exclusivement à la recette indépendante - voir
`docs/GATE_R1_STATUS.md`.**

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
