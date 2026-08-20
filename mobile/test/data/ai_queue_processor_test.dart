// R2 - preuve par test du processeur de file `AiOperationQueue`
// (`lib/data/ai_queue_processor.dart`), qui relie `AiApiClient` et
// `IncidentRepository.saveCandidateFactSet` pour que la chaîne capture ->
// IA -> candidat fonctionne de bout en bout.
//
// Même philosophie que `test/data/local_incident_repository_test.dart` :
// tout ce qui PEUT tourner réellement dans ce sandbox tourne réellement
// (vraie base Drift/SQLite sur fichier temporaire, vrai `EvidenceStorageService`
// sur un vrai dossier temporaire) - seul le point réellement impossible à
// exécuter ici (l'appel réseau vers le backend ReserveFlash) est remplacé
// par un `AiHttpTransport` fait à la main, comme dans
// `test/data/remote/ai_api_client_test.dart`.
//
// Statut d'exécution (mobile/README.md) : écrit avec la même rigueur qu'un
// test qui tournerait réellement, mais N'A PAS ÉTÉ EXÉCUTÉ dans cette
// session (aucun SDK Flutter/Dart disponible) - à faire tourner en priorité
// dès que le SDK est disponible.

import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reserveflash/data/ai_queue_processor.dart';
import 'package:reserveflash/data/local/app_database.dart';
import 'package:reserveflash/data/local/evidence_storage.dart';
import 'package:reserveflash/data/local/local_incident_repository.dart';
import 'package:reserveflash/data/local/ocr_service.dart';
import 'package:reserveflash/data/remote/ai_api_client.dart';
import 'package:reserveflash/domain/entities/ai_queue_item.dart';
import 'package:reserveflash/domain/entities/candidate_fact_set.dart' as domain;
import 'package:reserveflash/domain/entities/evidence_asset.dart' as domain;
import 'package:reserveflash/domain/entities/incident.dart' as domain;
import 'package:reserveflash/domain/entities/issue.dart' as domain;
import 'package:reserveflash/domain/repositories/incident_repository.dart';
import 'package:reserveflash/domain/value_objects/issue_type.dart';

/// Fausse implémentation du SEUL point non exécutable localement (réseau
/// vers le backend) - miroir de
/// `test/data/remote/ai_api_client_test.dart::_FakeAiHttpTransport`.
class _FakeAiHttpTransport implements AiHttpTransport {
  _FakeAiHttpTransport(this._responsesByPath, {this.transportErrorPath});

  final Map<String, AiHttpResponse> _responsesByPath;

  /// Si non-null, `postJson` sur ce chemin lève [AiTransportException]
  /// plutôt que de retourner une réponse simulée (panne réseau).
  final String? transportErrorPath;

  final List<String> calledPaths = <String>[];

  @override
  Future<AiHttpResponse> postJson(String path, Map<String, dynamic> body) async {
    calledPaths.add(path);
    if (path == transportErrorPath) {
      throw const AiTransportException('connectionError: simulé');
    }
    final AiHttpResponse? response = _responsesByPath[path];
    if (response == null) {
      throw StateError('Aucune réponse simulée pour $path dans ce test.');
    }
    return response;
  }
}

/// Fausse implémentation du SEUL point non exécutable localement pour
/// l'OCR (le plugin natif ML Kit, qui nécessite un vrai appareil/émulateur -
/// voir docstring de `lib/data/local/ocr_service.dart`) - même principe que
/// `_FakeAiHttpTransport` ci-dessus.
class _FakeOcrService implements OcrService {
  _FakeOcrService(this._textByPath, {this.throwsForPath});

  final Map<String, String> _textByPath;

  /// Si non-null, `recognizeText` sur ce chemin lève une exception plutôt
  /// que de retourner un texte simulé.
  final String? throwsForPath;

  final List<String> calledPaths = <String>[];

  @override
  Future<String> recognizeText(String imagePath) async {
    calledPaths.add(imagePath);
    if (imagePath == throwsForPath) {
      throw StateError('OCR simulé en échec pour $imagePath.');
    }
    return _textByPath[imagePath] ?? '';
  }
}

