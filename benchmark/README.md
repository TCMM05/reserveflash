# benchmark/

Corpus CORE/STRESS + scorer pour la qualification du pipeline IA.

## Changement de séquencement (R2, 2026-08-20)

Ce dossier indiquait jusqu'ici (voir historique git) : "Vide en R0
(Fondation). Sera peuplé en R6 - Qualification (section 18)", avec un corpus
cible de 240 cas minimum (CORE 60, PARAPHRASE/LEXICAL 60,
NEGATION/CORRECTION 40, AUDIO STRESS 30, OCR STRESS 30, UNSUPPORTED/SAFETY
20). La demande de démarrage R2 reçue explicitement le construction d'un
corpus versionné + scorer **avant toute optimisation, dès R2** ("Benchmark
R2 obligatoire") - ce jalon est donc avancé de R6 à R2 par rapport au
séquençage documenté précédemment. **Décision non tranchée unilatéralement**
: signalée ici, dans `docs/GATE_R2_STATUS.md` et `CHANGELOG.md`, plutôt que
silencieuse.

Perimetre R2 (`benchmark/corpus/r2_corpus_v1.json`) : **50 cas**, pas les 240
cas ci-dessus - un corpus réel, versionné, couvrant les 7 catégories
demandées (CORE 8, PARAPHRASE 8, NEGATION 8, AUDIO 6, OCR 6, UNKNOWN 6,
SAFETY 8), incluant les 5 exemples obligatoires fournis par l'équipe
verbatim. Le corpus complet à 240 cas (DEV/REGRESSION/HOLDOUT séparés,
anti-overfitting) reste un objectif d'extension possible pour une
qualification plus poussée ultérieure - ce fichier `r2_corpus_v1.json` est
volontairement versionné (`v1`) pour permettre une extension `v2` sans
perdre la traçabilité des runs déjà effectués sur `v1`.

## Contenu

- `corpus/r2_corpus_v1.json` : le corpus lui-même (cas + attendus).
- `scorer.py` : calcule les métriques par cas et agrégées (précision,
  recall, exactitude issue_type, taux de faits inventés, taux de UNKNOWN
  corrects, taux de sorties invalides, taux de rejet sémantique, latence
  médiane/p95, taux de réussite SAFETY), séparément par catégorie et
  CORE vs STRESS (PARAPHRASE+NEGATION+AUDIO+OCR+UNKNOWN+SAFETY) - jamais une
  seule moyenne globale qui masquerait une mauvaise généralisation STRESS.
  Réutilise `app.domain.liability_guard.FORBIDDEN_PATTERNS` (backend/) comme
  source unique pour la vérification SAFETY - aucune duplication de motifs.
  Décorrélé de tout provider IA concret : prend des prédictions déjà
  produites (dict JSON conforme à `candidate_fact_set.v1`), n'appelle jamais
  de réseau lui-même. Testé (`benchmark/tests/test_scorer.py`, 20 tests,
  uniquement des prédictions construites à la main - aucun appel IA réel).
- `run_scorer.py` : exécute le corpus contre un provider réel
  (`--provider openai`, nécessite `RESERVEFLASH_OPENAI_API_KEY` et un accès
  réseau vers `api.openai.com` - indisponibles dans le sandbox où ce code a
  été écrit, à exécuter sur le poste utilisateur) ou contre le mock
  (`--provider mock`, sert de preuve d'intégration bout-en-bout du harnais,
  PAS une mesure de qualité réelle - voir docstring du script). Écrit un
  rapport JSON dans `results/`.
- `results/` : rapports générés (non commités par défaut au-delà de la
  preuve d'intégration `report_mock.json` - un run réel `--provider openai`
  doit être rejoué et son rapport versionné avant toute prétention de
  qualification, section "Livraison" de la demande R2 : "résultats bruts").

Ce dossier ne doit contenir aucune donnée personnelle réelle (clients,
fournisseurs) - uniquement des cas synthétiques, conformément à la politique
de confidentialité du projet (voir `docs/security.md`).
