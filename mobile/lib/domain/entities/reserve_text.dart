/// Réserve composée persistée - miroir de
/// `backend/app/domain/entities.py::ReserveText`. Le texte a déjà traversé
/// `lib/domain/reserve_composer.dart` (donc `lib/domain/liability_guard.dart`)
/// avant d'exister sous cette forme : aucune ligne de cette entité ne peut
/// contenir de contenu interdit (section 2.4, correctif R0.1 point 8).
final class ReserveText {
  const ReserveText({
    required this.id,
    required this.incidentId,
    required this.templateVersion,
    required this.confirmedFactRevision,
    required this.text,
    required this.sha256,
    required this.createdAt,
  });

  final String id;
  final String incidentId;
  final String templateVersion;
  final int confirmedFactRevision;
  final String text;
  final String sha256;
  final DateTime createdAt;
}
