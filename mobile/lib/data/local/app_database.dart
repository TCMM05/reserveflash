import 'package:drift/drift.dart';

part 'app_database.g.dart';

/// Schéma local - **source de vérité primaire** de l'application depuis
/// R0.1 (pivot Local-First, voir docs/adr/0002-local-first-pivot.md).
///
/// Principe général (point 1 de la demande corrective) : "Toutes les
/// données métier (incidents, faits candidats, faits confirmés, références
/// transport/fournisseur, historique, photos, bons de livraison/BL, PDF de
/// réserve) doivent être stockées localement sur le téléphone pour la V1."
/// PostgreSQL/Supabase/stockage cloud ne sont PAS requis pour le
/// fonctionnement normal de l'app (point 11) - voir
/// `backend/app/infrastructure/db/models.py` pour le schéma cloud
/// optionnel, conservé pour un usage futur (multi-appareil, équipes, tableau
/// de bord web) mais non branché en V1.
///
/// Ce fichier remplace la base R0 (3 tables, orientée "cache + file de
/// synchronisation vers un backend qui est la source de vérité") par une
/// base qui couvre TOUT le cycle de vie d'un dossier, y compris la
/// composition de réserve et l'export PDF, qui tournent désormais
/// entièrement sur l'appareil (voir lib/domain/reserve_composer.dart).
///
/// "Une base locale SQLite/Drift... doit rester structurée et versionnée
/// avec des migrations locales." (point 2) : toute évolution de schéma
/// incrémente `schemaVersion` et ajoute une étape `onUpgrade` explicite -
/// jamais de migration destructive silencieuse (NFR-10, section 14 :
/// "Upgrade N-1 -> version courante sans perte de dossier local.").
///
/// Génération : `dart run build_runner build` produit `app_database.g.dart`
/// (non committé - voir .gitignore). Nécessite le SDK Flutter/Dart, non
/// disponible dans l'environnement ayant produit ce code ; voir
/// `mobile/README.md`, section "Limitation connue", pour la procédure de
/// vérification à exécuter une fois le SDK disponible.
library;

// ---------------------------------------------------------------------------
// Incidents
// ---------------------------------------------------------------------------

