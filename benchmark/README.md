# benchmark/

Corpus CORE/STRESS + scorer pour la qualification du pipeline IA (section
15.1, 15.2, 15.3).

Vide en R0 (Fondation). Sera peuplé en **R6 - Qualification** (section 18) :

- Corpus (section 15.1) : CORE (60), PARAPHRASE/LEXICAL (60),
  NEGATION/CORRECTION (40), AUDIO STRESS (30), OCR STRESS (30),
  UNSUPPORTED/SAFETY (20) - total 240 cas minimum.
- Scorer : calcule les métriques du gate section 15.2 (issue type correct
  ≥95%, quantités exactes ≥98%, cas incertains signalés ≥95%, demandes hors
  scope bloquées 100%, réserve avec fait non confirmé = 0, contradiction
  résolue silencieusement = 0, fallback disponible = 100%).
- Anti-overfitting (section 15.3) : DEV/REGRESSION/HOLDOUT strictement
  séparés ; le HOLDOUT n'est scoré qu'après gel de la version candidate.

Ce dossier ne doit contenir aucune donnée personnelle réelle (clients,
fournisseurs) - uniquement des cas synthétiques ou anonymisés, conformément
à la politique de confidentialité (section 10).
