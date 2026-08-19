# SPEC_BASELINE - référence contractuelle de ce dépôt

Ce document existe en réponse directe au point 3 (🟠) du retour de recette
R0.1 : *"Le dépôt pointe toujours sur le mauvais cahier des charges"*, qui
demandait d'enregistrer dans le dépôt un marqueur `SPEC_BASELINE` /
`SPEC_DATE` / `SPEC_SHA256`, puis au point 1 du retour de recette R0.2.2 :
*"remplacer toutes les références v1.0 par le baseline v1.1 (avec son
SHA-256)"*.

## Mise à jour R0.2.2 : le cahier v1.1 a été fourni et vérifié

Le fichier `ReserveFlash_Incident_Cahier_des_Charges_v1.1_LocalFirst.pdf` a
été déposé dans la conversation le 2026-08-19. Contrairement au SHA-256 cité
par l'équipe dans son retour, qui n'avait pas pu être vérifié faute de
fichier réel (voir historique ci-dessous), ce fichier a été vérifié
indépendamment par ce développeur :

- `sha256sum` recalculé directement sur le fichier reçu ->
  `1c6b3db672d9d622679ecd6c8b20908e575e2702eeb4dcc839609b21ea5ccd1b` -
  **identique, caractère pour caractère**, au SHA-256 cité par l'équipe dans
  le retour de recette. Le fichier est donc authentifié par ce
  développeur lui-même, pas seulement pris sur la foi d'une citation.
- Les 33 pages du document ont été lues intégralement et chaque clause
  précédemment traitée "sans source numérotée" (voir section suivante) a
  été retrouvée mot pour mot dans le texte.

## Ce qui EST enregistré ici, vérifiable par quiconque a accès au dépôt

| Clé | Valeur |
|---|---|
| `SPEC_BASELINE` | ReserveFlash Incident - Cahier des charges **v1.1 Local-First** - "RÉFÉRENCE CONTRACTUELLE - REMPLACE V1.0" (page 1, tableau de métadonnées du document) |
| `SPEC_DATE` | 18 août 2026 (date de baseline indiquée en page 1 et en pied de page de chaque page : *"Baseline contractuelle v1.1 Local-First - 18 août 2026"*) |
| `SPEC_SHA256` | `1c6b3db672d9d622679ecd6c8b20908e575e2702eeb4dcc839609b21ea5ccd1b` - calculé indépendamment par ce développeur avec `sha256sum` sur le fichier reçu dans la conversation, et confirmé identique au SHA-256 cité par l'équipe |
| `SPEC_V1_1_STATUS` | **TROUVÉ ET VÉRIFIÉ** (2026-08-19) - fichier reçu, hash vérifié, contenu lu intégralement (33 pages) et confronté aux clauses citées dans les retours de recette précédents |
| `SPEC_V1_0_SHA256` (archive) | `f5bf84b5d42ac705d27771a3aa9174dcdbb5c8c2b542b1550ff799e3bf7cc371` - cahier v1.0, conservé ici uniquement à titre d'historique ; **remplacé** par le v1.1 ci-dessus, qui est désormais la seule référence contractuelle active |

## Clauses vérifiées mot pour mot contre le texte source du v1.1

Les clauses suivantes, précédemment traitées comme des "exigences du
Product Owner sans clause numérotée vérifiable" (voir historique
ci-dessous), ont maintenant une source exacte dans le cahier v1.1 :

1. *"Aucun endpoint d'historique métier : l'historique appartient à la base
   locale Drift."* -> section 9.2, page 19. Confirmé conforme :
   `/v1/incidents/*` n'est plus monté par défaut (voir
   `backend/app/config.py::enable_legacy_cloud_incident_api`,
   `backend/app/main.py`, `backend/tests/api/test_legacy_api_disabled_by_default.py`).
