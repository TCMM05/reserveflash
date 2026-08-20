import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reserveflash/data/remote/ai_api_client.dart';
import 'package:reserveflash/domain/errors/domain_errors.dart';
import 'package:reserveflash/domain/value_objects/issue_type.dart';

/// Fausse implémentation de [AiHttpTransport] entièrement faite à la main
/// (voir la docstring de fichier de `lib/data/remote/ai_api_client.dart`
/// pour la justification : aucun SDK Flutter/Dart dans ce sandbox, donc
/// aucun mécanisme de mock spécifique à `package:dio` n'a pu être vérifié
/// par exécution ici) - miroir du rôle de `httpx.MockTransport` côté
/// backend (`backend/tests/infrastructure/test_openai_provider.py`).
class _FakeAiHttpTransport implements AiHttpTransport {
  _FakeAiHttpTransport({AiHttpResponse? response, AiTransportException? transportError})
      : _response = response,
        _transportError = transportError;

  final AiHttpResponse? _response;
  final AiTransportException? _transportError;

  String? lastPath;
  Map<String, dynamic>? lastBody;

  @override
  Future<AiHttpResponse> postJson(String path, Map<String, dynamic> body) async {
    lastPath = path;
    lastBody = body;
    if (_transportError != null) {
      throw _transportError;
    }
    return _response!;
  }
}

