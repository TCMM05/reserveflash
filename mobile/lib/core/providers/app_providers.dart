/// Câblage Riverpod de l'app - R1 "Capture Offline".
///
/// Avant R1, `ProviderScope` (voir lib/main.dart) n'avait AUCUN override et
/// aucun fichier ne déclarait de provider : ce fichier est le premier point
/// d'entrée de la DI Riverpod du projet. Toute la chaîne
/// `AppDatabase -> LocalIncidentRepository -> IncidentRepository` est
/// construite ICI, une seule fois, pour toute la durée de vie de l'app -
/// aucun écran ne doit instancier `AppDatabase`/`LocalIncidentRepository`
/// directement (section 5.1 - "pas de logique métier dans les widgets").
library;

import 'dart:async';
import 'dart:io';

// R1 (bug decouvert par execution reelle - `flutter analyze`/`flutter test`) :
// `LazyDatabase` vit dans `package:drift/drift.dart` (le coeur de drift),
// PAS dans `package:drift/native.dart` (qui n'expose que `NativeDatabase`,
// specifique a l'implementation native/desktop/mobile) - les deux imports
// sont necessaires ici. Sans risque de collision `isNotNull`/`isNull` avec
// `flutter_test` (voir la mise en garde dans
// test/data/local_incident_repository_test.dart) car ce fichier n'importe
// pas `flutter_test`.
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/ai_queue_connectivity_listener.dart';
import '../../data/ai_queue_processor.dart';
import '../../data/local/app_database.dart';
import '../../data/local/evidence_storage.dart';
import '../../data/local/local_incident_repository.dart';
import '../../data/local/ocr_service.dart';
import '../../data/remote/ai_api_client.dart';
import '../../domain/entities/ai_queue_item.dart';
import '../../domain/entities/candidate_fact_set.dart' as domain;
import '../../domain/entities/confirmed_fact_set.dart' as domain;
import '../../domain/entities/evidence_asset.dart' as domain;
import '../../domain/entities/incident.dart' as domain;
import '../../domain/entities/issue.dart' as domain;
import '../../domain/entities/reserve_text.dart' as domain;
import '../../domain/repositories/incident_repository.dart';
import '../config/backend_config.dart';
import '../network/connectivity_watcher.dart';

/// Ouvre la base Drift/SQLite réelle de l'app (points 1/2 - "source de
/// vérité locale") : fichier persistant dans l'espace privé de l'app
/// (`path_provider`), JAMAIS `NativeDatabase.memory()` - toute la garantie
/// de résilience R1 (R1-T02/T05/T09) repose sur une vraie écriture disque.
///
/// `LazyDatabase` (pattern recommandé par drift, déjà utilisé par
/// `mobile/test/data/local_incident_repository_test.dart` sous une forme
/// non-lazy équivalente) : le fichier n'est ouvert qu'au premier accès réel,
/// pas au démarrage de l'app (S01 - "<1s visuel ; ne bloque pas le mode
/// local plus que nécessaire"). `createInBackground` (recommandé par drift
/// en production) évite de bloquer le thread UI pendant l'ouverture/les
/// migrations du fichier SQLite.
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final Directory appDocs = await getApplicationDocumentsDirectory();
    final File dbFile = File(p.join(appDocs.path, 'reserveflash.sqlite'));
    return NativeDatabase.createInBackground(dbFile);
  });
}

/// Singleton applicatif : une seule connexion DB pour toute la durée de vie
/// du `ProviderScope` racine (voir lib/main.dart). `ref.onDispose` ferme
/// proprement la connexion si ce provider est un jour recréé (tests,
/// hot-restart) - en usage normal, il vit aussi longtemps que l'app.
final Provider<AppDatabase> appDatabaseProvider = Provider<AppDatabase>((ref) {
  final AppDatabase db = AppDatabase(_openConnection());
  ref.onDispose(db.close);
  return db;
});

final Provider<EvidenceStorageService> evidenceStorageServiceProvider =
    Provider<EvidenceStorageService>((ref) => const EvidenceStorageService());

/// R2 (lot OCR `document_capture_screen.dart`) - voir
/// `lib/data/local/ocr_service.dart` : OCR on-device (ML Kit), aucun appel
/// réseau, aucun coût IA.
final Provider<OcrService> ocrServiceProvider =
    Provider<OcrService>((ref) => const MlKitOcrService());

/// R2 - unique client HTTP de l'app (voir
/// `lib/data/remote/ai_api_client.dart` : seul appel réseau optionnel,
/// jamais requis pour la capture locale, section 8.1). `baseUrl` vient de
/// `lib/core/config/backend_config.dart` - jamais codé en dur ici.
final Provider<Dio> dioProvider = Provider<Dio>((ref) {
  return Dio(
    BaseOptions(
      baseUrl: backendBaseUrl,
      connectTimeout: const Duration(seconds: 30),
      // Généreux côté réception : une extraction IA (LLM) peut prendre
      // plusieurs secondes, voir backend/app/config.py::
      // openai_request_timeout_seconds (30s également côté backend - pas de
      // sens à couper côté mobile avant que le backend lui-même n'ait
      // renvoyé AI_UNAVAILABLE).
      receiveTimeout: const Duration(seconds: 35),
    ),
  );
});

