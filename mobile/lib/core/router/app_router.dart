import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

export 'package:go_router/go_router.dart' show GoRouterHelper;

import 'package:reserveflash/features/account/presentation/account_screen.dart';
import 'package:reserveflash/features/auth/presentation/auth_screen.dart';
import 'package:reserveflash/features/checklist/presentation/checklist_screen.dart';
import 'package:reserveflash/features/checklist/presentation/dossier_complete_screen.dart';
import 'package:reserveflash/features/document_capture/presentation/document_capture_screen.dart';
import 'package:reserveflash/features/document_capture/presentation/document_metadata_screen.dart';
import 'package:reserveflash/features/error/presentation/error_screen.dart';
import 'package:reserveflash/features/evidence_capture/presentation/evidence_capture_screen.dart';
import 'package:reserveflash/features/facts_review/presentation/facts_review_screen.dart';
import 'package:reserveflash/features/final_document/presentation/final_document_screen.dart';
import 'package:reserveflash/features/history/presentation/history_screen.dart';
import 'package:reserveflash/features/home/presentation/home_screen.dart';
import 'package:reserveflash/features/incident_create/presentation/create_incident_screen.dart';
import 'package:reserveflash/features/incident_detail/presentation/incident_detail_screen.dart';
import 'package:reserveflash/features/issue_type/presentation/issue_type_screen.dart';
import 'package:reserveflash/features/onboarding/presentation/onboarding_screen.dart';
import 'package:reserveflash/features/paywall/presentation/paywall_screen.dart';
import 'package:reserveflash/features/reserve/presentation/reserve_screen.dart';
import 'package:reserveflash/features/splash/presentation/splash_screen.dart';
import 'package:reserveflash/features/voice_description/presentation/voice_description_screen.dart';

/// Routes nommées - une par écran S01-S20 (section 3.2). Les noms de route
/// sont stables et ne doivent JAMAIS changer sans mise à jour des deep links
/// prévus pour dossiers/paywall (section 5.1).
abstract final class AppRoutes {
  static const String splash = '/splash';
  static const String onboarding = '/onboarding';
  static const String auth = '/auth';
  static const String home = '/home';
  static const String createIncident = '/incidents/new';
  static const String documentCapture = '/incidents/new/document';
  static const String documentMetadata = '/incidents/new/document/metadata';
  static const String issueType = '/incidents/new/issue-type';
  static const String evidenceCapture = '/incidents/new/evidence';
  static const String voiceDescription = '/incidents/new/description';
  static const String factsReview = '/incidents/new/facts-review';
  static const String reserve = '/incidents/new/reserve';
  static const String finalDocument = '/incidents/new/final-document';
  static const String checklist = '/incidents/new/checklist';
  static const String dossierComplete = '/incidents/new/complete';
  static const String history = '/history';
  static const String incidentDetail = '/incidents/:incidentId';
  static const String account = '/account';
  static const String paywall = '/paywall';
  static const String error = '/error';
}

