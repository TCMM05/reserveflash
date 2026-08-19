# Sécurité et confidentialité - état de conformité R0.1

Suivi des exigences GATE section 10.1. Statut honnête à date de cette
baseline (18 août 2026) - certaines lignes sont "conforme par construction
mais non déployé" tant que le backend ne tourne qu'en local/dev.

**Mise à jour R0.1 (pivot Local-First, voir
docs/adr/0002-local-first-pivot.md)** : le périmètre de ce document change de
nature. En R0, la confidentialité portait principalement sur un futur
backend qui aurait hébergé les dossiers. En R0.1, les dossiers ne quittent
plus jamais le téléphone par défaut (point 14 de la demande corrective) - le
seul flux réseau possible est un appel ponctuel et minimal vers
`/v1/ai/transcribe` ou `/v1/ai/extract` (voir section "Minimisation des
données envoyées à l'IA" ci-dessous), qui ne persiste rien côté serveur.

| ID | Exigence | Statut R0.1 | Détail |
|---|---|---|---|
| SEC-01 | TLS obligatoire ; aucune API HTTP non chiffrée en production. | ⏳ N/A en dev | À appliquer par la configuration de l'hébergeur en R7 (aucun serveur de production n'existe encore) ; portée réduite en R0.1 au seul trafic `/v1/ai/*` (voir mise à jour ci-dessus). |
| SEC-02 | Secrets uniquement backend/secret manager ; aucun secret sensible dans le mobile. | ✅ Conforme | `app/config.py` : tout secret est `SecretStr | None`, jamais de valeur par défaut en dur. `GET /config` ne renvoie que des versions de template/schéma (voir `tests/api/test_incidents_flow.py::test_config_never_exposes_secrets`). Le mobile n'embarque aucune clé (aucun provider réel câblé côté client) - GATE renforcée en R0.1, point 5 : flux obligatoire Flutter -> Backend -> OpenAI -> Backend -> Flutter, jamais d'appel direct mobile -> OpenAI. |
| SEC-03 | Buckets privés ; accès aux médias par URL signée courte. | ⏳ Optionnel/futur (R0.1, point 11) | Chemin cloud non requis pour la V1 (`app/api/routes/incidents.py` conservé mais non appelé par le mobile). Les médias vivent dans l'espace privé de l'app (`LocalEvidenceAssets`, voir docs/local_storage_schema.md) - la question "URL signée courte" ne s'applique qu'à un futur mode cloud. |
| SEC-04 | Isolation multi-tenant par organization_id + contrôles backend ; RLS si compatible. | ⏳ Optionnel/futur (R0.1, point 11) | Contrôles applicatifs toujours présents et testés côté chemin cloud conservé (`InMemoryIncidentRepository._assert_same_tenant`), mais non pertinents pour la V1 locale (un dossier local n'a pas d'`organization_id` obligatoire, point 13). |
| SEC-05 | Tokens dans Keychain/Keystore ; pas dans SharedPreferences en clair. | ⏳ Différé (R0.1, point 13) | `flutter_secure_storage` listé en dépendance mobile ; sans objet tant qu'aucun flux d'auth réel n'est activé (compte cloud optionnel, différé). |
| SEC-06 | Logs production sans audio, photo, document, adresse, nom chauffeur, texte de réserve complet. | ✅ Conforme par construction | `AuditEvent.metadata_safe_json` (nommage explicite) ; aucun log applicatif n'écrit de champ métier brut dans ce squelette. Renforcé en R0.1 : les routes `/v1/ai/*` ne persistent ni ne loggent le contenu transmis (voir section "Minimisation des données envoyées à l'IA"). À revalider par revue de code à chaque PR (pas d'outil automatique). |
| SEC-07 | Rate limiting et limites taille MIME ; validation type réel des fichiers. | ⏳ ROADMAP | Non implémenté (pas de gateway/API réelle exposée publiquement). Prévu avant exposition publique des routes `/v1/ai/*` (voir docstring `app/api/routes/ai.py`). |
| SEC-08 | Suppression compte/données disponible et testée. | ⏳ ROADMAP | En V1 locale, la suppression est déjà possible nativement (désinstallation de l'app, ou suppression d'incident individuel une fois l'écran S16 implémenté) - aucune donnée serveur à supprimer puisqu'aucune n'y est stockée durablement (point 4). Un écran dédié "Supprimer toutes mes données locales" reste ROADMAP. |
| SEC-09 | Backups DB et procédure de restauration documentée. | 🟠 Partiel - NON chiffré, NON conforme R4 | Remplacé par le point 9 de la demande corrective (portée R0.1, PAS R4) : voir `mobile/lib/data/backup/backup_service.dart`. Fait : format versionné `reserveflash_backup.v1`, restauration testable, refus d'une archive corrompue AVANT toute mutation locale (vérification SHA-256 par pièce, ajoutée en R0.2). **Pas fait, ne pas déclarer conforme avant que ce soit le cas : l'archive n'est PAS chiffrée** (`BackupResult.isEncrypted` renvoie explicitement `false`). Le cahier des charges exige un export de sauvegarde chiffré pour la fonctionnalité complète (R4) - voir `docs/GATE_R0.1_STATUS.md`. |
| SEC-10 | Secret scan CI ; dépendances scannées ; aucune clé dans Git history de livraison. | ✅ Conforme | Job `secret-scan` (gitleaks) + grep de motifs de clé dans le job `backend` (`.github/workflows/ci.yml`). |

## Minimisation des données envoyées à l'IA (R0.1, point 14)

"Par défaut, les dossiers professionnels restent sur le téléphone de
l'utilisateur. Ne transmettre au backend IA que les données strictement
nécessaires à l'opération demandée. Éviter d'envoyer systématiquement toutes
les photos si cela n'est pas nécessaire pour l'analyse. Documenter
précisément quelles données sont envoyées à l'API IA."

Les DEUX seules routes réseau que l'app mobile peut appeler pour une
opération IA sont `POST /v1/ai/transcribe` et `POST /v1/ai/extract`
(`backend/app/api/routes/ai.py`, `mobile/lib/domain/entities/ai_queue_item.dart`
pour la file locale qui les déclenche). Contrat exact :

| Route | Envoyé au backend | JAMAIS envoyé |
|---|---|---|
| `POST /v1/ai/transcribe` | UN extrait audio (`audio_base64`) + son type MIME. L'extrait correspond à une seule note vocale ponctuelle choisie explicitement par l'utilisateur (F06/F11), jamais un enregistrement continu ni l'historique audio de l'incident. | Aucun identifiant d'incident/organisation (la requête n'en contient pas - voir `tests/api/test_ai_routes.py::test_ai_routes_do_not_expose_incident_or_organization_concepts`) ; aucune photo ; aucun autre champ du dossier (fournisseur, transporteur, notes, faits déjà confirmés). |
| `POST /v1/ai/extract` | UN texte déjà transcrit ou OCRisé (`document_text` OU `transcript`) + la version de prompt. | Aucune image/audio brut (l'app effectue l'OCR/la transcription AVANT cet appel - étape locale ou via `/transcribe` au préalable) ; aucun autre incident/anomalie que celui concerné par l'appel ; aucun `ConfirmedFactData` déjà validé (ce serait inutile : seul `CandidateFactData`, non confirmé, est produit par cette route). |

