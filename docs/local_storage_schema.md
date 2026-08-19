# Schéma de stockage local - ReserveFlash Incident (R0.1)

Document requis par le point 16 de la demande corrective "Local-First"
("schéma de stockage local" comme livrable explicite). Décrit le schéma
Drift/SQLite (`mobile/lib/data/local/app_database.dart`), qui est la source
de vérité canonique d'un dossier ReserveFlash pour la V1 (voir
`docs/adr/0002-local-first-pivot.md`).

## 1. Principes

- SQLite via Drift, structuré et versionné - jamais un fichier JSON à plat
  (point 2 de la demande corrective).
- Aucune table ne dépend du réseau pour être lue/écrite. La seule table liée
  au réseau (`AiOperationQueue`) porte des opérations *optionnelles* : leur
  absence de traitement immédiat ne bloque jamais la création, la
  consultation ou la modification d'un dossier.
- Toute pièce jointe (photo, audio, BL, PDF) est un fichier sur le disque de
  l'appareil (espace privé de l'app, `path_provider`) ; les tables Drift ne
  stockent que des métadonnées + chemin + hash.

## 2. Tables (schéma v2, R0.1)

### `LocalIncidents`

| Colonne | Type | Notes |
|---|---|---|
| `id` (PK) | text | UUID local, généré côté app - AUCUNE dépendance à un ID serveur en V1. |
| `organization_id` | text? | Nullable - aucun compte requis pour créer un incident (point 13). |
| `status` | text | `IncidentStatus.wireValue` (section 2.2, machine à états inchangée). |
| `occurred_at` | datetime | Date de l'incident (saisie utilisateur). |
| `local_created_at` | datetime | Horodatage de création locale. |
| `server_created_at` | datetime? | Réservé à un futur mode cloud - toujours `null` en V1. |
| `supplier_name`, `carrier_name`, `delivery_ref`, `notes` | text? | Champs libres saisis par l'utilisateur. |
| `pending_server_id` | bool | Réservé futur cloud (défaut `false`). |
| `archived` | bool | Archivage local (défaut `false`). |

### `LocalIssues`

Une anomalie déclarée au sein d'un incident (section 2.5 - un incident peut
avoir plusieurs anomalies indépendantes). `id` (PK), `incident_id`,
`issue_type` (`IssueType.wireValue`), `sort_order`, `status`.

### `LocalCandidateFactSets`

Sortie IA brute, en attente de revue (section 7.2) - **jamais lue par le
Reserve Composer** (GATE zéro invention). `id` (PK), `issue_id`,
`schema_version`, `prompt_version`, `model`, `raw_structured_json`
(`CandidateFactData` sérialisé), `created_at`.

### `LocalConfirmedFactSets`

Faits validés par l'utilisateur (F09, invariant 6.3) - historisés par
révision, jamais mutés en place. `id` (PK), `issue_id`, `schema_version`,
`confirmed_json` (`ConfirmedFactData` sérialisé, **déjà passé par
`liability_guard`** avant insertion), `confirmed_by` (nullable, point 13),
`confirmed_at`, `revision`.

### `LocalReserveTexts`

Réserve composée localement (F10). Une ligne = la dernière composition
valide pour un incident. `id` (PK), `incident_id`, `template_version`,
`confirmed_fact_revision`, `text`, `sha256`, `created_at`.

### `LocalExportBundles`

Métadonnées du PDF exporté (F14). `id` (PK), `incident_id`, `version`,
`local_file_path`, `sha256`, `created_at`, `superseded`.

### `LocalEvidenceAssets`

Champs minimum imposés par le point 3 de la demande corrective - **tous
présents, aucun optionnel sauf `issue_id`/`sha256`** :

