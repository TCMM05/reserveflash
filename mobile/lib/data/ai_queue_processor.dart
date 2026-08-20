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
///
/// Optimisation coût IA (deux points, ajoutés après le premier câblage) :
///
/// 1. **Une note vocale n'est JAMAIS transcrite deux fois pour produire un
///    seul candidat.** `AiOperationKind.transcribeAudio` ne fait QUE
///    transcrire, puis met en file une opération séparée
///    (`extractFromTranscript`, payload = le transcript déjà obtenu) pour
///    l'extraction. Si l'extraction échoue et doit être retentée (réseau,
///    quota...), seul CET appel - déjà gratuit, le transcript est en main -
///    est refait : la transcription déjà payée en tokens n'est jamais
///    reperdue. Avant ce découpage, un échec d'extraction après une
///    transcription réussie faisait retenter les DEUX appels au prochain
///    passage, gaspillant les tokens de transcription à chaque tentative.
/// 2. **`IncidentRepository.enqueueAiOperation` est idempotent par
///    `idempotencyKey`** (voir sa docstring) : une mise en file en double de
///    la même opération (double-tap, retry applicatif) ne déclenche jamais
///    deux appels IA payants pour un contenu identique.
///
/// Conséquence pour [AiQueueProcessor.processPendingOperations] : une
/// opération `transcribeAudio` traitée avec succès crée un NOUVEL item
/// `pending` (`extractFromTranscript`) - ce fichier boucle donc sur
/// plusieurs "rounds" au sein d'un même appel (voir sa docstring) pour que
/// la chaîne complète progresse en un seul appel côté appelant (écran),
/// plutôt que d'exiger un deuxième appel explicite pour l'étape suivante.
///
/// OCR document (R2, lot `document_capture_screen.dart`) : `_runExtractFromDocument`
/// ne suit PAS ce découpage en deux étapes - voir la docstring
/// d'[ExtractFromDocumentPayload] pour la raison (OCR on-device gratuit,
/// contrairement à la transcription audio payante).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../domain/entities/ai_queue_item.dart';
import '../domain/entities/candidate_fact_set.dart';
import '../domain/entities/evidence_asset.dart';
import '../domain/repositories/incident_repository.dart';
import 'local/evidence_storage.dart';
import 'local/ocr_service.dart';
import 'remote/ai_api_client.dart';

/// Voir docstring de fichier : disjoncteur de retry, appliqué uniformément.
/// Volontairement bas (retour d'équipe, exigence coût IA point 7 - "jamais
/// de boucle automatique", "une erreur persistante doit basculer vers
/// saisie manuelle/UNKNOWN") : tant que `facts_review_screen.dart` ne
/// consomme pas encore le statut de la file pour proposer cette bascule
/// manuelle explicitement (voir docs/GATE_R2_STATUS.md, "Reste à faire"),
/// ce disjoncteur reste la seule protection contre un item qui resterait
/// silencieusement retenté indéfiniment - une valeur basse limite le
/// nombre d'appels IA payants gaspillés sur une source qui échoue de façon
/// persistante, en attendant cette bascule UI réelle.
const int defaultAiQueueMaxRetryCount = 2;

/// Version du pipeline mobile de traitement IA (transcription + extraction)
/// - à incrémenter si sa logique change de façon à invalider un résultat
/// déjà obtenu avec une version antérieure. Fait partie de la clé
/// d'idempotence (voir [aiOperationIdempotencyKey]) - composition imposée
/// par le retour d'équipe (exigence coût IA, point 8) :
/// `incident_id + operation_type + source_hash + pipeline_version`.
const String aiPipelineVersion = 'ai_pipeline.v1';

/// Construit la clé d'idempotence d'une opération IA - voir
/// [aiPipelineVersion]. [sourceHash] doit être une empreinte STABLE de la
/// donnée source de CETTE étape (le SHA-256 déjà calculé de l'audio pour
/// `transcribeAudio`, un SHA-256 du texte transcrit pour
/// `extractFromTranscript`, etc.), jamais un identifiant généré aléatoirement
/// à chaque appel (un id aléatoire romprait toute déduplication réelle).
/// Utilisée par TOUS les points de mise en file (écran, ce processeur) pour
/// que deux mises en file de la même opération sur la même source ne créent
/// jamais un doublon qui déclencherait un appel IA payant superflu (voir
/// `IncidentRepository.enqueueAiOperation`, idempotent par cette clé).
String aiOperationIdempotencyKey({
  required String incidentId,
  required AiOperationKind operationKind,
  required String sourceHash,
  String pipelineVersion = aiPipelineVersion,
}) {
  return '$incidentId:${operationKind.name}:$sourceHash:$pipelineVersion';
}

