// KEPT regression sweep (was throwaway; promoted 2026-10-23 with R23).
// Targeted hunt for the reported 49px RenderFlex overflow in the screens the
// first sweep never laid out: Settings (past ListView cacheExtent) and the
// PAT/backup-token button rows in both states.
//
// No FlutterError.onError override: the test binding already records overflow
// errors and prints their full widget chain — a capture sink silently swallows
// non-overflow errors and trips the binding's `_pendingExceptionDetails`
// assertion (R22-style trap).
import 'package:firefly_mobile/core/providers.dart';
import 'package:firefly_mobile/core/settings/connection_settings.dart';
import 'package:firefly_mobile/ui/screens/settings_screen.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

/// Drives Settings at [logical] width through every state/scroll position.
Future<void> driveSettings(WidgetTester tester, double logical) async {
  tester.view.physicalSize = Size(logical * 3, 640 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  final store = InMemoryConnectionSettingsStore(
    const ConnectionSettings(
      baseUrl: 'https://firefly.example.com',
      pat: 'secret-token-value',
      backupUrl: 'http://pc:8095',
      backupToken: 'secret-backup-token',
    ),
  );
  final overrides = <Override>[
    connectionSettingsStoreProvider.overrideWith((_) async => store),
    // Settings never opens the DB here; overriding stops the FFI chain (R19).
    databaseProvider.overrideWith((_) async => throw UnimplementedError()),
  ];

  Future<void> pumpSettings() async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Brings [f] into view even when it sits below the ListView cacheExtent.
  Future<void> scrollTo(Finder f) async {
    if (f.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        f,
        200,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
  }

  /// Drags the whole ListView both ways so every child (Diagnostics, Sync,
  /// About — below the cacheExtent at phone heights) lays out.
  Future<void> scrollWholeList() async {
    final scrollable = find.byType(Scrollable).first;
    for (var i = 0; i < 14; i++) {
      await tester.drag(scrollable, const Offset(0, -240));
      await tester.pumpAndSettle();
    }
    for (var i = 0; i < 14; i++) {
      await tester.drag(scrollable, const Offset(0, 240));
      await tester.pumpAndSettle();
    }
  }

  // Pass A: saved-token state (Replace + Clear side by side) + full scroll.
  await pumpSettings();
  await scrollWholeList();

  // Two 'Replace' buttons exist (PAT + backup token) — scope to the first
  // so ensureVisible's `.single` does not throw "Too many elements".
  final replaceBtn = find.widgetWithText(FilledButton, 'Replace').first;

  // Pass B: PAT editing row (Save token + Cancel).
  await scrollTo(replaceBtn);
  await tester.tap(replaceBtn);
  await tester.pumpAndSettle();
  await scrollWholeList();

  // Pass C: backup-token editing row (Add backup token → Save + Cancel).
  final addBackup = find.widgetWithText(FilledButton, 'Add backup token');
  if (addBackup.evaluate().isNotEmpty) {
    await scrollTo(addBackup);
    await tester.tap(addBackup);
    await tester.pumpAndSettle();
    await scrollWholeList();
  }

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  for (final w in [320.0, 360.0, 393.0, 412.0]) {
    testWidgets('diagnostic: Settings overflow hunt @ $w', (tester) async {
      await driveSettings(tester, w);
    });
  }
}
