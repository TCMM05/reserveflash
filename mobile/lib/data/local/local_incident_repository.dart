import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/ai_queue_item.dart';
import '../../domain/entities/confirmed_fact_set.dart' as domain;
import '../../domain/entities/evidence_asset.dart' as domain;
import '../../domain/entities/incident.dart' as domain;
import '../../domain/entities/issue.dart' as domain;
import '../../domain/entities/reserve_text.dart' as domain;
import '../../domain/fact_set/confirmed_fact_data.dart';
import '../../domain/liability_guard.dart';
import '../../domain/repositories/incident_repository.dart';
import '../../domain/reserve_composer.dart' as composer;
import '../../domain/value_objects/incident_status.dart';
import '../../domain/value_objects/issue_type.dart';
import 'app_database.dart';
import 'evidence_storage.dart';

const Uuid _uuid = Uuid();

/// Implémentation V1 de [IncidentRepository], entièrement locale
/// (SQLite/Drift via [AppDatabase]) - point 12 de la demande corrective.
///
/// C'est la SEULE implémentation utilisée en runtime pour la V1. Toute la
/// logique métier (use cases, services, écrans) doit passer par
/// l'interface [IncidentRepository], jamais par cette classe ni par
/// [AppDatabase] directement, pour qu'une future `CloudIncidentRepository`
/// (hors scope V1) puisse être substituée sans réécriture (section 12).
///
/// Aucune méthode ici ne fait d'appel réseau : c'est un invariant de cette
/// classe (voir tests/data/local_incident_repository_test.dart - à écrire
/// une fois le SDK Flutter disponible, voir mobile/README.md).
final class LocalIncidentRepository implements IncidentRepository {
  LocalIncidentRepository(this._db, {EvidenceStorageService evidenceStorage = const EvidenceStorageService()})
      : _evidenceStorage = evidenceStorage;

  final AppDatabase _db;

  // R1 : utilisé UNIQUEMENT par `verifyEvidenceAssetsIntegrity` pour relire
  // le disque (frontière stricte préservée - ce repository ne fait aucune
  // écriture binaire lui-même, voir docstring de
  // `lib/data/local/evidence_storage.dart`). Injectable pour les tests
  // (fournir un `EvidenceStorageService` custom pointant vers un dossier
  // temporaire).
  final EvidenceStorageService _evidenceStorage;

  // -- Incidents ------------------------------------------------------

  @override
  Future<domain.Incident> createIncident({
    required DateTime occurredAt,
    String? supplierName,
    String? carrierName,
    String? deliveryRef,
    String? notes,
  }) async {
    final String id = _uuid.v4();
    final DateTime now = DateTime.now().toUtc();
    await _db.into(_db.localIncidents).insert(
          LocalIncidentsCompanion.insert(
            id: id,
            status: IncidentStatus.draftLocal.wireValue,
            occurredAt: occurredAt,
            localCreatedAt: now,
            supplierName: Value<String?>(supplierName),
            carrierName: Value<String?>(carrierName),
            deliveryRef: Value<String?>(deliveryRef),
            notes: Value<String?>(notes),
          ),
        );
    return domain.Incident(
      id: id,
      status: IncidentStatus.draftLocal,
      occurredAt: occurredAt,
      localCreatedAt: now,
      supplierName: supplierName,
      carrierName: carrierName,
      deliveryRef: deliveryRef,
      notes: notes,
    );
  }

  @override
  Future<domain.Incident?> getIncident(String incidentId) async {
    final LocalIncident? row = await (_db.select(_db.localIncidents)
          ..where((t) => t.id.equals(incidentId)))
        .getSingleOrNull();
    return row == null ? null : _toDomainIncident(row);
  }

  @override
  Future<List<domain.Incident>> listIncidents({bool includeArchived = false}) async {
    final query = _db.select(_db.localIncidents);
    if (!includeArchived) {
      query.where((t) => t.archived.equals(false));
    }
    query.orderBy([(t) => OrderingTerm.desc(t.localCreatedAt)]);
    final List<LocalIncident> rows = await query.get();
    return rows.map(_toDomainIncident).toList();
  }

