// R2 (point "déclenchement de la file au retour réseau", voir
// docs/GATE_R2_STATUS.md) - preuve par test d'`AiQueueConnectivityListener`
// (`lib/data/ai_queue_connectivity_listener.dart`), découplé volontairement
// d'un `ConnectivityWatcher`/`AiQueueProcessor` réels (voir docstring du
// fichier testé) : un `ConnectivityWatcher` fait à la main pilote
// exactement les transitions "retour en ligne" voulues par chaque test,
// même philosophie que `_FakeAiHttpTransport` dans
// `test/data/ai_queue_processor_test.dart`.
//
// Statut d'exécution (mobile/README.md) : écrit avec la même rigueur qu'un
// test qui tournerait réellement, mais N'A PAS ÉTÉ EXÉCUTÉ dans cette
// session (aucun SDK Flutter/Dart disponible) - à faire tourner en priorité
// dès que le SDK est disponible.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reserveflash/core/network/connectivity_watcher.dart';
import 'package:reserveflash/data/ai_queue_connectivity_listener.dart';
import 'package:reserveflash/data/ai_queue_processor.dart';

class _FakeConnectivityWatcher implements ConnectivityWatcher {
  final StreamController<void> _controller = StreamController<void>.broadcast();
  bool disposeCalled = false;

  /// Simule une transition hors-ligne -> en ligne (voir docstring
  /// `ConnectivityWatcher.onBecameOnline` : édge-triggered uniquement,
  /// jamais émis à la simple connexion initiale).
  void emitBecameOnline() => _controller.add(null);

  @override
  Stream<void> get onBecameOnline => _controller.stream;

  @override
  Future<void> dispose() async {
    disposeCalled = true;
    await _controller.close();
  }
}

const AiQueueProcessingSummary _emptySummary =
    AiQueueProcessingSummary(succeeded: 0, failed: 0, skipped: 0);
const AiQueueProcessingSummary _skippedOnlySummary =
    AiQueueProcessingSummary(succeeded: 0, failed: 0, skipped: 1);
const AiQueueProcessingSummary _succeededSummary =
    AiQueueProcessingSummary(succeeded: 1, failed: 0, skipped: 0);
const AiQueueProcessingSummary _failedSummary =
    AiQueueProcessingSummary(succeeded: 0, failed: 1, skipped: 0);

