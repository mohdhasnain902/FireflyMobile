import 'package:firefly_mobile/app.dart';
import 'package:firefly_mobile/ui/screens/home_screen.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// P0 smoke test: the app must build, render and show its home shell.
///
/// This is the CI gate — if it fails, the scaffold itself is broken, so no
/// feature work can land. Feature tests live beside their module from P1 on.
void main() {
  testWidgets('app boots and renders the home shell', (tester) async {
    await tester.pumpWidget(const FireflyApp());
    await tester.pumpAndSettle();

    // MaterialApp must be present and the placeholder home must render.
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home shell shows the product title', (tester) async {
    await tester.pumpWidget(const FireflyApp());
    await tester.pumpAndSettle();

    expect(find.text('Firefly III'), findsWidgets);
  });
}
