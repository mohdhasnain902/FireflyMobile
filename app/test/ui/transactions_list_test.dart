import 'package:firefly_mobile/core/providers.dart';
import 'package:firefly_mobile/data/dao/device_meta_dao.dart';
import 'package:firefly_mobile/data/repositories/entity_repositories.dart';
import 'package:firefly_mobile/domain/entities/currency.dart';
import 'package:firefly_mobile/domain/entities/sync_bookkeeping.dart';
import 'package:firefly_mobile/domain/entities/transaction.dart';
import 'package:firefly_mobile/ui/configs/entity_configs.dart';
import 'package:firefly_mobile/ui/models/entity_config.dart';
import 'package:firefly_mobile/ui/screens/entity_list_screen.dart';
import 'package:firefly_mobile/ui/theme/app_theme.dart';
import 'package:firefly_mobile/ui/widgets/sync_badge.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 hides `Override` behind misc.dart; flutter_riverpod re-exports it.
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

import '../data/db/app_database_test.dart';

/// Widget tests for the transactions-specific 2nd-UI list
/// (docs/2nd UI 2.png): card rows, Today/Yesterday day-grouping,
/// All/Withdrawals/Deposits/Transfers filter pills, signed colored amounts
/// with thousands grouping and currency symbol, tag chips, and the labeled
/// "New transaction" FAB — all through the production `transactionsConfig`
/// and a real in-memory SQLite database (single `databaseProvider`
/// override, same recipe as the airplane-mode integration test).
void main() {
  setUpAll(sqfliteFfiInit);

  late Database db;
  late DeviceMetaDao meta;
  late TransactionRepository repo;

  setUpAll(() async {
    db = await openTestDatabase();
    meta = DeviceMetaDao(db);
    repo = TransactionRepository(db: db, meta: meta);
  });

  // Wipe every table the list + its subtitle hooks touch so each test runs
  // hermetically: rows, the op queue, the seq counter, and currencies
  // (symbol resolution).
  setUp(() async {
    for (final table in [
      'transactions',
      'op_log',
      'device_meta',
      'currencies',
    ]) {
      await db.delete(table);
    }
  });

  /// One override binds every repository (they all derive from
  /// `databaseProvider`) to the suite's in-memory database.
  List<Override> overrides() => [
    databaseProvider.overrideWith((ref) async => db),
  ];

  Future<void> pumpList(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: MaterialApp(
          home: EntityListScreen<Transaction>(config: transactionsConfig),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Seeds one transaction through the production write path (pending row
  /// + queued op), exactly like a local create on the phone.
  Future<void> seed({
    required String type,
    required String description,
    required String amount,
    required DateTime date,
    String? currencyCode,
    String? sourceName,
    String? destName,
    String? categoryName,
    String? tagsJson,
  }) async {
    await repo.create(
      (id, at, seq) => Transaction(
        id: id,
        type: type,
        description: description,
        date: date,
        amount: amount,
        updatedAt: at,
        seq: seq,
        currencyCode: currencyCode,
        sourceName: sourceName,
        destName: destName,
        categoryName: categoryName,
        tagsJson: tagsJson,
      ),
    );
  }

  /// Currencies are pull-only, so the USD row is inserted straight into the
  /// table (same pattern as `sync_repository_test`) for the symbol tests.
  Future<void> seedUsdCurrency() async {
    await db.insert(
      'currencies',
      Currency(
        id: 'cur-usd',
        code: 'USD',
        name: 'US Dollar',
        symbol: r'$',
        updatedAt: DateTime.now().toUtc(),
        seq: 1,
      ).toRow(),
    );
  }

  final now = DateTime.now();
  // Deterministic same-day instants: 00:00 is always ≤ 23:59, so the
  // newest-first sort holds regardless of the wall clock the suite runs at
  // (a wall-clock `now` can sit before an 08:00 anchor in PKT evenings).
  final todayEarly = DateTime(now.year, now.month, now.day);
  final todayLate = DateTime(now.year, now.month, now.day, 23, 59);
  final yesterdayNoon = DateTime(
    now.year,
    now.month,
    now.day - 1,
    12,
  );
  final jan15 = DateTime(2020, 1, 15, 12);

  testWidgets(
    'empty database shows the empty state with a labeled New transaction FAB',
    (tester) async {
      await pumpList(tester);
      expect(find.text('No Transactions yet'), findsOneWidget);
      // Extended FAB: label text lives inside the button, not as a tooltip.
      expect(
        find.widgetWithText(FloatingActionButton, 'New transaction'),
        findsOneWidget,
      );
      // Search + filter pills only appear once there is something to filter.
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);
    },
  );

  testWidgets(
    'rows render as cards with type icons, search hint, pills and badges',
    (tester) async {
      await seed(
        type: 'withdrawal',
        description: 'Coffee',
        amount: '4.50',
        date: now,
        currencyCode: 'USD',
      );
      await seed(
        type: 'deposit',
        description: 'Paycheck',
        amount: '1200.50',
        date: now,
      );
      await seed(
        type: 'transfer',
        description: 'Move',
        amount: '1000',
        date: now,
      );
      await pumpList(tester);

      // Card rows (cardRows: true wraps each ListTile in a Card).
      expect(find.byType(Card), findsNWidgets(3));
      expect(find.text('Coffee'), findsOneWidget);
      expect(find.text('Paycheck'), findsOneWidget);
      expect(find.text('Move'), findsOneWidget);

      // Leading type glyphs: − / + / ⇄ (one of each type seeded). Scoped
      // to the Cards — the extended FAB also carries an Icons.add glyph.
      Finder inCards(Finder f) => find.descendant(
        of: find.byType(Card),
        matching: f,
      );
      expect(inCards(find.byIcon(Icons.remove)), findsOneWidget);
      expect(inCards(find.byIcon(Icons.add)), findsOneWidget);
      expect(inCards(find.byIcon(Icons.swap_horiz)), findsOneWidget);

      // Search hint + the four pills (All + the three config filters).
      expect(find.text('Search transactions'), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNWidgets(4));
      for (final label in ['All', 'Withdrawals', 'Deposits', 'Transfers']) {
        expect(find.text(label), findsOneWidget);
      }

      // Locally created rows carry the pending badge (schema default).
      expect(find.byType(SyncBadge), findsNWidgets(3));
      expect(find.byIcon(Icons.schedule), findsNWidgets(3));
      expect(find.byTooltip('Pending sync'), findsNWidgets(3));

      // Writable config → per-row overflow menu.
      expect(find.byIcon(Icons.more_vert), findsNWidgets(3));
    },
  );

  testWidgets(
    'day sections run Today → Yesterday → older, newest first within a day',
    (tester) async {
      // Created oldest-first; the grouped list must re-sort newest-first.
      await seed(
        type: 'withdrawal',
        description: 'Old rent',
        amount: '500.00',
        date: jan15,
      );
      await seed(
        type: 'withdrawal',
        description: 'Yesterday tea',
        amount: '3.00',
        date: yesterdayNoon,
      );
      await seed(
        type: 'withdrawal',
        description: 'Earlier coffee',
        amount: '4.50',
        date: todayEarly,
      );
      await seed(
        type: 'deposit',
        description: 'Late bonus',
        amount: '99.00',
        date: todayLate,
      );
      await pumpList(tester);

      // Section headers: Today / Yesterday / `MMM d` (en_US).
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Yesterday'), findsOneWidget);
      expect(find.text('Jan 15'), findsOneWidget);

      // Vertical order proves both the day grouping and the newest-first
      // sort: Today's later row sits above the earlier one, then Yesterday,
      // then the older section.
      double dy(Finder f) => tester.getTopLeft(f).dy;
      expect(dy(find.text('Today')), lessThan(dy(find.text('Late bonus'))));
      expect(
        dy(find.text('Late bonus')),
        lessThan(dy(find.text('Earlier coffee'))),
      );
      expect(
        dy(find.text('Earlier coffee')),
        lessThan(dy(find.text('Yesterday'))),
      );
      expect(
        dy(find.text('Yesterday')),
        lessThan(dy(find.text('Yesterday tea'))),
      );
      expect(
        dy(find.text('Yesterday tea')),
        lessThan(dy(find.text('Jan 15'))),
      );
      expect(dy(find.text('Jan 15')), lessThan(dy(find.text('Old rent'))));
    },
  );

  testWidgets(
    'amounts group digits, take the type sign and prepend the currency symbol',
    (tester) async {
      await seedUsdCurrency();
      // Plain withdrawal → type sign, symbol, two decimals.
      await seed(
        type: 'withdrawal',
        description: 'Coffee',
        amount: '4.50',
        date: now,
        currencyCode: 'USD',
      );
      // Deposit → plus sign, thousands separator.
      await seed(
        type: 'deposit',
        description: 'Salary',
        amount: '1200.50',
        date: now,
        currencyCode: 'USD',
      );
      // Transfer → no type sign (textPrimary), still grouped + symbol.
      await seed(
        type: 'transfer',
        description: 'Move',
        amount: '1000',
        date: now,
        currencyCode: 'USD',
      );
      // Raw negative already carries its sign — not doubled.
      await seed(
        type: 'withdrawal',
        description: 'Refund adjust',
        amount: '-7.25',
        date: now,
        currencyCode: 'USD',
      );
      // Unresolved currency → clean number, no symbol.
      await seed(
        type: 'withdrawal',
        description: 'Cashback',
        amount: '9.99',
        date: now,
      );
      await pumpList(tester);

      expect(find.text(r'-$4.50'), findsOneWidget);
      expect(find.text(r'+$1,200.50'), findsOneWidget);
      expect(find.text(r'$1,000'), findsOneWidget);
      expect(find.text(r'-$7.25'), findsOneWidget);
      expect(find.text('-9.99'), findsOneWidget);

      // Amount colors match the palette: withdrawal/cancel = negative,
      // deposit = primary, transfer = plain text.
      Color? colorOf(String label) =>
          tester.widget<Text>(find.text(label)).style?.color;
      expect(colorOf(r'-$4.50'), FireflyPalette.negative);
      expect(colorOf(r'+$1,200.50'), FireflyPalette.primary);
      expect(colorOf(r'$1,000'), FireflyPalette.textPrimary);

      // Trailing time is the row's local HH:mm.
      final expectedTime = DateFormat(
        'HH:mm',
        'en_US',
      ).format(now.toLocal());
      expect(find.text(expectedTime), findsWidgets);
    },
  );

  testWidgets(
    'subtitle falls back from category to type; first tag renders as a chip',
    (tester) async {
      // Category name + explicit source name both win over the type word.
      await seed(
        type: 'withdrawal',
        description: 'Market',
        amount: '20.00',
        date: now,
        categoryName: 'Groceries',
        sourceName: 'Cash',
        tagsJson: '["groceries","weekly"]',
      );
      // Transfer joins both accounts with an arrow; head = 'Transfer'.
      await seed(
        type: 'transfer',
        description: 'Move savings',
        amount: '100.00',
        date: now,
        sourceName: 'Checking',
        destName: 'Savings',
      );
      // Invalid tags_json: not a tag, no chip, row still renders.
      await seed(
        type: 'withdrawal',
        description: 'BadJSON',
        amount: '5.00',
        date: now,
        tagsJson: 'not-json',
      );
      // Deposit falls back to the type word + destination name.
      await seed(
        type: 'deposit',
        description: 'Bonus',
        amount: '50.00',
        date: now,
        destName: 'Revenue',
      );
      await pumpList(tester);

      expect(find.text('Groceries · Cash'), findsOneWidget);
      // Only the FIRST tag becomes the mini chip.
      expect(find.text('groceries'), findsOneWidget);
      expect(find.text('weekly'), findsNothing);

      expect(find.text('Transfer · Checking → Savings'), findsOneWidget);
      // Bad JSON → plain type head, no chip, no crash.
      expect(find.text('Withdrawal'), findsOneWidget);
      expect(find.text('Deposit · Revenue'), findsOneWidget);
    },
  );

  testWidgets(
    'filter pills narrow the list and label the no-match view when empty',
    (tester) async {
      await seed(
        type: 'withdrawal',
        description: 'Coffee',
        amount: '4.50',
        date: now,
      );
      await seed(
        type: 'deposit',
        description: 'Paycheck',
        amount: '1200.50',
        date: now,
      );
      // No transfer seeded — the Transfers pill must hit the no-match view.
      await pumpList(tester);
      expect(find.byType(ListTile), findsNWidgets(2));

      await tester.tap(find.text('Deposits'));
      await tester.pump();
      expect(find.byType(ListTile), findsOneWidget);
      expect(find.text('Paycheck'), findsOneWidget);
      expect(find.text('Coffee'), findsNothing);

      await tester.tap(find.text('Transfers'));
      await tester.pump();
      expect(find.byType(ListTile), findsNothing);
      expect(find.text('No matches for "Transfers"'), findsOneWidget);

      // Back to All restores every row.
      await tester.tap(find.text('All'));
      await tester.pump();
      expect(find.byType(ListTile), findsNWidgets(2));
      expect(find.text('Coffee'), findsOneWidget);
      expect(find.text('Paycheck'), findsOneWidget);
    },
  );

  testWidgets('search matches title and the plain-text subtitle', (
    tester,
  ) async {
    await seed(
      type: 'withdrawal',
      description: 'Coffee shop',
      amount: '4.50',
      date: now,
    );
    await seed(
      type: 'deposit',
      description: 'Paycheck',
      amount: '1200.50',
      date: now,
    );
    await seed(
      type: 'transfer',
      description: 'Move savings',
      amount: '100.00',
      date: yesterdayNoon,
    );
    await pumpList(tester);
    expect(find.byType(ListTile), findsNWidgets(3));

    // Title match.
    await tester.enterText(find.byType(TextField), 'paycheck');
    await tester.pump();
    expect(find.byType(ListTile), findsOneWidget);
    expect(find.text('Paycheck'), findsOneWidget);

    // Clear button (appears with text) restores the full list.
    await tester.tap(find.byKey(const Key('clear-search')));
    await tester.pump();
    expect(find.byType(ListTile), findsNWidgets(3));

    // Subtitle match: `_matches` runs against the plain-text rowSubtitle
    // ('deposit · 1200.50 · …'), not the widget subtitle — 'deposit' must
    // surface the deposit row while withdrawal/transfer rows stay hidden.
    await tester.enterText(find.byType(TextField), 'deposit');
    await tester.pump();
    expect(find.text('Paycheck'), findsOneWidget);
    expect(find.text('Coffee shop'), findsNothing);
    expect(find.text('Move savings'), findsNothing);

    // No hits → the query labels the no-match view (lowercased).
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump();
    expect(find.byType(ListTile), findsNothing);
    expect(find.text('No matches for "zzz"'), findsOneWidget);
  });

  testWidgets(
    'full-precision Firefly amounts keep the row usable at phone width',
    (tester) async {
      // R25 regression pin. Firefly sends amounts at full precision
      // (`2023.440000000000`); rendering that raw made the trailing column
      // wider than the whole ListTile, so every row threw "Trailing widget
      // consumes the entire tile width", descriptions collapsed to one
      // character per line and the ⋮ menu could not be hit — which is what
      // made Delete look dead on the phone.
      tester.view.physicalSize = const Size(360 * 3, 720 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await seedUsdCurrency();
      await seed(
        type: 'withdrawal',
        description: 'Utility bill',
        amount: '2023.440000000000',
        date: now,
        currencyCode: 'USD',
      );
      await seed(
        type: 'deposit',
        description: 'Big deposit',
        amount: '1234567.890000000000',
        date: now,
        currencyCode: 'USD',
      );
      await pumpList(tester);

      expect(
        tester.takeException(),
        isNull,
        reason: 'the row must fit the tile at 360dp',
      );
      // Rounded to two decimals, trailing zeros dropped, digits grouped.
      expect(find.text(r'-$2,023.44'), findsOneWidget);
      expect(find.text(r'+$1,234,567.89'), findsOneWidget);

      // The description still renders as one line, not per character.
      expect(tester.getSize(find.text('Utility bill')).height, lessThan(40));

      // The ⋮ menu sits inside the 360dp viewport and opens the actions.
      final menu = find.byIcon(Icons.more_vert).first;
      expect(tester.getTopRight(menu).dx, lessThanOrEqualTo(360));
      await tester.tap(menu);
      await tester.pumpAndSettle();
      expect(find.text('Delete'), findsOneWidget);
    },
  );

  testWidgets(
    'config.buildListScreen() (More-tab push) re-binds T and renders rows',
    (tester) async {
      // R20 regression pin: the More tab iterates `allEntityConfigs` typed
      // List<EntityConfig<SyncBookkeeping>>. Constructing the screen with
      // the erased type bound T to SyncBookkeeping while the runtime config
      // stays EntityConfig<Transaction> — rowTitle's runtime closure
      // (Transaction)=>String then failed the (SyncBookkeeping)=>String
      // covariance check in _buildRow. The fix routes the push through
      // EntityConfig.buildListScreen(), which re-binds T virtually; this
      // test pins that fixed path under an erased static receiver.
      await seed(
        type: 'withdrawal',
        description: 'Coffee',
        amount: '4.50',
        date: now,
      );
      // Static receiver mirrors the More tab (List<EntityConfig<...>>).
      final EntityConfig<SyncBookkeeping> erased = transactionsConfig;
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides(),
          child: MaterialApp(home: erased.buildListScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Coffee'), findsOneWidget);
    },
  );
}
