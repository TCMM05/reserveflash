import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import 'package:reserveflash/core/design_system/rf_colors.dart';
import 'package:reserveflash/core/design_system/rf_spacing.dart';
import 'package:reserveflash/core/design_system/rf_typography.dart';
import 'package:reserveflash/core/providers/app_providers.dart';
import 'package:reserveflash/core/utils/duration_format.dart';
import 'package:reserveflash/core/widgets/rf_confirm_dialog.dart';
import 'package:reserveflash/domain/entities/evidence_asset.dart' as domain;

/// Lecteur plein écran d'une note vocale déjà enregistrée.
///
/// Correction ciblée post-recette terrain R1 (avant freeze final) :
/// "après capture d'une note vocale, l'utilisateur ne peut pas réellement
/// contrôler le média enregistré." Ouvert au tap de n'importe quelle
/// [EvidenceThumbnailTile] audio, depuis n'importe quel écran du parcours
/// (S10/S17). Poussé via `Navigator.push`, jamais via go_router (même
/// convention que [CameraCapturePage]/[EvidencePhotoViewerScreen]).
///
/// Lecture 100% locale via `just_audio` (fichier sur disque uniquement,
/// jamais de source réseau/streaming) : aucune dépendance Internet
/// introduite (R1-T09/T10). Ne plante jamais sur un fichier manquant/
/// corrompu - même invariant que le reste de R1 (R1-T07), étendu ici au cas
/// où le fichier serait référencé `available` mais illisible par le
/// décodeur audio au moment de l'ouverture (`setFilePath` peut lever).
class EvidenceAudioPlayerScreen extends ConsumerStatefulWidget {
  const EvidenceAudioPlayerScreen({
    required this.incidentId,
    required this.asset,
    this.label,
    super.key,
  });

  final String incidentId;
  final domain.EvidenceAsset asset;
  final String? label;

  @override
  ConsumerState<EvidenceAudioPlayerScreen> createState() => _EvidenceAudioPlayerScreenState();
}

enum _PlayerLoadState { loading, ready, unavailable }

