/// Port `IncidentRepository` (point 12 de la demande corrective -
/// "Préparer l'avenir sans complexifier la V1") : la logique métier (use
/// cases, services applicatifs, écrans) dépend UNIQUEMENT de cette
/// interface, jamais directement de Drift ni d'un futur client HTTP/cloud.
///
///   "Garder une architecture interfaces/repositories, ex: IncidentRepository
///   avec LocalIncidentRepository pour la V1, et éventuellement plus tard
///   CloudIncidentRepository. La logique métier ne doit pas dépendre
///   directement de Drift ou de PostgreSQL, pour permettre d'ajouter le
///   cloud plus tard sans réécrire le moteur."
///
/// Implémentation V1 (seule utilisée en runtime, voir
/// `lib/data/local/local_incident_repository.dart`) : `LocalIncidentRepository`,
/// entièrement backée par Drift/SQLite (`AppDatabase`). Une future
/// `CloudIncidentRepository` (hors scope V1, section 12) implémenterait la
/// même interface pour un usage multi-appareil/équipes/tableau de bord web,
/// sans qu'aucun use case n'ait besoin d'être modifié.
///
/// Ce fichier ne doit importer AUCUN package Drift/sqlite/dio : c'est la
/// frontière stricte de dépendance (miroir mobile de
/// `backend/app/application/ports.py`, section 5.3).
library;

import '../entities/ai_queue_item.dart';
import '../entities/confirmed_fact_set.dart';
import '../entities/evidence_asset.dart';
import '../entities/incident.dart';
import '../entities/issue.dart';
import '../entities/reserve_text.dart';
import '../fact_set/confirmed_fact_data.dart';
import '../value_objects/incident_status.dart';
import '../value_objects/issue_type.dart';

abstract interface class IncidentRepository {
  // -- Incidents ------------------------------------------------------

  /// Crée un incident 100% local (point 1/13 - aucun réseau, aucun compte
  /// requis). `id` est généré par l'implémentation (UUID local).
  Future<Incident> createIncident({
    required DateTime occurredAt,
    String? supplierName,
    String? carrierName,
    String? deliveryRef,
    String? notes,
  });

  Future<Incident?> getIncident(String incidentId);

  Future<List<Incident>> listIncidents({bool includeArchived = false});

  Future<Incident> updateIncidentStatus(String incidentId, IncidentStatus status);

  Future<void> archiveIncident(String incidentId);

  /// R1 (point 7 - "corriger métadonnées") : réécrit les champs saisissables
  /// d'un incident déjà créé. `occurredAt` reste obligatoire (un incident a
  /// toujours une date/heure) ; les champs optionnels passés à `null`
  /// EFFACENT explicitement la valeur existante (pas de distinction
  /// "non fourni" / "remis à vide" - l'écran d'édition renvoie toujours son
  /// état complet). Aucune suppression silencieuse (point 7) : c'est
  /// l'appelant (UI) qui doit demander confirmation avant d'appeler cette
  /// méthode pour un champ effacé, cette méthode elle-même applique
  /// simplement ce qui lui est demandé.
  Future<Incident> updateIncidentMetadata({
    required String incidentId,
    required DateTime occurredAt,
    String? supplierName,
    String? carrierName,
    String? deliveryRef,
    String? notes,
  });

  /// R1 (point 7 - "supprimer un incident avec confirmation explicite") :
  /// supprime l'incident ET toutes les données qui en dépendent (issues,
  /// faits candidats/confirmés, réserve(s), preuves, opérations IA en
  /// attente), dans une seule transaction Drift - jamais d'état partiel.
  ///
  /// Ne supprime PAS les fichiers binaires référencés par les
  /// `EvidenceAsset` de cet incident (photos, audio...) : cette méthode ne
  /// touche QUE les métadonnées (frontière stricte de dépendance, voir
  /// docstring de fichier). L'appelant DOIT lister les preuves
  /// (`listEvidenceAssets`) et supprimer leurs fichiers via
  /// `lib/data/local/evidence_storage.dart` AVANT d'appeler cette méthode,
  /// pour ne jamais laisser de fichier orphelin sur le disque de l'appareil.
  Future<void> deleteIncident(String incidentId);

  // -- Issues -----------------------------------------------------------

  Future<Issue> addIssue(String incidentId, IssueType issueType);

  Future<List<Issue>> listIssues(String incidentId);