/// R0.1 (point 13 - "l'utilisateur doit pouvoir commencer à créer un
/// incident immédiatement, pas de compte cloud obligatoire") : ce routeur
/// ne définit AUCUN `redirect` gardant `AppRoutes.home`/`createIncident`/
/// etc. derrière `AppRoutes.auth`. `AppRoutes.splash` -> `AppRoutes.home`
/// (ou `onboarding` la première fois) est un chemin valide sans jamais
/// passer par `auth`. Si une fonctionnalité de compte/synchronisation cloud
/// est ajoutée plus tard (hors scope V1, voir
/// docs/adr/0002-local-first-pivot.md), elle devra rester un choix
/// utilisateur explicite depuis `AccountScreen`, jamais un blocage au
/// démarrage.
final GoRouter appRouter = GoRouter(
  initialLocation: AppRoutes.splash,
  routes: <RouteBase>[
    GoRoute(
      path: AppRoutes.splash,
      builder: (BuildContext context, GoRouterState state) => const SplashScreen(),
    ),
    GoRoute(
      path: AppRoutes.onboarding,
      builder: (BuildContext context, GoRouterState state) => const OnboardingScreen(),
    ),
    GoRoute(
      path: AppRoutes.auth,
      builder: (BuildContext context, GoRouterState state) => const AuthScreen(),
    ),
    GoRoute(
      path: AppRoutes.home,
      builder: (BuildContext context, GoRouterState state) => const HomeScreen(),
    ),
    GoRoute(
      path: AppRoutes.createIncident,
      builder: (BuildContext context, GoRouterState state) => const CreateIncidentScreen(),
    ),
    GoRoute(
      path: AppRoutes.documentCapture,
      builder: (BuildContext context, GoRouterState state) => const DocumentCaptureScreen(),
    ),
    GoRoute(
      path: AppRoutes.documentMetadata,
      builder: (BuildContext context, GoRouterState state) => const DocumentMetadataScreen(),
    ),
    GoRoute(
      path: AppRoutes.issueType,
      builder: (BuildContext context, GoRouterState state) => const IssueTypeScreen(),
    ),
    GoRoute(
      path: AppRoutes.evidenceCapture,
      builder: (BuildContext context, GoRouterState state) => const EvidenceCaptureScreen(),
    ),
    GoRoute(
      path: AppRoutes.voiceDescription,
      builder: (BuildContext context, GoRouterState state) => const VoiceDescriptionScreen(),
    ),
    GoRoute(
      path: AppRoutes.factsReview,
      builder: (BuildContext context, GoRouterState state) => const FactsReviewScreen(),
    ),
    GoRoute(
      path: AppRoutes.reserve,
      builder: (BuildContext context, GoRouterState state) => const ReserveScreen(),
    ),
    GoRoute(
      path: AppRoutes.finalDocument,
      builder: (BuildContext context, GoRouterState state) => const FinalDocumentScreen(),
    ),
    GoRoute(
      path: AppRoutes.checklist,
      builder: (BuildContext context, GoRouterState state) => const ChecklistScreen(),
    ),
    GoRoute(
      path: AppRoutes.dossierComplete,
      builder: (BuildContext context, GoRouterState state) => const DossierCompleteScreen(),
    ),
    GoRoute(
      path: AppRoutes.history,
      builder: (BuildContext context, GoRouterState state) => const HistoryScreen(),
    ),
    GoRoute(
      path: AppRoutes.incidentDetail,
      builder: (BuildContext context, GoRouterState state) => IncidentDetailScreen(
        incidentId: state.pathParameters['incidentId'] ?? '',
      ),
    ),
    GoRoute(
      path: AppRoutes.account,
      builder: (BuildContext context, GoRouterState state) => const AccountScreen(),
    ),
    GoRoute(
      path: AppRoutes.paywall,
      builder: (BuildContext context, GoRouterState state) => const PaywallScreen(),
    ),
    GoRoute(
      path: AppRoutes.error,
      builder: (BuildContext context, GoRouterState state) {
        final Object? extra = state.extra;
        final String message = extra is String
            ? extra
            : 'Une erreur est survenue. Vos preuves sont sauvegardées.';
        return ErrorScreen(message: message);
      },
    ),
  ],
);

/// Helpers de navigation - centralisent les `context.push(...)` pour éviter
/// de disperser des chemins littéraux dans les écrans (section 3.3 -
/// parcours nominal à 7 étapes).
extension AppNavigation on BuildContext {
  void pushCreateIncident() => push(AppRoutes.createIncident);
  void pushDocumentCapture() => push(AppRoutes.documentCapture);
  void pushDocumentMetadata() => push(AppRoutes.documentMetadata);
  void pushIssueType() => push(AppRoutes.issueType);
  void pushEvidenceCapture() => push(AppRoutes.evidenceCapture);
  void pushVoiceDescription() => push(AppRoutes.voiceDescription);
  void pushFactsReview() => push(AppRoutes.factsReview);
  void pushReserve() => push(AppRoutes.reserve);
  void pushFinalDocument() => push(AppRoutes.finalDocument);
  void pushChecklist() => push(AppRoutes.checklist);
  void pushDossierComplete() => push(AppRoutes.dossierComplete);
  void pushHistory() => push(AppRoutes.history);
  void pushIncidentDetail(String incidentId) =>
      push('/incidents/$incidentId');
  void pushAccount() => push(AppRoutes.account);
  void pushPaywall() => push(AppRoutes.paywall);
  void pushErrorScreen(String message) => push(AppRoutes.error, extra: message);

  // `pop()` n'est PAS redéfini ici : `GoRouterHelper.pop()` (ré-exporté
  // ci-dessus) est utilisé directement par les écrans qui importent ce
  // fichier, pour rester cohérent avec la pile de navigation de go_router.
}
