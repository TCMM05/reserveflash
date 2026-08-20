// Câblage réel R2 de `facts_review_screen.dart` (S11) : avant ce fichier,
// l'écran affichait des champs codés en dur, jamais branché sur
// `IncidentRepository` (voir docs/GATE_R2_STATUS.md, "Reste à faire" - point
// désormais couvert). Ce test répond concrètement à la question laissée
// ouverte : "le principe R2 (l'IA propose, l'utilisateur confirme) est-il
// démontrable de bout en bout ?" - en vérifiant que l'écran lit une vraie
// extraction candidate depuis Drift, que les actions de l'utilisateur
// (confirmer / marquer inconnu) appellent réellement
// `IncidentRepository.confirmFacts`, et que le résultat est bien persisté
// (relu depuis le repository, pas seulement affiché à l'écran).
//
// Même politique que `test/data/local_incident_repository_test.dart` : ne
// PAS importer `package:drift/drift.dart` en plus de `package:drift/native.dart`
// (collision `isNotNull`/`isNull` avec `package:flutter_test`). Aucune des
// opérations exercées ici (Drift/sqlite3 FFI uniquement, aucun fichier
// preuve) ne touche `dart:io` de façon réellement asynchrone - contrairement
// à `test/features/evidence_viewer_test.dart`, `tester.runAsync()` n'est
// donc pas nécessaire (voir le diagnostic documenté dans ce dernier fichier :
// seul un vrai appel dart:io asynchrone bloque sous `testWidgets`, pas
// Drift/FFI).
//
// Non couvert ici, volontairement (limite documentée, même politique que
// `evidence_viewer_test.dart` pour l'audio) : le bouton "Générer la réserve"
// navigue via `context.pushReserve` (go_router) - ce fichier n'installe pas
// de vrai `GoRouter` (hors scope de ce câblage), donc ce bouton n'est pas
// tapé ici. `reserve_screen_test.dart` couvre séparément l'affichage réel de
// `ReserveScreen` (atteint directement, sans navigation).

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:reserveflash/core/providers/app_providers.dart';
import 'package:reserveflash/data/local/app_database.dart';
import 'package:reserveflash/data/local/local_incident_repository.dart';
import 'package:reserveflash/domain/entities/confirmed_fact_set.dart' as domain;
import 'package:reserveflash/domain/entities/incident.dart' as domain;
import 'package:reserveflash/domain/entities/issue.dart' as domain;
import 'package:reserveflash/domain/fact_set/candidate_fact_data.dart';
import 'package:reserveflash/domain/value_objects/confidence_level.dart';
import 'package:reserveflash/domain/value_objects/issue_type.dart';
import 'package:reserveflash/features/facts_review/presentation/facts_review_screen.dart';

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
    tempDir = await Directory.systemTemp.createTemp('reserveflash_facts_review_test_');
    dbFile = File('${tempDir.path}/reserveflash_facts_review_test.sqlite');
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

  group('FactsReviewScreen - lecture réelle du candidat IA', () {
    testWidgets(
      'affiche les champs candidats reçus, "Non détecté" pour les champs '
      'absents, et désactive la confirmation tant que tout n\'est pas résolu',
      (WidgetTester tester) async {
        final domain.Incident incident = await repository.createIncident(
          occurredAt: DateTime.utc(2026, 8, 20, 9),
        );
        final domain.Issue issue = await repository.addIssue(incident.id, IssueType.missingQty);
        const CandidateFactData extracted = CandidateFactData(
          issueTypeCandidate: IssueType.missingQty,
          fields: <String, CandidateField>{
            'product_label': CandidateField(
              value: 'Ballon eau chaude 200L',
              source: FactSource.voiceTranscript,
              confidence: ConfidenceLevel.high,
            ),
            'expected_quantity': CandidateField(
              value: 8,
              source: FactSource.voiceTranscript,
              confidence: ConfidenceLevel.high,
            ),
            'received_quantity': CandidateField(
              value: 6,
              source: FactSource.voiceTranscript,
              confidence: ConfidenceLevel.high,
            ),
          },
          requiresReview: true,
        );
        await repository.saveCandidateFactSet(
          issueId: issue.id,
          data: extracted,
          promptVersion: 'extraction_fr_v1',
          model: 'gpt-4o-mini',
        );

        await tester.pumpWidget(wrap(FactsReviewScreen(incidentId: incident.id)));
        await tester.pumpAndSettle();

        // Champs candidats affichés tels que renvoyés par l'IA (section 3.1
        // - "transparence IA").
        expect(find.text('Ballon eau chaude 200L'), findsOneWidget);
        expect(find.text('8'), findsOneWidget);
        expect(find.text('6'), findsOneWidget);
        // Les 5 champs V1 restants n'ont aucun candidat -> "Non détecté",
        // jamais une valeur inventée (GATE zéro invention).
        expect(find.text('Non détecté'), findsNWidgets(5));

        // GATE section 2.3 : bouton désactivé tant que tout n'est pas résolu.
        final Finder confirmIssueButton = find.widgetWithText(
          OutlinedButton,
          'Valider les faits de cette anomalie',
        );
        expect(confirmIssueButton, findsOneWidget);
        expect(tester.widget<OutlinedButton>(confirmIssueButton).onPressed, isNull);
      },
    );
  });

  group('FactsReviewScreen - bascule manuelle/UNKNOWN (retour équipe, point 7)', () {
    testWidgets(
      "sans aucune extraction IA (aucun CandidateFactSet), l'anomalie reste "
      'entièrement confirmable manuellement : marquer tous les champs comme '
      "inconnus persiste réellement un ConfirmedFactSet via confirmFacts",
      (WidgetTester tester) async {
        final domain.Incident incident = await repository.createIncident(
          occurredAt: DateTime.utc(2026, 8, 20, 10),
        );
        final domain.Issue issue = await repository.addIssue(incident.id, IssueType.wrongQty);
        // Volontairement AUCUN saveCandidateFactSet ici : c'est le scénario
        // "IA jamais exécutée / disjoncteur épuisé" - la seule vraie
        // "bascule manuelle" exigée par le retour d'équipe (exigence coût
        // IA, point 7), pas seulement un cas particulier après plusieurs
        // tentatives échouées.

        await tester.pumpWidget(wrap(FactsReviewScreen(incidentId: incident.id)));
        await tester.pumpAndSettle();

        expect(find.text('Non détecté'), findsNWidgets(8));

        final Finder unknownButtons = find.widgetWithText(TextButton, 'Je ne sais pas');
        expect(unknownButtons, findsNWidgets(8));
        for (int i = 0; i < 8; i++) {
          await tester.tap(unknownButtons.at(i));
          await tester.pump();
        }
        await tester.pumpAndSettle();

        final Finder confirmIssueButton = find.widgetWithText(
          OutlinedButton,
          'Valider les faits de cette anomalie',
        );
        expect(tester.widget<OutlinedButton>(confirmIssueButton).onPressed, isNotNull);

        await tester.tap(confirmIssueButton);
        await tester.pumpAndSettle();

        // Persisté réellement (pas seulement affiché) : relecture directe
        // du repository, indépendamment de l'état de l'écran.
        final domain.ConfirmedFactSet? confirmed = await repository.latestConfirmedFactSet(issue.id);
        expect(confirmed, isNotNull);
        expect(confirmed!.revision, equals(1));
        expect(confirmed.confirmedData.issueType, equals(IssueType.wrongQty));
        expect(confirmed.confirmedData.userUncertainty, isTrue);
        expect(
          confirmed.confirmedData.unknownFields,
          unorderedEquals(<String>[
            'product_label',
            'product_reference',
            'expected_quantity',
            'received_quantity',
            'affected_quantity',
            'packaging_condition',
            'product_condition',
            'location_on_item',
          ]),
        );

        // L'écran reflète la confirmation (chip "Confirmé (rév. 1)").
        expect(find.text('Confirmé (rév. 1)'), findsOneWidget);
      },
    );

    testWidgets(
      "accepter tous les champs candidats tels quels (bouton 'Confirmer') "
      'persiste EXACTEMENT les valeurs proposées par l\'IA, sans champ '
      'inconnu',
      (WidgetTester tester) async {
        final domain.Incident incident = await repository.createIncident(
          occurredAt: DateTime.utc(2026, 8, 20, 11),
        );
        final domain.Issue issue =
            await repository.addIssue(incident.id, IssueType.packagingDamage);
        const CandidateFactData extracted = CandidateFactData(
          issueTypeCandidate: IssueType.packagingDamage,
          fields: <String, CandidateField>{
            'product_label': CandidateField(
              value: 'Carton n°3',
              source: FactSource.ocr,
              confidence: ConfidenceLevel.high,
            ),
            'product_reference': CandidateField(
              value: 'REF-200L',
              source: FactSource.ocr,
              confidence: ConfidenceLevel.medium,
            ),
            'expected_quantity': CandidateField(
              value: 8,
              source: FactSource.voiceTranscript,
              confidence: ConfidenceLevel.high,
            ),
            'received_quantity': CandidateField(
              value: 6,
              source: FactSource.voiceTranscript,
              confidence: ConfidenceLevel.high,
            ),
            'affected_quantity': CandidateField(
              value: 2,
              source: FactSource.llmNormalization,
              confidence: ConfidenceLevel.high,
            ),
            'packaging_condition': CandidateField(
              value: 'un coin écrasé',
              source: FactSource.voiceTranscript,
              confidence: ConfidenceLevel.high,
            ),
            'product_condition': CandidateField(
              value: 'apparemment intact',
              source: FactSource.voiceTranscript,
              confidence: ConfidenceLevel.medium,
            ),
            'location_on_item': CandidateField(
              value: 'coin inférieur droit',
              source: FactSource.voiceTranscript,
              confidence: ConfidenceLevel.medium,
            ),
          },
          requiresReview: false,
        );
        await repository.saveCandidateFactSet(
          issueId: issue.id,
          data: extracted,
          promptVersion: 'extraction_fr_v1',
          model: 'gpt-4o-mini',
        );

        await tester.pumpWidget(wrap(FactsReviewScreen(incidentId: incident.id)));
        await tester.pumpAndSettle();

        final Finder confirmButtons = find.widgetWithText(FilledButton, 'Confirmer');
        expect(confirmButtons, findsNWidgets(8));
        for (int i = 0; i < 8; i++) {
          await tester.tap(confirmButtons.at(i));
          await tester.pump();
        }
        await tester.pumpAndSettle();

        final Finder confirmIssueButton = find.widgetWithText(
          OutlinedButton,
          'Valider les faits de cette anomalie',
        );
        await tester.tap(confirmIssueButton);
        await tester.pumpAndSettle();

        final domain.ConfirmedFactSet? confirmed = await repository.latestConfirmedFactSet(issue.id);
        expect(confirmed, isNotNull);
        expect(confirmed!.confirmedData.userUncertainty, isFalse);
        expect(confirmed.confirmedData.unknownFields, isEmpty);
        expect(confirmed.confirmedData.productLabel, equals('Carton n°3'));
        expect(confirmed.confirmedData.productReference, equals('REF-200L'));
        expect(confirmed.confirmedData.expectedQuantity, equals(8.0));
        expect(confirmed.confirmedData.receivedQuantity, equals(6.0));
        expect(confirmed.confirmedData.affectedQuantity, equals(2.0));
        expect(confirmed.confirmedData.packagingCondition, equals('un coin écrasé'));
        expect(confirmed.confirmedData.productCondition, equals('apparemment intact'));
        expect(confirmed.confirmedData.locationOnItem, equals('coin inférieur droit'));
      },
    );
  });
}
