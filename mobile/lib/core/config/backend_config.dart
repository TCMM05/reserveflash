/// Configuration du backend ReserveFlash côté mobile (R2 - premier appel
/// réseau optionnel de l'app, voir `lib/data/remote/ai_api_client.dart`).
///
/// Aucune valeur par défaut ne peut être correcte pour tous les contextes
/// d'exécution (émulateur Android, simulateur iOS, appareil physique sur le
/// même réseau, environnement de recette/prod). Cette configuration ne
/// contient JAMAIS de clé API OpenAI (voir `docs/security.md`, GATE
/// secret) : l'app ne parle qu'au backend ReserveFlash, jamais à OpenAI
/// directement (flux imposé section 4/5, voir docstring de
/// `lib/data/remote/ai_api_client.dart`).
library;

/// URL de base du backend ReserveFlash (sans slash final), surchargeable au
/// build/run via `--dart-define=RESERVEFLASH_BACKEND_BASE_URL=...` (ex:
/// `flutter run --dart-define=RESERVEFLASH_BACKEND_BASE_URL=http://192.168.1.42:8000`).
///
/// Valeur par défaut : `10.0.2.2` est l'alias réseau standard de
/// l'émulateur Android vers `localhost` de la machine hôte qui fait tourner
/// le backend (`uvicorn app.main:app`, voir `backend/README.md`). Cette
/// valeur par défaut ne convient PAS à :
/// - un simulateur iOS - utiliser `http://localhost:8000` ;
/// - un appareil physique (Android ou iOS) - utiliser l'IP LAN de la
///   machine qui exécute le backend, ex: `http://192.168.1.42:8000` ;
/// - un environnement de recette/prod - utiliser l'URL publique du backend
///   déployé.
const String backendBaseUrl = String.fromEnvironment(
  'RESERVEFLASH_BACKEND_BASE_URL',
  defaultValue: 'http://10.0.2.2:8000',
);