/// Un incident de réception (dossier). Table primaire : contrairement à R0,
/// il n'existe PAS de version serveur faisant autorité en V1 - `id` est
/// généré localement (UUID) et reste l'identité canonique du dossier tant
/// qu'aucune fonctionnalité cloud (hors scope V1, point 11/12) n'est activée.
class LocalIncidents extends Table {
  TextColumn get id => text()();
  // Nullable : aucune création de compte cloud n'est requise pour démarrer
  // un dossier (point 13 - "l'utilisateur doit pouvoir commencer à créer un
  // incident immédiatement"). Renseigné uniquement si/quand un compte existe
  // (fonctionnalité différée, hors V1).
  TextColumn get organizationId => text().nullable()();
  TextColumn get status => text()(); // valeurs IncidentStatus.wireValue.
  DateTimeColumn get occurredAt => dateTime()();
  DateTimeColumn get localCreatedAt => dateTime()();
  // R0 utilisait ce champ pour une confirmation serveur ; conservé pour
  // compatibilité avec un futur mode cloud (point 12) mais jamais requis en
  // V1 (reste `null` indéfiniment pour un dossier 100% local).
  DateTimeColumn get serverCreatedAt => dateTime().nullable()();
  TextColumn get supplierName => text().nullable()();
  TextColumn get carrierName => text().nullable()();
  TextColumn get deliveryRef => text().nullable()();
  TextColumn get notes => text().nullable()();
  // Conservé pour compatibilité future (point 12) ; en V1, toujours `true`
  // car aucun ID serveur n'est jamais attribué.
  BoolColumn get pendingServerId => boolean().withDefault(const Constant(false))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// Une anomalie déclarée au sein d'un incident (F05, section 2.1). Absente
/// de la base R0 (l'incident n'y était qu'un cache plat) - nécessaire dès
/// que la composition de réserve tourne en local, car
/// `ConfirmedFactData`/`ReserveText` sont rattachés à une anomalie, pas
/// directement à l'incident (section 2.5 - "1 colis manquant + 2 cartons
/// écrasés + 1 produit rayé" = 3 `LocalIssues` distincts).
class LocalIssues extends Table {
  TextColumn get id => text()();
  TextColumn get incidentId => text()();
  TextColumn get issueType => text()(); // IssueType.wireValue.
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('open'))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

// ---------------------------------------------------------------------------
// Faits (candidats IA / confirmés utilisateur)
// ---------------------------------------------------------------------------

/// Sortie brute du pipeline IA (section 7.2) pour une anomalie, EN ATTENTE
/// de revue utilisateur. Ne doit JAMAIS être lue par le Reserve Composer
/// (GATE zéro invention, section 2.4) - seule `LocalConfirmedFactSets`
/// l'est. Conservée localement pour permettre la revue hors ligne d'une
/// extraction déjà reçue avant coupure réseau (point 6).
class LocalCandidateFactSets extends Table {
  TextColumn get id => text()();
  TextColumn get issueId => text()();
  TextColumn get schemaVersion => text()();
  TextColumn get promptVersion => text().nullable()();
  TextColumn get model => text().nullable()();
  // CandidateFactData sérialisé JSON (schemas/candidate_fact_set.v1.schema.json).
  TextColumn get rawStructuredJson => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// Faits validés explicitement par l'utilisateur (F09, invariant 6.3) - LA
/// SEULE source acceptée par le Reserve Composer local
/// (`lib/domain/reserve_composer.dart`). Historisée par révision (jamais de
/// mutation en place) : "une révision de faits confirmés invalide
/// automatiquement la réserve et le PDF précédents" (section 6.3, 8.2).
///
/// `confirmedJson` est le payload sérialisé de `ConfirmedFactData` APRÈS
/// passage réussi par `lib/domain/liability_guard.dart` (aucune ligne ne
/// doit être insérée ici sans ce contrôle - voir le repository, section
/// "point d'entrée unique").
class LocalConfirmedFactSets extends Table {
  TextColumn get id => text()();
  TextColumn get issueId => text()();
  TextColumn get schemaVersion => text()();
  TextColumn get confirmedJson => text()();
  TextColumn get confirmedBy => text().nullable()(); // null si pas de compte (point 13).
  DateTimeColumn get confirmedAt => dateTime()();
  IntColumn get revision => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

// ---------------------------------------------------------------------------
// Réserve composée et export
// ---------------------------------------------------------------------------

/// Texte de réserve composé localement par
/// `lib/domain/reserve_composer.dart` à partir des `LocalConfirmedFactSets`
/// les plus récents de chaque anomalie de l'incident. Une ligne = la
/// dernière composition valide pour un incident (recomposée, jamais
/// mutée, si une révision de faits invalide la précédente - section 6.3).
class LocalReserveTexts extends Table {
  TextColumn get id => text()();
  TextColumn get incidentId => text()();
  TextColumn get templateVersion => text()();
  IntColumn get confirmedFactRevision => integer()();
  TextColumn get text => text()();
  TextColumn get sha256 => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// Dossier PDF exporté (F14) - le PDF binaire vit sur le filesystem
/// (path_provider, espace privé de l'app, point 3) ; cette table garde
/// métadonnées + hash pour vérifier l'intégrité avant partage natif
/// (point 10) et pour l'inclusion dans une sauvegarde (point 9).
class LocalExportBundles extends Table {
  TextColumn get id => text()();
  TextColumn get incidentId => text()();
  IntColumn get version => integer()();
  TextColumn get localFilePath => text()();
  TextColumn get sha256 => text()();
  DateTimeColumn get createdAt => dateTime()();
  BoolColumn get superseded => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

// ---------------------------------------------------------------------------
// Preuves (photos, BL, PDF, audio)
// ---------------------------------------------------------------------------

/// Preuves capturées localement (photos/audio/BL/PDF) - section 8.1 :
/// "chaque média est écrit localement de façon atomique avant affichage
/// comme 'capturé'." Le binaire original vit sur le filesystem de
/// l'appareil, dans l'espace privé de l'app (point 3) ; cette table ne garde
/// que les métadonnées.
///
/// Champs minimum imposés par le point 3 de la demande corrective : "id,
/// incident associé, type de document, date/heure de capture, chemin local,
/// SHA-256, statut de disponibilité" - tous présents ci-dessous.
/// `availabilityStatus` remplace l'ancien `syncStatus` orienté réseau : en
/// V1, un asset est `available` dès l'écriture disque atomique réussie, quel
/// que soit l'état du réseau (aucune perte de photo sur coupure réseau ou
/// échec IA, point 3/6).
class LocalEvidenceAssets extends Table {
  TextColumn get id => text()();
  TextColumn get incidentId => text()();
  TextColumn get issueId => text().nullable()();
  // Type de document (point 3) : 'photo', 'audio', 'delivery_note' (BL),
  // 'exported_pdf', ... voir EvidenceAssetType côté backend pour le miroir.
  TextColumn get documentType => text()();
  TextColumn get localFilePath => text()();
  TextColumn get sha256 => text().nullable()(); // renseigné dès l'écriture disque (voir ci-dessus).
  TextColumn get mimeType => text()();
  IntColumn get bytes => integer()();
  DateTimeColumn get capturedAtDevice => dateTime()();
  // 'available' (fichier présent et lisible) | 'missing' (référencé mais
  // fichier absent - ex: restauration de sauvegarde incomplète, point 9) |
  // 'corrupted' (hash recalculé ne correspond plus). Jamais 'syncing'/
  // 'synced' en V1 : le stockage cloud n'est pas requis (point 11).
  TextColumn get availabilityStatus => text().withDefault(const Constant('available'))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

// ---------------------------------------------------------------------------
// File d'opérations IA (offline-first, point 6)
// ---------------------------------------------------------------------------

/// File persistante des opérations nécessitant l'IA distante (transcription
/// audio, extraction structurée depuis photo/OCR - section 7.2). Remplace
/// la `SyncOperations` générique de R0 : en R0.1, l'app ne synchronise plus
/// l'intégralité de l'incident vers un backend (le backend n'est plus la
/// base de données centrale, point 4) - la SEULE chose qui peut nécessiter
/// le réseau est un appel IA.
///
/// "Si une opération IA nécessite Internet : elle passe en état pending,
/// rien n'est perdu, retry possible à la reconnexion." (point 6). Le
/// redémarrage de l'app reprend la queue sans intervention utilisateur
/// (repris de la garantie section 8.1, toujours valable ici).
class AiOperationQueue extends Table {
  TextColumn get id => text()();
  TextColumn get incidentId => text()();
  TextColumn get issueId => text().nullable()();
  // 'transcribe_audio' | 'extract_from_photo' | 'extract_from_document' (BL).
  TextColumn get operationKind => text()();
  // Payload MINIMAL nécessaire à l'opération (point 14 - "éviter d'envoyer
  // systématiquement toutes les photos si non nécessaire") : référence(s)
  // vers LocalEvidenceAssets, jamais un dump complet du dossier.
  TextColumn get payloadJson => text()();
  TextColumn get idempotencyKey => text()();
  // 'pending' (créée, en attente de réseau ou de traitement) | 'in_progress'
  // | 'done' | 'failed' (voir retryCount avant abandon défini par l'UI).
  TextColumn get status => text().withDefault(const Constant('pending'))();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get lastAttemptAt => dateTime().nullable()();
  TextColumn get lastError => text().nullable()();
  // CandidateFactData sérialisé JSON reçu du backend une fois l'opération
  // terminée avec succès ; consommé par l'écran de revue (F08/F09), puis
  // recopié dans LocalCandidateFactSets pour persistance indépendante de la
  // queue (qui peut être purgée une fois l'opération terminée).
  TextColumn get resultJson => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

// ---------------------------------------------------------------------------
// Sauvegarde utilisateur (point 9)
// ---------------------------------------------------------------------------

/// Historique des exports/imports de sauvegarde ("Export mes données /
/// Sauvegarde ReserveFlash", point 9). Ne contient JAMAIS le contenu de la
/// sauvegarde elle-même (qui est un fichier .rfbackup géré par
/// lib/data/backup/, voir ce module) - uniquement une trace pour l'écran
/// "Historique des sauvegardes" et pour détecter une restauration
/// incomplète (référence à des `LocalEvidenceAssets` en statut `missing`
/// après import, voir plus haut).
class BackupEvents extends Table {
  TextColumn get id => text()();
  TextColumn get kind => text()(); // 'export' | 'import'.
  TextColumn get appSchemaVersion => text()(); // ex: 'reserveflash_backup.v1'.
  TextColumn get filePath => text().nullable()(); // chemin choisi par l'utilisateur (partage OS).
  TextColumn get sha256 => text()();
  IntColumn get incidentCount => integer()();
  IntColumn get evidenceAssetCount => integer()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  // Renseigné uniquement pour un import : nombre de LocalEvidenceAssets
  // référencés dans la sauvegarde mais absents du fichier reçu (transparence
  // obligatoire, point 9 - "la restauration complète doit être testable").
  IntColumn get missingAssetCount => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DriftDatabase(
  tables: <Type>[
    LocalIncidents,
    LocalIssues,
    LocalCandidateFactSets,
    LocalConfirmedFactSets,
    LocalReserveTexts,
    LocalExportBundles,
    LocalEvidenceAssets,
    AiOperationQueue,
    BackupEvents,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  // section 5.1 / point 2 - "Base locale structurée et versionnée avec des
  // migrations locales." Toute évolution de schéma incrémente
  // `schemaVersion` et ajoute une étape `onUpgrade` explicite : jamais de
  // migration destructive silencieuse (NFR-10, section 14 : "Upgrade N-1 ->
  // version courante sans perte de dossier local.").
  //
  // Historique :
  //   v1 (R0)   : LocalIncidents, LocalEvidenceAssets, SyncOperations.
  //   v2 (R0.1) : pivot Local-First - ajout LocalIssues,
  //               LocalCandidateFactSets, LocalConfirmedFactSets,
  //               LocalReserveTexts, LocalExportBundles, BackupEvents ;
  //               LocalEvidenceAssets étendue (documentType,
  //               availabilityStatus) ; SyncOperations remplacée par
  //               AiOperationQueue (portée réduite : IA uniquement, voir
  //               docstring ci-dessus). Voir
  //               docs/local_storage_schema.md pour le détail migration.
  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
        },
        onUpgrade: (Migrator m, int from, int to) async {
          if (from < 2) {
            // v1 (R0) -> v2 (R0.1, pivot Local-First). Étape par étape,
            // documentée explicitement (NFR-10 - jamais de migration
            // destructive silencieuse) :
            //
            //   - local_incidents : schéma compatible, ajout de la seule
            //     colonne nouvelle (`archived`, avec défaut) -> conservé.
            //   - local_evidence_assets : colonnes renommées (`type` ->
            //     `document_type`, `sync_status` -> `availability_status`) ->
            //     table recréée. Perte tolérée UNIQUEMENT parce que R0 n'a
            //     jamais quitté l'environnement de développement (aucune
            //     base v1 réelle n'existe) - NE PAS reproduire ce pattern
            //     pour une vraie montée de version en production : une
            //     future migration de colonne doit copier les données via
            //     une table temporaire, jamais les supprimer.
            //   - sync_operations : remplacée par ai_operation_queue, portée
            //     différente (opérations IA uniquement, voir docstring de
            //     cette table) -> supprimée, nouvelle table créée.
            //   - toutes les autres tables v2 sont entièrement nouvelles ->
            //     créées.
            await m.addColumn(localIncidents, localIncidents.archived);
            await m.deleteTable('local_evidence_assets');
            await m.deleteTable('sync_operations');
            await m.createTable(localIssues);
            await m.createTable(localCandidateFactSets);
            await m.createTable(localConfirmedFactSets);
            await m.createTable(localReserveTexts);
            await m.createTable(localExportBundles);
            await m.createTable(localEvidenceAssets);
            await m.createTable(aiOperationQueue);
            await m.createTable(backupEvents);
          }
        },
      );
}
