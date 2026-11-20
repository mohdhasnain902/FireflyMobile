// KEPT regression sweep (was throwaway; promoted 2026-10-23 with R23).
// Sweeps viewports + navigation depth to reproduce the reported 49px
// RenderFlex overflow and print the offending widget chain.
import 'package:firefly_mobile/app.dart';
import 'package:firefly_mobile/core/providers.dart';
import 'package:firefly_mobile/core/settings/connection_settings.dart';
import 'package:firefly_mobile/ui/screens/dashboard_screen.dart';
import 'package:firefly_mobile/ui/screens/services_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/db/app_database_test.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late Database db;
  setUpAll(() async {
    db = await openTestDatabase();
  });

  Override dbOverride() => databaseProvider.overrideWith((ref) async => db);

  // Boot seam mirrors home_shell_test/smoke (R19): the real
  // DeviceConnectionSettingsStore reads Keystore/dart:io, which never
  // settles under fake async → pumpAndSettle times out. In-memory store
  // with a baseUrl also keeps _HomeOrOnboarding off OnboardingScreen.
  Override settingsOverride() => connectionSettingsStoreProvider.overrideWith(
        (_) async => InMemoryConnectionSettingsStore(
          const ConnectionSettings(baseUrl: 'http://localhost:8080'),
        ),
      );

  Future<void> pumpShell(WidgetTester tester, {required bool seed}) async {
    await tester.pumpWidget(
      FireflyApp(
        overrides: [
          dbOverride(),
          settingsOverride(),
          demoSeedEnabledProvider.overrideWithValue(seed),
        ],
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Sweeps one seed mode across phone widths, tapping every tab and then
  /// drilling into the sub-screens reachable from More.
  Future<void> sweep(WidgetTester tester, {required bool seed}) async {
    for (final logical in [320.0, 360.0, 393.0, 412.0, 600.0, 800.0]) {
      tester.view.physicalSize = Size(logical * 3, 640 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await pumpShell(tester, seed: seed);

      // Scope tab taps to the NavigationBar: bare find.text('Transactions')
      // matches both the destination label and the current AppBar title
      // (ambiguous hit test, R24).
      Finder tab(String label) => find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(label),
          );

      for (final label in [
        'Transactions',
        'Budgets',
        'Reports',
        'More',
        'Dashboard',
      ]) {
        if (tab(label).evaluate().isEmpty) continue;
          await tester.tap(tab(label));
          await tester.pumpAndSettle();
        }

        // --- ServicesScreen drill (Dashboard 'More' quick tile) -------------
        // The tab loop ends on 'Dashboard', so the quick-access grid is the
        // frontmost route. Scope to DashboardScreen: bare find.text('More')
        // would also match the NavigationBar destination label.
        final moreTile = find.descendant(
          of: find.byType(DashboardScreen),
          matching: find.text('More'),
        );
        // Empty when the dashboard body rendered its loading/error state
        // (no _QuickAccessGrid) — skip the whole drill, not just the tap.
        if (moreTile.evaluate().isNotEmpty) {
          await tester.ensureVisible(moreTile);
          await tester.pumpAndSettle();
          await tester.tap(moreTile);
          await tester.pumpAndSettle();

          if (find.byType(ServicesScreen).evaluate().isNotEmpty) {
            // a) AppBar Edit/Done toggle — pure setState, no favorites
            //    mutation, so tile counts stay deterministic across widths.
            final edit = find.widgetWithText(TextButton, 'Edit');
            if (edit.evaluate().isNotEmpty) {
              await tester.tap(edit);
              await tester.pumpAndSettle();
              final done = find.widgetWithText(TextButton, 'Done');
              if (done.evaluate().isNotEmpty) {
                await tester.tap(done);
                await tester.pumpAndSettle();
              }
            }

            // b) first favorite _ServiceTile IconButton → pushes its page.
            final favTile = find.descendant(
              of: find.byType(ServicesScreen),
              matching: find.byType(IconButton),
            );
            if (favTile.evaluate().isNotEmpty) {
              await tester.ensureVisible(favTile.first);
              await tester.pumpAndSettle();
              await tester.tap(favTile.first);
              await tester.pumpAndSettle();
              final back1 = find.byTooltip('Back');
              if (back1.evaluate().isNotEmpty) {
                await tester.pageBack();
                await tester.pumpAndSettle();
              }
            }

            // c) 'About' ListTile → pushes AboutScreen.
            final about = find.descendant(
              of: find.byType(ServicesScreen),
              matching: find.widgetWithText(ListTile, 'About'),
            );
            if (about.evaluate().isNotEmpty) {
              await tester.ensureVisible(about);
              await tester.pumpAndSettle();
              await tester.tap(about);
              await tester.pumpAndSettle();
              final back2 = find.byTooltip('Back');
              if (back2.evaluate().isNotEmpty) {
                await tester.pageBack();
                await tester.pumpAndSettle();
              }
            }
            debugPrint('-- $logical / ServicesScreen settled --');
          }

          // d) back to Dashboard.
          final back3 = find.byTooltip('Back');
          if (back3.evaluate().isNotEmpty) {
            await tester.pageBack();
            await tester.pumpAndSettle();
          }
        }

        // Re-tap More so sub-screen drill starts from that tab (already
      // scoped — bare find.text('More') warnIfMissed when AppBar collides).
      if (tab('More').evaluate().isNotEmpty) {
        await tester.tap(tab('More'));
        await tester.pumpAndSettle();
      }
      for (final sub in ['Accounts', 'Categories', 'Settings']) {
        final tile = find.widgetWithText(ListTile, sub);
        if (tile.evaluate().isEmpty) continue;
        // Bottom nav can overlap lower list tiles at 320×640 — scroll the
        // tile clear before tapping (R24 Categories miss → pageBack 0-match).
        await tester.ensureVisible(tile);
        await tester.pumpAndSettle();
        await tester.tap(tile);
        await tester.pumpAndSettle();
        debugPrint('-- $logical / $sub settled --');
        // Only pop if the tap actually pushed a route (Material AppBar
        // exposes tooltip 'Back'; More tab itself has none).
        final back = find.byTooltip('Back');
        if (back.evaluate().isNotEmpty) {
          await tester.pageBack();
          await tester.pumpAndSettle();
        }
      }
    }
  }

  testWidgets(
    'diagnostic: sweep for the overflow',
    (tester) async {
    final errors = <String>[];
    final prev = FlutterError.onError;
    FlutterError.onError = (details) {
      // details.toString() includes informationCollector — the widget
      // chain that pinpoints the overflowing RenderFlex.
      errors.add('### ${details.exceptionAsString()}\n$details');
    };

    // finally: sweep itself can throw (tap on missing widget, settle
    // timeout). Leaving onError overridden then wedges the binding
    // (_pendingExceptionDetails assertion) and hangs tearDownAll until
    // the suite timeout (R24). Restore must not depend on reaching line 87.
    try {
      await sweep(tester, seed: true);
      await sweep(tester, seed: false);
    } finally {
      FlutterError.onError = prev;
    }

    debugPrint('=== CAPTURED ${errors.length} error(s) ===');
    final seen = <String>{};
    for (final e in errors) {
      final head = e.split('\n').first;
      if (seen.add(head)) debugPrint(e);
    }
    expect(errors, isEmpty, reason: 'see printed stacks for location');
    },
    // Two full seed sweeps over 6 widths exceed the default 10-min budget.
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
