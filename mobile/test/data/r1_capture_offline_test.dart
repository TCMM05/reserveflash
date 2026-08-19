// R1 "Capture Offline" - tests obligatoires listés par la demande
// corrective (R1-T01 à R1-T10). Chaque groupe ci-dessous porte l'identifiant
// exact du test qu'il vérifie.
//
// R1-T06 (refus de permission caméra/micro) et R1-T09 (mode avion pendant
// tout le parcours) NE SONT PAS testables ici : ils nécessitent un vrai
// canal de plateforme (permission_handler, camera, record) qu'un test
// `flutter test` en Dart pur n'exécute pas (voir aussi l'en-tête de
// `local_incident_repository_test.dart` pour le même constat sur
// `NativeDatabase`, qui LUI reste testable car il n'a pas besoin d'un
// plugin natif). Ces deux critères doivent être vérifiés manuellement sur
// un vrai appareil (voir GATE_R1_STATUS.md) : activer le mode avion réel,
// et refuser explicitement la permission caméra à l'invite système.
//
// R1-T10 (aucun appel réseau déclenché par la capture locale) est garanti
// PAR CONSTRUCTION : ni `LocalIncidentRepository`, ni `EvidenceStorageService`
// n'importent `package:dio` ni aucun client HTTP (voir les imports de ces
// deux fichiers) - il n'existe tout simplement aucun objet capable de faire
// un appel réseau dans le chemin de code exercé par les tests ci-dessous.
// Vérifié aussi manuellement en mode avion (voir GATE_R1_STATUS.md).
//
// Comme pour `local_incident_repository_test.dart` : chaque test ouvre une
// VRAIE base SQLite sur fichier temporaire (jamais `NativeDatabase.memory()`)
// et un VRAI répertoire temporaire pour les fichiers de preuve (jamais de
// mock de contenu binaire) - la preuve demandée est une preuve par
// exécution réelle du disque, pas une simulation en mémoire.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reserveflash/data/local/app_database.dart';
import 'package:reserveflash/data/local/evidence_storage.dart';
import 'package:reserveflash/data/local/local_incident_repository.dart';
import 'package:reserveflash/domain/entities/evidence_asset.dart' as domain;
import 'package:reserveflash/domain/entities/incident.dart' as domain;
import 'package:reserveflash/domain/entities/issue.dart' as domain;
import 'package:reserveflash/domain/value_objects/issue_type.dart';

AppDatabase _openFileBackedDatabase(File dbFile) {
  return AppDatabase(NativeDatabase(dbFile, logStatements: false));
}

LocalIncidentRepository _repositoryFor(AppDatabase db, Directory evidenceDocsDir) {
  return LocalIncidentRepository(
    db,
    evidenceStorage: EvidenceStorageService(
      documentsDirectoryProvider: () async => evidenceDocsDir,
    ),
  );
}

