import 'package:firefly_mobile/ui/screens/about_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Widget tests for the P2.4 About/licenses screen.
///
/// Asserts the bundled NOTICE.md (registered under `flutter: assets:` in
/// pubspec.yaml) actually renders as read-only text. This is the attribution
/// gate for SQLCipher (BSD-3-Clause) and friends, so a silent load failure is
/// a licensing bug, not a cosmetic one — the screen must show content, never
/// an empty body.
void main() {
  testWidgets('renders the bundled NOTICE.md as scrollable text', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: AboutScreen()));
    // First frame: loading spinner while rootBundle resolves the asset.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Two pumps: one to let the asset future complete, one to rebuild with
    // the loaded text (pumpAndSettle can race a single future kick).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    // Spot-check real content, not just "some text rendered".
    expect(find.textContaining('Open-source notices'), findsOneWidget);
    expect(find.textContaining('SQLCipher'), findsOneWidget);
    expect(find.text('Notices unavailable'), findsNothing);
  });
}
