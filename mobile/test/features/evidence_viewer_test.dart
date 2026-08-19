// Correction ciblée post-recette terrain R1 (avant freeze final) : "après
// capture d'une photo ou d'une note vocale, l'utilisateur ne peut pas
// réellement contrôler le média enregistré." Ce fichier couvre, dans la
// même limite déjà documentée par l'en-tête de
// `test/data/r1_capture_offline_test.dart`, les tests obligatoires listés
// par cette correction :
//
//  - "photo locale -> ouverture plein écran" : COUVERT ci-dessous (tap
//    d'une vignette réelle, vraie image PNG 1x1 décodable sur disque).
//  - "photo toujours consultable après fermeture/réouverture" : COUVERT
//    ci-dessous (fichier réel relu après réouverture d'une seconde base).
//  - "fichier photo manquant -> aucun crash" : COUVERT ci-dessous.
//  - "fichier photo corrompu -> aucun crash" : COUVERT ci-dessous.
//  - "audio local -> lecture/pause" / "audio toujours lisible après
//    fermeture/réouverture" / "fichier audio manquant/corrompu -> aucun
//    crash" : NON automatisés ici, volontairement. `EvidenceAudioPlayerScreen`
//    construit un `just_audio.AudioPlayer` dès `initState` (avant même de
//    savoir si le fichier est disponible) - contrairement à
//    `EvidencePhotoViewerScreen` (qui n'appelle `dart:io`/`dart:ui`, jamais
//    un plugin natif, pour son propre état "indisponible"), on ne peut pas
//    garantir que la simple construction/destruction d'un `AudioPlayer`
//    reste sans effet de bord sur un canal de plateforme absent en
//    `flutter test` - même limite déjà actée pour `record`/`camera` (voir
//    l'en-tête de `r1_capture_offline_test.dart`). L'écran complet
//    (lecture/pause, durée/progression, arrêt/reprise, fichier manquant/
//    corrompu) reste donc "manuel requis" sur un vrai appareil (voir
//    GATE_R1_STATUS.md) - seule sa logique pure (`formatMmSs`, testée
//    ci-dessous) est automatisée.
//  - "mode avion" : garanti par construction (aucun des deux nouveaux
//    écrans n'importe `package:dio` ni aucun client HTTP - mêmes grep que
//    R1-T10 initial), vérifié aussi manuellement (GATE_R1_STATUS.md).

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reserveflash/core/providers/app_providers.dart';
import 'package:reserveflash/core/utils/duration_format.dart';
import 'package:reserveflash/data/local/app_database.dart';
import 'package:reserveflash/data/local/evidence_storage.dart';
import 'package:reserveflash/data/local/local_incident_repository.dart';
import 'package:reserveflash/domain/entities/evidence_asset.dart' as domain;
import 'package:reserveflash/domain/entities/incident.dart' as domain;
import 'package:reserveflash/domain/repositories/incident_repository.dart';
import 'package:reserveflash/features/common/presentation/evidence_photo_viewer_screen.dart';
import 'package:reserveflash/features/common/presentation/evidence_thumbnail_tile.dart';

// PNG 1x1 blanc valide (généré et vérifié via Pillow), décodable par le
// codec image intégré à `dart:ui` - contrairement aux canaux de
// plateforme, ce décodage fonctionne bien en environnement `flutter test`
// headless.
const List<int> _validPngBytes = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
  0x0C, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xFF, 0xFF, 0x3F,
  0x00, 0x05, 0xFE, 0x02, 0xFE, 0x0D, 0xEF, 0x46, 0xB8, 0x00, 0x00, 0x00,
  0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

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

// Bug réel révélé par `flutter test` sur poste (pas seulement un test lent) :
// `EvidenceThumbnailTile` et `EvidencePhotoViewerScreen` font toutes deux
// décoder une vraie image sur disque via `Image.file` pour un asset
// `available` - ce n'est PAS un canal de plateforme (contrairement à
// caméra/audio), mais une vraie opération asynchrone `dart:io`. Le binding
// de `flutter test` pompe les widgets dans une zone à horloge simulée : un
// simple `pumpAndSettle()` ne suffit pas à laisser cette lecture réelle se
// terminer et le test reste bloqué indéfiniment ("did not complete"),
// comme documenté officiellement par `WidgetTester.runAsync`
// (https://api.flutter.dev/flutter/flutter_test/WidgetTester/runAsync.html)
// et de nombreux rapports similaires (ex. flutter/flutter#97737). Solution
// officielle : laisser tourner le vrai event loop brièvement via
// `runAsync()` avant de reprendre le pump normal.
// Diagnostic temporaire v2 (à retirer une fois la cause réelle du blocage
// identifiée) : v1 (print() + Future.timeout()) n'a RIEN affiché du tout -
// aucune ligne DIAGNOSTIC, et le test a quand même couru jusqu'au timeout
// par défaut du binding de test (~5 minutes, "did not complete"), preuve
// que ni le print() (mis en mémoire tampon par le runner de test tant que
// le test ne "termine" pas normalement) ni le Timer de Future.timeout() ne
// se déclenchent dans ce contexte bloqué. On abandonne ces deux mécanismes
// et on écrit à la place, de façon 100% synchrone et immédiatement forcée
// sur disque (`flush: true`), une trace dans un vrai fichier - un simple
// appel bloquant `writeAsStringSync`, indépendant de tout Timer/Future/
// zone de test, qui persiste même si le processus est ensuite tué. Inutile
// d'attendre le timeout du framework : dès que le fichier arrête de
// grossir, l'étape en cours est celle qui bloque.
final File _diagLogFile = File(
  '${Directory.systemTemp.path}${Platform.pathSeparator}reserveflash_diag.log',
);

