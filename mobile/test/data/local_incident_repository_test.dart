// R0.2 (retour de recette R0.1, point "La base locale Drift n'a pas
// réellement été testée") :
//
// > "Nous devons absolument tester : Créer incident, écrire dans Drift,
// > fermer l'application, rouvrir, retrouver exactement l'incident... et
// > idéalement : incident + faits + chemins photos + PendingAIJob."
// > "Le Gate R0 ne doit pas être accepté sur la simple affirmation :
// > « SQLite persiste par nature ». Nous voulons la preuve par test."
//
// Ce fichier répond littéralement à cette demande : chaque test ouvre une
// VRAIE base SQLite sur disque (`NativeDatabase` de `package:drift`,
// fichier temporaire réel via `dart:io`, PAS `NativeDatabase.memory()`),
// écrit des données via [LocalIncidentRepository], FERME la connexion
// (`db.close()` - équivalent réel d'un kill du process app), puis rouvre
// une [AppDatabase] TOTALEMENT NOUVELLE sur le MÊME fichier (nouvelle
// instance Dart, nouvelle connexion `QueryExecutor`, aucun état partagé en
// mémoire avec la première) pour prouver que les données survivent - c'est
// la seule façon de distinguer "persistance réelle sur disque" de
// "persistance en mémoire du process de test".
//
// Statut d'exécution (honnêteté de livraison, voir docs/GATE_R0.1_STATUS.md
// et mobile/README.md) : ce fichier est écrit avec la même rigueur qu'un
// test qui tournerait réellement, mais N'A PAS ÉTÉ EXÉCUTÉ dans cette
// session - le SDK Flutter/Dart est resté inaccessible dans les deux
// environnements disponibles (sandbox cloud et pont `device_bash`, voir
// CHANGELOG.md, section R0.2). Il a été relu ligne à ligne contre le schéma
// réel de `app_database.dart` et `local_incident_repository.dart` (types de
// colonnes, noms de companions, valeurs wire des enums) pour maximiser les
// chances qu'il passe tel quel une fois `flutter test` exécutable - mais
// seule une exécution réelle (voir `mobile/README.md`, section
// "Bootstrap") constitue une preuve. Ne pas déclarer ce critère du Gate
// validé tant que ce fichier n'a pas tourné au moins une fois avec un
// résultat vert.

import 'dart:convert';
import 'dart:io';

// R0.2 (hotfix decouvert par execution reelle) : ne PAS importer
// `package:drift/drift.dart` ici en plus de `package:drift/native.dart` -
// le premier re-exporte `isNotNull`/`isNull`, qui entrent en collision avec
// les matchers de meme nom de `package:flutter_test` (`ambiguous_import`).
// Seul `NativeDatabase` (de `drift/native.dart`) est reellement utilise par
// ce fichier.
import 'package:drift/native.dart';
import 'package:reserveflash/data/local/app_database.dart';
import 'package:reserveflash/data/local/local_incident_repository.dart';
import 'package:reserveflash/domain/entities/candidate_fact_set.dart' as domain;
import 'package:reserveflash/domain/entities/confirmed_fact_set.dart' as domain;
import 'package:reserveflash/domain/entities/evidence_asset.dart' as domain;
import 'package:reserveflash/domain/entities/incident.dart' as domain;
import 'package:reserveflash/domain/entities/issue.dart' as domain;
import 'package:reserveflash/domain/errors/domain_errors.dart';
import 'package:reserveflash/domain/entities/ai_queue_item.dart';
import 'package:reserveflash/domain/fact_set/candidate_fact_data.dart';
import 'package:reserveflash/domain/fact_set/confirmed_fact_data.dart';
import 'package:reserveflash/domain/value_objects/confidence_level.dart';
import 'package:reserveflash/domain/value_objects/incident_status.dart';
import 'package:reserveflash/domain/value_objects/issue_type.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ouvre une base Drift persistée sur un VRAI fichier temporaire (pas
/// `NativeDatabase.memory()`) : le but explicite de ce test est de prouver
/// une persistance disque, pas une persistance mémoire de process.
AppDatabase _openFileBackedDatabase(File dbFile) {
  return AppDatabase(NativeDatabase(dbFile, logStatements: false));
}

