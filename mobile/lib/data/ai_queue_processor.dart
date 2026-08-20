/// Traitement de la file `AiOperationQueue` (point 6 de la demande
/// corrective R1 - "fonctionnement offline") : la pièce qui relie
/// `lib/data/remote/ai_api_client.dart` (déjà posé, R2) et
/// `IncidentRepository.saveCandidateFactSet` (déjà posé, R2) pour que la
/// chaîne complète capture -> IA -> candidat -> revue fonctionne de bout en
/// bout.
///
/// "Si une opération IA nécessite Internet : elle passe en état pending,
/// rien n'est perdu, retry possible à la reconnexion." (docstring de
/// `lib/domain/entities/ai_queue_item.dart`). Ce fichier réalise ce
/// principe : chaque item `pending` est retenté au prochain appel de
/// [AiQueueProcessor.processPendingOperations] (déclenché par l'appelant -
/// écran juste après une capture, retour réseau, etc. - ce fichier ne
/// possède aucun timer/listener de connectivité lui-même, voir
/// `docs/GATE_R2_STATUS.md` pour ce qui reste à câbler).
///
/// Politique de retry : voir la docstring de `AiUnavailableException`/
/// `AiRateLimitedException` (`lib/domain/errors/domain_errors.dart`) -
/// "aucune boucle infinie de retries", "ne jamais bloquer l'utilisateur". Ce
/// fichier applique un disjoncteur simple et UNIFORME (même politique quelle
/// que soit la cause de l'échec - réseau transitoire ou sortie IA invalide) :
/// au-delà de [AiQueueProcessor.maxRetryCount] tentatives, un item n'est
/// plus retenté automatiquement, mais reste `pending` en base (rien n'est
/// supprimé ni marqué `failed` de façon définitive - pas encore d'écran pour
/// réarmer manuellement un item bloqué, limitation documentée). Une
/// politique plus fine (ex : ne jamais retenter un `AiInvalidOutputException`,
/// qui a peu de chances de réussir sur la même entrée) est un raffinement
/// possible, non nécessaire pour ce premier câblage bout en bout.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../domain/entities/ai_queue_item.dart';
import '../domain/entities/candidate_fact_set.dart';
import '../domain/entities/evidence_asset.dart';
import '../domain/repositories/incident_repository.dart';
import 'local/evidence_storage.dart';
import 'remote/ai_api_client.dart';

/// Voir docstring de fichier : disjoncteur de retry, appliqué uniformément.
const int defaultAiQueueMaxRetryCount = 5;

/// Miroir de la valeur par défaut `Settings.prompt_version`
/// (`backend/app/config.py`). V1 : pas encore synchronisée dynamiquement
/// depuis le backend (`GET /config`, `backend/app/api/routes/config.py`) -
/// limitation documentée, voir `docs/GATE_R2_STATUS.md`.
const String defaultExtractionPromptVersion = 'extraction_fr_v1';

/// Contrat du payload JSON minimal pour `AiOperationKind.transcribeAudio`
/// (point 14 - "payload minimal nécessaire, jamais un dump complet du
/// dossier") : UNE référence vers l'[EvidenceAsset] audio déjà capturé et
/// persisté sur le disque de l'appareil. Partagé entre l'écran qui met
/// l'opération en file (ex : `voice_description_screen.dart`) et
/// [AiQueueProcessor], pour que les deux s'accordent sur la même forme sans
/// dupliquer une chaîne magique de part et d'autre.
final class TranscribeAudioPayload {
  const TranscribeAudioPayload({required this.evidenceAssetId});

  factory TranscribeAudioPayload.fromJson(Map<String, dynamic> json) {
    return TranscribeAudioPayload(evidenceAssetId: json['evidence_asset_id'] as String);
  }

  final String evidenceAssetId;

  Map<String, dynamic> toJson() => <String, dynamic>{'evidence_asset_id': evidenceAssetId};

  String encode() => jsonEncode(toJson());
}

