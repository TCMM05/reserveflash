/// Client HTTP vers les routes `/v1/ai/*` du backend ReserveFlash - miroir
/// mobile de `backend/app/api/routes/ai.py`.
///
/// Flux imposé par le pivot Local-First (`docs/adr/0002-local-first-pivot.md`,
/// points 4/5 de la demande corrective) : Flutter -> Backend ReserveFlash ->
/// OpenAI -> Backend -> Flutter. Ce client n'appelle JAMAIS OpenAI
/// directement (aucune clé OpenAI n'est ni ne doit être embarquée dans
/// l'app - voir `mobile/README.md`, `docs/security.md`) ; il ne connaît que
/// l'URL du backend ReserveFlash lui-même (voir
/// `lib/core/config/backend_config.dart`).
///
/// Ne persiste rien : c'est le rôle de
/// `lib/data/local/local_incident_repository.dart::saveCandidateFactSet`
/// (candidats), l'appelant restant responsable de la suite (queue
/// `AiOperationQueue`, écran de revue).
///
/// [AiHttpTransport] est une frontière volontairement minimale au-dessus de
/// `package:dio` : ce sandbox ne dispose d'aucun SDK Flutter/Dart (voir
/// `mobile/README.md`) et ne peut donc pas vérifier par exécution le
/// comportement exact des mécanismes de mock internes à `dio` (adapters
/// HTTP). En testant contre cette interface plutôt que contre `Dio`
/// directement, `test/data/remote/ai_api_client_test.dart` peut fournir une
/// implémentation entièrement faite à la main, sans dépendre d'un détail de
/// version de `dio` - même logique que le choix de `httpx` brut (plutôt que
/// le SDK `openai`) pour `backend/app/infrastructure/ai/openai_provider.py`.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../domain/errors/domain_errors.dart';
import '../../domain/fact_set/candidate_fact_data.dart';

/// Résultat d'une transcription - miroir de
/// `backend/app/application/ports.py::TranscriptionResult`.
final class AiTranscriptionResult {
  const AiTranscriptionResult({
    required this.text,
    required this.provider,
    required this.modelId,
    required this.latencyMs,
    this.requestId,
  });

  final String text;
  final String provider;
  final String modelId;
  final int latencyMs;
  final String? requestId;
}

/// Résultat d'une extraction - miroir de
/// `backend/app/application/ports.py::ExtractionResult`. `candidate` a déjà
/// été filtré côté backend par `screen_candidate_fact_data` (point d'entrée
/// unique, voir `backend/app/api/routes/ai.py`) - l'appelant mobile DOIT
/// néanmoins réappliquer
/// `lib/domain/candidate_guard.dart::screenCandidateFactData` avant toute
/// persistance (défense en profondeur, même principe que partout ailleurs
/// dans ce projet - voir `LocalIncidentRepository.saveCandidateFactSet`).
final class AiExtractionResult {
  const AiExtractionResult({
    required this.candidate,
    required this.provider,
    required this.modelId,
    required this.promptVersion,
    required this.schemaVersion,
    required this.latencyMs,
    this.requestId,
  });

  final CandidateFactData candidate;
  final String provider;
  final String modelId;
  final String promptVersion;
  final String schemaVersion;
  final int latencyMs;
  final String? requestId;
}

/// Réponse HTTP brute, décodée en JSON quand c'est possible - le
/// contrat que [AiApiClient] attend de tout [AiHttpTransport], réel ou
/// factice.
final class AiHttpResponse {
  const AiHttpResponse({required this.statusCode, required this.body});

  final int statusCode;

  /// `null` si le corps de la réponse n'était pas un objet JSON exploitable
  /// (ex: page d'erreur HTML d'un proxy, corps vide).
  final Map<String, dynamic>? body;
}

/// Erreur de TRANSPORT (réseau) - jamais une erreur applicative, celle-ci
/// étant portée par [AiHttpResponse.statusCode]/[AiHttpResponse.body].
/// Recouvre : timeout, hôte injoignable, certificat TLS invalide, requête
/// annulée.
final class AiTransportException implements Exception {
  const AiTransportException(this.message);
  final String message;

  @override
  String toString() => 'AiTransportException: $message';
}

/// Frontière HTTP minimale utilisée par [AiApiClient] (voir docstring de
/// fichier pour la justification de cette abstraction).
abstract interface class AiHttpTransport {
  /// Envoie [body] en JSON vers [path]. Doit renvoyer un [AiHttpResponse]
  /// pour TOUT code HTTP reçu (y compris 4xx/5xx) - seule une véritable
  /// erreur de transport (pas de réponse HTTP du tout) doit lever
  /// [AiTransportException].
  Future<AiHttpResponse> postJson(String path, Map<String, dynamic> body);
}

/// Implémentation réelle de [AiHttpTransport], au-dessus de `package:dio`.
/// Construite/injectée par `lib/core/providers/app_providers.dart` - jamais
/// instanciée directement par un écran ou un service (même principe de
/// frontière stricte que `IncidentRepository`/`LocalIncidentRepository`).
final class DioAiHttpTransport implements AiHttpTransport {
  const DioAiHttpTransport(this._dio);

