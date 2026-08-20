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

/// R2 : levées par `lib/data/remote/ai_api_client.dart` lors d'un appel à
/// `/v1/ai/transcribe`/`/v1/ai/extract` - miroir mobile de
/// `backend/app/domain/errors.py::AIUnavailableError`/`AIInvalidOutputError`/
/// `AIRateLimitedError` (mêmes `code`, pour que le corps d'erreur JSON du
/// backend - `{"code": ..., "message": ..., "trace_id": ...}`, voir
/// `backend/app/api/errors.py` - se retraduise directement en exception
/// typée côté mobile).
///
/// Distinction utile pour la file `AiOperationQueue` (traitement online/
/// offline) : [AiUnavailableException] et [AiRateLimitedException] couvrent
/// des pannes transitoires (réseau, provider indisponible, quota) où un
/// nouveau essai plus tard a du sens ; [AiInvalidOutputException] couvre un
/// échec sémantique du pipeline IA lui-même (sortie non conforme même après
/// la tentative de réparation contrôlée côté backend) - un nouvel essai
/// immédiat sur la même entrée a peu de chances de réussir, mais ce fichier
/// ne décide PAS de politique de retry : il se contente de porter
/// l'information, la décision reste à la couche qui traite la file (section
/// "Échec IA" de la demande R2 - "aucune boucle infinie de retries", "ne
/// jamais bloquer l'utilisateur").
final class AiUnavailableException extends DomainException {
  const AiUnavailableException(super.message);

  @override
  String get code => 'AI_UNAVAILABLE';
}

final class AiInvalidOutputException extends DomainException {
  const AiInvalidOutputException(super.message);

  @override
  String get code => 'AI_INVALID_OUTPUT';
}

final class AiRateLimitedException extends DomainException {
  const AiRateLimitedException(super.message);

  @override
  String get code => 'RATE_LIMITED';
}

/// Toute autre erreur de requête (validation du payload envoyé, erreur
/// interne backend, réponse imprévue) - distincte des trois ci-dessus pour
/// ne jamais masquer un bug côté appelant sous un code "IA indisponible".
final class AiRequestFailedException extends DomainException {
  const AiRequestFailedException(super.message, {required this.httpStatusCode});

  @override
  String get code => 'AI_REQUEST_FAILED';

  /// Code HTTP réel reçu (ou -1 si aucune réponse n'a été reçue mais que ce
  /// n'est pas non plus un cas réseau couvert par [AiUnavailableException] -
  /// ex: réponse reçue mais corps illisible).
  final int httpStatusCode;
}
