/// Une preuve capturée localement (photo, audio, bon de livraison, PDF
/// exporté) - miroir de `backend/app/domain/entities.py::EvidenceAsset`,
/// adapté au stockage 100% local (point 3 de la demande corrective) :
///
/// "Chaque pièce doit conserver au minimum : id, incident associé, type de
/// document, date/heure de capture, chemin local, SHA-256, statut de
/// disponibilité." Tous ces champs sont obligatoires ci-dessous (aucun
/// n'est nullable), à l'exception de `issueId` (une preuve peut concerner
/// l'incident entier, ex: un BL global) et `sha256` (calculé de façon
/// asynchrone immédiatement après écriture disque atomique, jamais avant -
/// voir lib/data/local/local_incident_repository.dart).
enum EvidenceAvailability { available, missing, corrupted }

enum EvidenceDocumentType { photo, audio, deliveryNote, exportedPdf }

final class EvidenceAsset {
  const EvidenceAsset({
    required this.id,
    required this.incidentId,
    required this.documentType,
    required this.localFilePath,
    required this.mimeType,
    required this.bytes,
    required this.capturedAtDevice,
    this.issueId,
    this.sha256,
    this.availabilityStatus = EvidenceAvailability.available,
  });

  final String id;
  final String incidentId;
  final String? issueId;
  final EvidenceDocumentType documentType;
  final String localFilePath;
  final String? sha256;
  final String mimeType;
  final int bytes;
  final DateTime capturedAtDevice;
  final EvidenceAvailability availabilityStatus;
}
