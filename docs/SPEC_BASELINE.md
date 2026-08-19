# SPEC_BASELINE - référence contractuelle de ce dépôt

Ce document existe en réponse directe au point 3 (🟠) du retour de recette
R0.1 : *"Le dépôt pointe toujours sur le mauvais cahier des charges"*, qui
demandait d'enregistrer dans le dépôt un marqueur `SPEC_BASELINE` /
`SPEC_DATE` / `SPEC_SHA256`.

## Constat, en toute transparence

Le retour de recette cite un document *"cahier v1.1 Local-First -
RÉFÉRENCE CONTRACTUELLE - REMPLACE V1.0"*, avec des extraits précis
(formulation exacte du Gate R0, interdiction d'endpoint d'historique
métier, obligation de chiffrement de la sauvegarde, exigences R4 sur
l'import chiffré/hashes/refus d'archive corrompue).

Une recherche exhaustive a été effectuée avant d'écrire ce document, dans
les deux seuls emplacements auxquels ce développeur a accès :

- le dossier des fichiers envoyés dans cette conversation
  (`/mnt/user-data/uploads/Reserveflash/`) ;
- le dossier connecté sur l'ordinateur de l'utilisateur
  (`Application claude/Reserveflash`, listé récursivement).

**Aucun fichier "v1.1" n'existe dans l'un ou l'autre emplacement.** Le seul
cahier des charges accessible est bien celui référencé ci-dessous, en
version 1.0. Ce document ne peut donc PAS enregistrer un `SPEC_SHA256`
pour un fichier v1.1 sans l'inventer - ce qui violerait directement le
principe "GATE zéro invention" (section 2.4 du cahier v1.0 lui-même) que ce
projet applique à son propre contenu métier.

**Si un cahier v1.1 existe réellement côté Product Owner**, merci de le
déposer dans la conversation ou dans le dossier connecté : ce document sera
alors mis à jour avec son SHA-256 réel, et chaque clause citée dans le
retour de recette (formulation exacte du Gate R0, périmètre API,
obligation de chiffrement) sera vérifiée mot pour mot contre le texte
source avant d'être déclarée respectée - plutôt que d'être supposée à partir
d'une citation dans un message.

## Ce qui EST enregistré ici, vérifiable par quiconque a accès au dépôt

| Clé | Valeur |
|---|---|
| `SPEC_BASELINE` | ReserveFlash Incident - Cahier des charges v1.0 (seul document contractuel confirmé disponible), **modifié** par la demande corrective officielle "R0.1 Local-First" (transmise dans la conversation ayant produit ce dépôt, retranscrite intégralement dans `docs/adr/0002-local-first-pivot.md`) |
| `SPEC_DATE` | Cahier v1.0 : date du fichier fourni. Demande corrective R0.1 : 2026-08-18. Présente clôture R0.2 : 2026-08-19. |
| `SPEC_SHA256` | `f5bf84b5d42ac705d27771a3aa9174dcdbb5c8c2b542b1550ff799e3bf7cc371` (SHA-256 réel, calculé dans cette session, du fichier `ReserveFlash_Incident_Cahier_des_Charges_v1.0.pdf` tel que fourni) |
| `SPEC_V1_1_STATUS` | **NON TROUVÉ** - aucun fichier v1.1 n'est présent dans les emplacements accessibles à ce développeur à la date ci-dessus. Les clauses attribuées à un "cahier v1.1" dans le retour de recette (ex: interdiction totale d'endpoint d'historique métier en V1, chiffrement obligatoire de la sauvegarde) sont traitées ci-dessous comme des **exigences explicitement demandées par le Product Owner dans sa revue**, et donc suivies au même titre qu'une exigence contractuelle - mais sans pouvoir leur attribuer une clause numérotée d'un document source vérifié. |

## Comment les clauses citées ont été traitées malgré l'absence du document

Trois clauses du retour de recette, attribuées au "cahier v1.1", ont un
impact direct sur le code de cette livraison R0.2. Chacune a été traitée
comme une demande directe et explicite du Product Owner (ce qui suffit à la
rendre opposable, indépendamment de son origine documentaire) :

1. *"Aucun endpoint d'historique métier : l'historique appartient à la base
   locale Drift."* -> `/v1/incidents/*` n'est plus monté par défaut (voir
   `backend/app/config.py::enable_legacy_cloud_incident_api`,
   `backend/app/main.py`, `backend/tests/api/test_legacy_api_disabled_by_default.py`).
2. *"Export de sauvegarde complet obligatoirement chiffré."* -> **PAS
   fait** dans cette clôture R0.2, et explicitement non déclaré conforme
   (voir `docs/security.md`, ligne SEC-09, et
   `mobile/lib/data/backup/backup_service.dart::BackupResult.isEncrypted`
   qui renvoie `false`). Le retour de recette lui-même précise que ce point
   ne bloque pas R0.1/R0.2 - seule la déclaration abusive de conformité
   était interdite.
3. *"[R4] export/import chiffré, hashes, puis refus d'une archive
   corrompue avant toute mutation locale."* -> la partie "hashes + refus
   d'une archive corrompue avant toute mutation locale" EST faite dans
   cette clôture R0.2 (vérification SHA-256 par pièce jointe, AVANT le
   `db.transaction(...)` destructeur - voir
   `BackupService.importBackup()` et `BackupIntegrityException`). La partie
   "chiffré" reste non faite (point 2 ci-dessus) - R4 dans son ensemble
   n'est donc PAS déclaré atteint.

## Traçabilité des versions de ce dépôt

| Version | Date | Portée |
|---|---|---|
| 0.1.0 | R0 Fondation | Baseline initiale, cahier v1.0 uniquement |
| 0.1.1 | R0.1 Local-First | Pivot architectural corrigeant R0 (voir `docs/adr/0002-local-first-pivot.md`) |
| 0.1.2 | R0.2 Clôture ciblée | Réponse point-par-point au retour de recette R0.1 (voir `CHANGELOG.md`) - **ce document `SPEC_BASELINE.md` est introduit à cette version** |