final Provider<AiApiClient> aiApiClientProvider = Provider<AiApiClient>((ref) {
  return AiApiClient(DioAiHttpTransport(ref.watch(dioProvider)));
});

/// Point d'entrée UNIQUE pour tout le code applicatif (écrans, use cases) -
/// voir docstring de `lib/domain/repositories/incident_repository.dart` :
/// "la logique métier ne doit jamais dépendre directement de Drift".
final Provider<IncidentRepository> incidentRepositoryProvider =
    Provider<IncidentRepository>((ref) {
  final AppDatabase db = ref.watch(appDatabaseProvider);
  final EvidenceStorageService storage = ref.watch(evidenceStorageServiceProvider);
  return LocalIncidentRepository(db, evidenceStorage: storage);
});

/// R2 - traite la file `AiOperationQueue` (voir `lib/data/ai_queue_processor.dart`) :
/// relie `incidentRepositoryProvider`/`aiApiClientProvider`/
/// `evidenceStorageServiceProvider` ci-dessus, aucun écran ne doit
/// construire `AiQueueProcessor` directement (même principe de frontière
/// que les autres providers de ce fichier).
final Provider<AiQueueProcessor> aiQueueProcessorProvider =
    Provider<AiQueueProcessor>((ref) {
  return AiQueueProcessor(
    incidentRepository: ref.watch(incidentRepositoryProvider),
    aiApiClient: ref.watch(aiApiClientProvider),
    evidenceStorage: ref.watch(evidenceStorageServiceProvider),
    ocrService: ref.watch(ocrServiceProvider),
  );
});

/// R2 (point "déclenchement de la file au retour réseau", voir
/// `lib/core/network/connectivity_watcher.dart`) - une seule instance pour
/// toute la durée de vie de l'app, fermée proprement à la destruction du
/// `ProviderScope` racine (hot-restart, tests).
final Provider<ConnectivityWatcher> connectivityWatcherProvider =
    Provider<ConnectivityWatcher>((ref) {
  final ConnectivityPlusWatcher watcher = ConnectivityPlusWatcher();
  ref.onDispose(() => unawaited(watcher.dispose()));
  return watcher;
});

/// R2 - s'abonne à [connectivityWatcherProvider] pour relancer
/// automatiquement `AiQueueProcessor.processPendingOperations` au retour
/// réseau (voir `lib/data/ai_queue_connectivity_listener.dart`). Ce
/// provider doit être "activé" une seule fois, tôt, pour toute la durée de
/// vie de l'app - voir `ReserveFlashApp` (`lib/main.dart`), qui le
/// `ref.watch` sans utiliser sa valeur (le seul but est de déclencher sa
/// construction, donc l'abonnement à la connectivité).
final Provider<AiQueueConnectivityListener> aiQueueConnectivityListenerProvider =
    Provider<AiQueueConnectivityListener>((ref) {
  final AiQueueConnectivityListener listener = AiQueueConnectivityListener(
    connectivityWatcher: ref.watch(connectivityWatcherProvider),
    processPendingOperations: () => ref.read(aiQueueProcessorProvider).processPendingOperations(),
    // Voir docstring de `ai_queue_connectivity_listener.dart` (bug trouvé
    // après [0.3.17]/[0.3.18] - traitement effectué SANS que l'UI ne soit
    // jamais notifiée) : même compteur que `notifyDataChanged(WidgetRef)`
    // ci-dessous, ce fichier n'ayant accès qu'à un `Ref` de provider, pas
    // un `WidgetRef`.
    notifyDataChanged: () => ref.read(dataRefreshTickProvider.notifier).state++,
  );
  ref.onDispose(() => unawaited(listener.dispose()));
  return listener;
});

/// Compteur incrémenté après toute mutation locale (création/suppression
/// d'incident, ajout/suppression de preuve, etc.) pour invalider les
/// `FutureProvider` de lecture ci-dessous sans dépendre d'un flux réactif
/// Drift complet (hors scope R1 - voir CHANGELOG.md pour la limitation
/// documentée : rafraîchissement explicite après action, pas de "watch"
/// live multi-écran).
final StateProvider<int> dataRefreshTickProvider = StateProvider<int>((ref) => 0);

/// Provoque le rafraîchissement de tous les providers de lecture ci-dessous
/// qui dépendent de [dataRefreshTickProvider]. À appeler après CHAQUE
/// mutation locale réussie (créer/modifier/supprimer un incident, une
/// preuve...).
void notifyDataChanged(WidgetRef ref) {
  ref.read(dataRefreshTickProvider.notifier).state++;
}