/// SHA-256 hexadécimal d'un texte - utilisé comme `sourceHash` pour les
/// opérations dont la source est déjà du texte (ex : `extractFromTranscript`,
/// dont la source est le transcript lui-même, pas un fichier sur disque).
String sha256OfText(String text) => sha256.convert(utf8.encode(text)).toString();

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

/// Contrat du payload JSON pour `AiOperationKind.extractFromTranscript` -
/// contient directement le texte du transcript (pas une référence à
/// relire ailleurs) : ce texte EST la donnée minimale nécessaire à cette
/// étape (point 14), le récupérer par référence à l'item `transcribeAudio`
/// d'origine n'apporterait aucun bénéfice et ajouterait une indirection.
final class ExtractFromTranscriptPayload {
  const ExtractFromTranscriptPayload({required this.transcript});

  factory ExtractFromTranscriptPayload.fromJson(Map<String, dynamic> json) {
    return ExtractFromTranscriptPayload(transcript: json['transcript'] as String);
  }

  final String transcript;

  Map<String, dynamic> toJson() => <String, dynamic>{'transcript': transcript};

  String encode() => jsonEncode(toJson());
}

/// Contrat du payload JSON pour `AiOperationKind.extractFromDocument` (R2,
/// lot OCR `document_capture_screen.dart`) - contient UNE référence vers
/// l'[EvidenceAsset] photo (bon de livraison) déjà capturé et persisté sur
/// le disque de l'appareil (point 14 - payload minimal), jamais le texte OCR
/// lui-même : contrairement à l'audio (transcription payante, séparée de
/// l'extraction pour ne jamais la refaire inutilement - voir docstring de
/// fichier), l'OCR tourne ENTIÈREMENT sur l'appareil (ML Kit, aucun coût IA,
/// aucun appel réseau) - il est donc relancé à chaque tentative de CET item
/// sans qu'il soit nécessaire de le séparer en une étape distincte comme
/// `transcribeAudio`/`extractFromTranscript` : seul l'appel réseau
/// d'extraction (`/v1/ai/extract`, payant) a besoin d'être retentable
/// indépendamment, et il l'est déjà (retry de CET item unique).
final class ExtractFromDocumentPayload {
  const ExtractFromDocumentPayload({required this.evidenceAssetId});

  factory ExtractFromDocumentPayload.fromJson(Map<String, dynamic> json) {
    return ExtractFromDocumentPayload(evidenceAssetId: json['evidence_asset_id'] as String);
  }

  final String evidenceAssetId;

  Map<String, dynamic> toJson() => <String, dynamic>{'evidence_asset_id': evidenceAssetId};

  String encode() => jsonEncode(toJson());
}

enum AiQueueProcessingOutcome { succeeded, failed, skipped }

/// Nombre maximal de "rounds" par appel à
/// [AiQueueProcessor.processPendingOperations] (voir sa docstring) - garde
/// bornée, généreuse par rapport à la profondeur réelle de chaîne connue à
/// ce jour (2 : transcribeAudio -> extractFromTranscript), pour ne jamais
/// boucler indéfiniment si une future opération créait elle-même une chaîne
/// plus longue par erreur.
const int defaultAiQueueMaxRoundsPerCall = 5;

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

/// Repli utilisé quand aucun [OcrService] n'est fourni explicitement au
/// constructeur d'[AiQueueProcessor] - `ocrService` est optionnel (plutôt
/// que `required`) précisément pour ça : ne pas casser tous les appelants
/// existants (production ET tests) qui construisaient `AiQueueProcessor`
/// avant l'ajout du lot OCR (R2) et n'exercent jamais
/// `extractFromDocument`. Lève une erreur explicite si jamais utilisée pour
/// de vrai, plutôt qu'un silence trompeur - `lib/core/providers/app_providers.dart`
/// fournit toujours le vrai [MlKitOcrService] en production.
final class _UnconfiguredOcrService implements OcrService {
  const _UnconfiguredOcrService();

