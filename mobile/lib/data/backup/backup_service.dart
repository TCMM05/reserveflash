import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../local/app_database.dart';

const Uuid _uuid = Uuid();

/// "Export mes données / Sauvegarde ReserveFlash" (point 9 de la demande
/// corrective "Local-First").
///
/// Format de sauvegarde (documenté et versionné, comme exigé) :
///
///   reserveflash_backup.v1 (extension conseillée : `.rfbackup`, un fichier
///   ZIP standard, lisible avec n'importe quel outil zip en cas de besoin) :
///     manifest.json     - métadonnées (version de format, date, compteurs,
///                          version de schéma app au moment de l'export).
///     tables.json        - contenu intégral des tables locales
///                          (LocalIncidents, LocalIssues,
///                          LocalConfirmedFactSets, LocalReserveTexts,
///                          LocalExportBundles, LocalEvidenceAssets),
///                          sérialisé en JSON simple (pas de dump binaire
///                          SQLite - voir "Pourquoi pas une copie brute du
///                          fichier .sqlite" ci-dessous).
///     evidence/<id>.<ext> - copie binaire de chaque pièce (photo, audio,
///                          BL, PDF exporté) référencée par
///                          LocalEvidenceAssets/LocalExportBundles.
///
/// Pourquoi pas une copie brute du fichier .sqlite : les chemins de fichiers
/// stockés (`local_file_path`) sont des chemins ABSOLUS dans le bac à sable
/// de l'application émettrice (path_provider) - une copie brute du fichier
/// .sqlite resterait valide en apparence mais référencerait des fichiers
/// inexistants dès qu'elle est restaurée sur un autre appareil ou une
/// autre installation. L'export structuré ci-dessus réécrit ces chemins au
/// moment de l'import pour qu'ils pointent vers le nouvel espace de
/// stockage local (voir `importBackup`).
///
/// "La restauration complète doit être pouvoir être testée" (point 9) :
/// voir `mobile/test/data/backup_service_test.dart` (round-trip
/// export -> import -> comparaison), à exécuter une fois le SDK Flutter
/// disponible (voir mobile/README.md, section "Limitation connue").
///
/// ## Statut de conformité (retour de recette R0.1, R0.2)
///
/// **CETTE IMPLÉMENTATION N'EST PAS CHIFFRÉE et n'est PAS la fonctionnalité
/// de sauvegarde complète prévue en R4.** Elle couvre le point 9 de la
/// demande corrective R0.1 ("export/import basique, format documenté et
/// versionné, restauration testable") mais PAS un chiffrement de
/// l'archive - explicitement noté comme non fait, à ne jamais présenter
/// comme terminé/conforme R4 tant que ce point n'est pas traité. Voir
/// `BackupResult.isEncrypted` (toujours `false` ici) et
/// `docs/GATE_R0.1_STATUS.md`.
///
/// `importBackup` effectue une passe de VALIDATION D'INTÉGRITÉ complète
/// (format de l'archive, présence/parsing de `manifest.json`/`tables.json`,
/// et désormais un recalcul SHA-256 de chaque preuve binaire comparé à la
/// valeur enregistrée dans `tables.json`) et lève avant toute mutation
/// locale destructrice si un problème est détecté - "refuser une archive
/// corrompue avant toute mutation locale" (retour de recette R0.2). Ce
/// contrôle vérifie la cohérence INTERNE de l'archive (le hash déclaré
/// correspond au contenu réel) ; il ne remplace pas un chiffrement
/// (confidentialité) ni une signature (authenticité de la source), qui
/// restent hors scope de cette implémentation.
class BackupService {
  BackupService({
    required this.db,
    required this.evidenceDirectoryPath,
    this.appSchemaVersion = 2,
  });

  final AppDatabase db;

  /// Répertoire privé de l'app où vivent les fichiers de preuves (photos,
  /// audio, BL, PDF exportés) - voir lib/data/local/evidence_storage.dart.
  final String evidenceDirectoryPath;

  final int appSchemaVersion;

  static const String formatVersion = 'reserveflash_backup.v1';

  // -- Export -------------------------------------------------------------

