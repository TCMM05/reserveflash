import 'package:reserveflash/domain/value_objects/issue_type.dart';

/// Une anomalie déclarée au sein d'un incident (F05, section 2.1) - miroir
/// allégé de `backend/app/domain/entities.py::Issue`. Introduite en R0.1 :
/// nécessaire dès que la composition de réserve tourne en local, puisque
/// `ConfirmedFactData`/`ReserveText` sont rattachés à une anomalie, pas
/// directement à l'incident (section 2.5).
final class Issue {
  const Issue({
    required this.id,
    required this.incidentId,
    required this.issueType,
    this.sortOrder = 0,
    this.status = 'open',
  });

  final String id;
  final String incidentId;
  final IssueType issueType;
  final int sortOrder;
  final String status;
}
