import 'package:flutter/material.dart';

import 'package:reserveflash/core/widgets/rf_screen_stub.dart';

/// S13 - Document final. "Instruction claire pour photographier le BL
/// complété" (section 3.2, F11).
class FinalDocumentScreen extends StatelessWidget {
  const FinalDocumentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const RfScreenStub(
      screenId: 'S13',
      title: 'Photographiez le document complété',
      designCriterion: 'Instruction claire pour photographier le BL complété.',
    );
  }
}