  /// Écrit une archive de sauvegarde à [destinationPath] et retourne son
  /// SHA-256. Ne fait AUCUN appel réseau : l'utilisateur choisit ensuite
  /// où stocker le fichier (partage natif OS - Drive, OneDrive, stockage
  /// local - voir point 9 : "aucun besoin de construire un cloud de
  /// sauvegarde propriétaire maintenant").
  Future<BackupResult> exportBackup(String destinationPath) async {
    // Sérialisation manuelle, explicite, en snake_case (et NON le
    // `toJson()` généré par Drift, dont le "case" des clés dépend d'options
    // de configuration non vérifiables sans le SDK) : ce choix garantit que
    // `export` et `import` (voir `_xFromJson` plus bas) restent
    // parfaitement symétriques, quelle que soit la configuration de
    // génération de code utilisée.
    final List<Map<String, dynamic>> incidents =
        (await db.select(db.localIncidents).get()).map(_incidentToJson).toList();
    final List<Map<String, dynamic>> issues =
        (await db.select(db.localIssues).get()).map(_issueToJson).toList();
    final List<Map<String, dynamic>> candidateFactSets =
        (await db.select(db.localCandidateFactSets).get()).map(_candidateFactSetToJson).toList();
    final List<Map<String, dynamic>> confirmedFactSets =
        (await db.select(db.localConfirmedFactSets).get()).map(_confirmedFactSetToJson).toList();
    final List<Map<String, dynamic>> reserveTexts =
        (await db.select(db.localReserveTexts).get()).map(_reserveTextToJson).toList();
    final List<Map<String, dynamic>> exportBundles =
        (await db.select(db.localExportBundles).get()).map(_exportBundleToJson).toList();
    final List<Map<String, dynamic>> evidenceAssets =
        (await db.select(db.localEvidenceAssets).get()).map(_evidenceAssetToJson).toList();

    final Archive archive = Archive();

    // Ajoute chaque pièce binaire référencée, sous un nom stable
    // (id + extension d'origine) - jamais le chemin absolu d'origine.
    int evidenceFilesMissingAtExportTime = 0;
    for (final Map<String, dynamic> row in evidenceAssets) {
      final String id = row['id'] as String;
      final String localFilePath = row['local_file_path'] as String;
      final File source = File(localFilePath);
      if (!await source.exists()) {
        // Documenté plutôt que silencieux (point 9 - transparence) : cette
        // pièce sera absente de la sauvegarde ; l'import la marquera
        // `missing` (voir importBackup).
        evidenceFilesMissingAtExportTime += 1;
        continue;
      }
      final String extension = _extensionOf(localFilePath);
      final List<int> bytes = await source.readAsBytes();
      archive.addFile(ArchiveFile('evidence/$id$extension', bytes.length, bytes));
    }

    final Map<String, dynamic> tables = <String, dynamic>{
      'local_incidents': incidents,
      'local_issues': issues,
      'local_candidate_fact_sets': candidateFactSets,
      'local_confirmed_fact_sets': confirmedFactSets,
      'local_reserve_texts': reserveTexts,
      'local_export_bundles': exportBundles,
      'local_evidence_assets': evidenceAssets,
    };
    final List<int> tablesBytes = utf8.encode(jsonEncode(tables));
    archive.addFile(
      ArchiveFile('tables.json', tablesBytes.length, tablesBytes),
    );

    final DateTime now = DateTime.now().toUtc();
    final Map<String, dynamic> manifest = <String, dynamic>{
      'format_version': formatVersion,
      'app_schema_version': appSchemaVersion,
      'created_at': now.toIso8601String(),
      'incident_count': incidents.length,
      'evidence_asset_count': evidenceAssets.length,
      'evidence_files_missing_at_export_time': evidenceFilesMissingAtExportTime,
    };
    final List<int> manifestBytes = utf8.encode(jsonEncode(manifest));
    archive.addFile(
      ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
    );

    final List<int>? zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null) {
      throw StateError("Échec de l'encodage de l'archive de sauvegarde.");
    }
    final File destination = File(destinationPath);
    await destination.writeAsBytes(zipBytes, flush: true);
    final String sha256Hex = sha256.convert(zipBytes).toString();

    await db.into(db.backupEvents).insert(
          BackupEventsCompanion.insert(
            id: _uuid.v4(),
            kind: 'export',
            appSchemaVersion: formatVersion,
            sha256: sha256Hex,
            incidentCount: incidents.length,
            evidenceAssetCount: evidenceAssets.length,
            filePath: Value<String?>(destinationPath),
          ),
        );

