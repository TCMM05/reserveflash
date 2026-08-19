import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:reserveflash/core/design_system/rf_colors.dart';
import 'package:reserveflash/core/design_system/rf_spacing.dart';

/// Page caméra plein écran réutilisée par S06 (photo BL) et S09 (photos
/// preuves) - R1 points 2/4/10. Retournée via `Navigator.pop(context,
/// filePath)` (chemin du fichier temporaire capturé par le plugin `camera`,
/// `null` si annulé/refusé) plutôt que via go_router : ce n'est pas une
/// étape nommée du parcours S01-S20 (section 3.2), juste un composant
/// caméra générique poussé par-dessus l'écran appelant, qui reste seul
/// responsable de sauvegarder le fichier définitivement dans l'espace privé
/// de l'app (voir lib/data/local/evidence_storage.dart) - jamais cette page
/// elle-même (séparation stricte capture UI / persistance).
///
/// Ne dépend d'aucun réseau (point 8/9) et ne fait AUCUN appel réseau à
/// aucune étape (R1-T10).
class CameraCapturePage extends StatefulWidget {
  const CameraCapturePage({required this.title, super.key});

  final String title;

  @override
  State<CameraCapturePage> createState() => _CameraCapturePageState();
}

enum _CameraStage { requestingPermission, permissionDenied, initializing, ready, error }

class _CameraCapturePageState extends State<CameraCapturePage> {
  CameraController? _controller;
  _CameraStage _stage = _CameraStage.requestingPermission;
  String? _errorMessage;
  bool _isCapturing = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    // Point 10 - "demander [la permission] au moment nécessaire,
    // comportement propre en cas de refus" (R1-T06) : la demande a lieu ICI,
    // juste avant l'ouverture de la page caméra, jamais au démarrage de
    // l'app ni en arrière-plan.
    final PermissionStatus status = await Permission.camera.request();
    if (!mounted) {
      return;
    }
    if (!status.isGranted) {
      setState(() => _stage = _CameraStage.permissionDenied);
      return;
    }
    setState(() => _stage = _CameraStage.initializing);
    try {
      final List<CameraDescription> cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() {
          _stage = _CameraStage.error;
          _errorMessage = 'Aucune caméra détectée sur cet appareil.';
        });
        return;
      }
      final CameraDescription description = cameras.firstWhere(
        (CameraDescription c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final CameraController controller = CameraController(
        description,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _stage = _CameraStage.ready;
      });
    } catch (e) {
      // R1-T06/T07 : aucune erreur caméra (matériel absent, driver,
      // permission révoquée entre-temps...) ne doit faire planter l'app -
      // uniquement une UI contrôlée, jamais une exception non gérée.
      if (!mounted) {
        return;
      }
      setState(() {
        _stage = _CameraStage.error;
        _errorMessage = 'Caméra indisponible : $e';
      });
    }
  }

  Future<void> _capture() async {
    final CameraController? controller = _controller;
    if (controller == null || !controller.value.isInitialized || _isCapturing) {
      return;
    }
    setState(() => _isCapturing = true);
    try {
      final XFile file = await controller.takePicture();
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(file.path);
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isCapturing = false;
        _stage = _CameraStage.error;
        _errorMessage = 'La capture a échoué : $e';
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(child: _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_stage) {
      case _CameraStage.requestingPermission:
      case _CameraStage.initializing:
        return const Center(child: CircularProgressIndicator(color: Colors.white));
      case _CameraStage.permissionDenied:
        return _PermissionDeniedView(onCancel: () => Navigator.of(context).pop());
      case _CameraStage.error:
        return _ErrorView(
          message: _errorMessage ?? 'Erreur caméra inconnue.',
          onCancel: () => Navigator.of(context).pop(),
        );
      case _CameraStage.ready:
        final CameraController controller = _controller!;
        return Column(
          children: <Widget>[
            Expanded(child: CameraPreview(controller)),
            Container(
              color: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: RfSpacing.lg),
              child: Center(
                child: GestureDetector(
                  onTap: _isCapturing ? null : _capture,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isCapturing ? RfColors.muted : Colors.white,
                      border: Border.all(color: RfColors.signal, width: 4),
                    ),
                    child: _isCapturing
                        ? const Padding(
                            padding: EdgeInsets.all(20),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : null,
                  ),
                ),
              ),
            ),
          ],
        );
    }
  }
}

class _PermissionDeniedView extends StatelessWidget {
  const _PermissionDeniedView({required this.onCancel});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(RfSpacing.lg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Icon(Icons.no_photography, color: Colors.white70, size: 48),
          const SizedBox(height: RfSpacing.md),
          const Text(
            "L'accès à la caméra a été refusé. Vous pouvez l'autoriser dans les "
            "réglages de l'appareil, ou revenir en arrière : aucune donnée n'est "
            'perdue.',
            style: TextStyle(color: Colors.white),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: RfSpacing.lg),
          FilledButton(onPressed: openAppSettings, child: const Text('Ouvrir les réglages')),
          const SizedBox(height: RfSpacing.xs),
          TextButton(
            onPressed: onCancel,
            child: const Text('Retour', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onCancel});

  final String message;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(RfSpacing.lg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Icon(Icons.error_outline, color: Colors.white70, size: 48),
          const SizedBox(height: RfSpacing.md),
          Text(message, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
          const SizedBox(height: RfSpacing.lg),
          TextButton(
            onPressed: onCancel,
            child: const Text('Retour', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }
}