void main() {
  group('AiApiClient.transcribe', () {
    test('succès : construit AiTranscriptionResult depuis le corps JSON', () async {
      final _FakeAiHttpTransport transport = _FakeAiHttpTransport(
        response: const AiHttpResponse(
          statusCode: 200,
          body: <String, dynamic>{
            'text': 'Il manque un carton sur la palette.',
            'provider': 'openai',
            'model_id': 'whisper-1',
            'latency_ms': 842,
            'request_id': 'req-abc',
          },
        ),
      );
      final AiApiClient client = AiApiClient(transport);

      final AiTranscriptionResult result = await client.transcribe(
        audioBytes: Uint8ListFixture.sample,
        mimeType: 'audio/m4a',
      );

      expect(result.text, 'Il manque un carton sur la palette.');
      expect(result.provider, 'openai');
      expect(result.modelId, 'whisper-1');
      expect(result.latencyMs, 842);
      expect(result.requestId, 'req-abc');

      expect(transport.lastPath, '/v1/ai/transcribe');
      expect(transport.lastBody!['mime_type'], 'audio/m4a');
      expect(transport.lastBody!['audio_base64'], isA<String>());
    });

    test('panne réseau (transport) -> AiUnavailableException', () async {
      final _FakeAiHttpTransport transport = _FakeAiHttpTransport(
        transportError: const AiTransportException('connectionTimeout: délai dépassé'),
      );
      final AiApiClient client = AiApiClient(transport);

      await expectLater(
        client.transcribe(audioBytes: Uint8ListFixture.sample, mimeType: 'audio/m4a'),
        throwsA(isA<AiUnavailableException>()),
      );
    });
  });

  group('AiApiClient.extractCandidateFacts', () {
    test('succès : construit AiExtractionResult avec un CandidateFactData valide', () async {
      final _FakeAiHttpTransport transport = _FakeAiHttpTransport(
        response: const AiHttpResponse(
          statusCode: 200,
          body: <String, dynamic>{
            'candidate': <String, dynamic>{
              'issue_type_candidate': 'MISSING_QTY',
              'fields': <String, dynamic>{
                'expected_quantity': <String, dynamic>{
                  'value': 5,
                  'source': 'VOICE_TRANSCRIPT',
                  'confidence': 'HIGH',
                },
              },
              'requires_review': false,
              'clarification_question_id': null,
            },
            'provider': 'openai',
            'model_id': 'gpt-4o-mini',
            'prompt_version': 'extraction_fr_v1',
            'schema_version': 'candidate_fact_set.v1',
            'latency_ms': 1204,
            'request_id': 'req-xyz',
          },
        ),
      );
      final AiApiClient client = AiApiClient(transport);

      final AiExtractionResult result = await client.extractCandidateFacts(
        transcript: 'Il devait y avoir 5 radiateurs, il n\'y en a que 4.',
        promptVersion: 'extraction_fr_v1',
      );

      expect(result.candidate.issueTypeCandidate, IssueType.missingQty);
      expect(result.candidate.fields['expected_quantity']!.value, 5);
      expect(result.provider, 'openai');
      expect(result.schemaVersion, 'candidate_fact_set.v1');
      expect(transport.lastPath, '/v1/ai/extract');
      expect(transport.lastBody!.containsKey('document_text'), isFalse);
      expect(transport.lastBody!['transcript'], isNotNull);
      expect(transport.lastBody!['prompt_version'], 'extraction_fr_v1');
    });

    for (final (int status, String code, Type expected) in <(int, String, Type)>[
      (503, 'AI_UNAVAILABLE', AiUnavailableException),
      (422, 'AI_INVALID_OUTPUT', AiInvalidOutputException),
      (429, 'RATE_LIMITED', AiRateLimitedException),
    ]) {
      test('HTTP $status/$code -> $expected', () async {
        final _FakeAiHttpTransport transport = _FakeAiHttpTransport(
          response: AiHttpResponse(
            statusCode: status,
            body: <String, dynamic>{
              'code': code,
              'message': 'erreur simulée',
              'trace_id': 'trace-1',
              'details': null,
            },
          ),
        );
        final AiApiClient client = AiApiClient(transport);

        await expectLater(
          client.extractCandidateFacts(
            transcript: 'texte',
            promptVersion: 'extraction_fr_v1',
          ),
          throwsA(isA<DomainException>().having((e) => e.runtimeType, 'type', expected)),
        );
      });
    }

    test(
      'HTTP 500 avec un code non catégorisé (ex: INTERNAL_ERROR) -> '
      'traité comme transitoire (AiUnavailableException)',
      () async {
        final _FakeAiHttpTransport transport = _FakeAiHttpTransport(
          response: const AiHttpResponse(
            statusCode: 500,
            body: <String, dynamic>{'code': 'INTERNAL_ERROR', 'message': 'oups'},
          ),
        );
        final AiApiClient client = AiApiClient(transport);

        await expectLater(
          client.extractCandidateFacts(transcript: 't', promptVersion: 'extraction_fr_v1'),
          throwsA(isA<AiUnavailableException>()),
        );
      },
    );

    test(
      'HTTP 400 VALIDATION_ERROR -> AiRequestFailedException (pas masqué en '
      "'IA indisponible')",
      () async {
        final _FakeAiHttpTransport transport = _FakeAiHttpTransport(
          response: const AiHttpResponse(
            statusCode: 400,
            body: <String, dynamic>{'code': 'VALIDATION_ERROR', 'message': 'payload invalide'},
          ),
        );
        final AiApiClient client = AiApiClient(transport);

        await expectLater(
          client.extractCandidateFacts(transcript: 't', promptVersion: 'extraction_fr_v1'),
          throwsA(
            isA<AiRequestFailedException>().having(
              (e) => e.httpStatusCode,
              'httpStatusCode',
              400,
            ),
          ),
        );
      },
    );

    test('réponse 2xx sans corps JSON exploitable -> AiRequestFailedException', () async {
      final _FakeAiHttpTransport transport = _FakeAiHttpTransport(
        response: const AiHttpResponse(statusCode: 200, body: null),
      );
      final AiApiClient client = AiApiClient(transport);

      await expectLater(
        client.extractCandidateFacts(transcript: 't', promptVersion: 'extraction_fr_v1'),
        throwsA(isA<AiRequestFailedException>()),
      );
    });
  });
}

/// Petit fixture réutilisable - le contenu binaire lui-même n'a aucune
/// importance pour ces tests (le transport est entièrement factice), seul
/// compte le fait qu'il soit correctement encodé en base64 dans le corps
/// envoyé (vérifié ci-dessus).
abstract final class Uint8ListFixture {
  static final Uint8List sample = Uint8List.fromList(List<int>.generate(16, (i) => i));
}