| Colonne | Exigence point 3 |
|---|---|
| `id` | "id" |
| `incident_id` | "incident associé" |
| `document_type` | "type de document" (`photo` \| `audio` \| `delivery_note` \| `exported_pdf`) |
| `captured_at_device` | "date/heure de capture" |
| `local_file_path` | "chemin local" |
| `sha256` | "SHA-256" (nullable uniquement pendant la fenêtre atomique entre écriture disque et calcul de hash, jamais après) |
| `availability_status` | "statut de disponibilité" (`available` \| `missing` \| `corrupted`) |

`issue_id` (nullable, une pièce peut concerner l'incident entier), `mime_type`,
`bytes` complètent le schéma.

### `AiOperationQueue`

File des opérations nécessitant le réseau (point 6 - remplace la
`SyncOperations` générique de R0, voir `docs/adr/0002-local-first-pivot.md`).
`id` (PK), `incident_id`, `issue_id` (nullable), `operation_kind`
(`transcribe_audio` \| `extract_from_photo` \| `extract_from_document`),
`payload_json` (minimal, point 14), `idempotency_key`, `status` (`pending` \|
`in_progress` \| `done` \| `failed`), `retry_count`, `created_at`,
`last_attempt_at`, `last_error`, `result_json`.

### `BackupEvents`

Historique des exports/imports de sauvegarde (point 9) - trace uniquement,
jamais le contenu de la sauvegarde elle-même. `id` (PK), `kind` (`export` \|
`import`), `app_schema_version`, `file_path`, `sha256`, `incident_count`,
`evidence_asset_count`, `created_at`, `missing_asset_count`.

## 3. Migrations

`AppDatabase.schemaVersion` (actuellement `2`). Toute évolution future doit :

1. Incrémenter `schemaVersion`.
2. Ajouter une branche explicite dans `MigrationStrategy.onUpgrade` (jamais
   de `createAll()` aveugle sur une base existante - voir le commentaire
   détaillé dans `app_database.dart` pour l'historique v1 -> v2).
3. Ne jamais supprimer une colonne/table contenant des données utilisateur
   sans étape de copie explicite vers le nouveau schéma (NFR-10, section 14 -
   "Upgrade N-1 -> version courante sans perte de dossier local").

## 4. Format de sauvegarde `reserveflash_backup.v1` (point 9)

Fichier ZIP standard (extension conseillée `.rfbackup`), produit/lu par
`mobile/lib/data/backup/backup_service.dart` :

```
manifest.json   - {format_version, app_schema_version, created_at,
                   incident_count, evidence_asset_count,
                   evidence_files_missing_at_export_time}
tables.json     - contenu intégral des 7 tables métier (hors AiOperationQueue
                   et BackupEvents, qui sont des files/historiques
                   techniques non restaurables tels quels), sérialisé en
                   JSON simple (clés snake_case, symétriques à l'export/import)
evidence/<id>.<ext> - copie binaire de chaque pièce référencée par
                   LocalEvidenceAssets, nommée par id (jamais par le chemin
                   absolu d'origine, qui n'est pas portable entre appareils)
```

Pourquoi pas une copie brute du fichier `.sqlite` : `local_file_path` est un
chemin ABSOLU dans le bac à sable de l'app émettrice - une copie brute
resterait valide en apparence mais référencerait des fichiers inexistants
dès qu'elle est restaurée sur un autre appareil/une autre installation.
L'export structuré ci-dessus réécrit ces chemins au moment de l'import.

Restauration (`importBackup`) : **remplace** l'état local actuel (pas de
fusion en V1, documenté explicitement - voir docstring de
`BackupService.importBackup`). Toute pièce référencée mais absente de
l'archive (déjà manquante au moment de l'export, ou fichier corrompu) est
marquée `availability_status = 'missing'` après import - jamais silencieux
(transparence obligatoire, point 9 : "la restauration complète doit être
testable").

Le PDF binaire d'un `LocalExportBundle` n'est PAS inclus dans la sauvegarde
en R0.1 (seules les preuves sources le sont) : après import, `local_file_path`
est réinitialisé et le dossier doit être re-exporté si besoin. Documenté
comme limitation connue (voir `docs/architecture.md`, section
"Limitations connues").