2. *"Export de sauvegarde complet obligatoirement chiffré ; le PDF partagé
   séparément suit l'intention explicite de l'utilisateur."* -> SEC-08,
   page 20 (tableau exigences sécurité), corroboré par la ligne "Backup"
   du tableau d'architecture technique (page 13 : *"Archive versionnée
   .rfbackup ou équivalent, **chiffrée**"*). **Toujours PAS fait** dans le
   code à ce jour, et explicitement non déclaré conforme (voir
   `docs/security.md`, ligne SEC-09, et
   `mobile/lib/data/backup/backup_service.dart::BackupResult.isEncrypted`
   qui renvoie `false`). Reste un écart ouvert, maintenant contre une
   source contractuelle vérifiée plutôt qu'une citation non confirmée.
3. *"[R4] export/import chiffré, hashes, puis refus d'une archive
   corrompue avant toute mutation locale."* -> section 8.2, page 17-18
   (tableau "Sauvegarde corrompue/incomplète -> Refuser l'import avant
   mutation locale ; afficher les éléments invalides ; aucune restauration
   partielle silencieuse"), section 18 "R4 - Backup & intégrité", page 29
   (Gate de sortie : *"Restauration complète sans perte ; sauvegarde
   corrompue rejetée sans mutation"*), et checklist section 19, page 30
   (*"Archive corrompue refusée sans altérer les données locales"*). La
   partie "hashes + refus d'une archive corrompue avant toute mutation
   locale" EST faite (vérification SHA-256 par pièce jointe, AVANT le
   `db.transaction(...)` destructeur - voir `BackupService.importBackup()`
   et `BackupIntegrityException`). La partie "chiffré" reste non faite
   (point 2 ci-dessus) - R4 dans son ensemble n'est donc PAS déclaré
   atteint.
4. Formulation exacte du Gate de sortie R0 citée par l'équipe -> section
   18, page 29, tableau de séquençage : *"R0 - Fondation Local-First ->
   Monorepo, CI, navigation, thème, domaine, Drift/SQLite source de
   vérité, stockage privé. -> Gate de sortie : Build reproductible + tests
   domaine et DB locale verts."* Confirmé atteint par l'exécution réelle
   R0.2.1 (52/52 tests, build APK réussi - voir `CHANGELOG.md` et
   `docs/GATE_R0.1_STATUS.md`).
5. GATE architecture et GATE juridique (page 3) -> correspondent à
   l'implémentation existante de `liability_guard.dart` et du Reserve
   Composer déterministe (aucune réserve générée directement depuis la
   sortie brute du LLM ; formulations de responsabilité/indemnisation/
   validité juridique interdites à l'affichage).

## Historique - constat avant réception du fichier (pour mémoire)

Avant le 2026-08-19, aucun fichier "v1.1" n'était accessible à ce
développeur (recherche exhaustive effectuée dans les fichiers envoyés en
conversation et dans le dossier connecté sur l'ordinateur de
l'utilisateur). Le SHA-256 cité par l'équipe n'avait alors pas pu être
vérifié contre un fichier réel, et n'avait donc PAS été inscrit ici -
l'inscrire sans avoir vu le fichier aurait violé le principe "GATE zéro
invention" (section 2.4 du cahier lui-même) que ce projet applique aussi à
sa propre documentation de traçabilité. Cette section est conservée pour
la traçabilité de la décision, maintenant que le point est clos.

## Traçabilité des versions de ce dépôt

| Version | Date | Portée |
|---|---|---|
| 0.1.0 | R0 Fondation | Baseline initiale, cahier v1.0 uniquement |
| 0.1.1 | R0.1 Local-First | Pivot architectural corrigeant R0 (voir `docs/adr/0002-local-first-pivot.md`) |
| 0.1.2 | R0.2 Clôture ciblée | Réponse point-par-point au retour de recette R0.1 (voir `CHANGELOG.md`) - **ce document `SPEC_BASELINE.md` est introduit à cette version** |
| 0.1.4 | R0.2.2 Clôture documentaire/build | Cahier v1.1 reçu et vérifié (hash + lecture intégrale) ; ce document mis à jour en conséquence (voir `CHANGELOG.md`) |
