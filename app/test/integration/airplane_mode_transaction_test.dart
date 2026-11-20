import 'dart:io';

import 'package:firefly_mobile/core/providers.dart';
import 'package:firefly_mobile/data/dao/device_meta_dao.dart';
import 'package:firefly_mobile/data/repositories/entity_repositories.dart';
import 'package:firefly_mobile/domain/entities/transaction.dart';
import 'package:firefly_mobile/ui/configs/entity_configs.dart';
import 'package:firefly_mobile/ui/screens/entity_list_screen.dart';
import 'package:firefly_mobile/ui/widgets/sync_badge.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 hides `Override` behind misc.dart; flutter_riverpod re-exports it.
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

import '../data/db/app_database_test.dart';

/// Airplane-mode probe: counts every `HttpClient` creation so the test can
/// assert the offline write path never touches the network, and fails fast
/// like a dead radio if something ever tries (a real attempt would both
/// increment [attempts] and throw inside the app's call stack).
class _AirplaneHttpOverrides extends HttpOverrides {
  /// Number of network clients the app tried to open during the test.
  int attempts = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    attempts++;
    throw const SocketException('airplane mode: network is off');
  }
}

/// P2 exit integration test (IMPLEMENTATION-PLAN P2):
/// "create a transaction in airplane mode → verify it appears in the list
/// with `pending` badge" — exercised through the production UI stack:
/// real in-memory SQLite (single `databaseProvider` override), the
/// production `transactionsConfig`, the generic form/list screens, and the
/// op_log queue. Network is blocked + counted by [_AirplaneHttpOverrides],
/// so "no network calls" is asserted, not assumed.
void main() {
  setUpAll(sqfliteFfiInit);

  late Database db;
  late DeviceMetaDao meta;
  late _AirplaneHttpOverrides airplane;
  // Whatever HttpOverrides the test binding installed — restored afterwards
  // so other suites keep their default environment.
  HttpOverrides? previousOverrides;

  setUpAll(() async {
    db = await openTestDatabase();
    meta = DeviceMetaDao(db);
    airplane = _AirplaneHttpOverrides();
    // `current` is the readable side (zone override ?? global); restore via
    // the `global` setter — dart:io has no public `global` getter.
    previousOverrides = HttpOverrides.current;
    HttpOverrides.global = airplane;
  });

  tearDownAll(() {
    HttpOverrides.global = previousOverrides;
  });

  // Wipe every table the transactions flow touches: the row table itself,
  // the op queue, and the seq counter (device_meta). Business tables used
  // only as (empty) dropdown sources are wiped too so runs stay hermetic.
  setUp(() async {
    for (final table in [
      'transactions',
      'op_log',
      'device_meta',
      'accounts',
      'categories',
      'budgets',
      'bills',
    ]) {
      await db.delete(table);
    }
    airplane.attempts = 0;
  });

  /// One override binds every repository (they all derive from
  /// `databaseProvider`) to the suite's in-memory database.
  List<Override> overrides() => [
    databaseProvider.overrideWith((ref) async => db),
  ];

  Future<void> pumpList(WidgetTester tester) {
    return tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: MaterialApp(
          home: EntityListScreen<Transaction>(config: transactionsConfig),
        ),
      ),
    );
  }

  testWidgets(
    'offline create lands the transaction in the list with a pending badge',
    (tester) async {
      await pumpList(tester);
      await tester.pumpAndSettle();
      expect(find.text('No Transactions yet'), findsOneWidget);

      // Create via the production form: FAB → fill required fields → Save.
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.text('New transaction'), findsOneWidget);

      // Type is the first field (a choice dropdown over kTransactionTypes).
      // Reference dropdowns below it render as DropdownButtonFormField too,
      // so target the first one — field order matches config order.
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('withdrawal'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description'),
        'Coffee',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount'),
        '4.50',
      );
      // 'date' is required → the form pins it to today automatically.

      // Save via the AppBar TextButton (always mounted); the FilledButton at
      // the list's end is off-screen with 16 fields and may not be built yet.
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pumpAndSettle();

      // Back on the list: the row is visible with the pending badge —
      // locally created rows default to sync_status 'pending' (schema) and
      // nothing has acked them (nothing could: there is no network).
      expect(find.text('No Transactions yet'), findsNothing);
      expect(find.text('Coffee'), findsOneWidget);
      expect(find.byType(SyncBadge), findsOneWidget);
      expect(find.byIcon(Icons.schedule), findsOneWidget);
      // The label lives on the badge's Tooltip/semanticLabel, not a Text.
      expect(find.byTooltip('Pending sync'), findsOneWidget);

      // The write landed in SQLite with bookkeeping intact and exactly one
      // queued create op waiting for the P3 replay loop.
      final rows = await db.query('transactions');
      expect(rows, hasLength(1));
      expect(rows.single['description'], 'Coffee');
      expect(rows.single['type'], 'withdrawal');
      expect(rows.single['amount'], '4.50');
      expect(rows.single['deleted_at'], isNull);
      expect(
        rows.single['sync_status'],
        'pending',
        reason: 'unacked local write must stay pending',
      );

      final ops = await db.query('op_log');
      expect(ops, hasLength(1));
      expect(ops.single['entity_type'], 'transactions');
      expect(ops.single['action'], 'create');
      expect(ops.single['entity_id'], rows.single['id']);

      // Airplane mode held for the whole flow: the form, the save and the
      // list rebuild never attempted a single network call.
      expect(airplane.attempts, 0, reason: 'offline flow must not touch net');
    },
  );

  testWidgets('pull-to-refresh stays local and resolves to the same row', (
    tester,
  ) async {
    // Seed through the repo's write path (pending row + queued op), then
    // verify the refresh gesture re-queries SQLite only.
    final repo = TransactionRepository(db: db, meta: meta);
    await repo.create(
      (id, at, seq) => Transaction(
        id: id,
        type: 'withdrawal',
        description: 'Tea',
        date: DateTime.utc(2026, 10, 16),
        amount: '3.00',
        updatedAt: at,
        seq: seq,
      ),
    );

    await pumpList(tester);
    await tester.pumpAndSettle();
    expect(find.text('Tea'), findsOneWidget);

    // Drag down past the trigger threshold → RefreshIndicator runs its
    // onRefresh (local invalidate) and must settle back to the row.
    await tester.fling(
      find.byType(ListTile).first,
      const Offset(0, 300),
      1000,
    );
    await tester.pump();
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.text('Tea'), findsOneWidget);
    expect(
      find.byType(CircularProgressIndicator),
      findsNothing,
      reason: 'refresh must settle — no spinner left behind offline',
    );
    expect(airplane.attempts, 0, reason: 'refresh must not touch the network');
  });
}
