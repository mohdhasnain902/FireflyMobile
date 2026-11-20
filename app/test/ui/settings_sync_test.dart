import 'dart:async';
import 'dart:convert';

import 'package:firefly_mobile/core/errors/failure.dart';
import 'package:firefly_mobile/core/providers.dart';
import 'package:firefly_mobile/core/settings/connection_probe.dart';
import 'package:firefly_mobile/core/settings/connection_settings.dart';
import 'package:firefly_mobile/data/api/firefly_api_client.dart';
import 'package:firefly_mobile/data/sync/pull_engine.dart'
    show PullEntityStats, PullStats;
import 'package:firefly_mobile/data/sync/sync_controller.dart';
import 'package:firefly_mobile/data/sync/sync_engine.dart';
import 'package:firefly_mobile/ui/screens/settings_screen.dart';
import 'package:firefly_mobile/ui/screens/sync_log_screen.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 hides `Override` behind misc.dart; flutter_riverpod re-exports it.
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/db/app_database_test.dart';

/// Widget tests for the Settings "Sync" section (P3.4, Story 2).
///
/// Every sync trigger must go through [SyncController]'s probe gate, so each
/// test injects a controller built from stub seams and asserts exactly what
/// the gate let through: no-server and unreachable probes must never touch
/// the engine, the button disables while a cycle is in flight, and a cycle
/// that really runs (real [SyncEngine] + [MockClient], no live network)
/// reports its outcome through the SnackBar. The Story 5 "Restore from
/// server" tile follows the same contract: a destructive confirm dialog is
/// its only gate, cancel runs nothing, and a confirmed restore reports the
/// wipe+pull outcome (or the gate's skip) through the SnackBar.
/// `describeSyncAttempt` — the SnackBar formatter — gets pure unit coverage
/// at the bottom.
void main() {
  setUpAll(sqfliteFfiInit);

  Override settingsOverride(ConnectionSettingsStore store) =>
      connectionSettingsStoreProvider.overrideWith((_) async => store);

  /// Pumps [SettingsScreen] with the settings store and sync controller
  /// both replaced — the store feeds the screen's fields, the controller
  /// feeds the "Sync now" button.
  Future<void> pumpSettings(
    WidgetTester tester, {
    required ConnectionSettingsStore store,
    required SyncController controller,
    List<Override> extraOverrides = const [],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsOverride(store),
          syncControllerProvider.overrideWithValue(controller),
          ...extraOverrides,
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Brings the Sync-tile button into the built window before tapping.
  ///
  /// The PC-backup section (P4.1) sits above the Sync tile and can push
  /// 'Sync now' past the ListView cacheExtent, where ensureVisible would
  /// hit "Bad state: No element" (same lazy-range trap as the About tile).
  /// Scrollable of the Settings list itself.
  ///
  /// `find.byType(Scrollable).first` resolves to the first *text field's*
  /// internal horizontal scrollable (the screen has three Scrollables), so
  /// `scrollUntilVisible` dragged horizontally, the list never moved, and
  /// every one of these button tests died with "Bad state: No element"
  /// before tapping anything.
  Finder settingsScrollable() => find
      .descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      )
      .first;

  Finder syncNowFinder() =>
      find.widgetWithText(FilledButton, 'Sync now (both ways)');

  /// Bounded settle: avoids `pumpAndSettle` timing out on indeterminate
  /// progress animations in this test environment while still advancing
  /// async work and frame callbacks enough for UI updates. Stays under the
  /// 4s SnackBar timeout so assertions can still see the snack.
  Future<void> settle(
    WidgetTester tester, {
    int frames = 10,
    Duration step = const Duration(milliseconds: 100),
  }) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(step);
    }
  }

  Future<void> tapSyncNow(WidgetTester tester) async {
    final syncNow = syncNowFinder();
    if (syncNow.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        syncNow,
        200,
        scrollable: settingsScrollable(),
      );
    }
    await tester.ensureVisible(syncNow);
    await tester.tap(syncNow);
  }

  /// Handler for an empty-but-well-formed Firefly list response — what a
  /// server with nothing new returns for every collection GET.
  http.Response emptyList(http.Request _) => http.Response(
    jsonEncode({
      'data': <dynamic>[],
      'meta': {
        'pagination': {
          'total': 0,
          'count': 0,
          'per_page': 100,
          'current_page': 1,
          'total_pages': 1,
          'links': <String, dynamic>{},
        },
      },
    }),
    200,
  );

  /// Handler failing every GET — exercises the `!ok` SnackBar path.
  /// Fails **one** list endpoint. A pull continues past a failed entity (R39),
  /// so failing all thirteen only made the test wait through every retry
  /// budget — the cycle still reports the failure, which is what this pins.
  http.Response currenciesError(http.Request request) =>
      request.url.path.endsWith('/currencies')
          ? http.Response('{"message":"boom"}', 500)
          : emptyList(request);

  /// A real engine over [db] that talks to [handler] instead of a server.
  /// [handler] may return a [Future] so a test can gate the first response
  /// (e.g. a completer held open while widget state is asserted).
  SyncEngine buildEngine(
    Database db,
    FutureOr<http.Response> Function(http.Request) handler,
  ) =>
      SyncEngine(
        db: db,
        client: FireflyApiClient(
          settings: InMemoryConnectionSettingsStore(
            const ConnectionSettings(
              baseUrl: 'https://firefly.test',
              pat: 'tok',
            ),
          ),
          httpClient: MockClient((req) async => await handler(req)),
        ),
        now: () => DateTime.utc(2026, 10, 18, 12),
      );

  testWidgets('Sync now with no server: gate skips, engine never builds', (
    tester,
  ) async {
    var engineBuilds = 0;
    var probeCalls = 0;
    final store = InMemoryConnectionSettingsStore();
    await pumpSettings(
      tester,
      store: store,
      controller: SyncController(
        engine: () async {
          engineBuilds++;
          fail('engine must not be built when the gate skips');
        },
        isConfigured: () async => (await store.read()).isConfigured,
        probe: () async {
          probeCalls++;
          return const ProbeResult(ProbeStatus.ok);
        },
      ),
    );

    await tapSyncNow(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      find.text('No server configured yet — add one in Settings.'),
      findsOneWidget,
    );
    expect(engineBuilds, 0, reason: 'gate must stop before the engine');
    expect(probeCalls, 0, reason: 'unconfigured must not even probe');
  });

  testWidgets('unreachable: gate reports failure, engine untouched', (
    tester,
  ) async {
    var engineBuilds = 0;
    final store = InMemoryConnectionSettingsStore(
      const ConnectionSettings(baseUrl: 'https://x.example', pat: 'tok'),
    );
    await pumpSettings(
      tester,
      store: store,
      controller: SyncController(
        engine: () async {
          engineBuilds++;
          fail('engine must not be built when the probe fails');
        },
        isConfigured: () async => (await store.read()).isConfigured,
        probe: () async => const ProbeResult(ProbeStatus.unreachable),
      ),
    );

    await tapSyncNow(tester);
    await settle(tester);

    expect(
      find.text('Firefly is unreachable — will retry when it is back.'),
      findsOneWidget,
    );
    expect(engineBuilds, 0);
  });

  testWidgets('button disables and shows a spinner while a cycle runs', (
    tester,
  ) async {
    final store = InMemoryConnectionSettingsStore(
      const ConnectionSettings(baseUrl: 'https://x.example', pat: 'tok'),
    );
    await pumpSettings(
      tester,
      store: store,
      controller: SyncController(
        engine: () async => fail('probe fails, so no engine'),
        isConfigured: () async => true,
        probe: () async {
          await Future<void>.delayed(const Duration(milliseconds: 80));
          return const ProbeResult(ProbeStatus.unreachable);
        },
      ),
    );

    await tapSyncNow(tester);
    // One frame after the tap: the handler has entered its first await.
    await tester.pump();

    final busyButton = find.widgetWithText(FilledButton, 'Syncing…');
    expect(busyButton, findsOneWidget);
    expect(tester.widget<FilledButton>(busyButton).onPressed, isNull,
        reason: 'a second tap must not join mid-flight');

    // Let the delayed probe finish; the gate skips and the SnackBar lands.
    await tester.pump(const Duration(milliseconds: 100));
    await settle(tester);
    expect(
      find.text('Firefly is unreachable — will retry when it is back.'),
      findsOneWidget,
    );
  });

  testWidgets('a real cycle reports success and appends two log lines', (
    tester,
  ) async {
    final db = await openTestDatabase();
    final store = InMemoryConnectionSettingsStore(
      const ConnectionSettings(baseUrl: 'https://x.example', pat: 'tok'),
    );
    final engine = buildEngine(db, emptyList);
    await pumpSettings(
      tester,
      store: store,
      controller: SyncController(
        engine: () async => engine,
        isConfigured: () async => true,
        probe: () async => const ProbeResult(ProbeStatus.ok),
      ),
    );

    await tapSyncNow(tester);
    await settle(tester);

    expect(
      find.text('Sync complete — already up to date'),
      findsOneWidget,
    );
    // Push + pull + the post-cycle backup/skip line (no backup URL saved).
    final rows = await db.query('sync_log');
    expect(rows, hasLength(3), reason: 'cycle must be auditable in-app');
  });

  testWidgets('a failed cycle reports the failure in the SnackBar', (
    tester,
  ) async {
    final db = await openTestDatabase();
    final store = InMemoryConnectionSettingsStore(
      const ConnectionSettings(baseUrl: 'https://x.example', pat: 'tok'),
    );
    final engine = buildEngine(db, currenciesError);
    await pumpSettings(
      tester,
      store: store,
      controller: SyncController(
        engine: () async => engine,
        isConfigured: () async => true,
        probe: () async => const ProbeResult(ProbeStatus.ok),
      ),
    );

    await tapSyncNow(tester);
    // The pull leg retries with backoff, so wait for the SnackBar to appear
    // rather than assuming a fixed number of frames.
    for (var i = 0;
        i < 100 && find.textContaining('Sync failed').evaluate().isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(find.textContaining('Sync failed'), findsOneWidget);
  });

  testWidgets('Sync log tile opens the log screen with live rows', (
    tester,
  ) async {
    final store = InMemoryConnectionSettingsStore();
    // Fake the log query itself so opening the screen never reaches the
    // engine (and therefore never opens the real database in a widget test).
    final logOverride = syncLogProvider.overrideWith(
      (_) async => <SyncLogEntry>[
        const SyncLogEntry(
          id: 1,
          startedAtMs: 1760760303000,
          phase: 'push',
          status: 'ok',
          pushedOps: 12,
        ),
      ],
    );
    await pumpSettings(
      tester,
      store: store,
      controller: SyncController(
        engine: () async => fail('opening the log must not run a sync'),
        isConfigured: () async => false,
        probe: () async => const ProbeResult(ProbeStatus.unreachable),
      ),
      extraOverrides: [logOverride],
    );

    // The log tile sits below the initial ListView cacheExtent, so it is
    // not built yet: scroll until lazy layout materialises it, then pull
    // it into the viewport (the PC-backup section can leave it built-but
    // still off-screen, where tap would hit-test nothing), then tap.
    await tester.scrollUntilVisible(
      find.widgetWithText(ListTile, kSyncLogTitle),
      200,
      scrollable: settingsScrollable(),
    );
    await tester.ensureVisible(find.widgetWithText(ListTile, kSyncLogTitle));
    await settle(tester);
    await tester.tap(find.widgetWithText(ListTile, kSyncLogTitle));
    await settle(tester);

    expect(find.byType(SyncLogScreen), findsOneWidget);
    expect(find.text('Push'), findsOneWidget);
    expect(find.text('12 ops pushed'), findsOneWidget);
  });

  // ── Restore from server (Story 5) ─────────────────────────────────────────

  testWidgets('restore tile asks for confirmation; Cancel runs nothing', (
    tester,
  ) async {
    var engineBuilds = 0;
    final store = InMemoryConnectionSettingsStore(
      const ConnectionSettings(baseUrl: 'https://x.example', pat: 'tok'),
    );
    await pumpSettings(
      tester,
      store: store,
      controller: SyncController(
        engine: () async {
          engineBuilds++;
          fail('a cancelled restore must never reach the engine');
        },
        isConfigured: () async => true,
        probe: () async => const ProbeResult(ProbeStatus.ok),
      ),
    );

    // The restore tile sits below the ListView cacheExtent (after the Sync
    // section), so it is not built yet: scroll until lazy layout materialises
    // it, then tap.
    await tester.scrollUntilVisible(
      find.widgetWithText(ListTile, 'Restore from server'),
      200,
      scrollable: settingsScrollable(),
    );
    await tester.tap(find.widgetWithText(ListTile, 'Restore from server'));
    await settle(tester);
    // The destructive confirm dialog is the only gate.
    expect(find.text('Restore from server?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await settle(tester);

    expect(find.text('Restore from server?'), findsNothing);
    expect(engineBuilds, 0, reason: 'cancel must not touch the controller');
  });

  testWidgets('confirmed restore runs, wipes local rows, reports the outcome',
      (tester) async {
    final db = await openTestDatabase();
    // A local-only row the wipe must remove (empty server re-creates it).
    await db.insert('currencies', {
      'id': 'loc-cur',
      'code': 'EUR',
      'name': 'Euro',
      'symbol': '€',
      'symbol_first': 0,
      'decimal_places': 2,
      'enabled': 1,
      'is_default': 0,
      'rate': '1.0',
      'firefly_id': 'srv-eur',
      'updated_at': 1000,
      'remote_updated_at': 1000,
      'sync_status': 'synced',
      'deleted_at': null,
      'seq': 1,
    });
    final store = InMemoryConnectionSettingsStore(
      const ConnectionSettings(baseUrl: 'https://x.example', pat: 'tok'),
    );
    final engine = buildEngine(db, emptyList);
    await pumpSettings(
      tester,
      store: store,
      controller: SyncController(
        engine: () async => engine,
        isConfigured: () async => true,
        probe: () async => const ProbeResult(ProbeStatus.ok),
      ),
    );

    // The restore tile sits below the ListView cacheExtent (after the Sync
    // section), so it is not built yet: scroll until lazy layout materialises
    // it, then tap.
    await tester.scrollUntilVisible(
      find.widgetWithText(ListTile, 'Restore from server'),
      200,
      scrollable: settingsScrollable(),
    );
    await tester.tap(find.widgetWithText(ListTile, 'Restore from server'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Erase & restore'));
    await settle(tester);

    expect(
      find.text('Restored from server — 0 added, 0 updated'),
      findsOneWidget,
    );
    final rows = await db.query('currencies');
    expect(rows, isEmpty, reason: 'the wipe must remove local-only rows');
    await db.close();
  });

  testWidgets('restore with no server: gate skips, engine never builds', (
    tester,
  ) async {
    var engineBuilds = 0;
    final store = InMemoryConnectionSettingsStore();
    await pumpSettings(
      tester,
      store: store,
      controller: SyncController(
        engine: () async {
          engineBuilds++;
          fail('engine must not be built when the gate skips');
        },
        isConfigured: () async => (await store.read()).isConfigured,
        probe: () async => const ProbeResult(ProbeStatus.ok),
      ),
    );

    // The restore tile sits below the ListView cacheExtent (after the Sync
    // section), so it is not built yet: scroll until lazy layout materialises
    // it, then tap.
    await tester.scrollUntilVisible(
      find.widgetWithText(ListTile, 'Restore from server'),
      200,
      scrollable: settingsScrollable(),
    );
    await tester.tap(find.widgetWithText(ListTile, 'Restore from server'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Erase & restore'));
    await settle(tester);

    expect(
      find.text('No server configured yet — add one in Settings.'),
      findsOneWidget,
    );
    expect(engineBuilds, 0, reason: 'gate must stop before the engine');
  });

  testWidgets('tile disables and spins while a restore is in flight', (
    tester,
  ) async {
    final release = Completer<void>();
    final db = await openTestDatabase();
    final store = InMemoryConnectionSettingsStore(
      const ConnectionSettings(baseUrl: 'https://x.example', pat: 'tok'),
    );
    // The first GET (currencies) blocks until the test releases the completer.
    var gated = false;
    final engine = buildEngine(db, (request) {
      if (!gated) {
        gated = true;
        return release.future.then((_) => emptyList(request));
      }
      return Future.value(emptyList(request));
    });
    await pumpSettings(
      tester,
      store: store,
      controller: SyncController(
        engine: () async => engine,
        isConfigured: () async => true,
        probe: () async => const ProbeResult(ProbeStatus.ok),
      ),
    );

    // The restore tile sits below the ListView cacheExtent (after the Sync
    // section), so it is not built yet: scroll until lazy layout materialises
    // it, then tap.
    await tester.scrollUntilVisible(
      find.widgetWithText(ListTile, 'Restore from server'),
      200,
      scrollable: settingsScrollable(),
    );
    await tester.tap(find.widgetWithText(ListTile, 'Restore from server'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Erase & restore'));
    await tester.pump();

    final tile = tester.widget<ListTile>(
      find.widgetWithText(ListTile, 'Restore from server'),
    );
    expect(tile.enabled, isFalse, reason: 'a second restore must not start');
    // trailing wraps the spinner in a fixed-size SizedBox.
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Restore from server'),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
      reason: 'an in-flight restore shows a spinner in the tile',
    );

    release.complete();
    await settle(tester);
    expect(
      find.text('Restored from server — 0 added, 0 updated'),
      findsOneWidget,
    );
    await db.close();
  });

  group('describeSyncAttempt', () {
    test('surfaces gate skips verbatim', () {
      expect(
        describeSyncAttempt(
          const SyncAttempt.skippedBy(SyncSkipReason.unauthorized),
        ),
        SyncSkipReason.unauthorized.message,
      );
    });

    test('says "already up to date" for a clean empty cycle', () {
      expect(
        describeSyncAttempt(
          const SyncAttempt.ran(
            SyncOutcome(ok: true, pushedOps: 0, pull: PullStats({})),
          ),
        ),
        'Sync complete — already up to date',
      );
    });

    test('lists every non-zero counter of a busy cycle', () {
      expect(
        describeSyncAttempt(
          const SyncAttempt.ran(
            SyncOutcome(
              ok: true,
              pushedOps: 3,
              pull: PullStats({
                'currencies': PullEntityStats(
                  inserted: 1,
                  updated: 2,
                  tombstoned: 1,
                ),
              }),
            ),
          ),
        ),
        'Sync complete — pushed 3, +1 new, ~2 updated, −1 removed',
      );
    });

    test('reports push-only work when pull never ran', () {
      expect(
        describeSyncAttempt(
          const SyncAttempt.ran(
            SyncOutcome(ok: true, pushedOps: 5, pull: null),
          ),
        ),
        'Sync complete — pushed 5',
      );
    });

    test('leads with "Sync failed" and keeps the failure message', () {
      expect(
        describeSyncAttempt(
          const SyncAttempt.ran(
            SyncOutcome(
              ok: false,
              pushedOps: 0,
              pull: null,
              failure: ValidationFailure('disk exploded'),
            ),
          ),
        ),
        'Sync failed — disk exploded',
      );
    });

    test('degrades to "Sync failed" when no failure was recorded', () {
      expect(
        describeSyncAttempt(
          const SyncAttempt.ran(
            SyncOutcome(ok: false, pushedOps: 0, pull: null),
          ),
        ),
        'Sync failed',
      );
    });
  });
}
