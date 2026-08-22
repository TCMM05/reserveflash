/// R2 (point "déclenchement de la file au retour réseau", voir
/// `docs/GATE_R2_STATUS.md`) - jusqu'ici `AiQueueProcessor.processPendingOperations`
/// (`lib/data/ai_queue_processor.dart`) n'était appelé que juste après une
/// capture (photo, note vocale) ou manuellement depuis
/// `facts_review_screen.dart` : un item resté `pending` faute de réseau
/// (ex : avion, zone blanche) ne repartait donc JAMAIS tout seul au retour
/// en ligne, tant que l'utilisateur ne refaisait pas une action explicite.
///
/// Ce fichier comble ce point, en s'abonnant à
/// [ConnectivityWatcher.onBecameOnline] (`lib/core/network/connectivity_watcher.dart`)
/// pour une seule et unique instance vivant toute la durée de vie de l'app
/// (voir câblage `aiQueueConnectivityListenerProvider`,
/// `lib/core/providers/app_providers.dart`, et `lib/main.dart`).
///
/// Découplé volontairement d'[AiQueueProcessor] lui-même (dépend d'une
/// simple fonction [processPendingOperations], pas de la classe complète) :
/// testable sans base Drift/`EvidenceStorageService` réels, seul le
/// déclenchement compte ici - le comportement de traitement lui-même est
/// déjà entièrement couvert par `test/data/ai_queue_processor_test.dart`.
///
/// Best-effort explicite, même politique que partout ailleurs dans le
/// pipeline IA (voir `evidence_capture_screen.dart`,
/// `issue_type_screen.dart`) : jamais d'erreur affichée à l'utilisateur
/// pour ce déclenchement automatique en arrière-plan. Logs
/// `[RF][connectivity]` PERMANENTS en debug uniquement (`kDebugMode`),
/// même convention que le reste du pipeline IA (voir CHANGELOG `[0.3.14]`,
/// consigne permanente du projet : toujours insérer des logs de diagnostic
/// sur un chemin silencieux par conception).
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

import '../core/network/connectivity_watcher.dart';
import 'ai_queue_processor.dart';

class AiQueueConnectivityListener {
  AiQueueConnectivityListener({
    required ConnectivityWatcher connectivityWatcher,
    required Future<AiQueueProcessingSummary> Function() processPendingOperations,
  })  : _connectivityWatcher = connectivityWatcher,
        _processPendingOperations = processPendingOperations {
    _subscription = _connectivityWatcher.onBecameOnline.listen((_) => _onBecameOnline());
  }

  final ConnectivityWatcher _connectivityWatcher;
  final Future<AiQueueProcessingSummary> Function() _processPendingOperations;
  StreamSubscription<void>? _subscription;

  void _onBecameOnline() {
    if (kDebugMode) {
      debugPrint(
        '[RF][connectivity] retour réseau détecté - relance de la file IA pending.',
      );
    }
    unawaited(
      _processPendingOperations().then((AiQueueProcessingSummary summary) {
        if (kDebugMode) {
          debugPrint(
            '[RF][connectivity] traitement après retour réseau terminé : '
            'succeeded=${summary.succeeded} failed=${summary.failed} '
            'skipped=${summary.skipped}.',
          );
        }
      }).catchError((Object e) {
        if (kDebugMode) {
          debugPrint(
            '[RF][connectivity] EXCEPTION lors du traitement après retour '
            'réseau (avalée, jamais affichée à l\'utilisateur) : $e',
          );
        }
      }),
    );
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _connectivityWatcher.dispose();
  }
}
