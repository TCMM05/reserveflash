import 'package:flutter_test/flutter_test.dart';
import 'package:reserveflash/domain/value_objects/incident_status.dart';

void main() {
  group('IncidentStatus - section 2.2', () {
    test('draft_local peut transitionner vers syncing', () {
      expect(
        IncidentStatus.draftLocal.canTransitionTo(IncidentStatus.syncing),
        isTrue,
      );
    });

    test('extraction_pending ne peut pas sauter directement à reserve_ready', () {
      expect(
        IncidentStatus.extractionPending.canTransitionTo(IncidentStatus.reserveReady),
        isFalse,
      );
    });

    test('pathTo calcule le plus court chemin via review_required', () {
      final List<IncidentStatus>? path =
          IncidentStatus.draftLocal.pathTo(IncidentStatus.factsConfirmed);
      expect(path, <IncidentStatus>[
        IncidentStatus.draftLocal,
        IncidentStatus.reviewRequired,
        IncidentStatus.factsConfirmed,
      ]);
    });

    test('exported peut être rouvert manuellement vers review_required', () {
      expect(
        IncidentStatus.exported.canTransitionTo(IncidentStatus.reviewRequired),
        isTrue,
      );
    });

    test('fromWire round-trip avec wireValue', () {
      for (final IncidentStatus status in IncidentStatus.values) {
        expect(IncidentStatus.fromWire(status.wireValue), status);
      }
    });

    test('fromWire lève sur une valeur inconnue', () {
      expect(() => IncidentStatus.fromWire('not_a_status'), throwsArgumentError);
    });
  });
}
