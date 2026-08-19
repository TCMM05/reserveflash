# rulepacks/

Règles métier/juridiques versionnées et désactivables (section 5.2, 11).

## Principe (section 11.1)

> "Les règles juridiques ou contractuelles ne doivent jamais être stockées
> dans un prompt. Elles sont décrites dans des fichiers/version DB RulePack,
> avec source, juridiction, mode de transport, périmètre, date d'effet,
> version et état d'activation."

Chaque fichier `*.yaml` de ce dossier est un RulePack. Le moteur de constat
(F01-F13) ne dépend d'AUCUN rule pack pour fonctionner (section 11.3) : un
rule pack ajoute uniquement des rappels contextuels (`Reminder`, section 6.1)
une fois validé et activé.

## Cycle de vie d'un RulePack

| status | Sens |
|---|---|
| `DISABLED_PENDING_LEGAL_REVIEW` | Créé mais non activé - c'est l'état par défaut de tout nouveau pack (voir `fr_road_domestic_general_2026_01.yaml`). |
| `ACTIVE` | Validé métier/juridique, ses rappels sont affichés avec source + version (section 11.3). |
| `RETIRED` | Remplacé par une version plus récente ; conservé pour audit, jamais réactivé. |

Règles strictes (section 11.3, GATE juridique section 1.4) :

- Aucun rule pack n'est sélectionné automatiquement à partir d'une
  supposition du LLM.
- Si le périmètre est ambigu, l'application affiche "vérifiez le cadre
  applicable" plutôt qu'un délai présenté comme certain.
- L'activation d'un pack (`DISABLED_PENDING_LEGAL_REVIEW` -> `ACTIVE`) exige
  un `reviewer`, une `reviewed_at` et suit la politique de changement section
  18.1 ("Tout changement rule pack = source + reviewer + effective date +
  tests.").

## Chargement applicatif

`backend/app/domain/rule_pack.py` définit le modèle `RulePack` (validation
stricte des champs ci-dessus) et `backend/app/infrastructure/rulepacks/loader.py`
charge et valide tous les fichiers de ce dossier. Un pack dont `status` n'est
pas `ACTIVE` n'est jamais proposé par `list_active_rule_packs()`.
