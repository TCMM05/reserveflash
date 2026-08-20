import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import 'package:reserveflash/core/design_system/rf_colors.dart';
import 'package:reserveflash/core/design_system/rf_spacing.dart';
import 'package:reserveflash/core/design_system/rf_typography.dart';
import 'package:reserveflash/core/providers/app_providers.dart';
import 'package:reserveflash/core/router/app_router.dart';
import 'package:reserveflash/core/utils/duration_format.dart';
import 'package:reserveflash/core/widgets/rf_confirm_dialog.dart';
import 'package:reserveflash/data/ai_queue_processor.dart';
import 'package:reserveflash/domain/entities/ai_queue_item.dart';
import 'package:reserveflash/domain/entities/evidence_asset.dart' as domain;
import 'package:reserveflash/domain/entities/incident.dart' as domain;
import 'package:reserveflash/domain/entities/issue.dart' as domain;
import 'package:reserveflash/features/common/presentation/evidence_audio_player_screen.dart';
import 'package:reserveflash/features/common/presentation/evidence_thumbnail_tile.dart';
import 'package:reserveflash/features/common/presentation/missing_incident_view.dart';

const Uuid _uuid = Uuid();

/// S10 - Description voix/texte. "Bouton micro large, timer, lecture/
/// annulation, texte éditable" (section 3.2). R1 point 5 : la saisie texte
/// manuelle est TOUJOURS disponible (sortie de secours, section 3.1) - la
/// note vocale locale est une capture au mieux-effort en plus, jamais un
/// prérequis pour continuer. Aucune transcription IA en R1 (voir
/// GATE_R1_STATUS.md pour la documentation explicite de ce risque, comme
/// demandé : "si l'intégration audio ajoute un risque important au Gate R1,
/// documenter clairement le point mais ne pas compromettre caméra, fichiers
/// et persistance").
class VoiceDescriptionScreen extends ConsumerStatefulWidget {
  const VoiceDescriptionScreen({required this.incidentId, super.key});

  final String incidentId;

  @override
  ConsumerState<VoiceDescriptionScreen> createState() => _VoiceDescriptionScreenState();
}

class _VoiceDescriptionScreenState extends ConsumerState<VoiceDescriptionScreen> {
  final TextEditingController _notesController = TextEditingController();
  final AudioRecorder _audioRecorder = AudioRecorder();

  bool _initializedFromExisting = false;
  bool _isSavingText = false;
  bool _isRecording = false;
  bool _isProcessingAudio = false;
  String? _errorMessage;
  String? _audioErrorMessage;

  // Correction ciblée post-recette terrain R1 : "pendant l'enregistrement,
  // afficher un timer" - `Timer.periodic` local à l'écran, jamais persisté
  // (purement un affichage temps réel, aucun impact sur la preuve
  // enregistrée elle-même).
  Timer? _recordingTimer;
  Duration _recordingElapsed = Duration.zero;

  @override
  void dispose() {
    _notesController.dispose();
    _recordingTimer?.cancel();
    // Best-effort : ne doit jamais faire planter la fermeture de l'écran
    // même si l'enregistreur natif est dans un état inattendu.
    _audioRecorder.dispose();
    super.dispose();
  }

