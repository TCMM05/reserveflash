/// Exceptions du domaine côté mobile - miroir de
/// `backend/app/domain/errors.py`. Portent un `code` stable, réutilisable par
/// l'UI (section 9.2/9.3), sans dépendre de Flutter/HTTP.
///
/// Depuis R0.1 (pivot Local-First), ces exceptions peuvent être levées
/// ENTIÈREMENT en local (le Reserve Composer tourne désormais sur l'appareil,
/// voir lib/domain/reserve_composer.dart) - elles ne sont plus uniquement des
/// miroirs d'erreurs renvoyées par le backend.
sealed class DomainException implements Exception {
  const DomainException(this.message);

  /// Code stable, indépendant de la langue du message (utilisable pour du
  /// routing UI ou de l'analytics safe).
  String get code;

  final String message;

  @override
  String toString() => '$code: $message';
}

final class UnconfirmedFactSetException extends DomainException {
  const UnconfirmedFactSetException(super.message);

  @override
  String get code => 'UNCONFIRMED_FACT_SET';
}

final class TemplateNotFoundException extends DomainException {
  const TemplateNotFoundException(super.message);

  @override
  String get code => 'TEMPLATE_NOT_FOUND';
}

/// Correctif R0.1 (point 8 de la demande corrective "Local-First") : levée
/// par `lib/domain/liability_guard.dart` quand un champ texte libre d'un
/// `ConfirmedFactData` contient une attribution de responsabilité, une
/// promesse d'indemnisation, une conclusion/qualification juridique, ou un
/// montant inventé. Voir la docstring de ce fichier pour le détail du bug
/// corrigé (identique côté backend : `app/domain/errors.py::
/// LiabilityAttributionError`).
final class LiabilityAttributionException extends DomainException {
  const LiabilityAttributionException(
    super.message, {
    required this.violationCode,
    required this.fieldName,
  });

  @override
  String get code => 'LIABILITY_ATTRIBUTION_BLOCKED';

  /// Une des clés de `LiabilityViolationCode` (voir liability_guard.dart) :
  /// LIABILITY_ATTRIBUTION, INDEMNIFICATION_PROMISE, LEGAL_CONCLUSION,
  /// INVENTED_AMOUNT, LEGAL_QUALIFICATION.
  final String violationCode;

  /// Nom du champ `ConfirmedFactData` fautif (ex: 'packagingCondition'), pour
  /// que l'UI puisse rouvrir précisément ce champ à la reformulation.
  final String fieldName;
}
