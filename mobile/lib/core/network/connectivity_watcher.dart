/// R2 (point "déclenchement de la file au retour réseau", voir
/// `docs/GATE_R2_STATUS.md`, section "Reste à faire") - frontière autour de
/// `package:connectivity_plus`, même principe que `OcrService`
/// (`lib/data/local/ocr_service.dart`) ou `AiHttpTransport`
/// (`lib/data/remote/ai_api_client.dart`) : la logique applicative
/// (`AiQueueConnectivityListener`, `lib/data/ai_queue_connectivity_listener.dart`)
/// ne dépend JAMAIS directement d'un plugin tiers - elle dépend de cette
/// interface, testable sans plugin réel (aucun canal de plateforme
/// nécessaire dans les tests).
library;

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart' as plus;
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

/// Émet un événement à chaque fois que l'appareil PASSE (ou repasse) à un
/// état connecté après avoir été détecté hors ligne - jamais à la simple
/// connexion initiale au démarrage de l'app (voir docstring
/// d'[onBecameOnline] ci-dessous pour le détail exact du déclenchement).
abstract class ConnectivityWatcher {
  Stream<void> get onBecameOnline;

  Future<void> dispose();
}

/// Implémentation réelle, au-dessus de `Connectivity().onConnectivityChanged`
/// (`connectivity_plus`).
///
/// Édge-triggered UNIQUEMENT (transition hors-ligne -> en ligne), jamais à
/// chaque événement de connectivité reçu : le premier événement reçu après
/// l'abonnement (état initial, quel qu'il soit) ne déclenche JAMAIS
/// `onBecameOnline` - seule une transition effective (était hors ligne au
/// dernier événement connu, est en ligne maintenant) le fait. Objectif :
/// relancer `AiQueueProcessor.processPendingOperations` uniquement quand
/// c'est utile (un item était potentiellement resté `pending` faute de
/// réseau), jamais au simple démarrage de l'app (déjà couvert par les
/// autres points de déclenchement - capture, écran de revue des faits).
///
/// Note connue (limitation documentée, pas un bug) : `connectivity_plus`
/// rapporte qu'une INTERFACE réseau est active (Wi-Fi, données mobiles...),
/// PAS qu'Internet est réellement joignable (aucune sonde active vers un
/// serveur distant) - un Wi-Fi sans accès Internet réel déclenchera quand
/// même une tentative. Sans risque : cette tentative échouera normalement
/// (timeout Dio -> `AiUnavailableException` -> l'item reste `pending`, le
/// disjoncteur de retry existant d'`AiQueueProcessor` s'applique
/// inchangé) - jamais de coût IA ni de boucle supplémentaire au-delà d'un
/// appel HTTP qui échoue rapidement.
class ConnectivityPlusWatcher implements ConnectivityWatcher {
  ConnectivityPlusWatcher([plus.Connectivity? connectivity])
      : _connectivity = connectivity ?? plus.Connectivity();

  final plus.Connectivity _connectivity;
  StreamSubscription<List<plus.ConnectivityResult>>? _subscription;
  final StreamController<void> _becameOnlineController = StreamController<void>.broadcast();

  /// `null` tant qu'aucun événement de connectivité n'a encore été reçu
  /// (état initial inconnu) - voir [_handleConnectivityChanged].
  bool? _wasOnline;

  @override
  Stream<void> get onBecameOnline {
    // `onError` explicite (best-effort, même politique que partout ailleurs
    // dans le pipeline IA) : si le plugin natif n'est pas disponible
    // (plateforme non supportée, canal non enregistré - ex : `flutter test`
    // hors intégration, où aucun canal de plateforme réel n'existe), cette
    // fonctionnalité optionnelle se dégrade silencieusement plutôt que de
    // faire planter l'app - les autres déclenchements existants (capture,
    // écran de revue) restent inchangés.
    _subscription ??= _connectivity.onConnectivityChanged.listen(
      _handleConnectivityChanged,
      onError: (Object e) {
        if (kDebugMode) {
          debugPrint(
            '[RF][connectivity] EXCEPTION du plugin connectivity_plus '
            '(avalée, déclenchement au retour réseau simplement indisponible) : $e',
          );
        }
      },
    );
    return _becameOnlineController.stream;
  }

  void _handleConnectivityChanged(List<plus.ConnectivityResult> results) {
    final bool isOnline = results.any((plus.ConnectivityResult r) => r != plus.ConnectivityResult.none);
    if (_wasOnline == false && isOnline) {
      _becameOnlineController.add(null);
    }
    _wasOnline = isOnline;
  }

  @override
  Future<void> dispose() async {
    await _subscription?.cancel();
    await _becameOnlineController.close();
  }
}