const AiHttpResponse _successfulTranscribeResponse = AiHttpResponse(
  statusCode: 200,
  body: <String, dynamic>{
    'text': 'Il manque deux radiateurs sur la palette.',
    'provider': 'openai',
    'model_id': 'whisper-1',
    'latency_ms': 500,
    'request_id': 'req-1',
  },
);

const AiHttpResponse _successfulExtractResponse = AiHttpResponse(
  statusCode: 200,
  body: <String, dynamic>{
    'candidate': <String, dynamic>{
      'issue_type_candidate': 'MISSING_QTY',
      'fields': <String, dynamic>{
        'expected_quantity': <String, dynamic>{
          'value': 8,
          'source': 'VOICE_TRANSCRIPT',
          'confidence': 'HIGH',
        },
      },
      'requires_review': false,
      'clarification_question_id': null,
    },
    'provider': 'openai',
    'model_id': 'gpt-4o-mini',
    'prompt_version': 'extraction_fr_v1',
    'schema_version': 'candidate_fact_set.v1',
    'latency_ms': 900,
    'request_id': 'req-2',
  },
);

void main() {
  late Directory tempDir;
  late AppDatabase db;
  late IncidentRepository repository;
  late EvidenceStorageService evidenceStorage;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('reserveflash_ai_queue_test_');
    final File dbFile = File('${tempDir.path}/db.sqlite');
    db = AppDatabase(NativeDatabase(dbFile, logStatements: false));
    evidenceStorage = EvidenceStorageService(documentsDirectoryProvider: () async => tempDir);
    repository = LocalIncidentRepository(db, evidenceStorage: evidenceStorage);
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      try {
        await tempDir.delete(recursive: true);
      } on FileSystemException {
        // R0.2 (hotfix connu, voir local_incident_repository_test.dart) :
        // verrou OS résiduel sur Windows juste après la fermeture de la
        // connexion SQLite - sans impact sur ce que ce test vérifie.
      }
    }
  });

  Future<domain.Incident> seedIncidentWithIssue() async {
    final domain.Incident incident = await repository.createIncident(
      occurredAt: DateTime.utc(2026, 1, 10),
    );
    await repository.addIssue(incident.id, IssueType.missingQty);
    return incident;
  }

  Future<domain.EvidenceAsset> seedAudioAsset(String incidentId, {String content = 'audio'}) async {
    final File sourceFile = File('${tempDir.path}/source.m4a');
    await sourceFile.writeAsBytes(utf8.encode(content), flush: true);
    final domain.EvidenceAsset asset = await evidenceStorage.captureFromFile(
      incidentId: incidentId,
      sourcePath: sourceFile.path,
      documentType: domain.EvidenceDocumentType.audio,
      mimeType: 'audio/m4a',
      extension: 'm4a',
    );
    return repository.registerEvidenceAsset(asset);
  }

  Future<AiQueueItem> enqueueTranscribeAudio({
    required String incidentId,
    required String evidenceAssetId,
    String? issueId,
    // Un test peut vouloir prouver la déduplication même quand l'appelant
    // ne connaît que l'id de la preuve (pas son sha256) - repli identique à
    // celui de voice_description_screen.dart.
    String? sourceHash,
  }) async {
    final TranscribeAudioPayload payload = TranscribeAudioPayload(evidenceAssetId: evidenceAssetId);
    return repository.enqueueAiOperation(
      incidentId: incidentId,
      issueId: issueId,
      operationKind: AiOperationKind.transcribeAudio,
      payloadJson: payload.encode(),
      idempotencyKey: aiOperationIdempotencyKey(
        incidentId: incidentId,
        operationKind: AiOperationKind.transcribeAudio,
        sourceHash: sourceHash ?? evidenceAssetId,
      ),
    );
  }

  Future<domain.EvidenceAsset> seedDocumentAsset(String incidentId, {String content = 'document'}) async {
    final File sourceFile = File('${tempDir.path}/source.jpg');
    await sourceFile.writeAsBytes(utf8.encode(content), flush: true);
    final domain.EvidenceAsset asset = await evidenceStorage.captureFromFile(
      incidentId: incidentId,
      sourcePath: sourceFile.path,
      documentType: domain.EvidenceDocumentType.deliveryNote,
      mimeType: 'image/jpeg',
      extension: 'jpg',
    );
    return repository.registerEvidenceAsset(asset);
  }

  Future<AiQueueItem> enqueueExtractFromDocument({
    required String incidentId,
    required String evidenceAssetId,
    String? issueId,
    String? sourceHash,
  }) async {
    final ExtractFromDocumentPayload payload =
        ExtractFromDocumentPayload(evidenceAssetId: evidenceAssetId);
    return repository.enqueueAiOperation(
      incidentId: incidentId,
      issueId: issueId,
      operationKind: AiOperationKind.extractFromDocument,
      payloadJson: payload.encode(),
      idempotencyKey: aiOperationIdempotencyKey(
        incidentId: incidentId,
        operationKind: AiOperationKind.extractFromDocument,
        sourceHash: sourceHash ?? evidenceAssetId,
      ),
    );
  }

  Future<domain.EvidenceAsset> seedPhotoAsset(String incidentId, {String content = 'photo'}) async {
    final File sourceFile = File('${tempDir.path}/source_photo.jpg');
    await sourceFile.writeAsBytes(utf8.encode(content), flush: true);
    final domain.EvidenceAsset asset = await evidenceStorage.captureFromFile(
      incidentId: incidentId,
      sourcePath: sourceFile.path,
      documentType: domain.EvidenceDocumentType.photo,
      mimeType: 'image/jpeg',
      extension: 'jpg',
    );
    return repository.registerEvidenceAsset(asset);
  }

  Future<AiQueueItem> enqueueExtractFromPhoto({
    required String incidentId,
    required String evidenceAssetId,
    String? issueId,
    String? sourceHash,
  }) async {
    final ExtractFromPhotoPayload payload =
        ExtractFromPhotoPayload(evidenceAssetId: evidenceAssetId);
    return repository.enqueueAiOperation(
      incidentId: incidentId,
      issueId: issueId,
      operationKind: AiOperationKind.extractFromPhoto,
      payloadJson: payload.encode(),
      idempotencyKey: aiOperationIdempotencyKey(
        incidentId: incidentId,
        operationKind: AiOperationKind.extractFromPhoto,
        sourceHash: sourceHash ?? evidenceAssetId,
      ),
    );
  }

  group('AiQueueProcessor - transcribeAudio, succès', () {
    test(
      'transcrit (round 1) puis extrait et persiste un CandidateFactSet '
      "(round 2), en un seul appel à processPendingOperations",
      () async {
        final domain.Incident incident = await seedIncidentWithIssue();
        final List<domain.Issue> issues = await repository.listIssues(incident.id);
        final domain.EvidenceAsset asset = await seedAudioAsset(incident.id);
        await enqueueTranscribeAudio(
          incidentId: incident.id,
          evidenceAssetId: asset.id,
          issueId: issues.first.id,
        );

        final _FakeAiHttpTransport transport = _FakeAiHttpTransport(const <String, AiHttpResponse>{
          '/v1/ai/transcribe': _successfulTranscribeResponse,
          '/v1/ai/extract': _successfulExtractResponse,
        });
        final AiQueueProcessor processor = AiQueueProcessor(
          incidentRepository: repository,
          aiApiClient: AiApiClient(transport),
          evidenceStorage: evidenceStorage,
        );

        final AiQueueProcessingSummary summary = await processor.processPendingOperations();

        // 2 succès : l'item transcribeAudio (round 1) ET l'item
        // extractFromTranscript qu'il a mis en file (round 2), traité dans
        // le MÊME appel - voir docstring de processPendingOperations.
        expect(summary.succeeded, 2);
        expect(summary.failed, 0);
        expect(summary.skipped, 0);
        expect(transport.calledPaths, <String>['/v1/ai/transcribe', '/v1/ai/extract']);

        expect(await repository.listPendingAiOperations(), isEmpty);
        final domain.CandidateFactSet? candidate =
            await repository.latestCandidateFactSet(issues.first.id);
        expect(candidate, isNotNull);
        expect(candidate!.candidateData.issueTypeCandidate, IssueType.missingQty);
        expect(candidate.candidateData.fields['expected_quantity']!.value, 8);
        expect(candidate.promptVersion, 'extraction_fr_v1');
        expect(candidate.model, 'gpt-4o-mini');
      },
    );
  });

  group('AiQueueProcessor - extractFromDocument (OCR, R2)', () {
    test(
      'OCR (mock) puis extraction en un seul item -> CandidateFactSet persisté',
      () async {
        final domain.Incident incident = await seedIncidentWithIssue();
        final List<domain.Issue> issues = await repository.listIssues(incident.id);
        final domain.EvidenceAsset asset = await seedDocumentAsset(incident.id);
        await enqueueExtractFromDocument(
          incidentId: incident.id,
          evidenceAssetId: asset.id,
          issueId: issues.first.id,
        );

        final _FakeAiHttpTransport transport = _FakeAiHttpTransport(const <String, AiHttpResponse>{
          '/v1/ai/extract': _successfulExtractResponse,
        });
        final _FakeOcrService ocr = _FakeOcrService(<String, String>{
          asset.localFilePath: 'Bon de livraison n°42 - 8 palettes reçues sur 10 attendues',
        });
        final AiQueueProcessor processor = AiQueueProcessor(
          incidentRepository: repository,
          aiApiClient: AiApiClient(transport),
          evidenceStorage: evidenceStorage,
          ocrService: ocr,
        );

        final AiQueueProcessingSummary summary = await processor.processPendingOperations();

        // UN SEUL item (contrairement à transcribeAudio/extractFromTranscript)
        // : l'OCR tourne SUR L'APPAREIL dans _runExtractFromDocument
        // lui-même, sans mettre en file d'item intermédiaire (voir docstring
        // d'ExtractFromDocumentPayload).
        expect(summary.succeeded, 1);
        expect(summary.failed, 0);
        expect(ocr.calledPaths, <String>[asset.localFilePath]);
        expect(transport.calledPaths, <String>['/v1/ai/extract']);

        expect(await repository.listPendingAiOperations(), isEmpty);
        final domain.CandidateFactSet? candidate =
            await repository.latestCandidateFactSet(issues.first.id);
        expect(candidate, isNotNull);
        expect(candidate!.candidateData.issueTypeCandidate, IssueType.missingQty);
      },
    );

    test(
      "l'OCR échoue (ex: bug du plugin natif) -> échoue proprement, requeue "
      'pending, jamais de perte',
      () async {
        final domain.Incident incident = await seedIncidentWithIssue();
        final List<domain.Issue> issues = await repository.listIssues(incident.id);
        final domain.EvidenceAsset asset = await seedDocumentAsset(incident.id);
        await enqueueExtractFromDocument(
          incidentId: incident.id,
          evidenceAssetId: asset.id,
          issueId: issues.first.id,
        );

        final _FakeOcrService ocr = _FakeOcrService(
          const <String, String>{},
          throwsForPath: asset.localFilePath,
        );
        final AiQueueProcessor processor = AiQueueProcessor(
          incidentRepository: repository,
          aiApiClient: AiApiClient(_FakeAiHttpTransport(const <String, AiHttpResponse>{})),
          evidenceStorage: evidenceStorage,
          ocrService: ocr,
        );

        final AiQueueProcessingSummary summary = await processor.processPendingOperations();

        expect(summary.failed, 1);
        final List<AiQueueItem> pending = await repository.listPendingAiOperations();
        expect(pending, hasLength(1));
        expect(pending.first.retryCount, 1);
        expect(await repository.latestCandidateFactSet(issues.first.id), isNull);
      },
    );
  });

  group('AiQueueProcessor - optimisation coût IA', () {
    test(
      "l'extraction échoue après une transcription réussie -> le retry ne "
      'refait JAMAIS la transcription déjà payée en tokens',
      () async {
        final domain.Incident incident = await seedIncidentWithIssue();
        final List<domain.Issue> issues = await repository.listIssues(incident.id);
        final domain.EvidenceAsset asset = await seedAudioAsset(incident.id);
        await enqueueTranscribeAudio(
          incidentId: incident.id,
          evidenceAssetId: asset.id,
          issueId: issues.first.id,
        );

        // Premier passage : la transcription réussit, mais l'extraction
        // tombe en panne réseau juste après (ex : coupure entre les deux
        // appels).
        final _FakeAiHttpTransport firstAttemptTransport = _FakeAiHttpTransport(
          const <String, AiHttpResponse>{'/v1/ai/transcribe': _successfulTranscribeResponse},
          transportErrorPath: '/v1/ai/extract',
        );
        final AiQueueProcessor firstProcessor = AiQueueProcessor(
          incidentRepository: repository,
          aiApiClient: AiApiClient(firstAttemptTransport),
          evidenceStorage: evidenceStorage,
        );
        final AiQueueProcessingSummary firstSummary = await firstProcessor.processPendingOperations();

        expect(firstSummary.succeeded, 1); // transcribeAudio.
        expect(firstSummary.failed, 1); // extractFromTranscript.
        expect(firstAttemptTransport.calledPaths, <String>['/v1/ai/transcribe', '/v1/ai/extract']);
        expect(await repository.listPendingAiOperations(), hasLength(1));

        // Deuxième passage (ex : retour réseau) : SEULE l'extraction doit
        // être retentée - la transcription ne doit JAMAIS être rappelée,
        // même si le transport du deuxième passage la supporterait.
        final _FakeAiHttpTransport secondAttemptTransport = _FakeAiHttpTransport(
          const <String, AiHttpResponse>{
            '/v1/ai/transcribe': _successfulTranscribeResponse,
            '/v1/ai/extract': _successfulExtractResponse,
          },
        );
        final AiQueueProcessor secondProcessor = AiQueueProcessor(
          incidentRepository: repository,
          aiApiClient: AiApiClient(secondAttemptTransport),
          evidenceStorage: evidenceStorage,
        );
        final AiQueueProcessingSummary secondSummary = await secondProcessor.processPendingOperations();

        expect(secondSummary.succeeded, 1); // extractFromTranscript, enfin.
        expect(secondSummary.failed, 0);
        expect(
          secondAttemptTransport.calledPaths,
          <String>['/v1/ai/extract'], // PAS '/v1/ai/transcribe'.
        );

        expect(await repository.listPendingAiOperations(), isEmpty);
        final domain.CandidateFactSet? candidate =
            await repository.latestCandidateFactSet(issues.first.id);
        expect(candidate, isNotNull);
      },
    );

    test(
      'enqueueAiOperation avec la même idempotencyKey ne crée jamais de '
      'doublon (jamais deux appels IA payants pour le même contenu)',
      () async {
        final domain.Incident incident = await seedIncidentWithIssue();
        final List<domain.Issue> issues = await repository.listIssues(incident.id);
        final domain.EvidenceAsset asset = await seedAudioAsset(incident.id);

        // sourceHash = asset.sha256, comme le fait réellement
        // voice_description_screen.dart (voir sa docstring) - preuve avec
        // la même composition de clé qu'en production, pas juste un id
        // arbitraire.
        final AiQueueItem first = await enqueueTranscribeAudio(
          incidentId: incident.id,
          evidenceAssetId: asset.id,
          issueId: issues.first.id,
          sourceHash: asset.sha256,
        );
        final AiQueueItem second = await enqueueTranscribeAudio(
          incidentId: incident.id,
          evidenceAssetId: asset.id,
          issueId: issues.first.id,
          sourceHash: asset.sha256,
        );

        expect(second.id, first.id);
        expect(await repository.listPendingAiOperations(), hasLength(1));
      },
    );
  });

  group('AiQueueProcessor - échecs transitoires (requeue, jamais perdu)', () {
    test('panne réseau au transcribe -> requeue pending, retryCount incrémenté', () async {
      final domain.Incident incident = await seedIncidentWithIssue();
      final List<domain.Issue> issues = await repository.listIssues(incident.id);
      final domain.EvidenceAsset asset = await seedAudioAsset(incident.id);
      await enqueueTranscribeAudio(
        incidentId: incident.id,
        evidenceAssetId: asset.id,
        issueId: issues.first.id,
      );

      final _FakeAiHttpTransport transport = _FakeAiHttpTransport(
        const <String, AiHttpResponse>{},
        transportErrorPath: '/v1/ai/transcribe',
      );
      final AiQueueProcessor processor = AiQueueProcessor(
        incidentRepository: repository,
        aiApiClient: AiApiClient(transport),
        evidenceStorage: evidenceStorage,
      );

      final AiQueueProcessingSummary summary = await processor.processPendingOperations();

      expect(summary.failed, 1);
      final List<AiQueueItem> pending = await repository.listPendingAiOperations();
      expect(pending, hasLength(1));
      expect(pending.first.retryCount, 1);
      expect(pending.first.lastError, contains('AI_UNAVAILABLE'));

      // Rien n'est perdu : aucun CandidateFactSet n'a été créé.
      expect(await repository.latestCandidateFactSet(issues.first.id), isNull);
    });

    test(
      'disjoncteur de retry : au-delà de maxRetryCount, un item pending '
      "n'est plus retenté (skipped) mais reste intact",
      () async {
        final domain.Incident incident = await seedIncidentWithIssue();
        final List<domain.Issue> issues = await repository.listIssues(incident.id);
        final domain.EvidenceAsset asset = await seedAudioAsset(incident.id);
        await enqueueTranscribeAudio(
          incidentId: incident.id,
          evidenceAssetId: asset.id,
          issueId: issues.first.id,
        );

        final _FakeAiHttpTransport transport = _FakeAiHttpTransport(
          const <String, AiHttpResponse>{},
          transportErrorPath: '/v1/ai/transcribe',
        );
        final AiQueueProcessor processor = AiQueueProcessor(
          incidentRepository: repository,
          aiApiClient: AiApiClient(transport),
          evidenceStorage: evidenceStorage,
          maxRetryCount: 2,
        );

        await processor.processPendingOperations(); // retryCount -> 1
        await processor.processPendingOperations(); // retryCount -> 2

        final AiQueueProcessingSummary third = await processor.processPendingOperations();
        expect(third.skipped, 1);
        expect(third.failed, 0);

        final List<AiQueueItem> pending = await repository.listPendingAiOperations();
        expect(pending, hasLength(1));
        expect(pending.first.retryCount, 2); // inchangé par le passage "skipped".
      },
    );
  });

  group('AiQueueProcessor - extractFromPhoto (OCR preuve générique, R2)', () {
    test(
      'OCR (mock) puis extraction en un seul item -> CandidateFactSet persisté',
      () async {
        final domain.Incident incident = await seedIncidentWithIssue();
        final List<domain.Issue> issues = await repository.listIssues(incident.id);
        final domain.EvidenceAsset asset = await seedPhotoAsset(incident.id);
        await enqueueExtractFromPhoto(
          incidentId: incident.id,
          evidenceAssetId: asset.id,
          issueId: issues.first.id,
        );

        final _FakeAiHttpTransport transport = _FakeAiHttpTransport(const <String, AiHttpResponse>{
          '/v1/ai/extract': _successfulExtractResponse,
        });
        final _FakeOcrService ocr = _FakeOcrService(<String, String>{
          asset.localFilePath: 'Réf. produit XZ-42 - 8 reçus sur 10 attendus',
        });
        final AiQueueProcessor processor = AiQueueProcessor(
          incidentRepository: repository,
          aiApiClient: AiApiClient(transport),
          evidenceStorage: evidenceStorage,
          ocrService: ocr,
        );

        final AiQueueProcessingSummary summary = await processor.processPendingOperations();

        // UN SEUL item (même raisonnement qu'extractFromDocument - voir
        // docstring d'ExtractFromPhotoPayload) : OCR gratuit on-device, pas
        // de découpage en deux étapes.
        expect(summary.succeeded, 1);
        expect(summary.failed, 0);
        expect(ocr.calledPaths, <String>[asset.localFilePath]);
        expect(transport.calledPaths, <String>['/v1/ai/extract']);

        expect(await repository.listPendingAiOperations(), isEmpty);
        final domain.CandidateFactSet? candidate =
            await repository.latestCandidateFactSet(issues.first.id);
        expect(candidate, isNotNull);
        expect(candidate!.candidateData.issueTypeCandidate, IssueType.missingQty);
      },
    );

    test(
      "l'OCR échoue (ex: bug du plugin natif) -> échoue proprement, requeue "
      'pending, jamais de perte',
      () async {
        final domain.Incident incident = await seedIncidentWithIssue();
        final List<domain.Issue> issues = await repository.listIssues(incident.id);
        final domain.EvidenceAsset asset = await seedPhotoAsset(incident.id);
        await enqueueExtractFromPhoto(
          incidentId: incident.id,
          evidenceAssetId: asset.id,
          issueId: issues.first.id,
        );

        final _FakeOcrService ocr = _FakeOcrService(
          const <String, String>{},
          throwsForPath: asset.localFilePath,
        );
        final AiQueueProcessor processor = AiQueueProcessor(
          incidentRepository: repository,
          aiApiClient: AiApiClient(_FakeAiHttpTransport(const <String, AiHttpResponse>{})),
          evidenceStorage: evidenceStorage,
          ocrService: ocr,
        );

        final AiQueueProcessingSummary summary = await processor.processPendingOperations();

        expect(summary.failed, 1);
        final List<AiQueueItem> pending = await repository.listPendingAiOperations();
        expect(pending, hasLength(1));
        expect(pending.first.retryCount, 1);
        expect(await repository.latestCandidateFactSet(issues.first.id), isNull);
      },
    );
  });

  group('AiQueueProcessor - erreurs de cohérence interne (bug de câblage écran)', () {
    test('transcribeAudio sans issueId -> échoue proprement, requeue pending', () async {
      final domain.Incident incident = await seedIncidentWithIssue();
      final domain.EvidenceAsset asset = await seedAudioAsset(incident.id);
      await enqueueTranscribeAudio(incidentId: incident.id, evidenceAssetId: asset.id);
      // issueId volontairement omis ci-dessus.

      final AiQueueProcessor processor = AiQueueProcessor(
        incidentRepository: repository,
        aiApiClient: AiApiClient(_FakeAiHttpTransport(const <String, AiHttpResponse>{})),
        evidenceStorage: evidenceStorage,
      );

      final AiQueueProcessingSummary summary = await processor.processPendingOperations();

      expect(summary.failed, 1);
      final List<AiQueueItem> pending = await repository.listPendingAiOperations();
      expect(pending, hasLength(1));
      expect(pending.first.lastError, contains('issueId'));
    });

    test('EvidenceAsset référencé introuvable -> échoue proprement, requeue pending', () async {
      final domain.Incident incident = await seedIncidentWithIssue();
      final List<domain.Issue> issues = await repository.listIssues(incident.id);
      await enqueueTranscribeAudio(
        incidentId: incident.id,
        evidenceAssetId: 'evidence-inconnue',
        issueId: issues.first.id,
      );

      final AiQueueProcessor processor = AiQueueProcessor(
        incidentRepository: repository,
        aiApiClient: AiApiClient(_FakeAiHttpTransport(const <String, AiHttpResponse>{})),
        evidenceStorage: evidenceStorage,
      );

      final AiQueueProcessingSummary summary = await processor.processPendingOperations();

      expect(summary.failed, 1);
      final List<AiQueueItem> pending = await repository.listPendingAiOperations();
      expect(pending, hasLength(1));
      expect(pending.first.lastError, contains('evidence-inconnue'));
    });
  });
}