enum AiQueueProcessingOutcome { succeeded, failed, skipped }

/// Résultat agrégé d'un passage sur la file - destiné à l'appelant (écran,
/// futur listener de connectivité) qui peut vouloir afficher/journaliser un
/// résumé, sans exposer le détail interne de chaque item traité.
final class AiQueueProcessingSummary {
  const AiQueueProcessingSummary({
    required this.succeeded,
    required this.failed,
    required this.skipped,
  });

  final int succeeded;
  final int failed;
  final int skipped;

  int get total => succeeded + failed + skipped;
}

/// Traite les items `pending` de la file `AiOperationQueue` - un item à la
/// fois, séquentiellement (pas de parallélisme : simplicité V1, aucune
/// exigence de débit connue à ce stade).
///
/// Ne fait AUCUNE hypothèse sur le déclencheur (appelé explicitement après
/// une capture, un retour réseau détecté ailleurs dans l'app, etc.) -
/// stateless entre deux appels, hormis ce qui est déjà persisté par
/// [IncidentRepository] lui-même.
final class AiQueueProcessor {
  const AiQueueProcessor({
    required IncidentRepository incidentRepository,
    required AiApiClient aiApiClient,
    required EvidenceStorageService evidenceStorage,
    this.maxRetryCount = defaultAiQueueMaxRetryCount,
    this.extractionPromptVersion = defaultExtractionPromptVersion,
  })  : _incidentRepository = incidentRepository,
        _aiApiClient = aiApiClient,
        _evidenceStorage = evidenceStorage;

  final IncidentRepository _incidentRepository;
  final AiApiClient _aiApiClient;
  final EvidenceStorageService _evidenceStorage;
  final int maxRetryCount;
  final String extractionPromptVersion;

  /// Traite tous les items actuellement `pending` (un snapshot au moment de
  /// l'appel - un item mis en file pendant ce traitement n'est PAS repris
  /// dans le même passage, il attendra le prochain appel).
  Future<AiQueueProcessingSummary> processPendingOperations() async {
    final List<AiQueueItem> pending = await _incidentRepository.listPendingAiOperations();
    int succeeded = 0;
    int failed = 0;
    int skipped = 0;
    for (final AiQueueItem item in pending) {
      final AiQueueProcessingOutcome outcome = await _processOne(item);
      switch (outcome) {
        case AiQueueProcessingOutcome.succeeded:
          succeeded++;
          break;
        case AiQueueProcessingOutcome.failed:
          failed++;
          break;
        case AiQueueProcessingOutcome.skipped:
          skipped++;
          break;
      }
    }
    return AiQueueProcessingSummary(succeeded: succeeded, failed: failed, skipped: skipped);
  }

  Future<AiQueueProcessingOutcome> _processOne(AiQueueItem item) async {
    if (item.retryCount >= maxRetryCount) {
      // Disjoncteur : laissé `pending` SANS être touché (retryCount inchangé)
      // - toujours visible via listPendingAiOperations, jamais perdu, mais
      // plus retenté automatiquement (voir docstring de fichier).
      return AiQueueProcessingOutcome.skipped;
    }
    if (!_isSupported(item.operationKind)) {
      // extractFromPhoto/extractFromDocument : l'OCR on-device n'est pas
      // encore câblé (voir docs/GATE_R2_STATUS.md, "Reste à faire") -
      // laissé `pending` intact plutôt que de consommer un essai pour un
      // échec certain.
      return AiQueueProcessingOutcome.skipped;
    }

    await _incidentRepository.markAiOperationInProgress(item.id);
    try {
      final String resultJson = await _run(item);
      await _incidentRepository.markAiOperationSucceeded(item.id, resultJson: resultJson);
      return AiQueueProcessingOutcome.succeeded;
    } catch (e) {
      // Toute exception (typée AI_*, StateError de cohérence interne, ou
      // imprévue) requeue l'item en `pending` avec `retryCount + 1` (jamais
      // un `failed` définitif ici - c'est
      // `IncidentRepository.markAiOperationFailed` qui décide de cette
      // politique, voir sa docstring : "rien n'est perdu, retry possible").
      await _incidentRepository.markAiOperationFailed(item.id, error: e.toString());
      return AiQueueProcessingOutcome.failed;
    }
  }

