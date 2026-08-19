# schemas/

Contrats JSON Schema partages entre backend, pipeline IA et (via generation) le mobile.
Ce sont les seuls schemas autorises a circuler entre les couches IA et domaine (section 5.3,
regle de dependance : le domaine ne connait ni OpenAI, ni Supabase, ni Flutter).

| Fichier | Objet | Genere/consomme par |
|---|---|---|
| `candidate_fact_set.v1.schema.json` | Sortie brute structuree du pipeline IA (etape 4, section 7.2). Jamais ecrite directement en base "confirmee". | `backend/app/infrastructure/ai/*`, valide en 422 `AI_INVALID_OUTPUT` si non conforme. |
| `confirmed_fact_set.v1.schema.json` | Jeu de faits canonique apres validation humaine (F09). Seule entree autorisee du Reserve Composer (GATE zero invention, section 2.4). | `backend/app/domain/*`, `backend/app/api/routes/facts.py`. |

## Regles de versioning (section 7.3 / 15.3)

- Tout changement de champ, d'enum ou de contrainte cree un nouveau fichier `*.v2.schema.json` ; les
  anciens schemas restent en place pour compatibilite/audit.
- `CandidateFactSet.schema_version` et `ConfirmedFactSet.schema_version` (voir modele de donnees,
  section 6.1) referencent le nom de fichier exact utilise a la generation.
- Tout changement de schema affectant l'extraction IA declenche un nouveau run de benchmark complet
  (section 18.1, politique de changement).
