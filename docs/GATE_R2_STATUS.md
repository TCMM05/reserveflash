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
   un OCR local/on-device lorsque cela est raisonnable" ; pas encore
   implémenté (voir section "Reste à faire" ci-dessous).
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
   sont destinées à l'écran déjà scaffoldé mais vide `S07`
   (`mobile/lib/features/document_capture/presentation/document_metadata_screen.dart`),
   distinct du flux `CandidateFactSet` de l'incident. Cette séparation reste
   à confirmer/implémenter côté mobile (non commencé).

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

### Mobile - PAS COMMENCÉ

- OCR on-device (ML Kit) sur la photo du BL.
- Entité Dart `CandidateFactSet` (absente malgré les tables Drift déjà
  prêtes - `LocalCandidateFactSets`, `LocalConfirmedFactSets`,
  `AiOperationQueue`).
- Câblage `AiOperationQueue`/`PendingAIJob` (déclenchement online, mise en
  file offline, traitement différé au retour réseau).
- Écran de revue réel (`facts_review_screen.dart` est aujourd'hui un stub à
  champs codés en dur, non connecté au pipeline).
- `document_metadata_screen.dart` (S07, métadonnées BL - voir décision 4
  ci-dessus).

### Recette terrain - PAS COMMENCÉE

Nécessite : une clé OpenAI réelle fournie par l'utilisateur, le mobile
fonctionnel (voir ci-dessus), et un appareil Android réel - aucun des trois
n'est disponible dans cet environnement de développement.

## Prochaines étapes

1. Mobile : OCR + entité `CandidateFactSet` + câblage `AiOperationQueue` +
   écran de revue réel.
2. Recette terrain avec clé OpenAI réelle sur appareil Android réel
   (protocole fourni par l'équipe, section "Test terrain obligatoire").
3. Run `benchmark/run_scorer.py --provider openai` réel, rapport versionné.
4. Livraison `r2-candidate` (ZIP, commit, tag, APK CI, SHA-256, ce document
   mis à jour, `R2_BENCHMARK_REPORT.md`, captures, preuve du test terrain) -
   soumission à la recette indépendante. **Aucun verdict "GATE R2 PASS" ne
   sera déclaré par ce document ni par son auteur.**
5. R3 : aucun développement avant validation du Gate R2 par la recette
   indépendante.