void main() {
  group('AiQueueConnectivityListener', () {
    test('retour réseau -> processPendingOperations appelé une fois', () async {
      final _FakeConnectivityWatcher watcher = _FakeConnectivityWatcher();
      int callCount = 0;
      final AiQueueConnectivityListener listener = AiQueueConnectivityListener(
        connectivityWatcher: watcher,
        processPendingOperations: () async {
          callCount++;
          return _emptySummary;
        },
        notifyDataChanged: () {},
      );

      watcher.emitBecameOnline();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(callCount, 1);
      await listener.dispose();
    });

    test('plusieurs retours réseau -> plusieurs appels', () async {
      final _FakeConnectivityWatcher watcher = _FakeConnectivityWatcher();
      int callCount = 0;
      final AiQueueConnectivityListener listener = AiQueueConnectivityListener(
        connectivityWatcher: watcher,
        processPendingOperations: () async {
          callCount++;
          return _emptySummary;
        },
        notifyDataChanged: () {},
      );

      watcher.emitBecameOnline();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      watcher.emitBecameOnline();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(callCount, 2);
      await listener.dispose();
    });

    test('aucun retour réseau -> jamais appelé', () async {
      final _FakeConnectivityWatcher watcher = _FakeConnectivityWatcher();
      int callCount = 0;
      final AiQueueConnectivityListener listener = AiQueueConnectivityListener(
        connectivityWatcher: watcher,
        processPendingOperations: () async {
          callCount++;
          return _emptySummary;
        },
        notifyDataChanged: () {},
      );

      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(callCount, 0);
      await listener.dispose();
    });

    test(
      'échec de processPendingOperations -> avalé (best-effort, jamais propagé)',
      () async {
        final _FakeConnectivityWatcher watcher = _FakeConnectivityWatcher();
        final AiQueueConnectivityListener listener = AiQueueConnectivityListener(
          connectivityWatcher: watcher,
          processPendingOperations: () async {
            throw StateError('panne réseau simulée');
          },
          notifyDataChanged: () {},
        );

        watcher.emitBecameOnline();
        // Ne doit lever aucune exception non gérée ici (voir catchError du
        // fichier testé) - si l'exception n'était pas avalée, ce test
        // échouerait avec une exception Zone non interceptée.
        await Future<void>.delayed(const Duration(milliseconds: 200));

        await listener.dispose();
      },
    );

    test('dispose() ferme le ConnectivityWatcher sous-jacent', () async {
      final _FakeConnectivityWatcher watcher = _FakeConnectivityWatcher();
      final AiQueueConnectivityListener listener = AiQueueConnectivityListener(
        connectivityWatcher: watcher,
        processPendingOperations: () async => _emptySummary,
        notifyDataChanged: () {},
      );

      await listener.dispose();

      expect(watcher.disposeCalled, isTrue);
    });

    // Bug trouvé en repréparant le test terrain de ce lot (voir docstring
    // de `ai_queue_connectivity_listener.dart` et CHANGELOG) : le fichier
    // ne prévenait initialement JAMAIS l'UI après un traitement réussi -
    // les 4 tests suivants couvrent précisément ce correctif.
    group('notifyDataChanged (correctif - rafraîchissement UI)', () {
      test('traitement avec un succès -> notifyDataChanged appelé', () async {
        final _FakeConnectivityWatcher watcher = _FakeConnectivityWatcher();
        int notifyCount = 0;
        final AiQueueConnectivityListener listener = AiQueueConnectivityListener(
          connectivityWatcher: watcher,
          processPendingOperations: () async => _succeededSummary,
          notifyDataChanged: () => notifyCount++,
        );

        watcher.emitBecameOnline();
        await Future<void>.delayed(const Duration(milliseconds: 200));

        expect(notifyCount, 1);
        await listener.dispose();
      });

      test('traitement avec un échec (mais pas d\'exception) -> notifyDataChanged appelé', () async {
        final _FakeConnectivityWatcher watcher = _FakeConnectivityWatcher();
        int notifyCount = 0;
        final AiQueueConnectivityListener listener = AiQueueConnectivityListener(
          connectivityWatcher: watcher,
          processPendingOperations: () async => _failedSummary,
          notifyDataChanged: () => notifyCount++,
        );

        watcher.emitBecameOnline();
        await Future<void>.delayed(const Duration(milliseconds: 200));

        // Un échec mute quand même l'item (retryCount, lastError) - la
        // bannière `pendingAiOperationsProvider` doit pouvoir le refléter.
        expect(notifyCount, 1);
        await listener.dispose();
      });

      test('résumé entièrement vide -> notifyDataChanged PAS appelé', () async {
        final _FakeConnectivityWatcher watcher = _FakeConnectivityWatcher();
        int notifyCount = 0;
        final AiQueueConnectivityListener listener = AiQueueConnectivityListener(
          connectivityWatcher: watcher,
          processPendingOperations: () async => _emptySummary,
          notifyDataChanged: () => notifyCount++,
        );

        watcher.emitBecameOnline();
        await Future<void>.delayed(const Duration(milliseconds: 200));

        expect(notifyCount, 0);
        await listener.dispose();
      });

      test('résumé "skipped" uniquement -> notifyDataChanged PAS appelé', () async {
        final _FakeConnectivityWatcher watcher = _FakeConnectivityWatcher();
        int notifyCount = 0;
        final AiQueueConnectivityListener listener = AiQueueConnectivityListener(
          connectivityWatcher: watcher,
          processPendingOperations: () async => _skippedOnlySummary,
          notifyDataChanged: () => notifyCount++,
        );

        watcher.emitBecameOnline();
        await Future<void>.delayed(const Duration(milliseconds: 200));

        // "skipped" = items déjà épuisés par le disjoncteur, laissés tels
        // quels (voir ai_queue_processor.dart) - rien n'a été muté.
        expect(notifyCount, 0);
        await listener.dispose();
      });

      test('exception de processPendingOperations -> notifyDataChanged PAS appelé', () async {
        final _FakeConnectivityWatcher watcher = _FakeConnectivityWatcher();
        int notifyCount = 0;
        final AiQueueConnectivityListener listener = AiQueueConnectivityListener(
          connectivityWatcher: watcher,
          processPendingOperations: () async {
            throw StateError('panne réseau simulée');
          },
          notifyDataChanged: () => notifyCount++,
        );

        watcher.emitBecameOnline();
        await Future<void>.delayed(const Duration(milliseconds: 200));

        expect(notifyCount, 0);
        await listener.dispose();
      });
    });
  });
}