final FutureProvider<List<domain.Incident>> incidentListProvider =
    FutureProvider<List<domain.Incident>>((ref) async {
  ref.watch(dataRefreshTickProvider);
  final IncidentRepository repo = ref.watch(incidentRepositoryProvider);
  return repo.listIncidents();
});

final FutureProviderFamily<domain.Incident?, String> incidentDetailProvider =
    FutureProvider.family<domain.Incident?, String>((ref, incidentId) async {
  ref.watch(dataRefreshTickProvider);
  final IncidentRepository repo = ref.watch(incidentRepositoryProvider);
  return repo.getIncident(incidentId);
});

final FutureProviderFamily<List<domain.Issue>, String> incidentIssuesProvider =
    FutureProvider.family<List<domain.Issue>, String>((ref, incidentId) async {
  ref.watch(dataRefreshTickProvider);
  final IncidentRepository repo = ref.watch(incidentRepositoryProvider);
  return repo.listIssues(incidentId);
});

final FutureProviderFamily<List<domain.EvidenceAsset>, String> incidentEvidenceProvider =
    FutureProvider.family<List<domain.EvidenceAsset>, String>((ref, incidentId) async {
  ref.watch(dataRefreshTickProvider);
  final IncidentRepository repo = ref.watch(incidentRepositoryProvider);
  return repo.verifyEvidenceAssetsIntegrity(incidentId);
});

// -- R2 : câblage écran de revue des faits (S11, facts_review_screen.dart) --

/// Dernière extraction candidate reçue pour une anomalie (résultat du
/// pipeline IA - `AiQueueProcessor`), ou `null` tant qu'aucune extraction
/// n'a encore été effectuée/reçue pour cette anomalie (l'écran de revue
/// affiche alors des champs entièrement à saisir manuellement - "bascule
/// manuelle" naturelle, pas seulement après épuisement du disjoncteur de
/// retry, voir docs/GATE_R2_STATUS.md).
final FutureProviderFamily<domain.CandidateFactSet?, String> latestCandidateFactSetProvider =
    FutureProvider.family<domain.CandidateFactSet?, String>((ref, issueId) async {
  ref.watch(dataRefreshTickProvider);
  final IncidentRepository repo = ref.watch(incidentRepositoryProvider);
  return repo.latestCandidateFactSet(issueId);
});

/// Dernière révision de faits CONFIRMÉS pour une anomalie (post-revue
/// utilisateur), ou `null` si l'anomalie n'a jamais encore été confirmée.
final FutureProviderFamily<domain.ConfirmedFactSet?, String> latestConfirmedFactSetProvider =
    FutureProvider.family<domain.ConfirmedFactSet?, String>((ref, issueId) async {
  ref.watch(dataRefreshTickProvider);
  final IncidentRepository repo = ref.watch(incidentRepositoryProvider);
  return repo.latestConfirmedFactSet(issueId);
});

/// Dernière révision confirmée de CHAQUE anomalie de l'incident (une entrée
/// par anomalie ayant au moins une confirmation) - utilisé par l'écran de
/// revue pour savoir si `composeAndSaveReserve` a au moins un fait confirmé
/// à composer (sinon `NoConfirmedFactsException`, voir
/// `IncidentRepository.composeAndSaveReserve`).
final FutureProviderFamily<List<domain.ConfirmedFactSet>, String>
    incidentConfirmedFactSetsProvider =
    FutureProvider.family<List<domain.ConfirmedFactSet>, String>((ref, incidentId) async {
  ref.watch(dataRefreshTickProvider);
  final IncidentRepository repo = ref.watch(incidentRepositoryProvider);
  return repo.listLatestConfirmedFactSetsForIncident(incidentId);
});

/// Items `pending` de la file IA, tous incidents confondus (l'app ne traite
/// qu'un incident à la fois côté UI - filtré côté écran par `issueId`/
/// `incidentId`, voir `IncidentRepository.listPendingAiOperations`). Permet
/// à l'écran de revue de distinguer "traitement IA encore en cours pour
/// cette anomalie" de "bloqué par le disjoncteur de retry" (retour
/// d'équipe, exigence coût IA point 7 - bascule manuelle/UNKNOWN).
final FutureProvider<List<AiQueueItem>> pendingAiOperationsProvider =
    FutureProvider<List<AiQueueItem>>((ref) async {
  ref.watch(dataRefreshTickProvider);
  final IncidentRepository repo = ref.watch(incidentRepositoryProvider);
  return repo.listPendingAiOperations();
});

/// Dernière réserve composée pour l'incident (S12, `reserve_screen.dart`),
/// ou `null` tant qu'`IncidentRepository.composeAndSaveReserve` n'a jamais
/// été appelé avec succès pour ce dossier.
final FutureProviderFamily<domain.ReserveText?, String> latestReserveTextProvider =
    FutureProvider.family<domain.ReserveText?, String>((ref, incidentId) async {
  ref.watch(dataRefreshTickProvider);
  final IncidentRepository repo = ref.watch(incidentRepositoryProvider);
  return repo.latestReserveText(incidentId);
});
