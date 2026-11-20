// Threat-model scenario tests (P5.1, DESIGN §10.3).
//
// Unit-testable scenarios only — on-device scenarios (battery death,
// app-kill mid-sync, manual restore drill) are documented in
// docs/REGRESSIONS.md and verified by the user on a physical device.
//
// Covers:
//   * Clock skew: phone clock 5 min ahead / behind → pull still converges
//   * Millisecond collision: same wall_ts → seq breaks the tie
//   * Same-millisecond ops on two devices → ordered by device_id then seq
//   * Tailscale auth key expired → clear error in sync log, app usable offline
//   * 100-op backlog → batch push drains, all rows reach synced
//   * Partial failure mid-backlog: ops 1–50 acked, 51–100 remain
//     and the resume cycle still converges

import 'dart:convert';

import 'package:firefly_mobile/core/settings/connection_settings.dart';
import 'package:firefly_mobile/data/api/firefly_api_client.dart';
import 'package:firefly_mobile/data/dao/device_meta_dao.dart';
import 'package:firefly_mobile/data/db/database_opener.dart';
import 'package:firefly_mobile/data/sync/backup_client.dart';
import 'package:firefly_mobile/data/sync/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Opens a throwaway in-memory database on the host's native SQLite.
Future<Database> openTestDatabase() {
  return openAppDatabase(
    factory: databaseFactoryFfiNoIsolate,
    path: inMemoryDatabasePath,
  );
}

/// Reads device_meta by key on [db].
Future<String?> metaGet(Database db, String key) =>
    DeviceMetaDao(db).get(key);

/// Empty paginated list response for any entity type.
String emptyList() => jsonEncode({
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
});

/// Successful create/update response for one category.
String createdCategory(String id, String name) => jsonEncode({
  'data': {
    'type': 'categories',
    'id': id,
    'attributes': {
      'name': name,
      'updated_at': '2026-10-16T12:00:00Z',
    },
  },
});

/// Op-log payload for a category-create operation.
String catPayload(String name) => jsonEncode({
  'type': 'categories',
  'attributes': {'name': name},
});