  // -- Faits confirmés --------------------------------------------------

  /// Crée une nouvelle révision de faits confirmés pour [issueId].
  ///
  /// DOIT appliquer `lib/domain/liability_guard.dart::screenConfirmedFact`
  /// avant toute persistance (correctif R0.1 point 8) - lève
  /// `LiabilityAttributionException` si [data] contient un contenu interdit,
  /// SANS rien écrire en base. Invalide (sans supprimer, historique
  /// conservé - section 8.2) la dernière `ReserveText` de l'incident, le cas
  /// échéant (invariant 6.3).
  Future<ConfirmedFactSet> confirmFacts({
    required String issueId,
    required ConfirmedFactData data,
    String? confirmedBy,
  });

  Future<ConfirmedFactSet?> latestConfirmedFactSet(String issueId);

  Future<List<ConfirmedFactSet>> listLatestConfirmedFactSetsForIncident(String incidentId);

  // -- Réserve (composition 100% locale, point 6) ------------------------

  /// Compose (via `lib/domain/reserve_composer.dart`) et persiste la
  /// réserve de [incidentId] à partir des derniers faits confirmés de
  /// chaque anomalie. Fonctionne intégralement hors ligne. Lève
  /// `NoConfirmedFactsException` si aucune anomalie n'a de faits confirmés,
  /// `LiabilityAttributionException` en dernier recours si un contenu
  /// interdit avait échappé à `confirmFacts` (défense en profondeur).
  Future<ReserveText> composeAndSaveReserve(
    String incidentId, {
    String templateVersion,
  });

  Future<ReserveText?> latestReserveText(String incidentId);

  // -- Preuves (photos, BL, PDF, audio - point 3) -------------------------

  /// Enregistre les métadonnées d'une preuve DÉJÀ écrite atomiquement sur le
  /// disque de l'appareil (le repository ne gère jamais l'écriture binaire
  /// elle-même - voir lib/data/local/evidence_storage.dart). Aucune preuve
  /// ne doit jamais être perdue sur coupure réseau ou échec IA (point 3/6) :
  /// cette méthode ne fait AUCUN appel réseau.
  Future<EvidenceAsset> registerEvidenceAsset(EvidenceAsset asset);

  Future<List<EvidenceAsset>> listEvidenceAssets(String incidentId);

  /// R1 (point 7 - "supprimer une photo avec confirmation") : supprime
  /// UNIQUEMENT la ligne de métadonnées `LocalEvidenceAssets`. Comme pour
  /// `deleteIncident`, le fichier binaire n'est PAS touché ici : l'appelant
  /// doit d'abord supprimer le fichier via
  /// `lib/data/local/evidence_storage.dart::EvidenceStorageService.deleteFile`
  /// (avec le `localFilePath` obtenu via `listEvidenceAssets`), puis appeler
  /// cette méthode. Ne lève pas si `assetId` est déjà inconnu (suppression
  /// idempotente).
  Future<void> deleteEvidenceAsset(String assetId);

  /// Recalcule `sha256`/`availabilityStatus` pour chaque preuve de
  /// [incidentId] en relisant le fichier local (détecte une preuve
  /// `missing`/`corrupted`, ex: après restauration de sauvegarde
  /// incomplète, point 9).
  Future<List<EvidenceAsset>> verifyEvidenceAssetsIntegrity(String incidentId);

  // -- File d'opérations IA (offline-first, point 6) ----------------------

  Future<AiQueueItem> enqueueAiOperation({
    required String incidentId,
    required AiOperationKind operationKind,
    required String payloadJson,
    required String idempotencyKey,
    String? issueId,
  });

  Future<List<AiQueueItem>> listPendingAiOperations();

  Future<AiQueueItem> markAiOperationInProgress(String id);

  Future<AiQueueItem> markAiOperationSucceeded(String id, {required String resultJson});

  Future<AiQueueItem> markAiOperationFailed(String id, {required String error});
}

/// Levée par `composeAndSaveReserve` quand aucune anomalie de l'incident n'a
/// encore de faits confirmés - miroir de
/// `backend/app/application/use_cases/generate_reserve.py::NoConfirmedFactsError`.
final class NoConfirmedFactsException implements Exception {
  const NoConfirmedFactsException(this.message);
  final String message;

  @override
  String toString() => 'NoConfirmedFactsException: $message';
}
