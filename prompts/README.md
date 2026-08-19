# prompts/

Prompts versionnés pour le pipeline d'extraction IA (section 7.2, 7.3).

Vide en R0 (Fondation) : le provider IA actif est `mock`
(`backend/app/infrastructure/ai/mock_provider.py`), qui ne consomme aucun
prompt réel. Ce dossier sera peuplé en **R2 - IA extraction** (section 18)
lors de l'implémentation du provider OpenAI réel
(`backend/app/infrastructure/ai/openai_provider.py`, non encore créé).

Rappel (section 7.3) : "Tout changement de prompt/schéma/modèle qui affecte
l'extraction nécessite un nouveau run benchmark et un CHANGELOG." Les prompts
doivent être versionnés ici en fichiers texte/YAML nommés
`<usage>_<langue>_v<N>.txt`, jamais modifiés en place une fois utilisés en
production (créer une nouvelle version).