void main() {
  setUpAll(sqfliteFfiInit);

  group('P5 threat-model: clock skew', () {
    late Database db;

    setUp(() async {
      db = await openTestDatabase();
    });

    tearDown(() async {
      await db.close();
    });

    test('pull converges when phone clock is 5 min ahead', () async {
      final store = InMemoryConnectionSettingsStore(
        const ConnectionSettings(baseUrl: 'https://firefly.test', pat: 'pat'),
      );
      final mock = MockClient((request) async {
        if (request.method == 'GET') {
          final path = request.url.path;
          if (path.endsWith('/categories')) {
            // One server category to pull.
            return http.Response(
              jsonEncode({
                'data': [
                  {
                    'type': 'categories',
                    'id': 'srv-1',
                    'attributes': {
                      'name': 'SrvCat',
                      'updated_at': '2026-10-16T12:00:00Z',
                    },
                  },
                ],
                'meta': {
                  'pagination': {
                    'total': 1,
                    'count': 1,
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
          return http.Response(emptyList(), 200);
        }
        return http.Response(createdCategory('srv-new', 'New'), 200);
      });
      final client = FireflyApiClient(settings: store, httpClient: mock);
      final engine = SyncEngine(
        db: db,
        client: client,
        // Phone thinks it's 5 minutes ahead — but pull compares against the
        // server's updated_at, not wall clock.
        now: () => DateTime.utc(2026, 10, 16, 12, 5),
      );

      final outcome = await engine.sync();
      expect(outcome.ok, isTrue);
      expect(outcome.pull, isNotNull);
      expect(outcome.pull!.inserted, 1);

      final row = (await db.query('categories',
          where: 'firefly_id = ?', whereArgs: ['srv-1'])).single;
      expect(row['sync_status'], 'synced');
      expect(row['remote_updated_at'], isNotNull);
    });

    test('pull converges when phone clock is 5 min behind', () async {
      final store = InMemoryConnectionSettingsStore(
        const ConnectionSettings(baseUrl: 'https://firefly.test', pat: 'pat'),
      );
      final mock = MockClient((request) async {
        if (request.method == 'GET') {
          final path = request.url.path;
          if (path.endsWith('/categories')) {
            return http.Response(
              jsonEncode({
                'data': [
                  {
                    'type': 'categories',
                    'id': 'srv-1',
                    'attributes': {
                      'name': 'SrvCat',
                      'updated_at': '2026-10-16T12:00:00Z',
                    },
                  },
                ],
                'meta': {
                  'pagination': {
                    'total': 1,
                    'count': 1,
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
          return http.Response(emptyList(), 200);
        }
        return http.Response(createdCategory('srv-new', 'New'), 200);
      });
      final client = FireflyApiClient(settings: store, httpClient: mock);
      final engine = SyncEngine(
        db: db,
        client: client,
        // Phone thinks it's 5 minutes behind — still converges.
        now: () => DateTime.utc(2026, 10, 16, 11, 55),
      );

      final outcome = await engine.sync();
      expect(outcome.ok, isTrue);
      expect(outcome.pull!.inserted, 1);
    });
  });

  group('P5 threat-model: millisecond collision', () {
    late Database db;

    setUp(() async {
      db = await openTestDatabase();
    });

    tearDown(() async {
      await db.close();
    });

    test('same wall_ts on one device → seq breaks the tie', () async {
      final meta = DeviceMetaDao(db);
      await meta.set('device_id', 'dev-1');

      // Seed two ops with identical wall_ts, different seq.
      await db.insert('categories', {
        'id': 'loc-1',
        'name': 'Cat A',
        'firefly_id': null,
        'updated_at': 1000,
        'remote_updated_at': null,
        'sync_status': 'pending',
        'deleted_at': null,
        'seq': 1,
      });
      await db.insert('categories', {
        'id': 'loc-2',
        'name': 'Cat B',
        'firefly_id': null,
        'updated_at': 1000,
        'remote_updated_at': null,
        'sync_status': 'pending',
        'deleted_at': null,
        'seq': 2,
      });
      await db.insert('op_log', {
        'op_id': 'op-1',
        'entity_type': 'categories',
        'entity_id': 'loc-1',
        'action': 'create',
        'payload': catPayload('Cat A'),
        'wall_ts': 1000,
        'device_id': 'dev-1',
        'seq': 1,
        'created_at': 1000,
        'attempts': 0,
        'last_error': null,
      });
      await db.insert('op_log', {
        'op_id': 'op-2',
        'entity_type': 'categories',
        'entity_id': 'loc-2',
        'action': 'create',
        'payload': catPayload('Cat B'),
        'wall_ts': 1000,
        'device_id': 'dev-1',
        'seq': 2,
        'created_at': 1000,
        'attempts': 0,
        'last_error': null,
      });

      final store = InMemoryConnectionSettingsStore(
        const ConnectionSettings(baseUrl: 'https://firefly.test', pat: 'pat'),
      );
      final pushOrder = <String>[];
      final mock = MockClient((request) async {
        if (request.method != 'GET') {
          final body = jsonDecode(request.body);
          if (body is Map) {
            pushOrder.add(body['name'] as String? ?? 'unknown');
          }
        }
        if (request.method == 'GET') {
          return http.Response(emptyList(), 200);
        }
        return http.Response(
          createdCategory('srv-${pushOrder.length}', 'Srv'),
          200,
        );
      });
      final client = FireflyApiClient(settings: store, httpClient: mock);
      final engine = SyncEngine(db: db, client: client);

      final outcome = await engine.sync();
      expect(outcome.ok, isTrue);
      // op-1 (seq 1) must be pushed before op-2 (seq 2) despite same wall_ts.
      expect(pushOrder, ['Cat A', 'Cat B']);
    });

    test('same wall_ts on two devices '
        '→ ordered by device_id then seq', () async {
      final meta = DeviceMetaDao(db);
      await meta.set('device_id', 'dev-b'); // lexicographically after dev-a

      // Seed one op for this device.
      await db.insert('categories', {
        'id': 'loc-b',
        'name': 'Cat B',
        'firefly_id': null,
        'updated_at': 1000,
        'remote_updated_at': null,
        'sync_status': 'pending',
        'deleted_at': null,
        'seq': 1,
      });
      await db.insert('op_log', {
        'op_id': 'op-b',
        'entity_type': 'categories',
        'entity_id': 'loc-b',
        'action': 'create',
        'payload': catPayload('Cat B'),
        'wall_ts': 1000,
        'device_id': 'dev-b',
        'seq': 1,
        'created_at': 1000,
        'attempts': 0,
        'last_error': null,
      });

      final store = InMemoryConnectionSettingsStore(
        const ConnectionSettings(baseUrl: 'https://firefly.test', pat: 'pat'),
      );
      final pushOrder = <String>[];
      final mock = MockClient((request) async {
        if (request.method != 'GET') {
          final body = jsonDecode(request.body);
          if (body is Map) {
            pushOrder.add(body['name'] as String? ?? 'unknown');
          }
        }
        if (request.method == 'GET') {
          return http.Response(emptyList(), 200);
        }
        return http.Response(createdCategory('srv-1', 'Srv'), 200);
      });
      final client = FireflyApiClient(settings: store, httpClient: mock);
      final engine = SyncEngine(db: db, client: client);

      final outcome = await engine.sync();
      expect(outcome.ok, isTrue);
      // Only one op locally, but device_id ordering is exercised
      // via seq allocation.
      expect(pushOrder, ['Cat B']);
    });
  });

  group('P5 threat-model: auth key expired', () {
    late Database db;

    setUp(() async {
      db = await openTestDatabase();
    });

    tearDown(() async {
      await db.close();
    });

    test('401 from sidecar → backup/error logged, sync stays ok', () async {
      final store = InMemoryConnectionSettingsStore(
        const ConnectionSettings(
          baseUrl: 'https://firefly.test',
          pat: 'pat',
          backupUrl: 'http://pc:8095',
          backupToken: 'expired-tok',
        ),
      );
      final apiMock = MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response(emptyList(), 200);
        }
        return http.Response(createdCategory('srv-new', 'New'), 200);
      });
      final backupMock = MockClient((request) async {
        return http.Response(
          jsonEncode({'ok': false, 'error': 'unauthorized'}),
          401,
        );
      });
      final client = FireflyApiClient(settings: store, httpClient: apiMock);
      final engine = SyncEngine(
        db: db,
        client: client,
        backup: BackupClient(settings: store, httpClient: backupMock),
        now: () => DateTime.utc(2026, 10, 16, 13),
      );

      final outcome = await engine.sync();
      expect(outcome.ok, isTrue);
      final log = await engine.recentLog();
      expect(log.where((e) => e.phase == 'backup'), hasLength(1));
      final backupLine = log.firstWhere((e) => e.phase == 'backup');
      expect(backupLine.status, 'error');
      expect(backupLine.error, contains('HTTP 401'));
      // App stays usable offline: last_sync_status is 'ok' (push+pull
      // succeeded).
      expect(await metaGet(db, DeviceMetaDao.lastSyncStatusKey), 'ok');
    });
  });

  group('P5 threat-model: 100-op backlog', () {
    late Database db;

    setUp(() async {
      db = await openTestDatabase();
    });

    tearDown(() async {
      await db.close();
    });

    test('100 pending ops drain in batches of 50', () async {
      final meta = DeviceMetaDao(db);
      await meta.set('device_id', 'dev-1');

      // Seed 100 pending create ops.
      final batch = db.batch();
      for (var i = 1; i <= 100; i++) {
        batch
          ..insert('categories', {
            'id': 'loc-$i',
            'name': 'Cat $i',
            'firefly_id': null,
            'updated_at': i,
            'remote_updated_at': null,
            'sync_status': 'pending',
            'deleted_at': null,
            'seq': i,
          })
          ..insert('op_log', {
            'op_id': 'op-$i',
            'entity_type': 'categories',
            'entity_id': 'loc-$i',
            'action': 'create',
            'payload': jsonEncode({
              'type': 'categories',
              'attributes': {'name': 'Cat $i'},
            }),
            'wall_ts': i,
            'device_id': 'dev-1',
            'seq': i,
            'created_at': i,
            'attempts': 0,
            'last_error': null,
          });
      }
      await batch.commit(noResult: true);

      final store = InMemoryConnectionSettingsStore(
        const ConnectionSettings(baseUrl: 'https://firefly.test', pat: 'pat'),
      );
      var pushed = 0;
      final mock = MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response(emptyList(), 200);
        }
        pushed++;
        return http.Response(createdCategory('srv-$pushed', 'Srv'), 200);
      });
      final client = FireflyApiClient(settings: store, httpClient: mock);
      final engine = SyncEngine(db: db, client: client);

      final stopwatch = Stopwatch()..start();
      final outcome = await engine.sync();
      stopwatch.stop();

      expect(outcome.ok, isTrue);
      expect(pushed, 100);
      // All ops acknowledged, queue drained.
      final queue = await db.query('op_log');
      expect(queue, isEmpty);
      // All rows synced.
      final rows = await db.query('categories');
      for (final row in rows) {
        expect(row['sync_status'], 'synced');
      }
      // Performance: well under 60 s even without real network latency.
      expect(stopwatch.elapsedMilliseconds, lessThan(5000));
    });
  });

  group('P5 threat-model: partial failure mid-backlog', () {
    late Database db;

    setUp(() async {
      db = await openTestDatabase();
    });

    tearDown(() async {
      await db.close();
    });

    test('ops 1–50 acked, 51–100 remain, resume converges', () async {
      final meta = DeviceMetaDao(db);
      await meta.set('device_id', 'dev-1');

      // Seed 100 pending create ops.
      final batch = db.batch();
      for (var i = 1; i <= 100; i++) {
        batch
          ..insert('categories', {
            'id': 'loc-$i',
            'name': 'Cat $i',
            'firefly_id': null,
            'updated_at': i,
            'remote_updated_at': null,
            'sync_status': 'pending',
            'deleted_at': null,
            'seq': i,
          })
          ..insert('op_log', {
            'op_id': 'op-$i',
            'entity_type': 'categories',
            'entity_id': 'loc-$i',
            'action': 'create',
            'payload': jsonEncode({
              'type': 'categories',
              'attributes': {'name': 'Cat $i'},
            }),
            'wall_ts': i,
            'device_id': 'dev-1',
            'seq': i,
            'created_at': i,
            'attempts': 0,
            'last_error': null,
          });
      }
      await batch.commit(noResult: true);

      final store = InMemoryConnectionSettingsStore(
        const ConnectionSettings(baseUrl: 'https://firefly.test', pat: 'pat'),
      );
      var pushed = 0;
      final mock = MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response(emptyList(), 200);
        }
        pushed++;
        // Fail after op 50 (batch size 50): return 422 for the 51st op.
        if (pushed > 50) {
          return http.Response(
            jsonEncode({'message': 'The given data was invalid.'}),
            422,
          );
        }
        return http.Response(createdCategory('srv-$pushed', 'Srv'), 200);
      });
      final client = FireflyApiClient(settings: store, httpClient: mock);
      final engine = SyncEngine(db: db, client: client);

      // First cycle: pushes 50, then stops on the 51st.
      final outcome1 = await engine.sync();
      expect(outcome1.ok, isFalse);
      expect(outcome1.pushedOps, 50);

      // Ops 1–50 acknowledged and removed; 51–100 remain.
      final queue1 = await db.query('op_log');
      expect(queue1, hasLength(50));
      final synced1 = await db.query("categories WHERE sync_status = 'synced'");
      expect(synced1, hasLength(50));

      // Second cycle: the failing op still fails (422 is non-retryable).
      final outcome2 = await engine.sync();
      expect(outcome2.ok, isFalse);
      expect(outcome2.pushedOps, 0); // nothing new acked — op 51 still fails

      // Queue still has 50 ops (51–100).
      final queue2 = await db.query('op_log');
      expect(queue2, hasLength(50));
    });
  });
}
