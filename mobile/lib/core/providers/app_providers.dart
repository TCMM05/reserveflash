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

import 'dart:io';

// R1 (bug decouvert par execution reelle - `flutter analyze`/`flutter test`) :
// `LazyDatabase` vit dans `package:drift/drift.dart` (le coeur de drift),
// PAS dans `package:drift/native.dart` (qui n'expose que `NativeDatabase`,
// specifique a l'implementation native/desktop/mobile) - les deux imports
// sont necessaires ici. Sans risque de collision `isNotNull`/`isNull` avec
// `flutter_test` (voir la mise en garde dans
// test/data/local_incident_repository_test.dart) car ce fichier n'importe
// pas `flutter_test`.
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/local/app_database.dart';
import '../../data/local/evidence_storage.dart';
import '../../data/local/local_incident_repository.dart';
import '../../domain/entities/evidence_asset.dart' as domain;
import '../../domain/entities/incident.dart' as domain;
import '../../domain/entities/issue.dart' as domain;
import '../../domain/repositories/incident_repository.dart';

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

/// Point d'entrée UNIQUE pour tout le code applicatif (écrans, use cases) -
/// voir docstring de `lib/domain/repositories/incident_repository.dart` :
/// "la logique métier ne doit jamais dépendre directement de Drift".
final Provider<IncidentRepository> incidentRepositoryProvider =
    Provider<IncidentRepository>((ref) {
  final AppDatabase db = ref.watch(appDatabaseProvider);
  final EvidenceStorageService storage = ref.watch(evidenceStorageServiceProvider);
  return LocalIncidentRepository(db, evidenceStorage: storage);
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