  Future<void> _saveText() async {
    if (widget.incidentId.isEmpty || _isSavingText) {
      return;
    }
    setState(() {
      _isSavingText = true;
      _errorMessage = null;
    });
    try {
      final domain.Incident? current =
          await ref.read(incidentRepositoryProvider).getIncident(widget.incidentId);
      if (current == null) {
        throw StateError('Incident introuvable.');
      }
      final String trimmed = _notesController.text.trim();
      await ref.read(incidentRepositoryProvider).updateIncidentMetadata(
            incidentId: widget.incidentId,
            occurredAt: current.occurredAt,
            supplierName: current.supplierName,
            carrierName: current.carrierName,
            deliveryRef: current.deliveryRef,
            notes: trimmed.isEmpty ? null : trimmed,
          );
      notifyDataChanged(ref);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Description enregistrée.')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = "Impossible d'enregistrer la description : $e");
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingText = false);
      }
    }
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopAndSaveRecording();
      return;
    }
    setState(() => _audioErrorMessage = null);
    try {
      // "Demander au moment nécessaire" (point 10) : `hasPermission()`
      // déclenche la demande native de permission micro si elle n'a pas
      // encore été accordée/refusée.
      final bool granted = await _audioRecorder.hasPermission();
      if (!granted) {
        if (mounted) {
          setState(() {
            _audioErrorMessage =
                "Permission micro refusée : la note vocale n'est pas disponible, "
                'la description écrite reste utilisable normalement (R1-T06).';
          });
        }
        return;
      }
      final Directory tempDir = await getTemporaryDirectory();
      final String path = '${tempDir.path}/${_uuid.v4()}.m4a';
      await _audioRecorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
      if (mounted) {
        setState(() {
          _isRecording = true;
          _recordingElapsed = Duration.zero;
        });
        _recordingTimer?.cancel();
        _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) {
            setState(() => _recordingElapsed += const Duration(seconds: 1));
          }
        });
      }
    } catch (e) {
      // Best-effort explicite (point 5) : une erreur d'enregistrement audio
      // (plugin natif indisponible, matériel...) ne doit JAMAIS compromettre
      // la caméra, les fichiers ou la persistance déjà acquis - uniquement
      // désactiver la fonctionnalité audio pour cette session.
      if (mounted) {
        setState(() {
          _isRecording = false;
          _audioErrorMessage = "Enregistrement vocal indisponible sur cet appareil : $e";
        });
      }
    }
  }

  Future<void> _stopAndSaveRecording() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    setState(() => _isProcessingAudio = true);
    try {
      final String? path = await _audioRecorder.stop();
      setState(() => _isRecording = false);
      if (path == null) {
        return;
      }
      final domain.EvidenceAsset asset =
          await ref.read(evidenceStorageServiceProvider).captureFromFile(
                incidentId: widget.incidentId,
                sourcePath: path,
                documentType: domain.EvidenceDocumentType.audio,
                mimeType: 'audio/m4a',
                extension: 'm4a',
              );
      await ref.read(incidentRepositoryProvider).registerEvidenceAsset(asset);
      notifyDataChanged(ref);
      // R2 : la note vocale est DÉJÀ sauvegardée avec succès à ce stade -
      // ce qui suit est une étape optionnelle au mieux-effort, voir
      // docstring de _enqueueTranscriptionBestEffort.
      await _enqueueTranscriptionBestEffort(asset);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isRecording = false;
          _audioErrorMessage = "Impossible d'enregistrer la note vocale : $e";
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessingAudio = false);
      }
    }
  }

  /// R2 : déclenche la transcription IA de la note vocale qui vient d'être
  /// enregistrée, au mieux-effort - jamais un blocage de l'utilisateur,
  /// jamais une erreur affichée ici : la note vocale elle-même est déjà
  /// sauvegardée avec succès au moment où cette méthode est appelée (voir
  /// `_stopAndSaveRecording` ci-dessus), l'échec de cette étape optionnelle
  /// ne doit jamais donner l'impression à l'utilisateur que sa note vocale a
  /// été perdue.
  ///
  /// V1 : rattache l'opération à la première anomalie (`Issue`) de
  /// l'incident (`CandidateFactSet` est toujours rattaché à une anomalie,
  /// jamais à l'incident entier - voir
  /// `lib/data/ai_queue_processor.dart::_runTranscribeAudio`). Cet écran
  /// (S10) est aujourd'hui incident-scope, pas issue-scope (section 3.2) :
  /// si plusieurs anomalies existent, seule la première reçoit la
  /// transcription - limitation V1 documentée (voir
  /// `docs/GATE_R2_STATUS.md`), à revoir si l'app expose un jour un flux de
  /// capture par anomalie plutôt que par incident. Si aucune anomalie
  /// n'existe encore (S10 atteint hors du parcours nominal S06->S15, qui
  /// passe normalement par S08 avant S10), aucune opération n'est mise en
  /// file : rien n'est perdu (la note reste consultable), juste aucune
  /// extraction IA automatique.
  Future<void> _enqueueTranscriptionBestEffort(domain.EvidenceAsset asset) async {
    try {
      final List<domain.Issue> issues =
          await ref.read(incidentRepositoryProvider).listIssues(widget.incidentId);
      if (issues.isEmpty) {
        return;
      }
      final TranscribeAudioPayload payload = TranscribeAudioPayload(evidenceAssetId: asset.id);
      await ref.read(incidentRepositoryProvider).enqueueAiOperation(
            incidentId: widget.incidentId,
            issueId: issues.first.id,
            operationKind: AiOperationKind.transcribeAudio,
            payloadJson: payload.encode(),
            idempotencyKey: 'transcribe_audio:${asset.id}',
          );
      // Déclenchement "online" au mieux-effort (point 6 - "si une opération
      // IA nécessite Internet : pending, retry possible à la reconnexion") :
      // si le backend est injoignable maintenant, l'item reste `pending` en
      // base et sera retenté par un prochain appel à ce même processeur
      // (ex : un futur écran de revue, un listener de connectivité - pas
      // encore câblé, voir docs/GATE_R2_STATUS.md) - jamais une perte.
      unawaited(ref.read(aiQueueProcessorProvider).processPendingOperations());
    } catch (_) {
      // Best-effort explicite (voir docstring ci-dessus) : aucune erreur
      // affichée à l'utilisateur pour cette étape optionnelle.
    }
  }

  Future<void> _deleteAudio(domain.EvidenceAsset asset) async {
    final bool confirmed = await confirmDestructiveAction(
      context,
      title: 'Supprimer cette note vocale ?',
      message: 'Cette action est définitive.',
    );
    if (!confirmed || !mounted) {
      return;
    }
    setState(() => _isProcessingAudio = true);
    try {
      await ref.read(evidenceStorageServiceProvider).deleteFile(asset.localFilePath);
      await ref.read(incidentRepositoryProvider).deleteEvidenceAsset(asset.id);
      notifyDataChanged(ref);
    } catch (e) {
      if (mounted) {
        setState(() => _audioErrorMessage = 'Impossible de supprimer la note vocale : $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessingAudio = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.incidentId.isEmpty) {
      return const MissingIncidentView();
    }
    final AsyncValue<domain.Incident?> incidentAsync =
        ref.watch(incidentDetailProvider(widget.incidentId));
    final AsyncValue<List<domain.EvidenceAsset>> evidenceAsync =
        ref.watch(incidentEvidenceProvider(widget.incidentId));

    return Scaffold(
      appBar: AppBar(title: const Text('Décrivez ce que vous constatez')),
      body: incidentAsync.when(
        data: (domain.Incident? incident) {
          if (incident == null) {
            return const MissingIncidentView();
          }
          if (!_initializedFromExisting) {
            _notesController.text = incident.notes ?? '';
            _initializedFromExisting = true;
          }
          final List<domain.EvidenceAsset> audioAssets = evidenceAsync.maybeWhen(
            data: (List<domain.EvidenceAsset> assets) => assets
                .where((domain.EvidenceAsset a) => a.documentType == domain.EvidenceDocumentType.audio)
                .toList(),
            orElse: () => const <domain.EvidenceAsset>[],
          );

          return SingleChildScrollView(
            padding: const EdgeInsets.all(RfSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Saisie texte toujours disponible - la note vocale est facultative.',
                  style: RfTypography.secondary,
                ),
                const SizedBox(height: RfSpacing.md),
                TextField(
                  controller: _notesController,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Description (optionnel)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: RfSpacing.sm),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _isSavingText ? null : _saveText,
                    child: _isSavingText
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Enregistrer la description'),
                  ),
                ),
                if (_errorMessage != null)
                  Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                const Divider(height: RfSpacing.xl),
                const Text('Note vocale (optionnelle)', style: RfTypography.sectionTitle),
                const SizedBox(height: RfSpacing.sm),
                ...audioAssets.map(
                  (domain.EvidenceAsset a) => EvidenceThumbnailTile(
                    asset: a,
                    label: 'Note vocale',
                    onDelete: _isProcessingAudio ? null : () => _deleteAudio(a),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => EvidenceAudioPlayerScreen(
                          incidentId: widget.incidentId,
                          asset: a,
                          label: 'Note vocale',
                        ),
                      ),
                    ),
                  ),
                ),
                if (_isRecording) ...<Widget>[
                  Text(
                    'Enregistrement en cours : ${formatMmSs(_recordingElapsed)}',
                    style: RfTypography.secondary,
                  ),
                  const SizedBox(height: RfSpacing.xs),
                ],
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isProcessingAudio ? null : _toggleRecording,
                    icon: Icon(_isRecording ? Icons.stop_circle : Icons.mic),
                    label: Text(_isRecording ? "Arrêter l'enregistrement" : 'Enregistrer une note vocale'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _isRecording ? RfColors.danger : null,
                    ),
                  ),
                ),
                if (_audioErrorMessage != null) ...<Widget>[
                  const SizedBox(height: RfSpacing.sm),
                  Text(_audioErrorMessage!, style: const TextStyle(color: RfColors.muted)),
                ],
                const SizedBox(height: RfSpacing.xl),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => context.pushChecklist(widget.incidentId),
                    child: const Text('Continuer'),
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, StackTrace stackTrace) => Center(child: Text('Erreur de lecture locale : $e')),
      ),
    );
  }
}