  @override
  Future<domain.Incident> updateIncidentStatus(String incidentId, IncidentStatus status) async {
    await (_db.update(_db.localIncidents)..where((t) => t.id.equals(incidentId)))
        .write(LocalIncidentsCompanion(status: Value<String>(status.wireValue)));
    final domain.Incident? updated = await getIncident(incidentId);
    if (updated == null) {
      throw StateError('Incident $incidentId introuvable après mise à jour de statut.');
    }
    return updated;
  }

  @override
  Future<void> archiveIncident(String incidentId) async {
    await (_db.update(_db.localIncidents)..where((t) => t.id.equals(incidentId))).write(
      const LocalIncidentsCompanion(archived: Value<bool>(true)),
    );
  }

  @override
  Future<domain.Incident> updateIncidentMetadata({
    required String incidentId,
    required DateTime occurredAt,
    String? supplierName,
    String? carrierName,
    String? deliveryRef,
    String? notes,
  }) async {
    await (_db.update(_db.localIncidents)..where((t) => t.id.equals(incidentId))).write(
      LocalIncidentsCompanion(
        occurredAt: Value<DateTime>(occurredAt),
        supplierName: Value<String?>(supplierName),
        carrierName: Value<String?>(carrierName),
        deliveryRef: Value<String?>(deliveryRef),
        notes: Value<String?>(notes),
      ),
    );
    final domain.Incident? updated = await getIncident(incidentId);
    if (updated == null) {
      throw StateError('Incident $incidentId introuvable après mise à jour des métadonnées.');
    }
    return updated;
  }

  @override
  Future<void> deleteIncident(String incidentId) async {
    // Cascade transactionnelle (point 7) : soit tout disparaît, soit rien -
    // jamais d'issue/preuve orpheline si l'app est tuée au milieu de la
    // suppression (même invariant de résilience que le point 9).
    await _db.transaction(() async {
      final List<LocalIssue> issues = await (_db.select(_db.localIssues)
            ..where((t) => t.incidentId.equals(incidentId)))
          .get();
      final List<String> issueIds = issues.map((issue) => issue.id).toList();

      if (issueIds.isNotEmpty) {
        await (_db.delete(_db.localConfirmedFactSets)
              ..where((t) => t.issueId.isIn(issueIds)))
            .go();
        await (_db.delete(_db.localCandidateFactSets)
              ..where((t) => t.issueId.isIn(issueIds)))
            .go();
      }
      await (_db.delete(_db.localIssues)..where((t) => t.incidentId.equals(incidentId))).go();
      await (_db.delete(_db.localReserveTexts)..where((t) => t.incidentId.equals(incidentId)))
          .go();
      await (_db.delete(_db.localExportBundles)..where((t) => t.incidentId.equals(incidentId)))
          .go();
      await (_db.delete(_db.localEvidenceAssets)..where((t) => t.incidentId.equals(incidentId)))
          .go();
      await (_db.delete(_db.aiOperationQueue)..where((t) => t.incidentId.equals(incidentId)))
          .go();
      await (_db.delete(_db.localIncidents)..where((t) => t.id.equals(incidentId))).go();
    });
  }

  domain.Incident _toDomainIncident(LocalIncident row) {
    return domain.Incident(
      id: row.id,
      organizationId: row.organizationId,
      status: IncidentStatus.fromWire(row.status),
      occurredAt: row.occurredAt,
      localCreatedAt: row.localCreatedAt,
      serverCreatedAt: row.serverCreatedAt,
      supplierName: row.supplierName,
      carrierName: row.carrierName,
      deliveryRef: row.deliveryRef,
      notes: row.notes,
      archived: row.archived,
    );
  }

  // -- Issues -----------------------------------------------------------