void logStep(String label) {
  _diagLogFile.writeAsStringSync(
    '${DateTime.now().toIso8601String()} $label\n',
    mode: FileMode.append,
    flush: true,
  );
}

Future<T> traced<T>(Future<T> future, String label) async {
  logStep('DEBUT $label');
  final T result = await future;
  logStep('FIN   $label');
  return result;
}

Future<void> settleWithRealIo(WidgetTester tester) async {
  await traced(
    tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }),
    'settleWithRealIo -> runAsync(delay 50ms)',
  );
  await traced(tester.pumpAndSettle(), 'settleWithRealIo -> pumpAndSettle (après runAsync)');
}

Future<void> _cleanupTempDir(Directory dir) async {
  if (!await dir.exists()) {
    return;
  }
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
  late Directory sourceDir;
  late Directory evidenceDocsDir;
  late File dbFile;
  late AppDatabase db;
  late LocalIncidentRepository repository;
  late EvidenceStorageService storage;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('reserveflash_evidence_viewer_test_');
    sourceDir = Directory('${tempDir.path}/source')..createSync();
    evidenceDocsDir = Directory('${tempDir.path}/app_documents')..createSync();
    dbFile = File('${tempDir.path}/reserveflash_evidence_viewer_test.sqlite');
    db = _openFileBackedDatabase(dbFile);
    repository = _repositoryFor(db, evidenceDocsDir);
    storage = EvidenceStorageService(documentsDirectoryProvider: () async => evidenceDocsDir);
  });

  tearDown(() async {
    await db.close();
    await _cleanupTempDir(tempDir);
  });

  Widget wrap(Widget child) {
    return ProviderScope(
      overrides: <Override>[
        incidentRepositoryProvider.overrideWithValue(repository),
        evidenceStorageServiceProvider.overrideWithValue(storage),
      ],
      child: MaterialApp(home: child),
    );
  }

  // Les écrans testés ci-dessous appellent `Navigator.pop()` après une
  // suppression réussie (même comportement qu'en usage réel, où ils sont
  // TOUJOURS poussés par-dessus un autre écran, jamais utilisés comme
  // unique route racine) - ce wrapper reproduit fidèlement cette situation
  // (un écran de base + le vrai écran poussé par-dessus), pour que `pop()`
  // ait réellement une route sous lui vers laquelle revenir.
  Widget wrapPushed(Widget child) {
    return wrap(
      Builder(
        builder: (BuildContext context) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => child));
          });
          return const Scaffold(body: SizedBox.shrink());
        },
      ),
    );
  }

  group('formatMmSs (utilitaire partagé timer/lecture)', () {
    test('formate correctement des durées sous et au-dessus d\'une minute', () {
      expect(formatMmSs(Duration.zero), equals('00:00'));
      expect(formatMmSs(const Duration(seconds: 7)), equals('00:07'));
      expect(formatMmSs(const Duration(minutes: 1, seconds: 5)), equals('01:05'));
      expect(formatMmSs(const Duration(minutes: 12, seconds: 34)), equals('12:34'));
    });
  });

  group('Correction R1 - visionneuse photo : ouverture plein écran', () {
    testWidgets('un tap sur une vignette photo disponible ouvre la visionneuse plein écran',
        (WidgetTester tester) async {
      // Log réinitialisé au début de ce test précis (celui qui bloque de
      // façon reproductible) - chemin affiché explicitement pour pouvoir le
      // retrouver facilement sur le poste Windows.
      if (_diagLogFile.existsSync()) {
        _diagLogFile.deleteSync();
      }
      logStep('=== DEBUT DU TEST === (fichier log : ${_diagLogFile.path})');

      logStep('DEBUT repository.createIncident');
      final domain.Incident incident = await repository.createIncident(
        occurredAt: DateTime.utc(2026, 8, 19, 8),
      );
      logStep('FIN   repository.createIncident');

      logStep('DEBUT ecriture fichier photo source');
      final File source = File('${sourceDir.path}/photo.png')
        ..writeAsBytesSync(_validPngBytes, flush: true);
      logStep('FIN   ecriture fichier photo source');

      // Diagnostic v3 : v2 a localisé le blocage précisément DANS
      // `storage.captureFromFile` (dernier log : "DEBUT storage.
      // captureFromFile", jamais de "FIN") - AVANT tout pumpWidget, donc
      // rien à voir avec Image.file/pumpAndSettle/runAsync (hypothèses v1/
      // v2 réfutées). Comme cette même méthode est utilisée avec succès des
      // dizaines de fois dans test/data/r1_capture_offline_test.dart (déjà
      // vert), le problème n'est pas la méthode elle-même mais PEUT-ÊTRE une
      // étape précise de son corps dans ce contexte précis. On reproduit ici
      // son corps exact (voir lib/data/local/evidence_storage.dart) avec un
      // `logStep` avant/après chaque opération disque, pour isoler l'étape
      // fautive au lieu de traiter la méthode comme une boîte noire.
      logStep('DEBUT source.exists()');
      final bool sourceExists = await source.exists();
      logStep('FIN   source.exists() = $sourceExists');

      logStep('DEBUT source.readAsBytes()');
      final List<int> rawBytes = await source.readAsBytes();
      logStep('FIN   source.readAsBytes() (${rawBytes.length} octets)');

      logStep('DEBUT storage.evidenceDirectoryFor');
      final Directory evDir = await storage.evidenceDirectoryFor(incident.id);
      logStep('FIN   storage.evidenceDirectoryFor -> ${evDir.path}');

      const String diagId = 'diag-test-asset-1';
      final String finalPath = '${evDir.path}/$diagId.png';
      final File tempFile = File('$finalPath.tmp');

      logStep('DEBUT tempFile.writeAsBytes');
      await tempFile.writeAsBytes(rawBytes, flush: true);
      logStep('FIN   tempFile.writeAsBytes');

      logStep('DEBUT tempFile.rename');
      await tempFile.rename(finalPath);
      logStep('FIN   tempFile.rename');

      final domain.EvidenceAsset asset = domain.EvidenceAsset(
        id: diagId,
        incidentId: incident.id,
        documentType: domain.EvidenceDocumentType.photo,
        localFilePath: finalPath,
        sha256: 'diagnostic-sha-placeholder',
        mimeType: 'image/png',
        bytes: rawBytes.length,
        capturedAtDevice: DateTime.now().toUtc(),
      );
      logStep('FIN   construction EvidenceAsset manuelle');

      logStep('DEBUT repository.registerEvidenceAsset');
      await repository.registerEvidenceAsset(asset);
      logStep('FIN   repository.registerEvidenceAsset');

      bool opened = false;
      await traced(
        tester.pumpWidget(
          wrap(
            Builder(
              builder: (BuildContext context) => Scaffold(
                body: EvidenceThumbnailTile(
                  asset: asset,
                  onTap: () {
                    opened = true;
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => EvidencePhotoViewerScreen(
                          incidentId: incident.id,
                          asset: asset,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        'test1 -> pumpWidget (vignette)',
      );
      await traced(settleWithRealIo(tester), 'test1 -> settle #1 (après pumpWidget vignette)');

      await traced(tester.tap(find.byType(ListTile)), 'test1 -> tap(ListTile)');
      await traced(settleWithRealIo(tester), 'test1 -> settle #2 (après tap)');

      expect(opened, isTrue);
      expect(find.byType(EvidencePhotoViewerScreen), findsOneWidget);
      // Bouton retour clair (spec) + zoom/pan (InteractiveViewer).
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('reste consultable (fichier + métadonnées) après fermeture/réouverture',
        (WidgetTester tester) async {
      final domain.Incident incident = await repository.createIncident(
        occurredAt: DateTime.utc(2026, 8, 19, 9),
      );
      final File source = File('${sourceDir.path}/photo2.png')
        ..writeAsBytesSync(_validPngBytes, flush: true);
      final domain.EvidenceAsset asset = await storage.captureFromFile(
        incidentId: incident.id,
        sourcePath: source.path,
        documentType: domain.EvidenceDocumentType.photo,
        mimeType: 'image/png',
        extension: 'png',
      );
      await repository.registerEvidenceAsset(asset);

      // "Fermeture/réouverture" : nouvelle connexion DB sur le même fichier
      // (équivalent réel d'un kill/relance de l'app, même méthode que
      // R1-T02/T05).
      await db.close();
      final AppDatabase reopened = _openFileBackedDatabase(dbFile);
      final IncidentRepository reopenedRepository = _repositoryFor(reopened, evidenceDocsDir);
      final List<domain.EvidenceAsset> reopenedAssets =
          await reopenedRepository.listEvidenceAssets(incident.id);
      expect(reopenedAssets, hasLength(1));
      final domain.EvidenceAsset reopenedAsset = reopenedAssets.single;
      expect(await File(reopenedAsset.localFilePath).exists(), isTrue);

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            incidentRepositoryProvider.overrideWithValue(reopenedRepository),
            evidenceStorageServiceProvider.overrideWithValue(storage),
          ],
          child: MaterialApp(
            home: EvidencePhotoViewerScreen(incidentId: incident.id, asset: reopenedAsset),
          ),
        ),
      );
      await settleWithRealIo(tester);

      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.textContaining('introuvable'), findsNothing);
      expect(tester.takeException(), isNull);

      await reopened.close();
      db = _openFileBackedDatabase(dbFile); // pour que tearDown ferme une connexion valide.
    });

    testWidgets('fichier photo manquant -> message contrôlé, aucun crash', (WidgetTester tester) async {
      final domain.Incident incident = await repository.createIncident(
        occurredAt: DateTime.utc(2026, 8, 19, 10),
      );
      final File source = File('${sourceDir.path}/photo3.png')
        ..writeAsBytesSync(_validPngBytes, flush: true);
      final domain.EvidenceAsset asset = await storage.captureFromFile(
        incidentId: incident.id,
        sourcePath: source.path,
        documentType: domain.EvidenceDocumentType.photo,
        mimeType: 'image/png',
        extension: 'png',
      );
      await repository.registerEvidenceAsset(asset);
      // Perte de fichier hors du contrôle de l'app (même scénario que
      // R1-T07 initial).
      await File(asset.localFilePath).delete();
      final List<domain.EvidenceAsset> verified =
          await repository.verifyEvidenceAssetsIntegrity(incident.id);
      final domain.EvidenceAsset missingAsset = verified.single;
      expect(missingAsset.availabilityStatus, equals(domain.EvidenceAvailability.missing));

      await tester.pumpWidget(
        wrap(EvidencePhotoViewerScreen(incidentId: incident.id, asset: missingAsset)),
      );
      await settleWithRealIo(tester);

      expect(find.textContaining('introuvable'), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('fichier photo corrompu -> message contrôlé, aucun crash', (WidgetTester tester) async {
      final domain.Incident incident = await repository.createIncident(
        occurredAt: DateTime.utc(2026, 8, 19, 11),
      );
      final File source = File('${sourceDir.path}/photo4.png')
        ..writeAsBytesSync(_validPngBytes, flush: true);
      final domain.EvidenceAsset asset = await storage.captureFromFile(
        incidentId: incident.id,
        sourcePath: source.path,
        documentType: domain.EvidenceDocumentType.photo,
        mimeType: 'image/png',
        extension: 'png',
      );
      await repository.registerEvidenceAsset(asset);
      // Corruption simulée : octets remplacés directement sur le disque
      // (même scénario que R1-T07 initial) - ni une image PNG valide, ni
      // les octets d'origine.
      await File(asset.localFilePath).writeAsBytes(<int>[1, 2, 3, 4, 5]);
      final List<domain.EvidenceAsset> verified =
          await repository.verifyEvidenceAssetsIntegrity(incident.id);
      final domain.EvidenceAsset corruptedAsset = verified.single;
      expect(corruptedAsset.availabilityStatus, equals(domain.EvidenceAvailability.corrupted));

      await tester.pumpWidget(
        wrap(EvidencePhotoViewerScreen(incidentId: incident.id, asset: corruptedAsset)),
      );
      await settleWithRealIo(tester);

      expect(find.textContaining('corrompu'), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('le bouton supprimer déclenche la confirmation puis retire réellement la preuve',
        (WidgetTester tester) async {
      final domain.Incident incident = await repository.createIncident(
        occurredAt: DateTime.utc(2026, 8, 19, 12),
      );
      final File source = File('${sourceDir.path}/photo5.png')
        ..writeAsBytesSync(_validPngBytes, flush: true);
      final domain.EvidenceAsset asset = await storage.captureFromFile(
        incidentId: incident.id,
        sourcePath: source.path,
        documentType: domain.EvidenceDocumentType.photo,
        mimeType: 'image/png',
        extension: 'png',
      );
      await repository.registerEvidenceAsset(asset);

      await tester.pumpWidget(
        wrapPushed(EvidencePhotoViewerScreen(incidentId: incident.id, asset: asset)),
      );
      await settleWithRealIo(tester);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await settleWithRealIo(tester);
      expect(find.text('Supprimer cette photo ?'), findsOneWidget);

      await tester.tap(find.text('Supprimer'));
      await settleWithRealIo(tester);

      expect(await File(asset.localFilePath).exists(), isFalse);
      expect(await repository.listEvidenceAssets(incident.id), isEmpty);
      expect(tester.takeException(), isNull);
    });
  });
}
