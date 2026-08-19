import 'package:reserveflash/domain/value_objects/issue_type.dart';

/// Miroir Dart de `schemas/confirmed_fact_set.v1.schema.json` /
/// `backend/app/domain/fact_set.py::ConfirmedFactData`.
///
/// GATE zéro invention (section 2.4) : cette classe ne peut être construite
/// qu'avec `userConfirmed = true` (voir constructeur) - un jeu de faits non
/// confirmé n'a pas de représentation valide dans le type système, donc pas
/// de risque de l'envoyer par erreur au composeur de réserve.
///
/// Depuis R0.1 (pivot Local-First, point 6 - génération du dossier hors
/// ligne) : F10 "Composer la réserve descriptive" tourne DÉSORMAIS sur
/// l'appareil (voir `lib/domain/reserve_composer.dart`), pas uniquement côté
/// backend. Le backend conserve sa propre implémentation du même algorithme
/// (`backend/app/domain/reserve_composer.py`) comme référence/valeur de
/// secours pour un futur mode cloud (section 12 de la demande corrective) -
/// les deux DOIVENT rester alignées (voir docs/adr/0002-local-first-pivot.md).
final class ConfirmedFactData {
  ConfirmedFactData({
    required this.issueType,
    this.productLabel,
    this.productReference,
    this.expectedQuantity,
    this.receivedQuantity,
    this.affectedQuantity,
    this.packagingCondition,
    this.productCondition,
    this.locationOnItem,
    this.userUncertainty = false,
    this.unknownFields = const <String>[],
  }) {
    for (final double? quantity in <double?>[
      expectedQuantity,
      receivedQuantity,
      affectedQuantity,
    ]) {
      if (quantity != null && quantity < 0) {
        throw ArgumentError('Les quantités ne peuvent pas être négatives.');
      }
    }
  }

  final IssueType issueType;
  final String? productLabel;
  final String? productReference;
  final double? expectedQuantity;
  final double? receivedQuantity;
  final double? affectedQuantity;
  final String? packagingCondition;
  final String? productCondition;
  final String? locationOnItem;
  final bool userUncertainty;
  final List<String> unknownFields;

  /// `user_confirmed` est toujours `true` pour cette classe : c'est un
  /// invariant de type, pas un champ mutable (invariant section 6.3).
  bool get userConfirmed => true;

  /// Calculée par code UNIQUEMENT (invariant 6.3), jamais saisie par
  /// l'utilisateur ni par un LLM. Depuis R0.1, cette valeur est celle
  /// effectivement utilisée par le Reserve Composer local (voir
  /// `lib/domain/templates/fr_v1.dart`) pour générer la réserve hors ligne ;
  /// elle n'est jamais transmise dans le payload de confirmation (F09 ->
  /// POST /incidents/{id}/facts/confirm), qui reste le seul canal réseau
  /// optionnel de cette classe.
  double? get missingQuantity {
    final double? expected = expectedQuantity;
    final double? received = receivedQuantity;
    if (expected == null || received == null) {
      return null;
    }
    // Arrondi à 6 décimales, comme `app/domain/fact_set.py::
    // ConfirmedFactData.missing_quantity` (Python `round(x, 6)`), pour que
    // le texte de réserve généré sur l'appareil soit identique bit-à-bit à
    // celui que produirait un recalcul serveur à partir des mêmes faits.
    final double raw = expected - received;
    return (raw * 1e6).round() / 1e6;
  }

  bool isFieldUnknown(String fieldName) => unknownFields.contains(fieldName);

  /// Payload JSON envoyé à POST /incidents/{id}/facts/confirm (section 9.1).
  /// `user_confirmed` n'est PAS inclus : le serveur l'impose (cette route
  /// EST l'acte de confirmation, F09).
  Map<String, dynamic> toConfirmPayload() {
    return <String, dynamic>{
      'issue_type': issueType.wireValue,
      if (productLabel != null) 'product_label': productLabel,
      if (productReference != null) 'product_reference': productReference,
      if (expectedQuantity != null) 'expected_quantity': expectedQuantity,
      if (receivedQuantity != null) 'received_quantity': receivedQuantity,
      if (affectedQuantity != null) 'affected_quantity': affectedQuantity,
      if (packagingCondition != null) 'packaging_condition': packagingCondition,
      if (productCondition != null) 'product_condition': productCondition,
      if (locationOnItem != null) 'location_on_item': locationOnItem,
      'user_uncertainty': userUncertainty,
      'unknown_fields': unknownFields,
    };
  }
}