  final Dio _dio;

  @override
  Future<AiHttpResponse> postJson(String path, Map<String, dynamic> body) async {
    try {
      final Response<dynamic> response = await _dio.post<dynamic>(
        path,
        data: body,
        options: Options(
          contentType: Headers.jsonContentType,
          // On veut TOUJOURS récupérer la réponse (y compris 4xx/5xx) pour
          // que AiApiClient puisse lire le corps d'erreur JSON structuré
          // ({"code", "message", ...} - voir backend/app/api/errors.py) et
          // le retraduire en exception typée lui-même, plutôt que de
          // dépendre du mécanisme d'exception générique de dio pour les
          // erreurs HTTP.
          validateStatus: (_) => true,
        ),
      );
      final Object? data = response.data;
      return AiHttpResponse(
        statusCode: response.statusCode ?? -1,
        body: data is Map<String, dynamic> ? data : null,
      );
    } on DioException catch (e) {
      // Ici, uniquement les échecs de TRANSPORT (validateStatus ci-dessus
      // empêche dio de lever pour un simple code HTTP d'erreur) : timeout,
      // hôte injoignable, certificat invalide, requête annulée.
      throw AiTransportException('${e.type.name}: ${e.message ?? e.error ?? 'erreur inconnue'}');
    }
  }
}

final class AiApiClient {
  const AiApiClient(this._transport);

  final AiHttpTransport _transport;

  /// POST /v1/ai/transcribe. [audioBytes] doit être UNIQUEMENT l'extrait
  /// strictement nécessaire (voir docstring backend de
  /// `TranscribeAudioRequest` - "jamais un enregistrement complet non
  /// pertinent") : c'est à l'appelant de garantir cette minimisation avant
  /// d'appeler cette méthode.
  Future<AiTranscriptionResult> transcribe({
    required Uint8List audioBytes,
    required String mimeType,
  }) async {
    final Map<String, dynamic> body = await _post('/v1/ai/transcribe', <String, dynamic>{
      'audio_base64': base64Encode(audioBytes),
      'mime_type': mimeType,
    });
    return AiTranscriptionResult(
      text: body['text'] as String,
      provider: body['provider'] as String,
      modelId: body['model_id'] as String,
      latencyMs: body['latency_ms'] as int,
      requestId: body['request_id'] as String?,
    );
  }

  /// POST /v1/ai/extract. [documentText]/[transcript] sont déjà du texte
  /// (OCR/transcription) - jamais une image/un audio brut envoyé "au cas
  /// où" (mêmes principes que côté backend).
  Future<AiExtractionResult> extractCandidateFacts({
    String? documentText,
    String? transcript,
    required String promptVersion,
  }) async {
    final Map<String, dynamic> body = await _post('/v1/ai/extract', <String, dynamic>{
      if (documentText != null) 'document_text': documentText,
      if (transcript != null) 'transcript': transcript,
      'prompt_version': promptVersion,
    });
    return AiExtractionResult(
      candidate: CandidateFactData.fromJson(body['candidate'] as Map<String, dynamic>),
      provider: body['provider'] as String,
      modelId: body['model_id'] as String,
      promptVersion: body['prompt_version'] as String,
      schemaVersion: body['schema_version'] as String,
      latencyMs: body['latency_ms'] as int,
      requestId: body['request_id'] as String?,
    );
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> data) async {
    final AiHttpResponse response;
    try {
      response = await _transport.postJson(path, data);
    } on AiTransportException catch (e) {
      throw AiUnavailableException('Backend ReserveFlash injoignable ($path) : ${e.message}.');
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final Map<String, dynamic>? body = response.body;
      if (body == null) {
        throw AiRequestFailedException(
          'Réponse ${response.statusCode} sans corps JSON exploitable sur $path.',
          httpStatusCode: response.statusCode,
        );
      }
      return body;
    }
    throw _mapErrorResponse(response, path: path);
  }

  /// Retraduit l'enveloppe d'erreur backend (`{"code", "message", ...}` -
  /// voir `backend/app/api/errors.py`) en exception typée du domaine
  /// mobile, même taxonomie que `backend/app/domain/errors.py`.
  DomainException _mapErrorResponse(AiHttpResponse response, {required String path}) {
    final Map<String, dynamic>? body = response.body;
    final String code = (body?['code'] as String?) ?? 'HTTP_ERROR';
    final String message =
        (body?['message'] as String?) ?? 'Erreur backend (${response.statusCode}) sur $path.';
    switch (code) {
      case 'AI_UNAVAILABLE':
        return AiUnavailableException(message);
      case 'AI_INVALID_OUTPUT':
        return AiInvalidOutputException(message);
      case 'RATE_LIMITED':
        return AiRateLimitedException(message);
      default:
        if (response.statusCode >= 500) {
          // Panne serveur non catégorisée (ex: INTERNAL_ERROR) : traitée
          // comme transitoire, même politique que AI_UNAVAILABLE - un
          // nouvel essai plus tard a du sens.
          return AiUnavailableException(message);
        }
        return AiRequestFailedException(message, httpStatusCode: response.statusCode);
    }
  }
}
