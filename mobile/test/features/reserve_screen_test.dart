// Câblage réel R2 de `reserve_screen.dart` (S12) : avant ce fichier, l'écran
// affichait un texte d'exemple codé en dur (`_sampleReserveText`), jamais
// branché sur `IncidentRepository.latestReserveText` - voir
// docs/GATE_R2_STATUS.md. Ce test vérifie que l'écran affiche la VRAIE
// réserve persistée (composée par `lib/domain/reserve_composer.dart` via
// `composeAndSaveReserve`, jamais un texte inventé par ce widget), et
// qu'il indique clairement l'absence de réserve plutôt que d'afficher un
// texte factice quand aucune n'a encore été composée.
//
// Même politique que `facts_review_screen_test.dart`/
// `local_incident_repository_test.dart` : uniquement `package:drift/native.dart`
// (jamais `package:drift/drift.dart` en plus, collision `isNotNull`/`isNull`
// avec `package:flutter_test`) ; aucun `tester.runAsync()` nécessaire
// (Drift/FFI uniquement, aucune E/S fichier). Les boutons "Modifier les
// faits"/"Continuer" naviguent via go_router (`context.pop()`/
// `context.pushFinalDocument()`) - non tapés ici (même limite documentée que
// `facts_review_screen_test.dart` pour "Générer la réserve") : ce fichier
// vérifie l'AFFICHAGE réel, pas la navigation.

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:reserveflash/core/providers/app_providers.dart';
import 'package:reserveflash/data/local/app_database.dart';
import 'package:reserveflash/data/local/local_incident_repository.dart';
import 'package:reserveflash/domain/entities/incident.dart' as domain;
import 'package:reserveflash/domain/entities/issue.dart' as domain;
import 'package:reserveflash/domain/entities/reserve_text.dart' as domain;
import 'package:reserveflash/domain/fact_set/confirmed_fact_data.dart';
import 'package:reserveflash/domain/value_objects/issue_type.dart';
import 'package:reserveflash/features/reserve/presentation/reserve_screen.dart';

AppDatabase _openFileBackedDatabase(File dbFile) {
  return AppDatabase(NativeDatabase(dbFile, logStatements: false));
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
  late File dbFile;
  late AppDatabase db;
  late LocalIncidentRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('reserveflash_reserve_screen_test_');
    dbFile = File('${tempDir.path}/reserveflash_reserve_screen_test.sqlite');
    db = _openFileBackedDatabase(dbFile);
    repository = LocalIncidentRepository(db);
  });

  tearDown(() async {
    await db.close();
    await _cleanupTempDir(tempDir);
  });

  Widget wrap(Widget child) {
    return ProviderScope(
      overrides: <Override>[
        incidentRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(home: child),
    );
  }

  group('ReserveScreen - lecture réelle de la réserve composée', () {
    testWidgets(
      "aucune réserve encore composée -> message clair, jamais de texte factice",
      (WidgetTester tester) async {
        final domain.Incident incident = await repository.createIncident(
          occurredAt: DateTime.utc(2026, 8, 20, 12),
        );

        await tester.pumpWidget(wrap(ReserveScreen(incidentId: incident.id)));
        await tester.pumpAndSettle();

        expect(
          find.textContaining("Aucune réserve n'a encore été générée"),
          findsOneWidget,
        );
        expect(find.byType(SelectableText), findsNothing);
      },
    );

    testWidgets(
      'une réserve déjà composée (composeAndSaveReserve) est affichée TELLE '
      'QUELLE, pas un texte codé en dur',
      (WidgetTester tester) async {
        final domain.Incident incident = await repository.createIncident(
          occurredAt: DateTime.utc(2026, 8, 20, 13),
        );
        final domain.Issue issue =
            await repository.addIssue(incident.id, IssueType.packagingDamage);
        await repository.confirmFacts(
          issueId: issue.id,
          data: ConfirmedFactData(
            issueType: IssueType.packagingDamage,
            productLabel: 'Carton n°3',
            packagingCondition: 'un coin écrasé',
          ),
        );
        final domain.ReserveText composed = await repository.composeAndSaveReserve(incident.id);

        await tester.pumpWidget(wrap(ReserveScreen(incidentId: incident.id)));
        await tester.pumpAndSettle();

        // Le texte affiché est EXACTEMENT celui renvoyé par
        // `composeAndSaveReserve` (composé par `reserve_composer.dart`),
        // jamais `ReserveScreen._sampleReserveText` (supprimé par ce
        // câblage).
        expect(find.text(composed.text), findsOneWidget);
        expect(find.byType(SelectableText), findsOneWidget);
        expect(find.textContaining("Aucune réserve"), findsNothing);
      },
    );
  });
}
