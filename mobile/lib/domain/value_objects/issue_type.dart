/// Types d'anomalie déclarables (F05, section 2.1). Miroir exact de
/// `backend/app/domain/value_objects.py::IssueType` - toute divergence entre
/// les deux est un bug (les valeurs `wireValue` doivent matcher la sortie
/// JSON de l'API).
enum IssueType {
  packagingDamage('PACKAGING_DAMAGE'),
  productDamage('PRODUCT_DAMAGE'),
  missingQty('MISSING_QTY'),
  wrongQty('WRONG_QTY'),
  wrongProduct('WRONG_PRODUCT'),
  visibleNonconformity('VISIBLE_NONCONFORMITY'),
  other('OTHER');

  const IssueType(this.wireValue);

  /// Valeur exacte échangée avec l'API (schemas/confirmed_fact_set.v1.schema.json).
  final String wireValue;

  static IssueType fromWire(String value) {
    return IssueType.values.firstWhere(
      (candidate) => candidate.wireValue == value,
      orElse: () => throw ArgumentError('IssueType inconnu: $value'),
    );
  }
}
