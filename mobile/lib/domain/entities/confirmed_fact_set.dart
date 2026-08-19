import 'package:reserveflash/domain/fact_set/confirmed_fact_data.dart';

/// Une révision de faits confirmés pour une anomalie donnée - miroir de
/// `backend/app/domain/entities.py::ConfirmedFactSet`. Historisée : une
/// nouvelle confirmation crée une nouvelle ligne, jamais une mutation en
/// place (invariant 6.3 - "une révision de faits confirmés invalide
/// automatiquement la réserve et le PDF précédents").
final class ConfirmedFactSet {
  const ConfirmedFactSet({
    required this.id,
    required this.issueId,
    required this.schemaVersion,
    required this.confirmedData,
    required this.confirmedAt,
    required this.revision,
    this.confirmedBy,
  });

  final String id;
  final String issueId;
  final String schemaVersion;
  final ConfirmedFactData confirmedData;
  final String? confirmedBy; // null si pas de compte (point 13).
  final DateTime confirmedAt;
  final int revision;
}