  static bool _isSupported(AiOperationKind kind) => kind == AiOperationKind.transcribeAudio;

  Future<String> _run(AiQueueItem item) async {
    switch (item.operationKind) {
      case AiOperationKind.transcribeAudio:
        return _runTranscribeAudio(item);
      case AiOperationKind.extractFromPhoto:
      case AiOperationKind.extractFromDocument:
        // Ne devrait jamais être atteint : `_isSupported` filtre déjà ces
        // deux cas avant tout appel à `_run` (voir `_processOne`). Garde
        // défensive explicite plutôt qu'un comportement silencieux si cet
        // invariant est un jour cassé par erreur.
        throw StateError(
          '${item.operationKind} pas encore supporté par AiQueueProcessor '
          '(OCR on-device non câblé - voir docs/GATE_R2_STATUS.md).',
        );
    }
  }

  /// Pipeline complet d'une note vocale déjà capturée : transcription puis
  /// extraction de faits candidats puis persistance - `AiOperationKind`
  /// décrit la SOURCE de l'opération (une note vocale), pas un unique appel
  /// HTTP : il n'existe pas de kind "extraction depuis transcript" séparé
  /// car une transcription seule n'a aucune valeur pour la revue utilisateur
  /// (section 2.4 - candidat vs confirmé) sans être d'abord structurée en
  /// `CandidateFactData`.
  Future<String> _runTranscribeAudio(AiQueueItem item) async {
    final String? issueId = item.issueId;
    if (issueId == null) {
      // Un `CandidateFactSet` est toujours rattaché à une anomalie
      // (`IncidentRepository.saveCandidateFactSet`), jamais à un incident
      // entier - un item `transcribeAudio` sans `issueId` est une erreur de
      // l'appelant qui a mis l'opération en file (bug de câblage écran),
      // jamais un état attendu.
      throw StateError(
        'AiQueueItem ${item.id} (transcribeAudio) sans issueId : impossible '
        'de persister un CandidateFactSet (rattaché à une anomalie, jamais '
        'à un incident entier).',
      );
    }

    final TranscribeAudioPayload payload =
        TranscribeAudioPayload.fromJson(jsonDecode(item.payloadJson) as Map<String, dynamic>);

    final List<EvidenceAsset> assets =
        await _incidentRepository.listEvidenceAssets(item.incidentId);
    final EvidenceAsset asset = assets.firstWhere(
      (EvidenceAsset a) => a.id == payload.evidenceAssetId,
      orElse: () => throw StateError(
        "Preuve ${payload.evidenceAssetId} introuvable pour l'opération "
        '${item.id} (incident ${item.incidentId}).',
      ),
    );

    final Uint8List audioBytes = await _evidenceStorage.readBytes(asset);

    final AiTranscriptionResult transcription = await _aiApiClient.transcribe(
      audioBytes: audioBytes,
      mimeType: asset.mimeType,
    );

    final AiExtractionResult extraction = await _aiApiClient.extractCandidateFacts(
      transcript: transcription.text,
      promptVersion: extractionPromptVersion,
    );

    // `saveCandidateFactSet` réapplique `screenCandidateFactData` (défense
    // en profondeur, voir sa docstring) - ce processeur n'a pas à filtrer
    // lui-même le candidat reçu du backend.
    final CandidateFactSet saved = await _incidentRepository.saveCandidateFactSet(
      issueId: issueId,
      data: extraction.candidate,
      promptVersion: extraction.promptVersion,
      model: extraction.modelId,
    );

    return jsonEncode(<String, dynamic>{
      'transcript': transcription.text,
      'candidate_fact_set_id': saved.id,
    });
  }
}
