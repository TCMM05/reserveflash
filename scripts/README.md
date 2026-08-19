# scripts/

Utilitaires transverses au monorepo (build, seed, QA - section 5.2).

Les scripts spécifiques au backend vivent dans `backend/scripts/` (ex:
`generate_openapi.py`) pour rester proches de leur environnement Python. Ce
dossier racine est réservé aux scripts qui orchestrent plusieurs
sous-projets à la fois (ex: un futur `seed_demo_data.sh` qui démarre le
backend en mode staging ET peuple des incidents de démonstration côté
mobile). Vide en R0 - aucun script transverse n'est encore nécessaire.
