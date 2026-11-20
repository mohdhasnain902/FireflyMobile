import 'dart:async';

import 'package:firefly_mobile/core/providers.dart';
import 'package:firefly_mobile/data/dao/device_meta_dao.dart';
import 'package:firefly_mobile/data/repositories/entity_repositories.dart';
import 'package:firefly_mobile/domain/entities/tag.dart';
import 'package:firefly_mobile/ui/configs/entity_configs.dart';
import 'package:firefly_mobile/ui/models/entity_config.dart';
import 'package:firefly_mobile/ui/screens/entity_list_screen.dart';
import 'package:firefly_mobile/ui/widgets/sync_badge.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 hides `Override` behind misc.dart; flutter_riverpod re-exports it.
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/db/app_database_test.dart';
import 'support/tags_test_config.dart';

/// Widget tests for the generic EntityConfig-driven list screen (P2.2.1,
/// P2.2.5) — real in-memory SQLite behind the production `tagsConfig`, so the
/// provider → rows → write path is exercised end to end, not mocked.
///
/// Covers: loading, empty, error+retry, populated rows with pending badges,
/// the popup edit/delete flows (delete round-trips through softDelete),
/// FAB/row navigation into the form, and `canWrite: false` gating.
void main() {
  setUpAll(sqfliteFfiInit);

  // One in-memory connection for the whole suite (the ffi no-isolate factory
  // hands back the same `:memory:` handle per open — same convention as
  // sync_repository_test.dart). setUp wipes the three tables these tests
  // touch, which also rewinds the seq counter.
  late Database db;
  late DeviceMetaDao meta;
  late TagRepository tags;

  setUpAll(() async {
    db = await openTestDatabase();
    meta = DeviceMetaDao(db);
    tags = TagRepository(db: db, meta: meta);
  });

  setUp(() async {
    await db.delete('op_log');
    await db.delete('tags');
    await db.delete('device_meta');
  });

  /// Binds the production `tagRepositoryProvider` (and thereby the production
  /// `tagListProvider`, which watches it) to this suite's database.
  Override repoOverride() => tagRepositoryProvider.overrideWith(
    (ref) async => TagRepository(db: db, meta: meta),
  );

  /// Seeds one locally created tag through the real write path — it lands
  /// pending (syncStatus default) with one queued create op.
  Future<Tag> seed(String name) {
    return tags.create(
      (id, at, seq) => Tag(id: id, tag: name, updatedAt: at, seq: seq),
    );
  }

  Future<void> pumpList(
    WidgetTester tester, {
    EntityConfig<Tag>? config,
    List<Override> extra = const [],
  }) {
    return tester.pumpWidget(
      ProviderScope(
        overrides: [repoOverride(), ...extra],
        child: MaterialApp(
          home: EntityListScreen<Tag>(config: config ?? tagsConfig),
        ),
      ),
    );
  }

  testWidgets('shows a spinner while the list provider is pending', (
    tester,
  ) async {
    // A never-completing provider keeps the screen in its loading branch —
    // hence plain pump() rather than pumpAndSettle() (the spinner animates
    // forever and would never settle).
    final pending = Completer<List<Tag>>();
    await pumpList(
      tester,
      extra: [tagListProvider.overrideWith((ref) => pending.future)],
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('empty database renders the empty state with a create FAB', (
    tester,
  ) async {
    await pumpList(tester);
    await tester.pumpAndSettle();

    expect(find.text('No Tags yet'), findsOneWidget);
    expect(find.text('Pull down to refresh'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('provider failure renders the error view with a working Retry', (
    tester,
  ) async {
    await pumpList(
      tester,
      extra: [
        tagListProvider.overrideWith((ref) async => throw Exception('boom')),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.text('Could not load tags.'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Retry'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);

    // Retry just re-invalidates; with the override still throwing the view
    // must survive the refetch without blowing up.
    await tester.tap(find.widgetWithText(OutlinedButton, 'Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Could not load tags.'), findsOneWidget);
  });

  testWidgets('populated list shows rows, pending badges and row menus', (
    tester,
  ) async {
    await seed('Coffee');
    await seed('Espresso');

    await pumpList(tester);
    await tester.pumpAndSettle();

    expect(find.text('Coffee'), findsOneWidget);
    expect(find.text('Espresso'), findsOneWidget);
    // Locally created rows are pending until the server acks them.
    expect(find.byType(SyncBadge), findsNWidgets(2));
    expect(find.byIcon(Icons.schedule), findsNWidgets(2));
    // Writable entity → one overflow menu per row plus the create FAB.
    expect(find.byIcon(Icons.more_vert), findsNWidgets(2));
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  testWidgets('canWrite: false hides FAB and row menus but still lists rows', (
    tester,
  ) async {
    await seed('Coffee');
    final readOnly = tagsConfigForTest(
      canWrite: false,
      repoOf: (ref) async => tags,
    );

    await pumpList(tester, config: readOnly);
    await tester.pumpAndSettle();

    expect(find.text('Coffee'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.byIcon(Icons.more_vert), findsNothing);
  });

  testWidgets('overflow → Delete asks, then soft-deletes through the repo', (
    tester,
  ) async {
    final row = await seed('Coffee');

    await pumpList(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    // Confirmation dialog (singular + row title from the config).
    expect(find.text('Delete tag?'), findsOneWidget);
    expect(find.textContaining('"Coffee" will be marked'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    // Row left the visible list (tombstones are filtered by getAll) …
    expect(find.text('No Tags yet'), findsOneWidget);
    final rows = await db.query('tags', where: 'id = ?', whereArgs: [row.id]);
    expect(rows, hasLength(1), reason: 'soft delete must keep the row');
    expect(rows.single['deleted_at'], isNotNull, reason: 'must be tombstoned');
    // … and the delete was queued exactly once.
    final ops = await db.query('op_log');
    expect(ops, hasLength(2)); // 1 create + 1 delete
  });

  testWidgets('tapping a row opens the edit form and back returns', (
    tester,
  ) async {
    await seed('Coffee');

    await pumpList(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Coffee'));
    await tester.pumpAndSettle();
    expect(find.text('Edit tag'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Tag'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Coffee'), findsOneWidget);
  });

  testWidgets('FAB opens the create form and back returns to the list', (
    tester,
  ) async {
    await pumpList(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('New tag'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('No Tags yet'), findsOneWidget);
  });

  group('search (P2.2.1)', () {
    testWidgets('filters rows case-insensitively as you type', (
      tester,
    ) async {
      await seed('Coffee');
      await seed('Espresso');

      await pumpList(tester);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'esp');
      await tester.pumpAndSettle();

      expect(find.text('Espresso'), findsOneWidget);
      expect(find.text('Coffee'), findsNothing);
      expect(find.byType(ListTile), findsOneWidget);
    });

    testWidgets('clear button restores the full list', (tester) async {
      await seed('Coffee');
      await seed('Espresso');

      await pumpList(tester);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsNothing);

      await tester.tap(find.byKey(const Key('clear-search')));
      await tester.pumpAndSettle();

      expect(find.text('Coffee'), findsOneWidget);
      expect(find.text('Espresso'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('no matches shows the no-match view, not the empty state', (
      tester,
    ) async {
      await seed('Coffee');

      await pumpList(tester);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();

      expect(find.text('No matches for "zzz"'), findsOneWidget);
      // Distinguishable from the true-empty state ("No Tags yet").
      expect(find.text('No Tags yet'), findsNothing);
      expect(find.byIcon(Icons.search_off_outlined), findsOneWidget);
    });

    testWidgets('empty database shows no search field at all', (
      tester,
    ) async {
      await pumpList(tester);
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      expect(find.text('No Tags yet'), findsOneWidget);
    });
  });
}