class _EvidenceAudioPlayerScreenState extends ConsumerState<EvidenceAudioPlayerScreen> {
  final AudioPlayer _player = AudioPlayer();
  _PlayerLoadState _loadState = _PlayerLoadState.loading;
  String? _unavailableMessage;
  bool _isDeleting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.asset.availabilityStatus != domain.EvidenceAvailability.available) {
      setState(() {
        _loadState = _PlayerLoadState.unavailable;
        _unavailableMessage = widget.asset.availabilityStatus == domain.EvidenceAvailability.missing
            ? 'Note vocale introuvable sur cet appareil. Les autres preuves de '
                'ce dossier ne sont pas affectées.'
            : 'Fichier audio corrompu - la note vocale ne peut plus être lue. '
                'Vous pouvez la supprimer.';
      });
      return;
    }
    try {
      await _player.setFilePath(widget.asset.localFilePath);
      if (!mounted) {
        return;
      }
      setState(() => _loadState = _PlayerLoadState.ready);
    } catch (e) {
      // R1-T07 étendu à l'audio par cette correction : un fichier
      // référencé "available" mais illisible par le décodeur au moment
      // précis de l'ouverture ne doit jamais faire planter l'écran.
      if (!mounted) {
        return;
      }
      setState(() {
        _loadState = _PlayerLoadState.unavailable;
        _unavailableMessage = 'Impossible de lire ce fichier audio : $e';
      });
    }
  }

  Future<void> _togglePlayPause() async {
    try {
      if (_player.playing) {
        await _player.pause();
        return;
      }
      if (_player.processingState == ProcessingState.completed) {
        await _player.seek(Duration.zero);
      }
      unawaited(_player.play());
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Lecture impossible : $e');
      }
    }
  }

  /// "Arrêter/recommencer" (spec) : revient au début et met en pause -
  /// appuyer de nouveau sur lecture relance donc depuis le début. Implémenté
  /// via pause + seek plutôt que `stop()` pour rester prévisible quel que
  /// soit le comportement exact de libération de ressources natives de
  /// `stop()` selon la plateforme.
  Future<void> _stopAndRestart() async {
    try {
      await _player.pause();
      await _player.seek(Duration.zero);
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = "Impossible d'arrêter la lecture : $e");
      }
    }
  }

  Future<void> _delete() async {
    final bool confirmed = await confirmDestructiveAction(
      context,
      title: 'Supprimer cette note vocale ?',
      message: 'Cette action est définitive.',
    );
    if (!confirmed || !mounted) {
      return;
    }
    setState(() {
      _isDeleting = true;
      _errorMessage = null;
    });
    try {
      await _player.pause();
    } catch (_) {
      // Best-effort : un échec de mise en pause ne doit jamais empêcher la
      // suppression de la preuve elle-même.
    }
    try {
      await ref.read(evidenceStorageServiceProvider).deleteFile(widget.asset.localFilePath);
      await ref.read(incidentRepositoryProvider).deleteEvidenceAsset(widget.asset.id);
      notifyDataChanged(ref);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Impossible de supprimer la note vocale : $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isDeleting = false);
      }
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.label ?? 'Note vocale'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Retour',
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.delete_outline, color: RfColors.danger),
            tooltip: 'Supprimer',
            onPressed: _isDeleting ? null : _delete,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(RfSpacing.lg),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    switch (_loadState) {
      case _PlayerLoadState.loading:
        return const Center(child: CircularProgressIndicator());
      case _PlayerLoadState.unavailable:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.error_outline, color: RfColors.muted, size: 64),
              const SizedBox(height: RfSpacing.md),
              Text(
                _unavailableMessage ?? 'Note vocale indisponible.',
                style: RfTypography.body,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      case _PlayerLoadState.ready:
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.audiotrack, size: 64, color: RfColors.navy),
            const SizedBox(height: RfSpacing.lg),
            StreamBuilder<Duration>(
              stream: _player.positionStream,
              builder: (BuildContext context, AsyncSnapshot<Duration> snapshot) {
                final Duration position = snapshot.data ?? Duration.zero;
                final Duration total = _player.duration ?? Duration.zero;
                final double sliderMax =
                    total.inMilliseconds > 0 ? total.inMilliseconds.toDouble() : 1;
                final double sliderValue =
                    position.inMilliseconds.clamp(0, sliderMax.toInt()).toDouble();
                return Column(
                  children: <Widget>[
                    Slider(
                      value: sliderValue,
                      max: sliderMax,
                      onChanged: total.inMilliseconds > 0
                          ? (double value) => _player.seek(Duration(milliseconds: value.toInt()))
                          : null,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: RfSpacing.sm),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          Text(formatMmSs(position), style: RfTypography.secondary),
                          Text(formatMmSs(total), style: RfTypography.secondary),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: RfSpacing.md),
            StreamBuilder<PlayerState>(
              stream: _player.playerStateStream,
              builder: (BuildContext context, AsyncSnapshot<PlayerState> snapshot) {
                final bool playing = snapshot.data?.playing ?? false;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    IconButton(
                      iconSize: 40,
                      icon: const Icon(Icons.stop_circle_outlined),
                      tooltip: 'Arrêter / recommencer',
                      onPressed: _stopAndRestart,
                    ),
                    const SizedBox(width: RfSpacing.lg),
                    IconButton(
                      iconSize: 64,
                      icon: Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_filled),
                      color: RfColors.signal,
                      tooltip: playing ? 'Pause' : 'Lecture',
                      onPressed: _togglePlayPause,
                    ),
                  ],
                );
              },
            ),
            if (_errorMessage != null) ...<Widget>[
              const SizedBox(height: RfSpacing.md),
              Text(
                _errorMessage!,
                style: const TextStyle(color: RfColors.danger),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        );
    }
  }
}