void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('reserveflash_drift_test_');
    dbFile = File('${tempDir.path}/reserveflash_test.sqlite');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      // R0.2 (hotfix decouvert par execution reelle sur Windows) : sur
      // Windows, le verrou OS sur le fichier SQLite ouvert par
      // `NativeDatabase` n'est pas toujours libere de facon synchrone au
      // retour de `db.close()` (le driver natif le relache de facon
      // asynchrone) - `Directory.delete(recursive: true)` levait alors
      // `PathAccessException` ("...ce fichier est utilise par un autre
      // processus", errno = 32), faisant echouer le test de nettoyage
      // alors que TOUTES les assertions metier avaient deja reussi.
      // Correctif : quelques tentatives espacees d'un court delai avant
      // d'abandonner ; si le nettoyage echoue quand meme, ne PAS faire
      // echouer le test pour un residu de fichier temporaire purement
      // cosmetique (le dossier restera dans le repertoire temp systeme,
      // sans consequence fonctionnelle ni impact sur la preuve de
      // persistance elle-meme, deja verifiee par les `expect` ci-dessus).
      const int maxAttempts = 5;
      for (int attempt = 1; attempt <= maxAttempts; attempt++) {
        try {
          await tempDir.delete(recursive: true);
          break;
        } on FileSystemException {
          if (attempt == maxAttempts) {
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
      }
    }
  });

  group('LocalIncidentRepository - persistance disque réelle (Gate R0, preuve par test)', () {
    test(
      'créer un incident, fermer la "app" (fermer la connexion DB), la '
      "rouvrir (nouvelle instance AppDatabase sur le même fichier), et "
      'retrouver EXACTEMENT le même incident',
      () async {
        // --- 1) "Ouverture de l'app" : premher lancement, DB vide. -------
        final AppDatabase firstOpen = _openFileBackedDatabase(dbFile);
        final LocalIncidentRepository firstRepository =
            LocalIncidentRepository(firstOpen);

        final DateTime occurredAt = DateTime.utc(2026, 8, 19, 10, 30);
        final domain.Incident created = await firstRepository.createIncident(
          occurredAt: occurredAt,
          supplierName: 'Fournisseur Test SARL',
          carrierName: 'Transporteur Test',
          deliveryRef: 'BL-2026-000123',
          notes: 'Palette abîmée à réception.',
        );

        // Sanity check immédiat (même connexion) avant la vraie preuve.
        final domain.Incident? readBackSameSession =
            await firstRepository.getIncident(created.id);
        expect(readBackSameSession, isNotNull);
        expect(readBackSameSession!.id, created.id);

        // --- 2) "Fermeture de l'app" : on ferme la connexion SQLite. ------
        // C'est l'équivalent réel d'un kill du process : aucun état Dart
        // en mémoire (cache, singleton) ne survit à cet appel.
        await firstOpen.close();

        // Le fichier doit exister réellement sur disque après fermeture -
        // sinon la "persistance" ne serait qu'une illusion de test.
        expect(await dbFile.exists(), isTrue);
        expect(await dbFile.length(), greaterThan(0));

        // --- 3) "Réouverture de l'app" : nouvelle instance, même fichier. -
        final AppDatabase secondOpen = _openFileBackedDatabase(dbFile);
        final LocalIncidentRepository secondRepository =
            LocalIncidentRepository(secondOpen);

        final domain.Incident? reopened =
            await secondRepository.getIncident(created.id);

        // --- 4) La preuve demandée : l'incident EXACT est retrouvé. -------
        expect(reopened, isNotNull);
        expect(reopened!.id, equals(created.id));
        expect(reopened.status, equals(IncidentStatus.draftLocal));
        expect(reopened.occurredAt, equals(occurredAt));
        expect(reopened.supplierName, equals('Fournisseur Test SARL'));
        expect(reopened.carrierName, equals('Transporteur Test'));
        expect(reopened.deliveryRef, equals('BL-2026-000123'));
        expect(reopened.notes, equals('Palette abîmée à réception.'));
        expect(reopened.archived, isFalse);

        await secondOpen.close();
      },
    );

    test(
      'idéal demandé par la recette : incident + fait confirmé + chemin '
      'photo (EvidenceAsset) + opération IA en attente (AiOperationQueue) '
      'survivent tous ensemble à une fermeture/réouverture',
      () async {
        final AppDatabase firstOpen = _openFileBackedDatabase(dbFile);
        final LocalIncidentRepository firstRepository =
            LocalIncidentRepository(firstOpen);

        final domain.Incident incident = await firstRepository.createIncident(
          occurredAt: DateTime.utc(2026, 8, 19, 9),
          supplierName: 'Fournisseur B',
        );
        final domain.Issue issue = await firstRepository.addIssue(
          incident.id,
          IssueType.packagingDamage,
        );

        // Fait confirmé : passe par le garde-fou anti-attribution de
        // responsabilité (point 8) - un champ neutre, factuel, doit être
        // accepté et persisté sans altération.
        final ConfirmedFactData confirmedData = ConfirmedFactData(
          issueType: IssueType.packagingDamage,
          productLabel: 'Carton de 12 bouteilles',
          expectedQuantity: 12,
          receivedQuantity: 10,
          affectedQuantity: 2,
          packagingCondition: 'Carton extérieur percé sur un angle.',
        );
        final domain.ConfirmedFactSet confirmedFactSet =
            await firstRepository.confirmFacts(
          issueId: issue.id,
          data: confirmedData,
          confirmedBy: null, // point 13 : aucun compte requis.
        );

        // Chemin photo : EvidenceAsset avec un `localFilePath` réaliste.
        final String evidenceId = 'evidence-${incident.id}';
        final String evidencePath =
            '${tempDir.path}/evidence/$evidenceId.jpg';
        final domain.EvidenceAsset evidenceAsset = domain.EvidenceAsset(
          id: evidenceId,
          incidentId: incident.id,
          issueId: issue.id,
          documentType: domain.EvidenceDocumentType.photo,
          localFilePath: evidencePath,
          sha256: 'a' * 64, // valeur factice au format attendu.
          mimeType: 'image/jpeg',
          bytes: 204800,
          capturedAtDevice: DateTime.utc(2026, 8, 19, 9, 5),
        );
        await firstRepository.registerEvidenceAsset(evidenceAsset);

        // Opération IA en attente (PendingAIJob demandé par la recette =
        // AiOperationQueue.status == 'pending' dans ce schéma).
        final AiQueueItem queuedJob = await firstRepository.enqueueAiOperation(
          incidentId: incident.id,
          issueId: issue.id,
          operationKind: AiOperationKind.extractFromPhoto,
          payloadJson: jsonEncode(<String, String>{'evidenceAssetId': evidenceId}),
          idempotencyKey: 'idem-$evidenceId',
        );
        expect(queuedJob.status, equals(AiOperationStatus.pending));

        // "Fermeture de l'app".
        await firstOpen.close();

        // "Réouverture de l'app".
        final AppDatabase secondOpen = _openFileBackedDatabase(dbFile);
        final LocalIncidentRepository secondRepository =
            LocalIncidentRepository(secondOpen);

        // -- Incident + statut avancé automatiquement à factsConfirmed. ----
        final domain.Incident? reopenedIncident =
            await secondRepository.getIncident(incident.id);
        expect(reopenedIncident, isNotNull);
        expect(reopenedIncident!.status, equals(IncidentStatus.factsConfirmed));

        // -- Fait confirmé retrouvé, avec les MÊMES valeurs. ---------------
        final domain.ConfirmedFactSet? reopenedFactSet =
            await secondRepository.latestConfirmedFactSet(issue.id);
        expect(reopenedFactSet, isNotNull);
        expect(reopenedFactSet!.id, equals(confirmedFactSet.id));
        expect(reopenedFactSet.revision, equals(1));
        expect(
          reopenedFactSet.confirmedData.packagingCondition,
          equals('Carton extérieur percé sur un angle.'),
        );
        expect(reopenedFactSet.confirmedData.expectedQuantity, equals(12));
        expect(reopenedFactSet.confirmedData.receivedQuantity, equals(10));
        expect(reopenedFactSet.confirmedData.affectedQuantity, equals(2));
        // Invariant 6.3 : un ConfirmedFactData désérialisé reste
        // `userConfirmed == true` par construction de type - aucune
        // désérialisation ne peut produire un fait "non confirmé".
        expect(reopenedFactSet.confirmedData.userConfirmed, isTrue);

        // -- Chemin photo (EvidenceAsset) retrouvé à l'identique. ----------
        final List<domain.EvidenceAsset> reopenedAssets =
            await secondRepository.listEvidenceAssets(incident.id);
        expect(reopenedAssets, hasLength(1));
        expect(reopenedAssets.single.id, equals(evidenceId));
        expect(reopenedAssets.single.localFilePath, equals(evidencePath));
        expect(reopenedAssets.single.sha256, equals('a' * 64));
        expect(
          reopenedAssets.single.availabilityStatus,
          equals(domain.EvidenceAvailability.available),
        );

        // -- PendingAIJob (AiOperationQueue) retrouvé, toujours 'pending'. -
        final List<AiQueueItem> reopenedPending =
            await secondRepository.listPendingAiOperations();
        expect(reopenedPending, hasLength(1));
        expect(reopenedPending.single.id, equals(queuedJob.id));
        expect(reopenedPending.single.incidentId, equals(incident.id));
        expect(
          reopenedPending.single.operationKind,
          equals(AiOperationKind.extractFromPhoto),
        );
        expect(reopenedPending.single.status, equals(AiOperationStatus.pending));
        expect(reopenedPending.single.retryCount, equals(0));

        await secondOpen.close();
      },
    );

    test(
      'garde-fou anti-attribution de responsabilité (point 8) : une '
      'tentative de confirmation contenant une attribution de '
      'responsabilité est REJETÉE et ne persiste RIEN, même après '
      'réouverture - reprend explicitement le cas signalé par la recette '
      '(packagingCondition = "transporteur responsable")',
      () async {
        final AppDatabase firstOpen = _openFileBackedDatabase(dbFile);
        final LocalIncidentRepository firstRepository =
            LocalIncidentRepository(firstOpen);

        final domain.Incident incident = await firstRepository.createIncident(
          occurredAt: DateTime.utc(2026, 8, 19, 11),
        );
        final domain.Issue issue = await firstRepository.addIssue(
          incident.id,
          IssueType.packagingDamage,
        );

        final ConfirmedFactData tainted = ConfirmedFactData(
          issueType: IssueType.packagingDamage,
          packagingCondition: 'transporteur responsable',
        );

        // Passer directement le Future (pas une closure) à `throwsA` : pour
        // une fonction `async`, seule cette forme fait réellement attendre
        // et intercepter le rejet - `() => f()` où `f` est async ne lève
        // JAMAIS de façon synchrone, donc `expect(() => f(), throwsA(...))`
        // ne détecterait rien ici.
        await expectLater(
          firstRepository.confirmFacts(issueId: issue.id, data: tainted),
          throwsA(isA<LiabilityAttributionException>()),
        );

        // Rien n'a été écrit : aucune LocalConfirmedFactSets pour cette
        // anomalie, avant même de fermer/rouvrir la base.
        final domain.ConfirmedFactSet? noneSameSession =
            await firstRepository.latestConfirmedFactSet(issue.id);
        expect(noneSameSession, isNull);

        await firstOpen.close();

        final AppDatabase secondOpen = _openFileBackedDatabase(dbFile);
        final LocalIncidentRepository secondRepository =
            LocalIncidentRepository(secondOpen);

        // Toujours rien après réouverture - la tentative rejetée n'a laissé
        // aucune trace persistée sur disque.
        final domain.ConfirmedFactSet? noneAfterReopen =
            await secondRepository.latestConfirmedFactSet(issue.id);
        expect(noneAfterReopen, isNull);
        // L'incident, lui, existe bien (créé avant la tentative rejetée) et
        // n'a PAS avancé à factsConfirmed puisqu'aucun fait n'a été confirmé.
        final domain.Incident? reopenedIncident =
            await secondRepository.getIncident(incident.id);
        expect(reopenedIncident, isNotNull);
        expect(reopenedIncident!.status, equals(IncidentStatus.draftLocal));

        await secondOpen.close();
      },
    );
  });

  group('LocalIncidentRepository - CandidateFactSet (R2, persistance + garde-fou)', () {
    test(
      'sauvegarder une extraction candidate, fermer/rouvrir, retrouver la '
      'plus récente avec les mêmes valeurs',
      () async {
        final AppDatabase firstOpen = _openFileBackedDatabase(dbFile);
        final LocalIncidentRepository firstRepository = LocalIncidentRepository(firstOpen);

        final domain.Incident incident = await firstRepository.createIncident(
          occurredAt: DateTime.utc(2026, 8, 20, 9),
        );
        final domain.Issue issue = await firstRepository.addIssue(
          incident.id,
          IssueType.missingQty,
        );

        const CandidateFactData extracted = CandidateFactData(
          issueTypeCandidate: IssueType.missingQty,
          fields: <String, CandidateField>{
            'expected_quantity': CandidateField(
              value: 5,
              source: FactSource.voiceTranscript,
              confidence: ConfidenceLevel.high,
            ),
            'received_quantity': CandidateField(
              value: 4,
              source: FactSource.voiceTranscript,
              confidence: ConfidenceLevel.high,
            ),
          },
          requiresReview: false,
        );

        final domain.CandidateFactSet saved = await firstRepository.saveCandidateFactSet(
          issueId: issue.id,
          data: extracted,
          promptVersion: 'extraction_fr_v1',
          model: 'gpt-4o-mini',
        );

        await firstOpen.close();

        final AppDatabase secondOpen = _openFileBackedDatabase(dbFile);
        final LocalIncidentRepository secondRepository = LocalIncidentRepository(secondOpen);

        final domain.CandidateFactSet? reopened =
            await secondRepository.latestCandidateFactSet(issue.id);
        expect(reopened, isNotNull);
        expect(reopened!.id, equals(saved.id));
        expect(reopened.promptVersion, equals('extraction_fr_v1'));
        expect(reopened.model, equals('gpt-4o-mini'));
        expect(reopened.candidateData.issueTypeCandidate, equals(IssueType.missingQty));
        expect(reopened.candidateData.fields['expected_quantity']!.value, equals(5));
        expect(reopened.candidateData.fields['received_quantity']!.value, equals(4));

        await secondOpen.close();
      },
    );

    test(
      'un champ candidat contenant un contenu interdit (exemple cité par '
      "l'équipe : packaging_condition = \"transporteur responsable\") est "
      'retiré AVANT persistance, jamais écrit tel quel sur disque',
      () async {
        final AppDatabase firstOpen = _openFileBackedDatabase(dbFile);
        final LocalIncidentRepository firstRepository = LocalIncidentRepository(firstOpen);

        final domain.Incident incident = await firstRepository.createIncident(
          occurredAt: DateTime.utc(2026, 8, 20, 10),
        );
        final domain.Issue issue = await firstRepository.addIssue(
          incident.id,
          IssueType.packagingDamage,
        );

        const CandidateFactData tainted = CandidateFactData(
          issueTypeCandidate: IssueType.packagingDamage,
          fields: <String, CandidateField>{
            'packaging_condition': CandidateField(
              value: 'transporteur responsable',
              source: FactSource.voiceTranscript,
              confidence: ConfidenceLevel.high,
            ),
            'product_label': CandidateField(
              value: 'PAC-284',
              source: FactSource.ocr,
              confidence: ConfidenceLevel.high,
            ),
          },
          requiresReview: false,
        );

        final domain.CandidateFactSet saved = await firstRepository.saveCandidateFactSet(
          issueId: issue.id,
          data: tainted,
        );

        // Filtré dès la valeur de retour, avant toute question de disque.
        expect(saved.candidateData.fields.containsKey('packaging_condition'), isFalse);
        expect(saved.candidateData.fields.containsKey('product_label'), isTrue);
        expect(saved.candidateData.requiresReview, isTrue);

        await firstOpen.close();

        final AppDatabase secondOpen = _openFileBackedDatabase(dbFile);
        final LocalIncidentRepository secondRepository = LocalIncidentRepository(secondOpen);

        // Preuve par disque : même après fermeture/réouverture, le champ
        // interdit n'a jamais existé dans rawStructuredJson.
        final domain.CandidateFactSet? reopened =
            await secondRepository.latestCandidateFactSet(issue.id);
        expect(reopened, isNotNull);
        expect(reopened!.candidateData.fields.containsKey('packaging_condition'), isFalse);
        expect(reopened.candidateData.requiresReview, isTrue);

        await secondOpen.close();
      },
    );

    test('sans extraction candidate, latestCandidateFactSet retourne null', () async {
      final AppDatabase open = _openFileBackedDatabase(dbFile);
      final LocalIncidentRepository repository = LocalIncidentRepository(open);
      final domain.Incident incident = await repository.createIncident(
        occurredAt: DateTime.utc(2026, 8, 20, 11),
      );
      final domain.Issue issue = await repository.addIssue(incident.id, IssueType.other);

      final domain.CandidateFactSet? none = await repository.latestCandidateFactSet(issue.id);
      expect(none, isNull);

      await open.close();
    });
  });
}