    return BackupResult(
      filePath: destinationPath,
      sha256: sha256Hex,
      incidentCount: incidents.length,
      evidenceAssetCount: evidenceAssets.length,
      missingAssetCount: evidenceFilesMissingAtExportTime,
    );
  }

  // -- Import ---------------------------------------------------------

  /// Restaure une archive produite par [exportBackup]. REMPLACE l'état
  /// local actuel (pas de fusion en V1 - documenté explicitement, voir
  /// docs/local_storage_schema.md) : à utiliser sur un appareil vide ou
  /// après confirmation explicite de l'utilisateur ("cette opération va
  /// remplacer les dossiers actuels").
  Future<BackupResult> importBackup(String sourcePath) async {
    final File source = File(sourcePath);
    final List<int> zipBytes = await source.readAsBytes();
    final Archive archive = ZipDecoder().decodeBytes(zipBytes);

    final ArchiveFile? manifestFile = archive.findFile('manifest.json');
    final ArchiveFile? tablesFile = archive.findFile('tables.json');
    if (manifestFile == null || tablesFile == null) {
      throw const FormatException(
        'Archive de sauvegarde invalide : manifest.json ou tables.json manquant.',
      );
    }
    final Map<String, dynamic> manifest =
        jsonDecode(utf8.decode(manifestFile.content as List<int>)) as Map<String, dynamic>;
    if (manifest['format_version'] != formatVersion) {
      throw FormatException(
        "Version de format de sauvegarde non supportée : '${manifest['format_version']}' "
        "(attendu '$formatVersion'). Une future version de l'app pourra ajouter un "
        'convertisseur - non fait en R0.1 (une seule version de format existe à ce jour).',
      );
    }
    final Map<String, dynamic> tables =
        jsonDecode(utf8.decode(tablesFile.content as List<int>)) as Map<String, dynamic>;

    // Retour de recette R0.2 : "refuser une archive corrompue AVANT toute
    // mutation locale." Passe de validation complète - AUCUNE table n'est
    // encore touchée à ce stade. Pour chaque preuve dont l'archive contient
    // le fichier ET dont tables.json enregistre un sha256, on recalcule le
    // hash réel et on le compare à la valeur déclarée. Toute divergence
    // signale une archive corrompue/altérée : on lève AVANT le
    // `db.transaction` ci-dessous, donc avant le moindre `DELETE`.
    final List<dynamic> evidenceRowsForIntegrityCheck =
        (tables['local_evidence_assets'] as List<dynamic>?) ?? const <dynamic>[];
    final List<String> integrityFailures = <String>[];
    for (final dynamic rawRow in evidenceRowsForIntegrityCheck) {
      final Map<String, dynamic> row = rawRow as Map<String, dynamic>;
      final String id = row['id'] as String;
      final String? declaredSha256 = row['sha256'] as String?;
      if (declaredSha256 == null) {
        continue; // Rien à vérifier - cohérent avec l'export (voir EvidenceAsset).
      }
      final String extension = _extensionOf(row['local_file_path'] as String);
      final ArchiveFile? assetFile = archive.findFile('evidence/$id$extension');
      if (assetFile == null) {
        continue; // Absence déjà gérée/signalée comme `missing` plus bas, pas une corruption.
      }
      final String actualSha256 =
          sha256.convert(assetFile.content as List<int>).toString();
      if (actualSha256 != declaredSha256) {
        integrityFailures.add(
          "preuve '$id' : sha256 attendu $declaredSha256, obtenu $actualSha256",
        );
      }
    }
    if (integrityFailures.isNotEmpty) {
      throw BackupIntegrityException(
        'Archive de sauvegarde corrompue - restauration ANNULÉE, aucune donnée '
        'locale modifiée. Détails : ${integrityFailures.join("; ")}',
      );
    }

    // Restauration = remplacement complet (documenté ci-dessus). Atteint
    // uniquement après la validation d'intégrité ci-dessus.
    await db.transaction(() async {
      await db.delete(db.localEvidenceAssets).go();
      await db.delete(db.localExportBundles).go();
      await db.delete(db.localReserveTexts).go();
      await db.delete(db.localConfirmedFactSets).go();
      await db.delete(db.localCandidateFactSets).go();
      await db.delete(db.localIssues).go();
      await db.delete(db.localIncidents).go();

      for (final dynamic row in tables['local_incidents'] as List<dynamic>) {
        await db.into(db.localIncidents).insert(_incidentFromJson(row), mode: InsertMode.insertOrReplace);
      }
      for (final dynamic row in tables['local_issues'] as List<dynamic>) {
        await db.into(db.localIssues).insert(_issueFromJson(row), mode: InsertMode.insertOrReplace);
      }
      for (final dynamic row in tables['local_candidate_fact_sets'] as List<dynamic>) {
        await db
            .into(db.localCandidateFactSets)
            .insert(_candidateFactSetFromJson(row), mode: InsertMode.insertOrReplace);
      }
      for (final dynamic row in tables['local_confirmed_fact_sets'] as List<dynamic>) {
        await db
            .into(db.localConfirmedFactSets)
            .insert(_confirmedFactSetFromJson(row), mode: InsertMode.insertOrReplace);
      }
      for (final dynamic row in tables['local_reserve_texts'] as List<dynamic>) {
        await db
            .into(db.localReserveTexts)
            .insert(_reserveTextFromJson(row), mode: InsertMode.insertOrReplace);
      }
      for (final dynamic row in tables['local_export_bundles'] as List<dynamic>) {
        await db
            .into(db.localExportBundles)
            .insert(_exportBundleFromJson(row, evidenceDirectoryPath), mode: InsertMode.insertOrReplace);
      }
    });

    // Fichiers de preuves : extraits vers le répertoire local de l'appareil
    // IMPORTANT, puis les lignes LocalEvidenceAssets sont recréées avec les
    // NOUVEAUX chemins locaux (jamais les chemins de l'appareil d'origine).
    int missingAssetCount = 0;
    final List<dynamic> evidenceRows = tables['local_evidence_assets'] as List<dynamic>;
    await Directory(evidenceDirectoryPath).create(recursive: true);
    for (final dynamic rawRow in evidenceRows) {
      final Map<String, dynamic> row = rawRow as Map<String, dynamic>;
      final String id = row['id'] as String;
      final String originalPath = row['local_file_path'] as String;
      final String extension = _extensionOf(originalPath);
      final ArchiveFile? assetFile = archive.findFile('evidence/$id$extension');
      final String newLocalPath = '$evidenceDirectoryPath/$id$extension';
      String availability = 'available';
      if (assetFile == null) {
        // Référencée dans tables.json mais absente de l'archive (ex: fichier
        // déjà manquant au moment de l'export, voir exportBackup) -
        // transparence obligatoire (point 9) : jamais silencieux.
        missingAssetCount += 1;
        availability = 'missing';
      } else {
        await File(newLocalPath).writeAsBytes(assetFile.content as List<int>, flush: true);
      }
      await db.into(db.localEvidenceAssets).insert(
            LocalEvidenceAssetsCompanion.insert(
              id: id,
              incidentId: row['incident_id'] as String,
              documentType: row['document_type'] as String,
              localFilePath: newLocalPath,
              mimeType: row['mime_type'] as String,
              bytes: row['bytes'] as int,
              capturedAtDevice: DateTime.parse(row['captured_at_device'] as String),
              issueId: Value<String?>(row['issue_id'] as String?),
              sha256: Value<String?>(row['sha256'] as String?),
              availabilityStatus: Value<String>(availability),
            ),
            mode: InsertMode.insertOrReplace,
          );
    }

    final String sha256Hex = sha256.convert(zipBytes).toString();
    final int incidentCount = (tables['local_incidents'] as List<dynamic>).length;
    await db.into(db.backupEvents).insert(
          BackupEventsCompanion.insert(
            id: _uuid.v4(),
            kind: 'import',
            appSchemaVersion: formatVersion,
            sha256: sha256Hex,
            incidentCount: incidentCount,
            evidenceAssetCount: evidenceRows.length,
            filePath: Value<String?>(sourcePath),
            missingAssetCount: Value<int>(missingAssetCount),
          ),
        );

    return BackupResult(
      filePath: sourcePath,
      sha256: sha256Hex,
      incidentCount: incidentCount,
      evidenceAssetCount: evidenceRows.length,
      missingAssetCount: missingAssetCount,
    );
  }

  // -- Sérialisation (export) - symétrique de _xFromJson (import) ---------

  static Map<String, dynamic> _incidentToJson(LocalIncident row) => <String, dynamic>{
        'id': row.id,
        'organization_id': row.organizationId,
        'status': row.status,
        'occurred_at': row.occurredAt.toIso8601String(),
        'local_created_at': row.localCreatedAt.toIso8601String(),
        'server_created_at': row.serverCreatedAt?.toIso8601String(),
        'supplier_name': row.supplierName,
        'carrier_name': row.carrierName,
        'delivery_ref': row.deliveryRef,
        'notes': row.notes,
        'pending_server_id': row.pendingServerId,
        'archived': row.archived,
      };

  static Map<String, dynamic> _issueToJson(LocalIssue row) => <String, dynamic>{
        'id': row.id,
        'incident_id': row.incidentId,
        'issue_type': row.issueType,
        'sort_order': row.sortOrder,
        'status': row.status,
      };

  static Map<String, dynamic> _candidateFactSetToJson(LocalCandidateFactSet row) =>
      <String, dynamic>{
        'id': row.id,
        'issue_id': row.issueId,
        'schema_version': row.schemaVersion,
        'prompt_version': row.promptVersion,
        'model': row.model,
        'raw_structured_json': row.rawStructuredJson,
        'created_at': row.createdAt.toIso8601String(),
      };

  static Map<String, dynamic> _confirmedFactSetToJson(LocalConfirmedFactSet row) =>
      <String, dynamic>{
        'id': row.id,
        'issue_id': row.issueId,
        'schema_version': row.schemaVersion,
        'confirmed_json': row.confirmedJson,
        'confirmed_by': row.confirmedBy,
        'confirmed_at': row.confirmedAt.toIso8601String(),
        'revision': row.revision,
      };

  static Map<String, dynamic> _reserveTextToJson(LocalReserveText row) => <String, dynamic>{
        'id': row.id,
        'incident_id': row.incidentId,
        'template_version': row.templateVersion,
        'confirmed_fact_revision': row.confirmedFactRevision,
        'text': row.text,
        'sha256': row.sha256,
        'created_at': row.createdAt.toIso8601String(),
      };

  static Map<String, dynamic> _exportBundleToJson(LocalExportBundle row) => <String, dynamic>{
        'id': row.id,
        'incident_id': row.incidentId,
        'version': row.version,
        'sha256': row.sha256,
        'created_at': row.createdAt.toIso8601String(),
        'superseded': row.superseded,
      };

  static Map<String, dynamic> _evidenceAssetToJson(LocalEvidenceAsset row) => <String, dynamic>{
        'id': row.id,
        'incident_id': row.incidentId,
        'issue_id': row.issueId,
        'document_type': row.documentType,
        'local_file_path': row.localFilePath,
        'sha256': row.sha256,
        'mime_type': row.mimeType,
        'bytes': row.bytes,
        'captured_at_device': row.capturedAtDevice.toIso8601String(),
        'availability_status': row.availabilityStatus,
      };

  static String _extensionOf(String path) {
    final int dotIndex = path.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == path.length - 1) {
      return '';
    }
    return path.substring(dotIndex);
  }

  static LocalIncidentsCompanion _incidentFromJson(dynamic raw) {
    final Map<String, dynamic> row = raw as Map<String, dynamic>;
    return LocalIncidentsCompanion.insert(
      id: row['id'] as String,
      status: row['status'] as String,
      occurredAt: DateTime.parse(row['occurred_at'] as String),
      localCreatedAt: DateTime.parse(row['local_created_at'] as String),
      organizationId: Value<String?>(row['organization_id'] as String?),
      serverCreatedAt: Value<DateTime?>(
        row['server_created_at'] == null ? null : DateTime.parse(row['server_created_at'] as String),
      ),
      supplierName: Value<String?>(row['supplier_name'] as String?),
      carrierName: Value<String?>(row['carrier_name'] as String?),
      deliveryRef: Value<String?>(row['delivery_ref'] as String?),
      notes: Value<String?>(row['notes'] as String?),
      pendingServerId: Value<bool>(row['pending_server_id'] as bool? ?? false),
      archived: Value<bool>(row['archived'] as bool? ?? false),
    );
  }

  static LocalIssuesCompanion _issueFromJson(dynamic raw) {
    final Map<String, dynamic> row = raw as Map<String, dynamic>;
    return LocalIssuesCompanion.insert(
      id: row['id'] as String,
      incidentId: row['incident_id'] as String,
      issueType: row['issue_type'] as String,
      sortOrder: Value<int>(row['sort_order'] as int? ?? 0),
      status: Value<String>(row['status'] as String? ?? 'open'),
    );
  }

  static LocalCandidateFactSetsCompanion _candidateFactSetFromJson(dynamic raw) {
    final Map<String, dynamic> row = raw as Map<String, dynamic>;
    return LocalCandidateFactSetsCompanion.insert(
      id: row['id'] as String,
      issueId: row['issue_id'] as String,
      schemaVersion: row['schema_version'] as String,
      rawStructuredJson: row['raw_structured_json'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
      promptVersion: Value<String?>(row['prompt_version'] as String?),
      model: Value<String?>(row['model'] as String?),
    );
  }

  static LocalConfirmedFactSetsCompanion _confirmedFactSetFromJson(dynamic raw) {
    final Map<String, dynamic> row = raw as Map<String, dynamic>;
    return LocalConfirmedFactSetsCompanion.insert(
      id: row['id'] as String,
      issueId: row['issue_id'] as String,
      schemaVersion: row['schema_version'] as String,
      confirmedJson: row['confirmed_json'] as String,
      confirmedAt: DateTime.parse(row['confirmed_at'] as String),
      revision: row['revision'] as int,
      confirmedBy: Value<String?>(row['confirmed_by'] as String?),
    );
  }

  static LocalReserveTextsCompanion _reserveTextFromJson(dynamic raw) {
    final Map<String, dynamic> row = raw as Map<String, dynamic>;
    return LocalReserveTextsCompanion.insert(
      id: row['id'] as String,
      incidentId: row['incident_id'] as String,
      templateVersion: row['template_version'] as String,
      confirmedFactRevision: row['confirmed_fact_revision'] as int,
      text: row['text'] as String,
      sha256: row['sha256'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  /// `localFilePath` du bundle exporté (PDF) n'est PAS restaurable de façon
  /// fiable (le PDF binaire lui-même n'est PAS inclus dans le backup en
  /// R0.1 - seules les preuves sources le sont, voir ROADMAP dans
  /// docs/local_storage_schema.md) : le champ est réinitialisé à une valeur
  /// vide, `superseded` reste tel quel pour l'historique, et l'écran de
  /// dossier doit re-générer le PDF si besoin (la réserve + les faits
  /// confirmés sont, eux, intégralement restaurés).
  static LocalExportBundlesCompanion _exportBundleFromJson(dynamic raw, String evidenceDir) {
    final Map<String, dynamic> row = raw as Map<String, dynamic>;
    return LocalExportBundlesCompanion.insert(
      id: row['id'] as String,
      incidentId: row['incident_id'] as String,
      version: row['version'] as int,
      localFilePath: '',
      sha256: row['sha256'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
      superseded: Value<bool>(row['superseded'] as bool? ?? false),
    );
  }
}

class BackupResult {
  const BackupResult({
    required this.filePath,
    required this.sha256,
    required this.incidentCount,
    required this.evidenceAssetCount,
    required this.missingAssetCount,
  });

  final String filePath;
  final String sha256;
  final int incidentCount;
  final int evidenceAssetCount;

  /// Nombre de preuves référencées mais dont le fichier binaire n'a pas pu
  /// être inclus (export) ou retrouvé (import) - transparence obligatoire
  /// (point 9).
  final int missingAssetCount;

  /// TOUJOURS `false` dans cette implémentation - voir la docstring de
  /// [BackupService], section "Statut de conformité". Champ présent
  /// explicitement (plutôt qu'omis) pour qu'un appelant (UI, tests) ne
  /// puisse pas accidentellement présenter cette sauvegarde comme chiffrée.
  bool get isEncrypted => false;
}

/// Levée par [BackupService.importBackup] quand la vérification d'intégrité
/// détecte une divergence entre le SHA-256 déclaré (`tables.json`) et le
/// SHA-256 réel d'une preuve incluse dans l'archive - AVANT toute mutation
/// locale (retour de recette R0.2, "refuser une archive corrompue avant
/// toute mutation locale"). Distincte de `FormatException` (structure de
/// l'archive invalide) : celle-ci signale un CONTENU altéré dans une
/// archive par ailleurs structurellement valide.
final class BackupIntegrityException implements Exception {
  const BackupIntegrityException(this.message);
  final String message;

  @override
  String toString() => 'BackupIntegrityException: $message';
}
