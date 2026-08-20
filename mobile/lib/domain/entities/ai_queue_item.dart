/// Statut d'une opération de la file IA (point 6 de la demande corrective -
/// fonctionnement offline). "Si une opération IA nécessite Internet : elle
/// passe en état pending, rien n'est perdu, retry possible à la
/// reconnexion."
enum AiOperationStatus { pending, inProgress, done, failed }

enum AiOperationKind {
  transcribeAudio,
  extractFromPhoto,
  extractFromDocument,

  /// R2 (optimisation coût IA) - étape d'extraction séparée de
  /// [transcribeAudio], mise en file par `lib/data/ai_queue_processor.dart`
  /// une fois la transcription obtenue : si CETTE étape échoue (réseau,
  /// quota...) et doit être retentée, la transcription déjà payée en tokens
  /// n'est JAMAIS refaite - seule l'extraction (gratuite, le transcript est
  /// déjà dans le payload de cet item) est retentée.
  extractFromTranscript,
}

/// Une opération IA en file d'attente - miroir de la table
/// `AiOperationQueue` (lib/data/local/app_database.dart), indépendant de
/// Drift pour que la couche métier (services, use cases) n'y dépende jamais
/// directement (point 12).
final class AiQueueItem {
  const AiQueueItem({
    required this.id,
    required this.incidentId,
    required this.operationKind,
    required this.payloadJson,
    required this.idempotencyKey,
    required this.createdAt,
    this.issueId,
    this.status = AiOperationStatus.pending,
    this.retryCount = 0,
    this.lastAttemptAt,
    this.lastError,
    this.resultJson,
  });

  final String id;
  final String incidentId;
  final String? issueId;
  final AiOperationKind operationKind;
  // Payload MINIMAL nécessaire à l'opération (point 14) : références vers
  // des EvidenceAsset, jamais un dump complet du dossier.
  final String payloadJson;
  final String idempotencyKey;
  final AiOperationStatus status;
  final int retryCount;
  final DateTime createdAt;
  final DateTime? lastAttemptAt;
  final String? lastError;
  final String? resultJson;

  AiQueueItem copyWith({
    AiOperationStatus? status,
    int? retryCount,
    DateTime? lastAttemptAt,
    String? lastError,
    String? resultJson,
  }) {
    return AiQueueItem(
      id: id,
      incidentId: incidentId,
      issueId: issueId,
      operationKind: operationKind,
      payloadJson: payloadJson,
      idempotencyKey: idempotencyKey,
      createdAt: createdAt,
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      lastError: lastError ?? this.lastError,
      resultJson: resultJson ?? this.resultJson,
    );
  }
}
