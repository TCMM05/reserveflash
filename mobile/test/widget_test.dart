// R0.2 (hotfix decouvert par execution reelle) : `flutter create .` regenere
// ce fichier avec son boilerplate par defaut (compteur `MyApp`), qui ne
// correspond a rien dans notre code (`flutter analyze` echouait avec
// `The name 'MyApp' isn't a class.` - notre app s'appelle `ReserveFlashApp`,
// voir lib/main.dart). Remplace par un smoke test minimal mais reel pour
// notre app.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:reserveflash/main.dart';

void main() {
  testWidgets('ReserveFlashApp demarre sans exception', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: ReserveFlashApp()));
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
