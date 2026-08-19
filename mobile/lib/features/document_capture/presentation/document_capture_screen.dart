import 'package:flutter/material.dart';

import 'package:reserveflash/core/widgets/rf_screen_stub.dart';

/// S06 - Capture document. "Caméra plein écran + cadrage + reprise photo"
/// (section 3.2). F02 : capture jamais dépendante du réseau (section 8.1).
class DocumentCaptureScreen extends StatelessWidget {
  const DocumentCaptureScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const RfScreenStub(
      screenId: 'S06',
      title: 'Photo du document de transport',
      designCriterion: 'Caméra plein écran + cadrage + reprise photo.',
    );
  }
}
