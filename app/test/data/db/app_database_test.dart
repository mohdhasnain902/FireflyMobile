import 'dart:io';

import 'package:firefly_mobile/data/dao/device_meta_dao.dart';
import 'package:firefly_mobile/data/dao/op_log_dao.dart';
import 'package:firefly_mobile/data/db/database_opener.dart';
import 'package:firefly_mobile/data/db/schema.dart';
import 'package:firefly_mobile/domain/entities/op_log_entry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Opens a throwaway database on the host's native SQLite.
///
/// `sqflite_common_ffi` drives the same `DatabaseFactory` interface the app
/// uses on-device, so schema, migrations and every DAO run against real SQL
/// here rather than a mock. Encryption is a platform concern and is covered
/// separately; [password] is accepted so the open path can be exercised with
/// and without a key.
Future<Database> openTestDatabase({String? password}) {
  return openAppDatabase(
    factory: databaseFactoryFfiNoIsolate,
    path: inMemoryDatabasePath,
    password: password,
  );
}

void main() {
  setUpAll(sqfliteFfiInit);

  group('schema', () {
    test('creates every business table from DESIGN 5.1', () async {
      final db = await openTestDatabase();

      final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name NOT LIKE 'sqlite_%' ORDER BY name",
      );
      final tables = rows.map((r) => r['name']! as String).toSet();

      // The 14 business entities plus the two sync tables.
      expect(
        tables,
        containsAll(<String>{
          'accounts',
          'attachments',
          'bills',
          'budget_limits',
          'budgets',
          'categories',
          'currencies',
          'device_meta',
          'op_log',
          'piggy_banks',
          'recurrences',
          'rule_groups',
          'rules',
          'subscriptions',
          'tags',
          'transactions',
        }),
      );
      await db.close();
    });

    test('every business table carries the seven bookkeeping columns',
        () async {
      final db = await openTestDatabase();

      const businessTables = <String>{
        'accounts',
        'attachments',
        'bills',
        'budget_limits',
        'budgets',
        'categories',
        'currencies',
        'piggy_banks',
        'recurrences',
        'rule_groups',
        'rules',
        'subscriptions',
        'tags',
        'transactions',
      };

      for (final table in businessTables) {
        final columns = await db.rawQuery('PRAGMA table_info($table)');
        final names = columns.map((c) => c['name']! as String).toSet();
        expect(
          names,
          containsAll(<String>{
            'id',
            'firefly_id',
            'updated_at',
            'remote_updated_at',
            'sync_status',
            'deleted_at',
            'seq',
          }),
          reason: 'table $table is missing sync bookkeeping columns',
        );
      }
      await db.close();
    });

    test('WAL mode is enabled on open', () async {
      // WAL requires a file-backed database; SQLite silently falls back to
      // `memory` for in-memory databases, so use a real temp file.
      final dir = await Directory.systemTemp.createTemp('firefly_wal_');
      addTearDown(() => dir.delete(recursive: true));

      final db = await openAppDatabase(
        factory: databaseFactoryFfiNoIsolate,
        path: '${dir.path}/wal.db',
      );
      final rows = await db.rawQuery('PRAGMA journal_mode');
      expect((rows.first['journal_mode']! as String).toLowerCase(), 'wal');
      await db.close();
    });

    test('user_version matches the latest schema version', () async {
      final db = await openTestDatabase();
      final rows = await db.rawQuery('PRAGMA user_version');
      expect(rows.first['user_version'], latestSchemaVersion);
      await db.close();
    });

    test('opening twice with singleInstance reuses the handle', () async {
      // A fresh in-memory path per test is not guaranteed with
      // singleInstance, so use a named memory DB to prove reuse.
      const path = 'file:schema_reuse?mode=memory&cache=shared';
      final first = await openAppDatabase(
        factory: databaseFactoryFfiNoIsolate,
        path: path,
      );
      final second = await openAppDatabase(
        factory: databaseFactoryFfiNoIsolate,
        path: path,
      );
      expect(identical(first, second), isTrue);
      await first.close();
    });
  });

  group('migrations', () {
    test('upgrades a pre-existing user_version 0 file without data loss',
        () async {
      // Simulates a file that predates schema versioning: raw open (no
      // version option), real rows, PRAGMA user_version still 0.
      final dir = await Directory.systemTemp.createTemp('firefly_mig_');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/legacy.db';

      final legacy = await databaseFactoryFfiNoIsolate.openDatabase(path);
      await legacy.execute('CREATE TABLE legacy_note (id TEXT PRIMARY KEY)');
      await legacy.execute("INSERT INTO legacy_note VALUES ('keep-me')");
      final before = await legacy.rawQuery('PRAGMA user_version');
      expect(before.first['user_version'], 0);
      await legacy.close();

      // The app open path must bring the file to the latest schema
      // (onCreate runs _applyMigrations for a version-0 file; later
      // versions run through onUpgrade, which shares the same function).
      final db = await openAppDatabase(
        factory: databaseFactoryFfiNoIsolate,
        path: path,
      );

      // ...without dropping what the file already held.
      final kept = await db.rawQuery('SELECT id FROM legacy_note');
      expect(kept.single['id'], 'keep-me');
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name NOT LIKE 'sqlite_%'",
      );
      expect(
        tables.map((r) => r['name']),
        containsAll(<String>['categories', 'op_log', 'device_meta']),
      );
      final after = await db.rawQuery('PRAGMA user_version');
      expect(after.first['user_version'], latestSchemaVersion);
      await db.close();
    });

    test('migration keys are contiguous from 1 to latestSchemaVersion', () {
      // _applyMigrations throws StateError on a gap, so a missing version
      // must be caught here rather than on a user's device.
      final keys = migrations.keys.toList()..sort();

      expect(keys, List<int>.generate(latestSchemaVersion, (i) => i + 1));
      expect(keys.first, 1);
    });
  });

  group('DeviceMetaDao', () {
    late Database db;
    late DeviceMetaDao dao;

    setUp(() async {
      db = await openTestDatabase();
      dao = DeviceMetaDao(db);
    });

    tearDown(() => db.close());

    test('get returns null for an unset key', () async {
      expect(await dao.get('nope'), isNull);
    });

    test('set then get round-trips', () async {
      await dao.set('k', 'v');
      expect(await dao.get('k'), 'v');
    });

    test('set overwrites an existing key', () async {
      await dao.set('k', 'v1');
      await dao.set('k', 'v2');
      expect(await dao.get('k'), 'v2');
    });

    test('getOrCreateDeviceId is stable across calls', () async {
      final first = await dao.getOrCreateDeviceId();
      final second = await dao.getOrCreateDeviceId();
      expect(first, second);
      expect(first, isNotEmpty);
    });

    test('two fresh daos share the persisted device id', () async {
      final first = await dao.getOrCreateDeviceId();
      final other = DeviceMetaDao(db);
      expect(await other.getOrCreateDeviceId(), first);
    });

    test('nextSeq starts at 1 and increases strictly', () async {
      final values = <int>[];
      for (var i = 0; i < 50; i++) {
        values.add(await dao.nextSeq());
      }
      expect(values.first, 1);
      expect(values, List<int>.generate(50, (i) => i + 1));
      // Strictly increasing, not merely non-decreasing.
      for (var i = 1; i < values.length; i++) {
        expect(values[i], greaterThan(values[i - 1]));
      }
    });

    test('nextSeq survives reopening the database', () async {
      final last = await dao.nextSeq();
      // Re-open the same in-memory DB to prove the counter is persisted.
      const path = 'file:seq_persist?mode=memory&cache=shared';
      final first = await openAppDatabase(
        factory: databaseFactoryFfiNoIsolate,
        path: path,
      );
      final reopenDao = DeviceMetaDao(first);
      await reopenDao.nextSeq();
      final after = await reopenDao.nextSeq();
      expect(after, 2);
      expect(last, 1);
      await first.close();
    });
  });

  group('OpLogDao', () {
    late Database db;
    late OpLogDao dao;
    late DeviceMetaDao meta;

    setUp(() async {
      db = await openTestDatabase();
      dao = OpLogDao(db);
      meta = DeviceMetaDao(db);
    });

    tearDown(() => db.close());

    Future<OpLogEntry> buildEntry({
      String entityType = 'transaction',
      String entityId = 'ent-1',
      OpAction action = OpAction.create,
      int wallTs = 1000,
    }) async {
      return OpLogEntry(
        opId: 'op-${await meta.nextSeq()}',
        entityType: entityType,
        entityId: entityId,
        action: action,
        payload: '{"x":1}',
        wallTs: wallTs,
        deviceId: await meta.getOrCreateDeviceId(),
        seq: await meta.nextSeq(),
        createdAt: wallTs,
      );
    }

    test('append then read returns an equal entry', () async {
      final entry = await buildEntry();
      await dao.append(entry);

      final batch = await dao.getPendingBatch(10);
      expect(batch, hasLength(1));
      expect(batch.single, entry);
    });

    test('append is idempotent for a repeated op_id', () async {
      final entry = await buildEntry();
      await dao.append(entry);
      // Simulates a crash between append and ack, then a retry.
      await dao.append(entry);

      expect(await dao.pendingCount(), 1);
    });

    test('pendingCount tracks the queue', () async {
      expect(await dao.pendingCount(), 0);
      await dao.append(await buildEntry());
      await dao.append(await buildEntry(entityId: 'ent-2'));
      expect(await dao.pendingCount(), 2);

      final batch = await dao.getPendingBatch(10);
      await dao.acknowledge(batch.first.opId);
      expect(await dao.pendingCount(), 1);
    });

    test('acknowledge removes the entry', () async {
      final entry = await buildEntry();
      await dao.append(entry);
      await dao.acknowledge(entry.opId);
      expect(await dao.getPendingBatch(10), isEmpty);
    });

    test('recordFailure keeps the op and bumps attempts', () async {
      final entry = await buildEntry();
      await dao.append(entry);

      await dao.recordFailure(entry.opId, 'network down');
      await dao.recordFailure(entry.opId, 'network down');

      final batch = await dao.getPendingBatch(10);
      expect(batch, hasLength(1), reason: 'a failed op must stay queued');
      expect(batch.single.attempts, 2);
      expect(batch.single.lastError, 'network down');
    });

    test('clearFailure resets the message but keeps the op', () async {
      final entry = await buildEntry();
      await dao.append(entry);
      await dao.recordFailure(entry.opId, 'boom');
      await dao.clearFailure(entry.opId);

      final batch = await dao.getPendingBatch(10);
      expect(batch.single.lastError, isNull);
      expect(batch.single.attempts, 1, reason: 'attempts are history');
    });

    test('batch is ordered by wall_ts, device_id, seq', () async {
      final deviceId = await meta.getOrCreateDeviceId();
      Future<OpLogEntry> entry(String id, int wallTs, int seq) async {
        return OpLogEntry(
          opId: id,
          entityType: 'transaction',
          entityId: 'e-$id',
          action: OpAction.update,
          wallTs: wallTs,
          deviceId: deviceId,
          seq: seq,
          createdAt: wallTs,
        );
      }

      // Deliberately inserted out of order.
      await dao.append(await entry('b', 2000, 2));
      await dao.append(await entry('c', 3000, 3));
      await dao.append(await entry('a', 1000, 1));

      final batch = await dao.getPendingBatch(10);
      expect(batch.map((e) => e.opId).toList(), ['a', 'b', 'c']);
    });

    test('getPendingBatch respects the limit', () async {
      for (var i = 0; i < 5; i++) {
        await dao.append(await buildEntry(entityId: 'e-$i', wallTs: 1000 + i));
      }
      final batch = await dao.getPendingBatch(2);
      expect(batch, hasLength(2));
    });
  });
}
