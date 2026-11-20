import 'package:firefly_mobile/data/dao/device_meta_dao.dart';
import 'package:firefly_mobile/data/demo/demo_seeder.dart';
import 'package:firefly_mobile/domain/entities/sync_bookkeeping.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../db/app_database_test.dart';

/// Unit tests for the one-tap demo seeder/eraser.
///
/// Contract under test (P2 demo polish):
/// - seed inserts a full 14-entity dataset in one transaction
/// - every demo row is born `SyncStatus.synced` with `seq: 0` and a null
///   `fireflyId` so the push engine never enqueues it
/// - erase deletes only `demo-` prefixed rows; non-demo data survives
/// - `ensureDemoSeeded` is idempotent and skips a non-empty DB
void main() {
  setUpAll(sqfliteFfiInit);

  late Database db;
  setUp(() async {
    db = await openTestDatabase();
  });
  tearDown(() async {
    await db.close();
  });

  group('seedDemoData', () {
    test('inserts at least one row in every business table', () async {
      await seedDemoData(db);
      for (final table in _tables) {
        final rows = await db.query(table, where: "id LIKE 'demo-%'");
        expect(rows, isNotEmpty, reason: 'table $table must have demo rows');
      }
    });

    test('marks every demo row synced with seq 0 and null firefly_id',
        () async {
      await seedDemoData(db);
      for (final table in _tables) {
        final rows = await db.query(
          table,
          where: "id LIKE 'demo-%'",
          columns: ['id', 'sync_status', 'seq', 'firefly_id'],
        );
        for (final row in rows) {
          expect(
            row['sync_status'],
            SyncStatus.synced.name,
            reason: '$table:${row['id']} must be synced',
          );
          expect(row['seq'], 0);
          expect(row['firefly_id'], isNull);
        }
      }
    });

    test('writes no op_log entries', () async {
      await seedDemoData(db);
      final ops = await db.query('op_log');
      expect(ops, isEmpty, reason: 'demo seed must not enqueue push ops');
    });

    test('sets the demo_seeded flag in device_meta', () async {
      await seedDemoData(db);
      final meta = await DeviceMetaDao(db).get(demoSeededMetaKey);
      expect(meta, '1');
    });

    test('is idempotent — re-seeding does not duplicate rows', () async {
      await seedDemoData(db);
      final before =
          (await db.query('transactions', where: "id LIKE 'demo-%'")).length;
      await seedDemoData(db);
      final after =
          (await db.query('transactions', where: "id LIKE 'demo-%'")).length;
      expect(after, before);
    });

    test('recurrence children are rewritten on upsert', () async {
      await seedDemoData(db);
      final children = await db.query(
        'recurrence_repetitions',
        where: "recurrence_id LIKE 'demo-%'",
      );
      expect(children, isNotEmpty);
      expect(children.first['recurrence_id'], 'demo-rec-salary');
      expect(children.first['ord'], 0);
    });
  });

  group('eraseDemoData', () {
    test('removes every demo- row and leaves non-demo data intact', () async {
      // Seed demo data, then insert a non-demo row that must survive erase.
      await seedDemoData(db);
      await db.insert('categories', {
        'id': 'real-cat-user',
        'name': 'User category',
        'sync_status': SyncStatus.synced.name,
        'seq': 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      await eraseDemoData(db);

      final remainingDemo = await db.query(
        'categories',
        where: "id LIKE 'demo-%'",
      );
      expect(
        remainingDemo,
        isEmpty,
        reason: 'demo rows must be gone',
      );
      final real = await db.query(
        'categories',
        where: 'id = ?',
        whereArgs: ['real-cat-user'],
      );
      expect(real, hasLength(1), reason: 'non-demo rows must survive erase');

      // Recurrence children must cascade.
      final children = await db.query(
        'recurrence_repetitions',
        where: "recurrence_id LIKE 'demo-%'",
      );
      expect(children, isEmpty);
    });

    test('clears the demo_seeded flag', () async {
      await seedDemoData(db);
      await eraseDemoData(db);
      final meta = await DeviceMetaDao(db).get(demoSeededMetaKey);
      expect(meta, isNull);
    });
  });

  group('ensureDemoSeeded', () {
    test('seeds an empty DB and returns true', () async {
      final seeded = await ensureDemoSeeded(db);
      expect(seeded, isTrue);
      final rows = await db.query('transactions', where: "id LIKE 'demo-%'");
      expect(rows, isNotEmpty);
    });

    test('is a no-op when the flag is already set', () async {
      await seedDemoData(db);
      final seeded = await ensureDemoSeeded(db);
      expect(seeded, isFalse);
    });

    test('skips when any business table is non-empty', () async {
      await db.insert('accounts', {
        'id': 'user-acc',
        'name': 'Real account',
        'type': 'asset',
        'sync_status': SyncStatus.synced.name,
        'seq': 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });
      final seeded = await ensureDemoSeeded(db);
      expect(seeded, isFalse);
      final demoAccounts =
          await db.query('accounts', where: "id LIKE 'demo-%'");
      expect(demoAccounts, isEmpty);
    });
  });
}

/// All fourteen business tables the seed touches.
const List<String> _tables = [
  'currencies',
  'accounts',
  'categories',
  'tags',
  'budgets',
  'budget_limits',
  'bills',
  'subscriptions',
  'piggy_banks',
  'rule_groups',
  'rules',
  'recurrences',
  'attachments',
  'transactions',
];
