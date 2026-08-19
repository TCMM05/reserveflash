import 'package:reserveflash/domain/value_objects/incident_status.dart';

/// Miroir allégé de `backend/app/domain/entities.py::Incident` - seuls les
/// champs nécessaires à l'affichage et à la navigation locale sont repris
/// ici.
///
/// Depuis R0.1 (pivot Local-First) : cette entité EST la source de vérité
/// (stockée dans `LocalIncidents`, voir lib/data/local/app_database.dart) -
/// il n'existe plus de version serveur faisant autorité en V1 (point 1/11).
/// `organizationId` est nullable : aucune création de compte cloud n'est
/// requise pour démarrer un incident (point 13).
final class Incident {
  const Incident({
    required this.id,
    required this.status,
    required this.occurredAt,
    required this.localCreatedAt,
    this.organizationId,
    this.supplierName,
    this.carrierName,
    this.deliveryRef,
    this.notes,
    this.serverCreatedAt,
    this.archived = false,
  });

  final String id;
  final String? organizationId;
  final IncidentStatus status;
  final DateTime occurredAt;
  final DateTime localCreatedAt;
  final DateTime? serverCreatedAt;
  final String? supplierName;
  final String? carrierName;
  final String? deliveryRef;
  final String? notes;
  final bool archived;

  Incident copyWith({IncidentStatus? status, bool? archived}) {
    return Incident(
      id: id,
      organizationId: organizationId,
      status: status ?? this.status,
      occurredAt: occurredAt,
      localCreatedAt: localCreatedAt,
      serverCreatedAt: serverCreatedAt,
      supplierName: supplierName,
      carrierName: carrierName,
      deliveryRef: deliveryRef,
      notes: notes,
      archived: archived ?? this.archived,
    );
  }

  /// Miroir de `Incident.transition_to` (backend) : lève si la transition
  /// n'est pas autorisée par le graphe section 2.2. Utilisé côté client pour
  /// désactiver une action avant même l'appel réseau (feedback immédiat,
  /// section 3.1).
  Incident transitionTo(IncidentStatus target) {
    if (!status.canTransitionTo(target)) {
      throw StateError('Transition ${status.wireValue} -> ${target.wireValue} interdite.');
    }
    return copyWith(status: target);
  }
}
