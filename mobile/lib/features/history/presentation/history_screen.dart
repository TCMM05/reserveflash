import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:reserveflash/core/design_system/rf_colors.dart';
import 'package:reserveflash/core/design_system/rf_spacing.dart';
import 'package:reserveflash/core/design_system/rf_typography.dart';
import 'package:reserveflash/core/providers/app_providers.dart';
import 'package:reserveflash/core/router/app_router.dart';
import 'package:reserveflash/domain/entities/incident.dart' as domain;

/// S16 - Historique. R1 : liste RÉELLE de tous les incidents locaux (point
/// 6 - "rouvrir un incident"), triée du plus récent au plus ancien (voir
/// `LocalIncidentRepository.listIncidents`). Recherche/filtres avancés
/// (mentionnés dans le critère de conception d'origine, hors périmètre
/// fonctionnel R1 - voir demande corrective) sont documentés comme
/// simplification connue dans CHANGELOG.md/GATE_R1_STATUS.md plutôt
/// qu'implémentés ici.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<domain.Incident>> incidentsAsync = ref.watch(incidentListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Historique')),
      body: Padding(
        padding: const EdgeInsets.all(RfSpacing.lg),
        child: incidentsAsync.when(
          data: (List<domain.Incident> incidents) {
            if (incidents.isEmpty) {
              return const Center(
                child: Text('Aucun incident enregistré sur cet appareil.', style: RfTypography.secondary),
              );
            }
            return ListView.builder(
              itemCount: incidents.length,
              itemBuilder: (BuildContext context, int index) {
                final domain.Incident incident = incidents[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: RfSpacing.sm),
                  child: ListTile(
                    title: Text(incident.supplierName ?? incident.deliveryRef ?? 'Incident sans nom'),
                    subtitle: Text(
                      '${DateFormat('dd/MM/yyyy HH:mm').format(incident.occurredAt.toLocal())} - '
                      '${incident.status.wireValue}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.pushIncidentDetail(incident.id),
                  ),
                );
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object e, StackTrace stackTrace) => Center(
            child: Text('Lecture locale impossible : $e', style: const TextStyle(color: RfColors.danger)),
          ),
        ),
      ),
    );
  }
}
