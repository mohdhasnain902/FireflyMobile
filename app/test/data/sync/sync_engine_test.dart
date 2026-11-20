import 'dart:convert';
import 'dart:io';

import 'package:firefly_mobile/core/errors/failure.dart';
import 'package:firefly_mobile/core/settings/connection_settings.dart';
import 'package:firefly_mobile/data/api/firefly_api_client.dart';
import 'package:firefly_mobile/data/dao/device_meta_dao.dart';
import 'package:firefly_mobile/data/sync/backup_client.dart';
import 'package:firefly_mobile/data/sync/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../db/app_database_test.dart';

/// Unit tests for [SyncEngine] (P3.4, DESIGN §7.1).
///
/// Driven through an in-memory SQLite database (the real schema) and a
/// [MockClient] so no real network is touched. The handler dispatches on
/// method+path so one mock serves both the push phase (POST/PUT/DELETE) and
/// the pull phase (GET collection list) in a single cycle. Covers:
///   * push-then-pull ordering (push finishes before the first pull GET)
///   * empty queue + empty server → ok, zero pushed, zero pull stats
///   * push success records device_meta last_sync_ts + last_sync_status=ok
///   * push replay failure (stopped) → cycle fails but the pull still runs
///   * push network Err → cycle fails, pull runs and fails too
///   * pull failure on one entity → ok=false, failure set, other entities
///     still pulled
///   * a failed push never hides a website-side deletion (R38)
///   * sync_log: one push line + one pull line per successful cycle, newest
///     first, prune to kMaxSyncLogEntries
///   * restoreFromServer wipes op_log + every synced-entity table (14 total,
///     incl. recurrence_repetitions) then pulls; device_meta/sync_log survive
///   * PC backup (P4.1): a successful cycle fires POST /backup once and logs
///     backup/ok newest-first; backup failure logs backup/error but the sync
///     stays ok; no backup URL → no request and no log line; restore never
///     re-triggers the backup
void main() {
  setUpAll(sqfliteFfiInit);

  late Database db;
  late List<http.Request> requests;
  late DeviceMetaDao meta;

  /// Dispatches a cycle's HTTP: POST/PUT/DELETE → push, GET → pull.
  /// [failPull] forces the currencies list GET to 500 (one failing entity, not
  /// every one: a pull continues past a failure, so failing all of them would
  /// test nothing but the client's retry budget). [backup] is the optional
  /// PC-backup client injected into the engine (P4.1); when null the engine
  /// runs without a backup step, like production with the feature
  /// unconfigured.
  SyncEngine buildEngine({bool failPull = false, BackupClient? backup}) {
    requests = [];
    final store = InMemoryConnectionSettingsStore(
      const ConnectionSettings(baseUrl: 'https://firefly.test', pat: 'tok'),
    );
    final mock = MockClient((request) async {
      requests.add(request);
      if (request.method == 'GET') {
        // Pull phase — currencies collection.
        if (failPull && request.url.path.endsWith('/currencies')) {
          return http.Response('{"message":"boom"}', 500);
        }
        return http.Response(
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
      }
      // Push phase — a create. Returns a stored resource.
      return http.Response(
        jsonEncode({
          'data': {
            'type': 'categories',
            'id': 'srv-1',
            'attributes': <String, dynamic>{
              'name': 'Test',
              'updated_at': DateTime.utc(2026, 10, 16, 12)
                  .toIso8601String(),
            },
          },
        }),
        200,
      );
    });
    final client = FireflyApiClient(settings: store, httpClient: mock);
    return SyncEngine(
      db: db,
      client: client,
      backup: backup,
      now: () => DateTime.utc(2026, 10, 16, 13),
    );
  }

  /// Builds a [BackupClient] over its own recording [MockClient] so the
  /// engine's post-sync trigger is observable independently of the API
  /// traffic captured by [buildEngine]. Defaults to a sidecar-style
  /// `ok:true` 200; [handler] overrides the response per test.
  ({BackupClient client, List<http.Request> requests}) buildBackup({
    ConnectionSettings settings = const ConnectionSettings(
      baseUrl: 'https://firefly.test',
      backupUrl: 'http://pc:8095',
      backupToken: 'btok',
    ),
    Future<http.Response> Function(http.Request request)? handler,
  }) {
    final recorded = <http.Request>[];
    final mock = MockClient((request) async {
      recorded.add(request);
      if (handler != null) return await handler(request);
      return http.Response(
        '{"ok":true,"time":"20261019T103129Z",'
        '"snapshot":"/mnt/data/firefly-backups/firefly-x.sqlite"}',
        200,
      );
    });
    return (
      client: BackupClient(
        settings: InMemoryConnectionSettingsStore(settings),
        httpClient: mock,
      ),
      requests: recorded,
    );
  }

  /// Seeds one pending create op for a category plus its local row, so the
  /// push phase has exactly one op to replay.
  Future<void> seedPendingCreate() async {
    await db.insert('categories', {
      'id': 'loc-1',
      'name': 'Test',
      'firefly_id': null,
      'updated_at': 1000,
      'remote_updated_at': null,
      'sync_status': 'pending',
      'deleted_at': null,
      'seq': 1,
    });
    await db.insert('op_log', {
      'op_id': 'op-1',
      'entity_type': 'categories',
      'entity_id': 'loc-1',
      'action': 'create',
      'payload': jsonEncode({
        'type': 'categories',
        'attributes': {'name': 'Test'},
      }),
      'wall_ts': 1000,
      'device_id': 'dev-1',
      'seq': 1,
      'created_at': 1000,
      'attempts': 0,
      'last_error': null,
    });
  }

  /// Reads device_meta by key.
  Future<String?> metaGet(String key) async => await meta.get(key);

  setUp(() async {
    db = await openTestDatabase();
    meta = DeviceMetaDao(db);
    // Reset the per-test request recorder here (not only inside buildEngine)
    // so tests that build their own MockClient inline still have it
    // initialized — otherwise `late requests` throws on first use.
    requests = [];
  });

  tearDown(() async {
    await db.close();
  });

  // ── Ordering & success ─────────────────────────────────────────────────────

  test('empty queue + empty server → ok, zero push, empty pull stats',
      () async {
    final engine = buildEngine();
    final outcome = await engine.sync();

    expect(outcome.ok, isTrue);
    expect(outcome.failure, isNull);
    expect(outcome.pushedOps, 0);
    // Only pull GETs were issued (no push HTTP) — currencies list + budget
    // limits walk, but all are GETs, so no non-GET request exists.
    expect(requests.where((r) => r.method != 'GET'), isEmpty);
    expect(outcome.pull, isNotNull);
    expect(outcome.pull!.inserted, 0);
  });

  test('push runs before pull: a create op is POSTed before the first GET',
      () async {
    await seedPendingCreate();
    final engine = buildEngine();
    final outcome = await engine.sync();

    expect(outcome.ok, isTrue);
    expect(outcome.pushedOps, greaterThan(0));
    // First non-GET (push) precedes first GET (pull).
    final firstPushIdx = requests.indexWhere((r) => r.method != 'GET');
    final firstPullIdx = requests.indexWhere((r) => r.method == 'GET');
    expect(firstPushIdx, greaterThanOrEqualTo(0));
    expect(firstPullIdx, greaterThan(firstPushIdx));
  });

  test('successful cycle records last_sync_ts and last_sync_status=ok',
      () async {
    final engine = buildEngine();
    final outcome = await engine.sync();

    expect(outcome.ok, isTrue);
    final tsRaw = await metaGet(DeviceMetaDao.lastSyncTsKey);
    expect(tsRaw, DateTime.utc(2026, 10, 16, 13).millisecondsSinceEpoch
        .toString());
    expect(await metaGet(DeviceMetaDao.lastSyncStatusKey), 'ok');
  });

  // ── A push failure never cancels the pull (R38) ───────────────────────────

  test('push replay failure (stopped) fails the cycle but pull still runs',
      () async {
    // Seed a pending create whose replay 500s → pushBatch returns stopped.
    await db.insert('categories', {
      'id': 'loc-err',
      'name': 'Boom',
      'firefly_id': null,
      'updated_at': 1000,
      'remote_updated_at': null,
      'sync_status': 'pending',
      'deleted_at': null,
      'seq': 1,
    });
    await db.insert('op_log', {
      'op_id': 'op-err',
      'entity_type': 'categories',
      'entity_id': 'loc-err',
      'action': 'create',
      'payload': jsonEncode({
        'type': 'categories',
        'attributes': {'name': 'Boom'},
      }),
      'wall_ts': 1000,
      'device_id': 'dev-1',
      'seq': 1,
      'created_at': 1000,
      'attempts': 0,
      'last_error': null,
    });

    final store = InMemoryConnectionSettingsStore(
      const ConnectionSettings(baseUrl: 'https://firefly.test', pat: 'tok'),
    );
    final mock = MockClient((request) async {
      requests.add(request);
      // Non-retryable 422 → pushBatch records the failure and returns
      // stopped (a retryable 500 would loop for the client's backoff window
      // and never classify as a hard stop).
      return http.Response(
        jsonEncode({'message': 'The given data was invalid.'}),
        422,
      );
    });
    final client = FireflyApiClient(settings: store, httpClient: mock);
    final engine = SyncEngine(
      db: db,
      client: client,
      now: () => DateTime.utc(2026, 10, 16, 13),
    );

    final outcome = await engine.sync();

    expect(outcome.ok, isFalse);
    expect(outcome.failure, isNotNull);
    // The pull ran anyway: the server is the authority on what still exists,
    // and a stuck op must not hide a website-side deletion forever.
    expect(requests.where((r) => r.method == 'GET'), isNotEmpty);
    expect(outcome.pull, isNotNull);
    expect(await metaGet(DeviceMetaDao.lastSyncStatusKey), 'error');
  });

  test('a failed push still delivers a website-side deletion (R38)', () async {
    // A currency the phone thinks is synced but the website has deleted.
    await db.insert('currencies', {
      'id': 'loc-deleted',
      'code': 'GONE',
      'name': 'Deleted on the website',
      'symbol': r'$',
      'symbol_first': 0,
      'decimal_places': 2,
      'enabled': 1,
      'is_default': 0,
      'rate': '1.0',
      'firefly_id': '777',
      'updated_at': 1000,
      'remote_updated_at': DateTime.utc(2026).millisecondsSinceEpoch,
      'sync_status': 'synced',
      'deleted_at': null,
      'seq': 1,
    });
    // A queued op the server keeps rejecting (e.g. it referenced the deleted
    // account): before R38 this stopped the cycle before the pull.
    await db.insert('op_log', {
      'op_id': 'op-rejected',
      'entity_type': 'currencies',
      'entity_id': 'loc-deleted',
      'action': 'update',
      'payload': jsonEncode({
        'type': 'currencies',
        'attributes': {'code': 'GONE'},
      }),
      'wall_ts': 1000,
      'device_id': 'dev-1',
      'seq': 1,
      'created_at': 1000,
      'attempts': 0,
      'last_error': null,
    });
    final store = InMemoryConnectionSettingsStore(
      const ConnectionSettings(baseUrl: 'https://firefly.test', pat: 'tok'),
    );
    final mock = MockClient((request) async {
      requests.add(request);
      if (request.method == 'GET') {
        // The server no longer lists the row.
        return http.Response(
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
      }
      return http.Response(
        jsonEncode({'message': 'The given data was invalid.'}),
        422,
      );
    });
    final client = FireflyApiClient(settings: store, httpClient: mock);
    final engine = SyncEngine(
      db: db,
      client: client,
      now: () => DateTime.utc(2026, 10, 16, 13),
    );

    final outcome = await engine.sync();

    // The push failure is still reported...
    expect(outcome.ok, isFalse);
    expect(outcome.failure, isNotNull);
    // ...but the deletion arrived: the row is gone from every list.
    final row = await db.query('currencies', where: "id = 'loc-deleted'");
    expect(row.single['deleted_at'], isNotNull);
  });

  test('push network Err (transport) fails cycle and skips the pull',
      () async {
    final store = InMemoryConnectionSettingsStore(
      const ConnectionSettings(baseUrl: 'https://firefly.test', pat: 'tok'),
    );
    final mock = MockClient((request) async {
      requests.add(request);
      // Throw a transport error → client returns NetworkFailure (an Err).
      throw const SocketException('connection refused');
    });
    final client = FireflyApiClient(settings: store, httpClient: mock);
    final engine = SyncEngine(
      db: db,
      client: client,
      now: () => DateTime.utc(2026, 10, 16, 13),
    );

    final outcome = await engine.sync();

    expect(outcome.ok, isFalse);
    expect(outcome.failure, isA<NetworkFailure>());
    // The pull stops at the first entity when the failure is transport-level: a
    // dead socket fails every request the same way, so the walk does not grind
    // through all 13 entities. Exactly one list path was attempted.
    final gets = requests.where((r) => r.method == 'GET');
    expect(gets, isNotEmpty);
    expect(gets.map((r) => r.url.path).toSet(), {'/api/v1/currencies'});
    expect(outcome.pull, isNull);
    expect(await metaGet(DeviceMetaDao.lastSyncStatusKey), 'error');
  });

  // ── Pull failure on one entity ──────────────────────────────────────────────

  test('pull failure on one entity fails the cycle but pulls the rest',
      () async {
    final engine = buildEngine(failPull: true);
    final outcome = await engine.sync();

    expect(outcome.ok, isFalse);
    expect(outcome.failure, isA<ServerFailure>());
    // Stats survive so the log can still say what did arrive.
    expect(outcome.pull, isNotNull);
    expect(outcome.pull!.hasFailures, isTrue);
    expect(outcome.pull!.failures.keys, contains('currencies'));
    expect(outcome.pull!.entities.keys, contains('accounts'));
    // Only one entity failed: the currencies list was the only 5xx.
    expect(
      requests.where((r) => r.method == 'GET' && r.url.path.endsWith('/currencies')),
      isNotEmpty,
    );
    expect(await metaGet(DeviceMetaDao.lastSyncStatusKey), 'error');
  });

  // ── sync_log ───────────────────────────────────────────────────────────────

  test('successful cycle appends a push line and a pull line, newest first',
      () async {
    final engine = buildEngine();
    await engine.sync();

    final log = await engine.recentLog();
    expect(log.length, greaterThanOrEqualTo(2));
    // Newest first: the pull line sits above the push line. (A `backup`
    // skipped line may sit on top of both when no backup URL is configured.)
    final pullIndex = log.indexWhere((e) => e.phase == 'pull');
    final pushIndex = log.indexWhere((e) => e.phase == 'push');
    expect(pullIndex, isNonNegative);
    expect(pullIndex, lessThan(pushIndex));
    expect(log[pullIndex].status, 'ok');
    expect(log[pushIndex].status, 'ok');
  });

  test('sync_log prunes to kMaxSyncLogEntries', () async {
    final engine = buildEngine();
    // Run enough cycles to exceed the cap (each cycle writes 2 lines).
    const cycles = (kMaxSyncLogEntries ~/ 2) + 5;
    for (var i = 0; i < cycles; i++) {
      await engine.sync();
    }
    final count = await db.rawQuery('SELECT COUNT(*) AS c FROM sync_log');
    expect((count.first['c']! as int) <= kMaxSyncLogEntries, isTrue);
  });

  // ── restoreFromServer ──────────────────────────────────────────────────────

  test('restoreFromServer wipes op_log + every entity table then pulls',
      () async {
    await seedPendingCreate(); // one pending op + one local category row
    // Entity rows across several tables the empty-server pull will NOT
    // recreate — pre-fix these survived the restore untouched.
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
    await db.insert('tags', {
      'id': 'loc-tag',
      'tag': 'groceries',
      'date': null,
      'firefly_id': 'srv-tag',
      'updated_at': 1000,
      'remote_updated_at': 1000,
      'sync_status': 'synced',
      'deleted_at': null,
      'seq': 2,
    });
    await db.insert('recurrences', {
      'id': 'loc-rec',
      'title': 'Rent',
      'type': 'withdrawal',
      'description': null,
      'first_date': '2026-01-01',
      'repeat_until': null,
      'nr_of_repetitions': null,
      'active': 1,
      'apply_rules': 1,
      'transactions_json': null,
      'latest_date': null,
      'firefly_id': 'srv-rec',
      'updated_at': 1000,
      'remote_updated_at': 1000,
      'sync_status': 'synced',
      'deleted_at': null,
      'seq': 3,
    });
    await db.insert('recurrence_repetitions', {
      'recurrence_id': 'loc-rec',
      'ord': 0,
      'repetition_type': 'monthly',
      'repetition_moment': '18:00:00',
      'repetition_skip': 0,
      'weekend': 1,
    });
    // Device + audit state that must survive the wipe.
    await meta.set('keep.key', 'keep');
    await db.insert('sync_log', {
      'started_at': 1000,
      'phase': 'pull',
      'status': 'ok',
      'pushed_ops': null,
      'pull_inserted': 1,
      'pull_updated': 0,
      'pull_tombstoned': 0,
      'error': null,
    });

    final engine = buildEngine();
    final result = await engine.restoreFromServer();

    expect(result.isOk, isTrue);
    // Every synced table (entities + children) and the queued edits are
    // empty: the empty-server pull re-created nothing, proving the wipe
    // removed the local-only rows rather than the merge preserving them.
    for (final table in [
      'op_log',
      'categories',
      'currencies',
      'tags',
      'recurrences',
      'recurrence_repetitions',
    ]) {
      final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM $table');
      expect(rows.first['c'], 0, reason: '$table must be wiped by restore');
    }
    // device_meta (not a synced entity) is preserved.
    expect(await metaGet('keep.key'), 'keep');
    // sync_log (audit trail) is preserved.
    final log = await engine.recentLog();
    expect(log, isNotEmpty, reason: 'sync_log must survive the restore');
    // status + timestamp updated.
    expect(await metaGet(DeviceMetaDao.lastSyncStatusKey), 'ok');
    expect(await metaGet(DeviceMetaDao.lastSyncTsKey), isNotNull);
  });

  test('restoreFromServer surfaces pull failure and marks error', () async {
    final engine = buildEngine(failPull: true);
    final result = await engine.restoreFromServer();

    expect(result.isOk, isFalse);
    expect(result.failureOrNull, isA<ServerFailure>());
    expect(await metaGet(DeviceMetaDao.lastSyncStatusKey), 'error');
  });

  // ── PC backup (P4.1, DESIGN §8.2) ──────────────────────────────────────────

  test('successful sync fires POST /backup once and logs backup/ok newest', () async {
    final backup = buildBackup();
    final engine = buildEngine(backup: backup.client);

    final outcome = await engine.sync();

    expect(outcome.ok, isTrue);
    expect(backup.requests, hasLength(1));
    final req = backup.requests.single;
    expect(req.method, 'POST');
    expect(req.url.toString(), 'http://pc:8095/backup');
    expect(req.headers['Authorization'], 'Bearer btok');

    // recentLog is newest-first: backup is recorded after push+pull, so it
    // sits on top; the push/pull lines still follow underneath.
    final log = await engine.recentLog();
    expect(log.first.phase, 'backup');
    expect(log.first.status, 'ok');
    expect(log.firstWhere((e) => e.phase == 'pull').status, 'ok');
    expect(log.firstWhere((e) => e.phase == 'push').status, 'ok');
  });

  test('backup failure logs backup/error but the sync cycle stays ok', () async {
    final backup = buildBackup(
      handler: (_) async => http.Response('{"message":"boom"}', 500),
    );
    final engine = buildEngine(backup: backup.client);

    final outcome = await engine.sync();

    // DESIGN §8: a dead PC must never fail the cycle or flip last status.
    expect(outcome.ok, isTrue, reason: 'backup must not fail the sync');
    expect(await metaGet(DeviceMetaDao.lastSyncStatusKey), 'ok');

    final log = await engine.recentLog();
    expect(log.first.phase, 'backup');
    expect(log.first.status, 'error');
    expect(log.first.error, contains('HTTP 500'));
    // The push/pull lines underneath are untouched.
    expect(log.firstWhere((e) => e.phase == 'pull').status, 'ok');
  });

  test('backup URL unset → disabled trigger: no request, '
      'one skipped log line', () async {
    final backup = buildBackup(
      settings: const ConnectionSettings(
        baseUrl: 'https://firefly.test',
        pat: 'tok',
      ),
    );
    final engine = buildEngine(backup: backup.client);

    final outcome = await engine.sync();

    expect(outcome.ok, isTrue);
    expect(backup.requests, isEmpty, reason: 'feature off = zero HTTP');
    final backupLines = (await engine.recentLog())
        .where((e) => e.phase == 'backup')
        .toList();
    // Unconfigured is now visible instead of silent: "backup did nothing"
    // was indistinguishable from a broken button.
    expect(backupLines, hasLength(1));
    expect(backupLines.single.status, 'skipped');
    expect(backupLines.single.error, contains('No backup URL'));
  });

  test('restoreFromServer never re-triggers the backup', () async {
    final backup = buildBackup();
    final engine = buildEngine(backup: backup.client);
    await engine.sync();
    expect(backup.requests, isNotEmpty, reason: 'sanity: sync did back up');

    backup.requests.clear();
    final result = await engine.restoreFromServer();

    expect(result.isOk, isTrue);
    expect(backup.requests, isEmpty, reason: 'restore must not back up');
  });
}
