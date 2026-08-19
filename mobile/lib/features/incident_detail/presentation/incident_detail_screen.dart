import 'package:flutter/material.dart';

import 'package:reserveflash/core/widgets/rf_screen_stub.dart';

/// S17 - Détail incident. "Timeline, faits confirmés, preuves, exports"
/// (section 3.2).
class IncidentDetailScreen extends StatelessWidget {
  const IncidentDetailScreen({required this.incidentId, super.key});

  final String incidentId;

  @override
  Widget build(BuildContext context) {
    return RfScreenStub(
      screenId: 'S17',
      title: 'Incident $incidentId',
      designCriterion: 'Timeline, faits confirmés, preuves, exports.',
    );
  }
}
