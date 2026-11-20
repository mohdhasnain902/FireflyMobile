import 'package:firefly_mobile/app.dart';
import 'package:firefly_mobile/core/providers.dart';
import 'package:firefly_mobile/core/settings/connection_settings.dart';
import 'package:firefly_mobile/ui/screens/home_screen.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'data/db/app_database_test.dart';

/// P0 smoke test: the app must build, render and show its home shell.
///
/// This is the CI gate — if it fails, the scaffold itself is broken, so no
/// feature work can land. Feature tests live beside their module from P1 on.
///
/// **Why the `databaseProvider` override (R19):** `FireflyApp`'s boot chain
/// opens the real database (on Linux: dart:io path creation + FFI isolate).
/// `testWidgets` runs a fake-async zone in which real dart:io/isolate futures
/// never settle, so `pumpAndSettle` spins on the sync-status spinner forever.
/// The pre-opened in-memory DB here is created in `setUpAll` (real async) and
/// swapped in via the documented seam (`providers.dart`: tests override seam
/// providers). No other boot seam touches real async — lifecycle sync fires
/// on resume transitions only, never at cold start.
void main() {
  setUpAll(sqfliteFfiInit);

  // Opened once, outside any fake-async test body (DIAG: real async stalls
  // under `testWidgets` but runs fine in a plain `setUpAll`/`test` zone).
  late Database db;
  setUpAll(() async {
    db = await openTestDatabase();
  });

  // Seam override so the boot chain queries the in-memory DB (no dart:io,
  // no isolate) instead of running the real Linux open path.
  // demoSeedEnabledProvider=false keeps the empty-DB smoke expectations
  // (auto-seed would populate the DB between frames).
  Override dbOverride() => databaseProvider.overrideWith((ref) async => db);

  // The real connection-settings store hits Keystore/dart:io via the meta
  // path, which never settles under testWidgets' fake-async zone (same R19
  // class of stall as the real DB open). In-memory store = same contract,
  // no real async. Seeded with a base URL: `_HomeOrOnboarding` gates on
  // empty baseUrl and would render OnboardingScreen instead of HomeScreen.
  Override settingsOverride() => connectionSettingsStoreProvider.overrideWith(
        (ref) async => InMemoryConnectionSettingsStore(
          const ConnectionSettings(baseUrl: 'http://localhost'),
        ),
      );

  testWidgets('app boots and renders the home shell', (tester) async {
    await tester.pumpWidget(
      FireflyApp(
        overrides: [
          dbOverride(),
          settingsOverride(),
          demoSeedEnabledProvider.overrideWithValue(false),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // MaterialApp must be present and the bottom-nav home shell must render.
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'home shell shows NavigationBar and the active tab title '
      '"Dashboard" (Phase 1 bottom-nav redesign)', (tester) async {
    await tester.pumpWidget(
      FireflyApp(
        overrides: [
          dbOverride(),
          settingsOverride(),
          demoSeedEnabledProvider.overrideWithValue(false),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    // App-bar title tracks the active tab; Dashboard is default index 0.
    expect(find.text('Dashboard'), findsWidgets);
  });
}
