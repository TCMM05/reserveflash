import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:reserveflash/core/design_system/rf_colors.dart';
import 'package:reserveflash/core/design_system/rf_spacing.dart';
import 'package:reserveflash/core/design_system/rf_typography.dart';
import 'package:reserveflash/core/providers/app_providers.dart';
import 'package:reserveflash/core/router/app_router.dart';
import 'package:reserveflash/domain/entities/incident.dart' as domain;

/// S04 - Accueil. "CTA 'Nouvelle réception problématique' + derniers
/// dossiers + état sync" (section 3.2). R1 point 1 : n'utilise plus AUCUNE
/// donnée fictive - la liste "Derniers dossiers" vient de
/// `IncidentRepository.listIncidents()` (Drift/SQLite réel).
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<domain.Incident>> incidentsAsync = ref.watch(incidentListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('ReserveFlash'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Historique',
            onPressed: () => context.pushHistory(),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(RfSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('Derniers dossiers', style: RfTypography.sectionTitle),
            const SizedBox(height: RfSpacing.sm),
            Expanded(
              child: incidentsAsync.when(
                data: (List<domain.Incident> incidents) {
                  if (incidents.isEmpty) {
                    return const Text(
                      'Aucun incident pour le moment.',
                      style: RfTypography.secondary,
                    );
                  }
                  final List<domain.Incident> recent = incidents.take(5).toList();
                  return ListView.builder(
                    itemCount: recent.length,
                    itemBuilder: (BuildContext context, int index) {
                      final domain.Incident incident = recent[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: RfSpacing.sm),
                        child: ListTile(
                          title: Text(
                            incident.supplierName ?? incident.deliveryRef ?? 'Incident sans nom',
                          ),
                          subtitle: Text(
                            DateFormat('dd/MM/yyyy HH:mm').format(incident.occurredAt.toLocal()),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.pushIncidentDetail(incident.id),
                        ),
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (Object e, StackTrace stackTrace) => Text(
                  'Lecture locale impossible : $e',
                  style: const TextStyle(color: RfColors.danger),
                ),
              ),
            ),
          ],
        ),
      ),
      // CTA principal en zone basse, pleine largeur (section 3.1/4.4).
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: RfSpacing.lg),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: RfColors.signal),
            onPressed: () => context.pushCreateIncident(),
            icon: const Icon(Icons.add_a_photo),
            label: const Text('Nouvelle réception problématique'),
          ),
        ),
      ),
    );
  }
}