Future<File> _writeFakeCapturedFile(Directory dir, String name, List<int> bytes) async {
  final File file = File('${dir.path}/$name');
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

Future<void> _cleanupTempDir(Directory dir) async {
  if (!await dir.exists()) {
    return;
  }
  // R0.2 (hotfix découvert par exécution réelle sur Windows, voir
  // local_incident_repository_test.dart) : même tolérance de nettoyage -
  // un verrou OS non relâché de façon synchrone ne doit jamais faire
  // échouer un test dont toutes les assertions métier ont déjà réussi.
  const int maxAttempts = 5;
  for (int attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      await dir.delete(recursive: true);
      return;
    } on FileSystemException {
      if (attempt == maxAttempts) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }
}

void main() {
  late Directory tempDir;
  late Directory sourceDir; // simule le cache temporaire d'un plugin camera/record.
  late Directory evidenceDocsDir; // simule l'espace privé "documents" de l'app.
  late File dbFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('reserveflash_r1_test_');
    sourceDir = Directory('${tempDir.path}/source')..createSync();
    evidenceDocsDir = Directory('${tempDir.path}/app_documents')..createSync();
    dbFile = File('${tempDir.path}/reserveflash_r1_test.sqlite');
  });

  tearDown(() async {
    await _cleanupTempDir(tempDir);
  });

  group('R1-T01 - création réelle d\'un incident offline', () {
    test('les champs saisis (y compris référence BL) sont persistés sans appel réseau', () async {
      final AppDatabase db = _openFileBackedDatabase(dbFile);
      final LocalIncidentRepository repository = _repositoryFor(db, evidenceDocsDir);

      final domain.Incident created = await repository.createIncident(
        occurredAt: DateTime.utc(2026, 8, 19, 8, 0),
        supplierName: 'Fournisseur R1',
        carrierName: 'Transporteur R1',
        deliveryRef: 'BL-R1-000001',
        notes: 'Palette abîmée.',
      );

      expect(created.id, isNotEmpty);
      expect(created.deliveryRef, equals('BL-R1-000001'));
      final domain.Incident? readBack = await repository.getIncident(created.id);
      expect(readBack, isNotNull);
      expect(readBack!.deliveryRef, equals('BL-R1-000001'));

      await db.close();
    });
  });

  group('R1-T02 - fermeture/réouverture -> incident retrouvé', () {
    test('un incident créé avec tous les champs R1 survit à une réouverture complète', () async {
      final AppDatabase firstOpen = _openFileBackedDatabase(dbFile);
      final LocalIncidentRepository firstRepository = _repositoryFor(firstOpen, evidenceDocsDir);

      final domain.Incident created = await firstRepository.createIncident(
        occurredAt: DateTime.utc(2026, 8, 19, 9, 15),
        deliveryRef: 'BL-R1-000002',
        notes: 'Carton percé, produit visible.',
      );
      await firstOpen.close();

      final AppDatabase secondOpen = _openFileBackedDatabase(dbFile);
      final LocalIncidentRepository secondRepository = _repositoryFor(secondOpen, evidenceDocsDir);
      final domain.Incident? reopened = await secondRepository.getIncident(created.id);

      expect(reopened, isNotNull);
      expect(reopened!.deliveryRef, equals('BL-R1-000002'));
      expect(reopened.notes, equals('Carton percé, produit visible.'));

      await secondOpen.close();
    });
  });

  group('R1-T03 - preuve photo enregistrée + SHA-256 conservé', () {
    test('le SHA-256 calculé à la capture est identique après persistance et réouverture', () async {
      final AppDatabase firstOpen = _openFileBackedDatabase(dbFile);
      final LocalIncidentRepository firstRepository = _repositoryFor(firstOpen, evidenceDocsDir);
      final EvidenceStorageService storage = EvidenceStorageService(
        documentsDirectoryProvider: () async => evidenceDocsDir,
      );

      final domain.Incident incident = await firstRepository.createIncident(
        occurredAt: DateTime.utc(2026, 8, 19, 10),
      );
      final List<int> photoBytes = utf8.encode('fausse-photo-bl-octets-de-test-r1');
      final File source = await _writeFakeCapturedFile(sourceDir, 'bl_source.jpg', photoBytes);

      final domain.EvidenceAsset asset = await storage.captureFromFile(
        incidentId: incident.id,
        sourcePath: source.path,
        documentType: domain.EvidenceDocumentType.deliveryNote,
        mimeType: 'image/jpeg',
      );
      final String expectedSha256 = sha256.convert(photoBytes).toString();
      expect(asset.sha256, equals(expectedSha256));
      expect(asset.bytes, equals(photoBytes.length));
      expect(await File(asset.localFilePath).exists(), isTrue);

      await firstRepository.registerEvidenceAsset(asset);
      await firstOpen.close();

      final AppDatabase secondOpen = _openFileBackedDatabase(dbFile);
      final LocalIncidentRepository secondRepository = _repositoryFor(secondOpen, evidenceDocsDir);
      final List<domain.EvidenceAsset> reopenedAssets =
          await secondRepository.listEvidenceAssets(incident.id);

      expect(reopenedAssets, hasLength(1));
      expect(reopenedAssets.single.sha256, equals(expectedSha256));
      expect(reopenedAssets.single.documentType, equals(domain.EvidenceDocumentType.deliveryNote));

      await secondOpen.close();
    });
  });

  group('R1-T04 - plusieurs photos dans le même incident', () {
    test('3 photos + 1 supplémentaire sont toutes conservées, avec des id/chemins distincts', () async {
      final AppDatabase db = _openFileBackedDatabase(dbFile);
      final LocalIncidentRepository repository = _repositoryFor(db, evidenceDocsDir);
      final EvidenceStorageService storage = EvidenceStorageService(
        documentsDirectoryProvider: () async => evidenceDocsDir,
      );

      final domain.Incident incident = await repository.createIncident(
        occurredAt: DateTime.utc(2026, 8, 19, 11),
      );

      final List<String> labels = <String>[
        'vue_generale.jpg',
        'etiquette.jpg',
        'dommage_rapproche.jpg',
        'supplementaire.jpg',
      ];
      final List<domain.EvidenceAsset> captured = <domain.EvidenceAsset>[];
      for (final String label in labels) {
        final File source =
            await _writeFakeCapturedFile(sourceDir, label, utf8.encode('octets-$label'));
        final domain.EvidenceAsset asset = await storage.captureFromFile(
          incidentId: incident.id,
          sourcePath: source.path,
          documentType: domain.EvidenceDocumentType.photo,
          mimeType: 'image/jpeg',
        );
        await repository.registerEvidenceAsset(asset);
        captured.add(asset);
      }

      final List<domain.EvidenceAsset> listed = await repository.listEvidenceAssets(incident.id);
      expect(listed, hasLength(4));
      expect(listed.map((domain.EvidenceAsset a) => a.id).toSet(), hasLength(4));
      expect(listed.map((domain.EvidenceAsset a) => a.localFilePath).toSet(), hasLength(4));
      expect(
        listed.every((domain.EvidenceAsset a) => a.documentType == domain.EvidenceDocumentType.photo),
        isTrue,
      );

      await db.close();
    });
  });

  group('R1-T05 - kill/restart -> données intactes', () {
    test(
      'incident + issue + 2 preuves + note vocale survivent tous ensemble à une '
      'fermeture/réouverture (équivalent réel d\'un kill du process)',
      () async {
        final AppDatabase firstOpen = _openFileBackedDatabase(dbFile);
        final LocalIncidentRepository firstRepository = _repositoryFor(firstOpen, evidenceDocsDir);
        final EvidenceStorageService storage = EvidenceStorageService(
          documentsDirectoryProvider: () async => evidenceDocsDir,
        );

        final domain.Incident incident = await firstRepository.createIncident(
          occurredAt: DateTime.utc(2026, 8, 19, 12),
          supplierName: 'Fournisseur Kill-Test',
        );
        final domain.Issue issue =
            await firstRepository.addIssue(incident.id, IssueType.productDamage);

        final File photoSource =
            await _writeFakeCapturedFile(sourceDir, 'photo_kill.jpg', utf8.encode('photo-kill'));
        final domain.EvidenceAsset photoAsset = await storage.captureFromFile(
          incidentId: incident.id,
          sourcePath: photoSource.path,
          documentType: domain.EvidenceDocumentType.photo,
          mimeType: 'image/jpeg',
          issueId: issue.id,
        );
        await firstRepository.registerEvidenceAsset(photoAsset);

        final File audioSource =
            await _writeFakeCapturedFile(sourceDir, 'note_kill.m4a', utf8.encode('audio-kill'));
        final domain.EvidenceAsset audioAsset = await storage.captureFromFile(
          incidentId: incident.id,
          sourcePath: audioSource.path,
          documentType: domain.EvidenceDocumentType.audio,
          mimeType: 'audio/m4a',
          extension: 'm4a',
        );
        await firstRepository.registerEvidenceAsset(audioAsset);

        // "Kill" : fermeture brutale de la connexion, aucun état Dart en
        // mémoire ne survit à cet appel (même invariant que R0/R1-T02).
        await firstOpen.close();

        final AppDatabase secondOpen = _openFileBackedDatabase(dbFile);
        final LocalIncidentRepository secondRepository = _repositoryFor(secondOpen, evidenceDocsDir);

        final domain.Incident? reopenedIncident = await secondRepository.getIncident(incident.id);
        expect(reopenedIncident, isNotNull);
        expect(reopenedIncident!.supplierName, equals('Fournisseur Kill-Test'));

        final List<domain.Issue> reopenedIssues = await secondRepository.listIssues(incident.id);
        expect(reopenedIssues, hasLength(1));
        expect(reopenedIssues.single.issueType, equals(IssueType.productDamage));

        final List<domain.EvidenceAsset> reopenedAssets =
            await secondRepository.listEvidenceAssets(incident.id);
        expect(reopenedAssets, hasLength(2));
        expect(
          reopenedAssets.map((domain.EvidenceAsset a) => a.documentType).toSet(),
          equals(<domain.EvidenceDocumentType>{
            domain.EvidenceDocumentType.photo,
            domain.EvidenceDocumentType.audio,
          }),
        );
        // Les fichiers binaires eux-mêmes existent toujours réellement sur
        // disque (pas seulement leurs métadonnées) - c'est la preuve
        // demandée par le point 9 : "une photo validée ne doit jamais
        // disparaître".
        for (final domain.EvidenceAsset asset in reopenedAssets) {
          expect(await File(asset.localFilePath).exists(), isTrue);
        }

        await secondOpen.close();
      },
    );
  });

  group('R1-T07 - fichier local manquant/corrompu -> UI contrôlée, aucun crash', () {
    test('un fichier supprimé hors app est détecté "missing" sans exception', () async {
      final AppDatabase db = _openFileBackedDatabase(dbFile);
      final LocalIncidentRepository repository = _repositoryFor(db, evidenceDocsDir);
      final EvidenceStorageService storage = EvidenceStorageService(
        documentsDirectoryProvider: () async => evidenceDocsDir,
      );

      final domain.Incident incident = await repository.createIncident(
        occurredAt: DateTime.utc(2026, 8, 19, 13),
      );
      final File source =
          await _writeFakeCapturedFile(sourceDir, 'a_supprimer.jpg', utf8.encode('sera-supprime'));
      final domain.EvidenceAsset asset = await storage.captureFromFile(
        incidentId: incident.id,
        sourcePath: source.path,
        documentType: domain.EvidenceDocumentType.photo,
        mimeType: 'image/jpeg',
      );
      await repository.registerEvidenceAsset(asset);

      // Simule une perte de fichier hors du contrôle de l'app (ex:
      // restauration de sauvegarde incomplète, point 9) : suppression
      // directe sur le disque, sans passer par `deleteEvidenceAsset`.
      await File(asset.localFilePath).delete();

      final List<domain.EvidenceAsset> verified =
          await repository.verifyEvidenceAssetsIntegrity(incident.id);
      expect(verified, hasLength(1));
      expect(verified.single.availabilityStatus, equals(domain.EvidenceAvailability.missing));

      // Persisté : une nouvelle lecture retrouve le même statut sans
      // re-déclencher d'exception.
      final List<domain.EvidenceAsset> listedAfter = await repository.listEvidenceAssets(incident.id);
      expect(listedAfter.single.availabilityStatus, equals(domain.EvidenceAvailability.missing));

      await db.close();
    });

    test('un fichier modifié hors app (hash différent) est détecté "corrupted" sans exception', () async {
      final AppDatabase db = _openFileBackedDatabase(dbFile);
      final LocalIncidentRepository repository = _repositoryFor(db, evidenceDocsDir);
      final EvidenceStorageService storage = EvidenceStorageService(
        documentsDirectoryProvider: () async => evidenceDocsDir,
      );

      final domain.Incident incident = await repository.createIncident(
        occurredAt: DateTime.utc(2026, 8, 19, 14),
      );
      final File source =
          await _writeFakeCapturedFile(sourceDir, 'a_corrompre.jpg', utf8.encode('contenu-original'));
      final domain.EvidenceAsset asset = await storage.captureFromFile(
        incidentId: incident.id,
        sourcePath: source.path,
        documentType: domain.EvidenceDocumentType.photo,
        mimeType: 'image/jpeg',
      );
      await repository.registerEvidenceAsset(asset);

      // Corruption simulée : octets remplacés directement sur le disque.
      await File(asset.localFilePath).writeAsBytes(utf8.encode('contenu-corrompu-different'));

      final List<domain.EvidenceAsset> verified =
          await repository.verifyEvidenceAssetsIntegrity(incident.id);
      expect(verified, hasLength(1));
      expect(verified.single.availabilityStatus, equals(domain.EvidenceAvailability.corrupted));

      await db.close();
    });
  });

  group('R1-T08 - suppression avec confirmation (niveau persistance)', () {
    // La boîte de dialogue de confirmation elle-même est de la
    // responsabilité de l'UI (voir lib/core/widgets/rf_confirm_dialog.dart,
    // utilisé par tous les écrans de suppression) - ce groupe vérifie que
    // LA SUPPRESSION EFFECTIVE, une fois confirmée, retire réellement et
    // durablement les données visées, sans effet de bord sur le reste.

    test('deleteEvidenceAsset retire une preuve précise, les autres restent intactes', () async {
      final AppDatabase db = _openFileBackedDatabase(dbFile);
      final LocalIncidentRepository repository = _repositoryFor(db, evidenceDocsDir);
      final EvidenceStorageService storage = EvidenceStorageService(
        documentsDirectoryProvider: () async => evidenceDocsDir,
      );

      final domain.Incident incident = await repository.createIncident(
        occurredAt: DateTime.utc(2026, 8, 19, 15),
      );
      final File source1 = await _writeFakeCapturedFile(sourceDir, 'p1.jpg', utf8.encode('p1'));
      final File source2 = await _writeFakeCapturedFile(sourceDir, 'p2.jpg', utf8.encode('p2'));
      final domain.EvidenceAsset asset1 = await storage.captureFromFile(
        incidentId: incident.id,
        sourcePath: source1.path,
        documentType: domain.EvidenceDocumentType.photo,
        mimeType: 'image/jpeg',
      );
      final domain.EvidenceAsset asset2 = await storage.captureFromFile(
        incidentId: incident.id,
        sourcePath: source2.path,
        documentType: domain.EvidenceDocumentType.photo,
        mimeType: 'image/jpeg',
      );
      await repository.registerEvidenceAsset(asset1);
      await repository.registerEvidenceAsset(asset2);

      await storage.deleteFile(asset1.localFilePath);
      await repository.deleteEvidenceAsset(asset1.id);

      final List<domain.EvidenceAsset> remaining = await repository.listEvidenceAssets(incident.id);
      expect(remaining, hasLength(1));
      expect(remaining.single.id, equals(asset2.id));
      expect(await File(asset1.localFilePath).exists(), isFalse);
      expect(await File(asset2.localFilePath).exists(), isTrue);

      // Idempotence : re-supprimer un id déjà supprimé ne lève pas.
      await expectLater(repository.deleteEvidenceAsset(asset1.id), completes);

      await db.close();
    });

    test(
      'deleteIncident supprime en cascade issue(s) + preuve(s) + l\'incident lui-même, '
      'de façon transactionnelle',
      () async {
        final AppDatabase db = _openFileBackedDatabase(dbFile);
        final LocalIncidentRepository repository = _repositoryFor(db, evidenceDocsDir);
        final EvidenceStorageService storage = EvidenceStorageService(
          documentsDirectoryProvider: () async => evidenceDocsDir,
        );

        final domain.Incident incident = await repository.createIncident(
          occurredAt: DateTime.utc(2026, 8, 19, 16),
        );
        final domain.Issue issue =
            await repository.addIssue(incident.id, IssueType.missingQty);
        final File source =
            await _writeFakeCapturedFile(sourceDir, 'a_effacer.jpg', utf8.encode('a-effacer'));
        final domain.EvidenceAsset asset = await storage.captureFromFile(
          incidentId: incident.id,
          sourcePath: source.path,
          documentType: domain.EvidenceDocumentType.photo,
          mimeType: 'image/jpeg',
          issueId: issue.id,
        );
        await repository.registerEvidenceAsset(asset);

        // Reproduit l'orchestration attendue de l'écran appelant (voir
        // docstring de `IncidentRepository.deleteIncident`) : supprimer les
        // fichiers AVANT la cascade de métadonnées.
        final List<domain.EvidenceAsset> assetsBeforeDelete =
            await repository.listEvidenceAssets(incident.id);
        for (final domain.EvidenceAsset a in assetsBeforeDelete) {
          await storage.deleteFile(a.localFilePath);
        }
        await repository.deleteIncident(incident.id);

        expect(await repository.getIncident(incident.id), isNull);
        expect(await repository.listIssues(incident.id), isEmpty);
        expect(await repository.listEvidenceAssets(incident.id), isEmpty);
        expect(await File(asset.localFilePath).exists(), isFalse);

        await db.close();
      },
    );
  });
}
