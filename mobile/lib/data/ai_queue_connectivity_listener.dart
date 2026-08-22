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
///
/// Bug trouvé en repréparant le test terrain de ce lot (avant tout retest
/// utilisateur - voir CHANGELOG) : ce fichier ne rafraîchissait RIEN côté
/// UI après un traitement automatique réussi. Tous les autres écrans qui
/// mutent des données locales appellent `notifyDataChanged` (`WidgetRef`,
/// `app_providers.dart`) - un simple compteur (`dataRefreshTickProvider`)
/// dont dépendent les `FutureProvider` de lecture (`latestCandidateFactSetProvider`,
/// `pendingAiOperationsProvider`, ...) pour se re-déclencher (pas de "watch"
/// live multi-écran sur Drift, limitation connue depuis R1). Ce fichier
/// n'a PAS accès à un `WidgetRef` (construit dans un `Provider`, pas un
/// widget) - [notifyDataChanged] ci-dessous est donc une simple fonction
/// injectée (même principe que [processPendingOperations]), câblée en
/// pratique sur le même compteur (voir `aiQueueConnectivityListenerProvider`).
/// Sans cet appel, le retour réseau automatique aurait bien fonctionné
/// CÔTÉ DONNÉES (la base contient le bon résultat), mais un écran déjà
/// ouvert au moment du retour réseau (ex: "Vérifier les faits") ne
/// l'aurait affiché qu'après une action explicite de l'utilisateur
/// (bouton de rafraîchissement manuel, ou sortie/re-entrée de l'écran) -
/// à l'opposé du but même de ce lot ("sans action utilisateur").
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

import '../core/network/connectivity_watcher.dart';
import 'ai_queue_processor.dart';

class AiQueueConnectivityListener {
  AiQueueConnectivityListener({
    required ConnectivityWatcher connectivityWatcher,
    required Future<AiQueueProcessingSummary> Function() processPendingOperations,
    required void Function() notifyDataChanged,
  })  : _connectivityWatcher = connectivityWatcher,
        _processPendingOperations = processPendingOperations,
        _notifyDataChanged = notifyDataChanged {
    _subscription = _connectivityWatcher.onBecameOnline.listen((_) => _onBecameOnline());
  }

  final ConnectivityWatcher _connectivityWatcher;
  final Future<AiQueueProcessingSummary> Function() _processPendingOperations;
  final void Function() _notifyDataChanged;
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
        // Voir docstring de fichier : sans ceci, un écran déjà ouvert (ex:
        // "Vérifier les faits") n'afficherait le résultat qu'après une
        // action explicite de l'utilisateur. `skipped` seul (items déjà
        // épuisés par le disjoncteur de retry, laissés tels quels) n'a
        // rien muté - inutile de rafraîchir dans ce cas précis.
        if (summary.succeeded + summary.failed > 0) {
          _notifyDataChanged();
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