Ce que le backend ne reçoit JAMAIS, par construction (aucune route ne les
accepte - vérifié par les schémas pydantic `extra="forbid"`, voir
`app/api/schemas.py`) : les photos elles-mêmes, les bons de livraison/PDF,
l'historique complet d'un incident, le nom du fournisseur/transporteur/
client, l'adresse de livraison, un `ConfirmedFactData` ou une réserve
composée.

Ce que le backend ne stocke JAMAIS durablement (point 4) : les routes
`/v1/ai/*` ne dépendent d'aucun `IncidentRepository` ni `StorageProvider` -
la requête est traitée en mémoire process pour la durée de l'appel HTTP puis
oubliée. Aucune base de données, aucun fichier, aucun log applicatif ne
conserve le contenu d'un extrait audio ou d'un texte transmis (SEC-06 reste
applicable : ni l'un ni l'autre n'apparaît dans les logs). Seul un provider
IA réel (ex: OpenAI en R2, non encore implémenté - `mock` en R0.1) recevrait
cette donnée en aval, selon sa propre politique de rétention documentée
séparément avant activation en production.

## Analytics - propriétés interdites (section 13.2)

Aucun événement analytics n'est implémenté en R0 (section 13 est prévue R5 -
"Produit commercial"). Ce document sert de rappel pour cette étape : nom
fournisseur/transporteur, n° BL, texte transcrit, description dommage, nom
client/chauffeur, contenu OCR, photo/audio, adresse exacte ne doivent JAMAIS
apparaître dans un payload analytics.
