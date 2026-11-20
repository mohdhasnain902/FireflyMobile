import 'package:firefly_mobile/app.dart';
import 'package:firefly_mobile/core/providers.dart';
import 'package:firefly_mobile/core/settings/connection_settings.dart';
import 'package:firefly_mobile/ui/screens/dashboard_screen.dart';
import 'package:firefly_mobile/ui/screens/entity_list_screen.dart';
import 'package:firefly_mobile/ui/screens/reports_screen.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/db/app_database_test.dart';

/// Widget tests for the Phase 1 bottom-nav shell: five destinations,
/// tab switching, and per-tab app-bar titles. Boot seam mirrors
/// app_smoke_test (R19): pre-opened in-memory DB swapped in via
/// [databaseProvider] override so real dart:io/FFI never run under
/// fake async.
void main() {
  setUpAll(sqfliteFfiInit);

  late Database db;
  setUpAll(() async {
    db = await openTestDatabase();
  });

  Override dbOverride() => databaseProvider.overrideWith((ref) async => db);

  Future<void> pumpShell(WidgetTester tester) async {
    await tester.pumpWidget(
      FireflyApp(
        overrides: [
          dbOverride(),
          // Keep the DB empty: the home shell's post-frame auto-seed would
          // otherwise populate it mid-pump and change list counts.
          demoSeedEnabledProvider.overrideWithValue(false),
          // Pre-configure a baseUrl so _HomeOrOnboarding reaches HomeScreen
          // instead of hanging forever on the real secure-storage read
          // (DeviceConnectionSettingsStore never settles under fake async).
          // No cold-start sync fires (baseUrl is not probed here), so the
          // dummy origin causes no network traffic in tests.
          connectionSettingsStoreProvider.overrideWith(
            (_) async => InMemoryConnectionSettingsStore(
              const ConnectionSettings(baseUrl: 'http://localhost:8080'),
            ),
          ),
        ],
      ),
    );
    // Dashboard watches five async providers; give them one settle pass.
    await tester.pumpAndSettle();
  }

  testWidgets('shell has NavigationBar with five destinations', (tester) async {
    await pumpShell(tester);

    final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(navBar.destinations.length, 5);
    expect(
      navBar.destinations.map((d) => switch (d) {
            NavigationDestination(
              :final label,
              icon: Icon(icon: final IconData data),
            ) =>
              (label, data),
            _ => null,
          }),
      [
        ('Dashboard', Icons.dashboard_outlined),
        ('Transactions', Icons.swap_vert),
        ('Budgets', Icons.savings_outlined),
        ('Reports', Icons.pie_chart_outline),
        ('Settings', Icons.settings_outlined),
      ],
    );
  });

  testWidgets('default tab is Dashboard (title + body present)',
      (tester) async {
    await pumpShell(tester);

    expect(find.text('Dashboard'), findsWidgets);
    expect(find.byType(DashboardScreen), findsOneWidget);
    // IndexedStack keeps siblings in the tree — visibility is the check.
    // byType matches exact runtimeType, so the generic
    // EntityListScreen<Transaction> needs a predicate, not byType.
    expect(
      find.byWidgetPredicate((w) => w is EntityListScreen).hitTestable(),
      findsNothing,
    );
  });

  testWidgets('tapping Transactions switches the app-bar title and body',
      (tester) async {
    await pumpShell(tester);

    await tester.tap(find.text('Transactions'));
    await tester.pumpAndSettle();

    expect(find.text('Transactions'), findsWidgets);
    // Embedded list (no own app bar) under the shell's Transactions title.
    // Predicate: runtimeType is EntityListScreen<Transaction>, not bare
    // EntityListScreen, so find.byType would miss it.
    expect(
      find.byWidgetPredicate((w) => w is EntityListScreen).hitTestable(),
      findsOneWidget,
    );
  });

  testWidgets('tapping Budgets, Reports and Settings updates the title',
      (tester) async {
    await pumpShell(tester);

    await tester.tap(find.text('Budgets'));
    await tester.pumpAndSettle();
    expect(find.text('Budgets'), findsWidgets);

    await tester.tap(find.text('Reports'));
    await tester.pumpAndSettle();
    expect(find.text('Reports'), findsWidgets);
    expect(find.byType(ReportsScreen).hitTestable(), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsWidgets);
  });

  testWidgets('NavigationBar selection index tracks taps', (tester) async {
    await pumpShell(tester);

    var navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(navBar.selectedIndex, 0);

    await tester.tap(find.text('Reports'));
    await tester.pumpAndSettle();
    navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(navBar.selectedIndex, 3);
  });
}