  @override
  Future<domain.Issue> addIssue(String incidentId, IssueType issueType) async {
    final String id = _uuid.v4();
    final int sortOrder = await _nextIssueSortOrder(incidentId);
    await _db.into(_db.localIssues).insert(
          LocalIssuesCompanion.insert(
            id: id,
            incidentId: incidentId,
            issueType: issueType.wireValue,
            sortOrder: Value<int>(sortOrder),
          ),
        );
    return domain.Issue(id: id, incidentId: incidentId, issueType: issueType, sortOrder: sortOrder);
  }

  Future<int> _nextIssueSortOrder(String incidentId) async {
    final List<domain.Issue> existing = await listIssues(incidentId);
    if (existing.isEmpty) {
      return 0;
    }
    return existing.map((i) => i.sortOrder).reduce((a, b) => a > b ? a : b) + 1;
  }

  @override
  Future<List<domain.Issue>> listIssues(String incidentId) async {
    final List<LocalIssue> rows = await (_db.select(_db.localIssues)
          ..where((t) => t.incidentId.equals(incidentId))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();
    return rows
        .map((row) => domain.Issue(
              id: row.id,
              incidentId: row.incidentId,
              issueType: IssueType.fromWire(row.issueType),
              sortOrder: row.sortOrder,
              status: row.status,
            ))
        .toList();
  }

  // -- Faits confirmés --------------------------------------------------

  @override
  Future<domain.ConfirmedFactSet> confirmFacts({
    required String issueId,
    required ConfirmedFactData data,
    String? confirmedBy,
  }) async {
    // Correctif R0.1 (point 8) : contrôle déterministe AVANT toute
    // persistance. Lève LiabilityAttributionException sans rien écrire.
    screenConfirmedFact(data);

    final domain.ConfirmedFactSet? previous = await latestConfirmedFactSet(issueId);
    final int nextRevision = previous == null ? 1 : previous.revision + 1;
    final String id = _uuid.v4();
    final DateTime now = DateTime.now().toUtc();
    const String schemaVersion = 'confirmed_fact_set.v1';

    await _db.into(_db.localConfirmedFactSets).insert(
          LocalConfirmedFactSetsCompanion.insert(
            id: id,
            issueId: issueId,
            schemaVersion: schemaVersion,
            confirmedJson: jsonEncode(data.toConfirmPayload()),
            confirmedAt: now,
            revision: nextRevision,
            confirmedBy: Value<String?>(confirmedBy),
          ),
        );

    // Invariant 6.3 : une nouvelle révision invalide la réserve précédente
    // (l'historique de LocalReserveTexts n'est pas purgé ici - seule la plus
    // récente compte pour `latestReserveText`, voir requête associée qui
    // trie par createdAt desc ; une recomposition explicite est requise
    // avant tout nouvel export, comme côté backend).
    final LocalIssue? issue = await (_db.select(_db.localIssues)
          ..where((t) => t.id.equals(issueId)))
        .getSingleOrNull();
    if (issue != null) {
      await _advanceIncidentAfterConfirmation(issue.incidentId);
    }

    return domain.ConfirmedFactSet(
      id: id,
      issueId: issueId,
      schemaVersion: schemaVersion,
      confirmedData: data,
      confirmedBy: confirmedBy,
      confirmedAt: now,
      revision: nextRevision,
    );
  }

  /// Miroir simplifié de
  /// `backend/app/application/use_cases/confirm_facts.py::_advance_incident_after_confirmation` :
  /// fait progresser l'incident vers `factsConfirmed` si un chemin existe
  /// dans le graphe (section 2.2), sans jamais sauter un état.
  Future<void> _advanceIncidentAfterConfirmation(String incidentId) async {
    final domain.Incident? incident = await getIncident(incidentId);
    if (incident == null) {
      return;
    }
    if (incident.status == IncidentStatus.factsConfirmed) {
      return;
    }
    final List<IncidentStatus>? path = incident.status.pathTo(IncidentStatus.factsConfirmed);
    if (path == null) {
      return;
    }
    await updateIncidentStatus(incidentId, IncidentStatus.factsConfirmed);
  }

  @override
  Future<domain.ConfirmedFactSet?> latestConfirmedFactSet(String issueId) async {
    final LocalConfirmedFactSet? row = await (_db.select(_db.localConfirmedFactSets)
          ..where((t) => t.issueId.equals(issueId))
          ..orderBy([(t) => OrderingTerm.desc(t.revision)])
          ..limit(1))
        .getSingleOrNull();
    return row == null ? null : _toDomainConfirmedFactSet(row);
  }

  @override
  Future<List<domain.ConfirmedFactSet>> listLatestConfirmedFactSetsForIncident(
    String incidentId,
  ) async {
    final List<domain.Issue> issues = await listIssues(incidentId);
    final List<domain.ConfirmedFactSet> latest = <domain.ConfirmedFactSet>[];
    for (final domain.Issue issue in issues) {
      final domain.ConfirmedFactSet? current = await latestConfirmedFactSet(issue.id);
      if (current != null) {
        latest.add(current);
      }
    }
    return latest;
  }

  domain.ConfirmedFactSet _toDomainConfirmedFactSet(LocalConfirmedFactSet row) {
    final Map<String, dynamic> payload =
        jsonDecode(row.confirmedJson) as Map<String, dynamic>;
    final ConfirmedFactData data = ConfirmedFactData(
      issueType: IssueType.fromWire(payload['issue_type'] as String),
      productLabel: payload['product_label'] as String?,
      productReference: payload['product_reference'] as String?,
      expectedQuantity: (payload['expected_quantity'] as num?)?.toDouble(),
      receivedQuantity: (payload['received_quantity'] as num?)?.toDouble(),
      affectedQuantity: (payload['affected_quantity'] as num?)?.toDouble(),
      packagingCondition: payload['packaging_condition'] as String?,
      productCondition: payload['product_condition'] as String?,
      locationOnItem: payload['location_on_item'] as String?,
      userUncertainty: payload['user_uncertainty'] as bool? ?? false,
      unknownFields:
          (payload['unknown_fields'] as List<dynamic>?)?.cast<String>() ?? const <String>[],
    );
    return domain.ConfirmedFactSet(
      id: row.id,
      issueId: row.issueId,
      schemaVersion: row.schemaVersion,
      confirmedData: data,
      confirmedBy: row.confirmedBy,
      confirmedAt: row.confirmedAt,
      revision: row.revision,
    );
  }

  // -- Réserve (composition 100% locale, point 6) ------------------------

  @override
  Future<domain.ReserveText> composeAndSaveReserve(
    String incidentId, {
    String templateVersion = 'fr_v1',
  }) async {
    final List<domain.ConfirmedFactSet> latestFactSets =
        await listLatestConfirmedFactSetsForIncident(incidentId);
    if (latestFactSets.isEmpty) {
      throw const NoConfirmedFactsException(
        "Aucun ConfirmedFactSet pour cet incident : confirmez au moins une "
        "anomalie avant de composer la réserve.",
      );
    }

    // composeReserve() ré-applique le garde-fou (défense en profondeur,
    // point 8) même si confirmFacts() l'a déjà fait pour chaque fait
    // individuellement.
    final composer.ComposedReserve composed = composer.composeReserve(
      latestFactSets.map((fs) => fs.confirmedData).toList(),
      templateVersion: templateVersion,
    );

    final String id = _uuid.v4();
    final DateTime now = DateTime.now().toUtc();
    final int maxRevision =
        latestFactSets.map((fs) => fs.revision).reduce((a, b) => a > b ? a : b);

    await _db.into(_db.localReserveTexts).insert(
          LocalReserveTextsCompanion.insert(
            id: id,
            incidentId: incidentId,
            templateVersion: composed.templateVersion,
            confirmedFactRevision: maxRevision,
            reserveText: composed.text,
            sha256: composed.sha256,
            createdAt: now,
          ),
        );

    final domain.Incident? incident = await getIncident(incidentId);
    if (incident != null && incident.status.pathTo(IncidentStatus.reserveReady) != null) {
      await updateIncidentStatus(incidentId, IncidentStatus.reserveReady);
    }

    return domain.ReserveText(
      id: id,
      incidentId: incidentId,
      templateVersion: composed.templateVersion,
      confirmedFactRevision: maxRevision,
      text: composed.text,
      sha256: composed.sha256,
      createdAt: now,
    );
  }

  @override
  Future<domain.ReserveText?> latestReserveText(String incidentId) async {
    final LocalReserveText? row = await (_db.select(_db.localReserveTexts)
          ..where((t) => t.incidentId.equals(incidentId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(1))
        .getSingleOrNull();
    if (row == null) {
      return null;
    }
    return domain.ReserveText(
      id: row.id,
      incidentId: row.incidentId,
      templateVersion: row.templateVersion,
      confirmedFactRevision: row.confirmedFactRevision,
      text: row.reserveText,
      sha256: row.sha256,
      createdAt: row.createdAt,
    );
  }

  // -- Preuves ------------------------------------------------------------

  @override
  Future<domain.EvidenceAsset> registerEvidenceAsset(domain.EvidenceAsset asset) async {
    await _db.into(_db.localEvidenceAssets).insert(
          LocalEvidenceAssetsCompanion.insert(
            id: asset.id,
            incidentId: asset.incidentId,
            documentType: _documentTypeWireValue(asset.documentType),
            localFilePath: asset.localFilePath,
            mimeType: asset.mimeType,
            bytes: asset.bytes,
            capturedAtDevice: asset.capturedAtDevice,
            issueId: Value<String?>(asset.issueId),
            sha256: Value<String?>(asset.sha256),
            availabilityStatus:
                Value<String>(_availabilityWireValue(asset.availabilityStatus)),
          ),
        );
    return asset;
  }

  @override
  Future<List<domain.EvidenceAsset>> listEvidenceAssets(String incidentId) async {
    final List<LocalEvidenceAsset> rows = await (_db.select(_db.localEvidenceAssets)
          ..where((t) => t.incidentId.equals(incidentId)))
        .get();
    return rows.map(_toDomainEvidenceAsset).toList();
  }

  @override
  Future<void> deleteEvidenceAsset(String assetId) async {
    // R1 (point 7) : supprime UNIQUEMENT la métadonnée. Le fichier binaire
    // doit être supprimé par l'appelant via
    // `EvidenceStorageService.deleteFile` AVANT cet appel (voir docstring de
    // l'interface) - jamais l'inverse, pour ne jamais laisser une métadonnée
    // pointer vers un fichier déjà supprimé en cas d'échec entre les deux
    // étapes (on préfère un fichier orphelin temporaire à une métadonnée
    // `available` mensongère).
    await (_db.delete(_db.localEvidenceAssets)..where((t) => t.id.equals(assetId))).go();
  }

  @override
  Future<List<domain.EvidenceAsset>> verifyEvidenceAssetsIntegrity(String incidentId) async {
    // R1 : implémentation réelle (relecture disque + recalcul SHA-256, voir
    // lib/data/local/evidence_storage.dart) - détecte `missing` (fichier
    // absent, ex: restauration de sauvegarde incomplète) et `corrupted`
    // (hash différent de celui enregistré à la capture), point 9/R1-T07.
    final List<domain.EvidenceAsset> current = await listEvidenceAssets(incidentId);
    final List<domain.EvidenceAsset> refreshed = <domain.EvidenceAsset>[];
    for (final domain.EvidenceAsset asset in current) {
      final EvidenceIntegrityCheck check = await _evidenceStorage.verify(asset);
      if (check.availabilityStatus == asset.availabilityStatus) {
        refreshed.add(asset);
        continue;
      }
      await (_db.update(_db.localEvidenceAssets)..where((t) => t.id.equals(asset.id))).write(
        LocalEvidenceAssetsCompanion(
          availabilityStatus: Value<String>(_availabilityWireValue(check.availabilityStatus)),
        ),
      );
      refreshed.add(
        domain.EvidenceAsset(
          id: asset.id,
          incidentId: asset.incidentId,
          issueId: asset.issueId,
          documentType: asset.documentType,
          localFilePath: asset.localFilePath,
          sha256: asset.sha256,
          mimeType: asset.mimeType,
          bytes: asset.bytes,
          capturedAtDevice: asset.capturedAtDevice,
          availabilityStatus: check.availabilityStatus,
        ),
      );
    }
    return refreshed;
  }

  domain.EvidenceAsset _toDomainEvidenceAsset(LocalEvidenceAsset row) {
    return domain.EvidenceAsset(
      id: row.id,
      incidentId: row.incidentId,
      issueId: row.issueId,
      documentType: _documentTypeFromWire(row.documentType),
      localFilePath: row.localFilePath,
      sha256: row.sha256,
      mimeType: row.mimeType,
      bytes: row.bytes,
      capturedAtDevice: row.capturedAtDevice,
      availabilityStatus: _availabilityFromWire(row.availabilityStatus),
    );
  }

  static String _documentTypeWireValue(domain.EvidenceDocumentType type) {
    switch (type) {
      case domain.EvidenceDocumentType.photo:
        return 'photo';
      case domain.EvidenceDocumentType.audio:
        return 'audio';
      case domain.EvidenceDocumentType.deliveryNote:
        return 'delivery_note';
      case domain.EvidenceDocumentType.exportedPdf:
        return 'exported_pdf';
    }
  }

  static domain.EvidenceDocumentType _documentTypeFromWire(String value) {
    switch (value) {
      case 'photo':
        return domain.EvidenceDocumentType.photo;
      case 'audio':
        return domain.EvidenceDocumentType.audio;
      case 'delivery_note':
        return domain.EvidenceDocumentType.deliveryNote;
      case 'exported_pdf':
        return domain.EvidenceDocumentType.exportedPdf;
      default:
        throw ArgumentError('documentType inconnu: $value');
    }
  }

  static String _availabilityWireValue(domain.EvidenceAvailability status) {
    switch (status) {
      case domain.EvidenceAvailability.available:
        return 'available';
      case domain.EvidenceAvailability.missing:
        return 'missing';
      case domain.EvidenceAvailability.corrupted:
        return 'corrupted';
    }
  }

  static domain.EvidenceAvailability _availabilityFromWire(String value) {
    switch (value) {
      case 'available':
        return domain.EvidenceAvailability.available;
      case 'missing':
        return domain.EvidenceAvailability.missing;
      case 'corrupted':
        return domain.EvidenceAvailability.corrupted;
      default:
        throw ArgumentError('availabilityStatus inconnu: $value');
    }
  }

  // -- File d'opérations IA (point 6) --------------------------------------

  @override
  Future<AiQueueItem> enqueueAiOperation({
    required String incidentId,
    required AiOperationKind operationKind,
    required String payloadJson,
    required String idempotencyKey,
    String? issueId,
  }) async {
    final String id = _uuid.v4();
    final DateTime now = DateTime.now().toUtc();
    await _db.into(_db.aiOperationQueue).insert(
          AiOperationQueueCompanion.insert(
            id: id,
            incidentId: incidentId,
            operationKind: _operationKindWireValue(operationKind),
            payloadJson: payloadJson,
            idempotencyKey: idempotencyKey,
            issueId: Value<String?>(issueId),
            createdAt: Value<DateTime>(now),
          ),
        );
    return AiQueueItem(
      id: id,
      incidentId: incidentId,
      issueId: issueId,
      operationKind: operationKind,
      payloadJson: payloadJson,
      idempotencyKey: idempotencyKey,
      createdAt: now,
    );
  }

  @override
  Future<List<AiQueueItem>> listPendingAiOperations() async {
    final List<AiOperationQueueData> rows = await (_db.select(_db.aiOperationQueue)
          ..where((t) => t.status.equals('pending'))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
    return rows.map(_toDomainQueueItem).toList();
  }

  @override
  Future<AiQueueItem> markAiOperationInProgress(String id) async {
    await (_db.update(_db.aiOperationQueue)..where((t) => t.id.equals(id))).write(
      AiOperationQueueCompanion(
        status: const Value<String>('in_progress'),
        lastAttemptAt: Value<DateTime?>(DateTime.now().toUtc()),
      ),
    );
    return _getQueueItemOrThrow(id);
  }

  @override
  Future<AiQueueItem> markAiOperationSucceeded(String id, {required String resultJson}) async {
    await (_db.update(_db.aiOperationQueue)..where((t) => t.id.equals(id))).write(
      AiOperationQueueCompanion(
        status: const Value<String>('done'),
        resultJson: Value<String?>(resultJson),
      ),
    );
    return _getQueueItemOrThrow(id);
  }

  @override
  Future<AiQueueItem> markAiOperationFailed(String id, {required String error}) async {
    final AiQueueItem current = await _getQueueItemOrThrow(id);
    await (_db.update(_db.aiOperationQueue)..where((t) => t.id.equals(id))).write(
      AiOperationQueueCompanion(
        // Repasse en 'pending' (pas 'failed' définitif) tant que le nombre
        // de tentatives n'a pas atteint la limite UI - "rien n'est perdu,
        // retry possible à la reconnexion" (point 6) : l'app ne doit jamais
        // abandonner silencieusement une opération IA.
        status: const Value<String>('pending'),
        retryCount: Value<int>(current.retryCount + 1),
        lastError: Value<String?>(error),
      ),
    );
    return _getQueueItemOrThrow(id);
  }

  Future<AiQueueItem> _getQueueItemOrThrow(String id) async {
    final AiOperationQueueData row = await (_db.select(_db.aiOperationQueue)
          ..where((t) => t.id.equals(id)))
        .getSingle();
    return _toDomainQueueItem(row);
  }

  AiQueueItem _toDomainQueueItem(AiOperationQueueData row) {
    return AiQueueItem(
      id: row.id,
      incidentId: row.incidentId,
      issueId: row.issueId,
      operationKind: _operationKindFromWire(row.operationKind),
      payloadJson: row.payloadJson,
      idempotencyKey: row.idempotencyKey,
      status: _operationStatusFromWire(row.status),
      retryCount: row.retryCount,
      createdAt: row.createdAt,
      lastAttemptAt: row.lastAttemptAt,
      lastError: row.lastError,
      resultJson: row.resultJson,
    );
  }

  static String _operationKindWireValue(AiOperationKind kind) {
    switch (kind) {
      case AiOperationKind.transcribeAudio:
        return 'transcribe_audio';
      case AiOperationKind.extractFromPhoto:
        return 'extract_from_photo';
      case AiOperationKind.extractFromDocument:
        return 'extract_from_document';
    }
  }

  static AiOperationKind _operationKindFromWire(String value) {
    switch (value) {
      case 'transcribe_audio':
        return AiOperationKind.transcribeAudio;
      case 'extract_from_photo':
        return AiOperationKind.extractFromPhoto;
      case 'extract_from_document':
        return AiOperationKind.extractFromDocument;
      default:
        throw ArgumentError('operationKind inconnu: $value');
    }
  }

  static AiOperationStatus _operationStatusFromWire(String value) {
    switch (value) {
      case 'pending':
        return AiOperationStatus.pending;
      case 'in_progress':
        return AiOperationStatus.inProgress;
      case 'done':
        return AiOperationStatus.done;
      case 'failed':
        return AiOperationStatus.failed;
      default:
        throw ArgumentError('status inconnu: $value');
    }
  }
}
