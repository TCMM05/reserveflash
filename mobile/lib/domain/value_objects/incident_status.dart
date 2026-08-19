import 'dart:collection';

/// États métier d'un incident (section 2.2). Miroir de
/// `backend/app/domain/value_objects.py::IncidentStatus`, y compris le
/// graphe de transitions et le calcul de plus court chemin (utilisé côté
/// client pour désactiver les actions non autorisées avant même l'appel
/// réseau - section 2.3 "feedback immédiat").
enum IncidentStatus {
  draftLocal('draft_local'),
  syncing('syncing'),
  extractionPending('extraction_pending'),
  reviewRequired('review_required'),
  factsConfirmed('facts_confirmed'),
  reserveReady('reserve_ready'),
  evidenceComplete('evidence_complete'),
  exported('exported'),
  archived('archived');

  const IncidentStatus(this.wireValue);

  final String wireValue;

  static IncidentStatus fromWire(String value) {
    return IncidentStatus.values.firstWhere(
      (candidate) => candidate.wireValue == value,
      orElse: () => throw ArgumentError('IncidentStatus inconnu: $value'),
    );
  }

  /// Transitions principales autorisées (section 2.2).
  static final Map<IncidentStatus, Set<IncidentStatus>> _graph =
      UnmodifiableMapView<IncidentStatus, Set<IncidentStatus>>({
    IncidentStatus.draftLocal: {IncidentStatus.syncing, IncidentStatus.reviewRequired},
    IncidentStatus.syncing: {IncidentStatus.extractionPending, IncidentStatus.draftLocal},
    IncidentStatus.extractionPending: {IncidentStatus.reviewRequired},
    IncidentStatus.reviewRequired: {IncidentStatus.factsConfirmed},
    IncidentStatus.factsConfirmed: {IncidentStatus.reserveReady},
    IncidentStatus.reserveReady: {IncidentStatus.evidenceComplete},
    IncidentStatus.evidenceComplete: {IncidentStatus.exported},
    IncidentStatus.exported: {IncidentStatus.archived, IncidentStatus.reviewRequired},
    IncidentStatus.archived: {IncidentStatus.reviewRequired},
  });

  Set<IncidentStatus> get allowedNext => _graph[this] ?? const <IncidentStatus>{};

  bool canTransitionTo(IncidentStatus target) => allowedNext.contains(target);

  /// Plus court chemin (BFS) vers [target], `this` inclus. Retourne `null`
  /// si aucun chemin n'existe dans le graphe section 2.2.
  List<IncidentStatus>? pathTo(IncidentStatus target) {
    if (this == target) {
      return <IncidentStatus>[this];
    }
    final Queue<List<IncidentStatus>> queue = Queue<List<IncidentStatus>>()
      ..add(<IncidentStatus>[this]);
    final Set<IncidentStatus> visited = <IncidentStatus>{this};

    while (queue.isNotEmpty) {
      final List<IncidentStatus> path = queue.removeFirst();
      for (final IncidentStatus next in path.last.allowedNext) {
        if (visited.contains(next)) {
          continue;
        }
        final List<IncidentStatus> newPath = <IncidentStatus>[...path, next];
        if (next == target) {
          return newPath;
        }
        visited.add(next);
        queue.add(newPath);
      }
    }
    return null;
  }
}