  @override
  Future<String> recognizeText(String imagePath) {
    throw StateError(
      'AiQueueProcessor construit sans OcrService explicite, mais '
      'extractFromDocument a été appelé - fournir ocrService: au '
      'constructeur (voir lib/core/providers/app_providers.dart).',
    );
  }
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
    OcrService ocrService = const _UnconfiguredOcrService(),
    this.maxRetryCount = defaultAiQueueMaxRetryCount,
    this.maxRoundsPerCall = defaultAiQueueMaxRoundsPerCall,
    this.extractionPromptVersion = defaultExtractionPromptVersion,
  })  : _incidentRepository = incidentRepository,
        _aiApiClient = aiApiClient,
        _evidenceStorage = evidenceStorage,
        _ocrService = ocrService;

  final IncidentRepository _incidentRepository;
  final AiApiClient _aiApiClient;
  final EvidenceStorageService _evidenceStorage;
  final OcrService _ocrService;
  final int maxRetryCount;
  final int maxRoundsPerCall;
  final String extractionPromptVersion;

  /// Traite les items `pending` de la file, en plusieurs "rounds" si
  /// nécessaire (optimisation coût IA - voir docstring de fichier) : un item
  /// traité avec succès peut lui-même mettre en file un NOUVEL item
  /// (`transcribeAudio` -> `extractFromTranscript`) - ce nouvel item est
  /// repris DANS LE MÊME appel (round suivant), pour que la chaîne complète
  /// progresse sans exiger un deuxième appel explicite côté appelant.
  /// Chaque item n'est traité QU'UNE FOIS par appel (même s'il reste
  /// `pending` après - ex : disjoncteur de retry, kind non supporté), pour
  /// garantir que la boucle termine ; borné en plus par [maxRoundsPerCall]
  /// par sécurité.
  Future<AiQueueProcessingSummary> processPendingOperations() async {
    int succeeded = 0;
    int failed = 0;
    int skipped = 0;
    final Set<String> processedIds = <String>{};

    for (int round = 0; round < maxRoundsPerCall; round++) {
      final List<AiQueueItem> pending = await _incidentRepository.listPendingAiOperations();
      final List<AiQueueItem> toProcess =
          pending.where((AiQueueItem item) => !processedIds.contains(item.id)).toList();
      if (toProcess.isEmpty) {
        break;
      }
      for (final AiQueueItem item in toProcess) {
        processedIds.add(item.id);
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
      // extractFromPhoto (preuve photo générique) : l'OCR on-device n'est
      // câblé QUE pour extractFromDocument (bon de livraison,
      // document_capture_screen.dart) à ce stade - voir
      // docs/GATE_R2_STATUS.md, "Reste à faire". Laissé `pending` intact
      // plutôt que de consommer un essai pour un échec certain.
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

  static bool _isSupported(AiOperationKind kind) {
    switch (kind) {
      case AiOperationKind.transcribeAudio:
      case AiOperationKind.extractFromTranscript:
      case AiOperationKind.extractFromDocument:
        return true;
      case AiOperationKind.extractFromPhoto:
        return false;
    }
  }

  Future<String> _run(AiQueueItem item) async {
    switch (item.operationKind) {
      case AiOperationKind.transcribeAudio:
        return _runTranscribeAudio(item);
      case AiOperationKind.extractFromTranscript:
        return _runExtractFromTranscript(item);
      case AiOperationKind.extractFromDocument:
        return _runExtractFromDocument(item);
      case AiOperationKind.extractFromPhoto:
        // Ne devrait jamais être atteint : `_isSupported` filtre déjà ce cas
        // avant tout appel à `_run` (voir `_processOne`). Garde défensive
        // explicite plutôt qu'un comportement silencieux si cet invariant
        // est un jour cassé par erreur.
        throw StateError(
          '${item.operationKind} pas encore supporté par AiQueueProcessor '
          '(OCR sur preuve photo générique non câblé - voir '
          'docs/GATE_R2_STATUS.md).',
        );
    }
  }

  /// Première étape d'une note vocale déjà capturée : transcription
  /// UNIQUEMENT. Met en file une opération `extractFromTranscript` séparée
  /// pour la suite (optimisation coût IA - voir docstring de fichier) au
  /// lieu d'enchaîner l'extraction directement ici : si l'extraction échoue
  /// et doit être retentée, la transcription (déjà payée en tokens) n'est
  /// alors jamais refaite.
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

    // idempotencyKey dérivée du CONTENU du transcript (pas de l'id de cet
    // item) : deux transcriptions produisant le même texte pour le même
    // incident (ex : ce même item retraité par extraordinaire après avoir
    // déjà réussi - ne devrait jamais arriver, un item `done` ne réapparaît
    // plus dans `listPendingAiOperations` - ou une source strictement
    // identique) partagent la même clé, donc jamais deux appels
    // d'extraction payants pour un contenu identique (défense en
    // profondeur, pas le mécanisme principal).
    final ExtractFromTranscriptPayload nextPayload =
        ExtractFromTranscriptPayload(transcript: transcription.text);
    final AiQueueItem nextItem = await _incidentRepository.enqueueAiOperation(
      incidentId: item.incidentId,
      issueId: issueId,
      operationKind: AiOperationKind.extractFromTranscript,
      payloadJson: nextPayload.encode(),
      idempotencyKey: aiOperationIdempotencyKey(
        incidentId: item.incidentId,
        operationKind: AiOperationKind.extractFromTranscript,
        sourceHash: sha256OfText(transcription.text),
      ),
    );

    return jsonEncode(<String, dynamic>{
      'transcript': transcription.text,
      'extract_operation_id': nextItem.id,
    });
  }

  /// Deuxième étape (voir [_runTranscribeAudio]) : extraction de faits
  /// candidats depuis un transcript DÉJÀ obtenu, puis persistance. Ne
  /// rappelle JAMAIS `AiApiClient.transcribe` - c'est tout le point de la
  /// séparation en deux opérations (optimisation coût IA).
  Future<String> _runExtractFromTranscript(AiQueueItem item) async {
    final String? issueId = item.issueId;
    if (issueId == null) {
      // Toujours fourni par `_runTranscribeAudio` ci-dessus lors de la mise
      // en file - un item `extractFromTranscript` sans issueId ne peut
      // provenir que d'un futur appelant qui contournerait ce chemin
      // normal, jamais un état attendu.
      throw StateError(
        'AiQueueItem ${item.id} (extractFromTranscript) sans issueId : '
        'impossible de persister un CandidateFactSet.',
      );
    }

    final ExtractFromTranscriptPayload payload = ExtractFromTranscriptPayload.fromJson(
      jsonDecode(item.payloadJson) as Map<String, dynamic>,
    );

    final AiExtractionResult extraction = await _aiApiClient.extractCandidateFacts(
      transcript: payload.transcript,
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

    return jsonEncode(<String, dynamic>{'candidate_fact_set_id': saved.id});
  }

  /// R2 (lot OCR) : OCR on-device (ML Kit, gratuit, aucun réseau) PUIS
  /// extraction en un seul item (voir docstring d'[ExtractFromDocumentPayload]
  /// pour la justification de ne pas séparer ces deux étapes, contrairement
  /// à `transcribeAudio`/`extractFromTranscript`). Un texte OCR vide (photo
  /// illisible, angle trop mauvais, document non textuel) n'est jamais une
  /// erreur ici : il est transmis tel quel à l'extraction, qui produira
  /// simplement un `CandidateFactData` sans champ (`fields: {}`,
  /// `requires_review: true`) - jamais un blocage de l'utilisateur pour ce
  /// cas (section "Échec IA", même principe que partout ailleurs).
  Future<String> _runExtractFromDocument(AiQueueItem item) async {
    final String? issueId = item.issueId;
    if (issueId == null) {
      // Même invariant que _runTranscribeAudio ci-dessus : un
      // CandidateFactSet est toujours rattaché à une anomalie.
      throw StateError(
        'AiQueueItem ${item.id} (extractFromDocument) sans issueId : '
        'impossible de persister un CandidateFactSet (rattaché à une '
        'anomalie, jamais à un incident entier).',
      );
    }

    final ExtractFromDocumentPayload payload = ExtractFromDocumentPayload.fromJson(
      jsonDecode(item.payloadJson) as Map<String, dynamic>,
    );

    final List<EvidenceAsset> assets =
        await _incidentRepository.listEvidenceAssets(item.incidentId);
    final EvidenceAsset asset = assets.firstWhere(
      (EvidenceAsset a) => a.id == payload.evidenceAssetId,
      orElse: () => throw StateError(
        "Preuve ${payload.evidenceAssetId} introuvable pour l'opération "
        '${item.id} (incident ${item.incidentId}).',
      ),
    );

    final String documentText = await _ocrService.recognizeText(asset.localFilePath);

    final AiExtractionResult extraction = await _aiApiClient.extractCandidateFacts(
      documentText: documentText,
      promptVersion: extractionPromptVersion,
    );

    // Même défense en profondeur que _runExtractFromTranscript ci-dessus.
    final CandidateFactSet saved = await _incidentRepository.saveCandidateFactSet(
      issueId: issueId,
      data: extraction.candidate,
      promptVersion: extraction.promptVersion,
      model: extraction.modelId,
    );

    return jsonEncode(<String, dynamic>{'candidate_fact_set_id': saved.id});
  }
}
