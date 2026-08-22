// R0.2 (hotfix decouvert par execution reelle) : `flutter create .` regenere
// ce fichier avec son boilerplate par defaut (compteur `MyApp`), qui ne
// correspond a rien dans notre code (`flutter analyze` echouait avec
// `The name 'MyApp' isn't a class.` - notre app s'appelle `ReserveFlashApp`,
// voir lib/main.dart). Remplace par un smoke test minimal mais reel pour
// notre app.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:reserveflash/core/network/connectivity_watcher.dart';
import 'package:reserveflash/core/providers/app_providers.dart';
import 'package:reserveflash/main.dart';

/// R2 (`[0.3.17]`) : `ReserveFlashApp` active désormais
/// `AiQueueConnectivityListener` dès la construction de son premier widget
/// (voir `lib/main.dart`), qui s'abonne immédiatement à
/// `ConnectivityWatcher.onBecameOnline`. Un `flutter test` classique (par
/// opposition à un test d'intégration sur un vrai appareil/émulateur) ne
/// fournit aucun canal de plateforme réel pour `connectivity_plus` - ce
/// smoke test reste donc volontairement isolé du plugin réel (même
/// principe que `OcrService`/`AiHttpTransport` ailleurs dans ce projet),
/// avec un faux `ConnectivityWatcher` qui n'émet jamais rien.
class _NoopConnectivityWatcher implements ConnectivityWatcher {
  @override
  Stream<void> get onBecameOnline => const Stream<void>.empty();

  @override
  Future<void> dispose() async {}
}

void main() {
  testWidgets('ReserveFlashApp demarre sans exception', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          connectivityWatcherProvider.overrideWithValue(_NoopConnectivityWatcher()),
        ],
        child: const ReserveFlashApp(),
      ),
    );
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
