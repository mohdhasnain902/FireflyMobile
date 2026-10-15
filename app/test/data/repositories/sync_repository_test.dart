import 'dart:convert';

import 'package:firefly_mobile/data/dao/device_meta_dao.dart';
import 'package:firefly_mobile/data/dao/op_log_dao.dart';
import 'package:firefly_mobile/data/repositories/entity_reader.dart';
import 'package:firefly_mobile/data/repositories/entity_repositories.dart';
import 'package:firefly_mobile/data/repositories/sync_repository.dart';
import 'package:firefly_mobile/domain/entities/account.dart';
import 'package:firefly_mobile/domain/entities/category.dart';
import 'package:firefly_mobile/domain/entities/currency.dart';
import 'package:firefly_mobile/domain/entities/op_log_entry.dart';
import 'package:firefly_mobile/domain/entities/sync_bookkeeping.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../db/app_database_test.dart';

/// Exercises the repository write layer against real SQLite
/// (DESIGN §5.2, §6.3).
///
/// Every mutation here is one transaction in a fixed order: allocate `seq`,
/// append the op, write the row. These tests pin the properties the replay
/// engine will lean on later — the queue and the row commit or roll back
/// together, `seq` never goes backwards and never burns a value on a failed
/// write, an edit to a row the server has never seen queues a `create`, and
/// `CurrencyRepository` exposes reads only because `currencies` is pull-only
/// (DESIGN §3.1) and has no write surface to test.
void main() {
  setUpAll(sqfliteFfiInit);

  // One connection for the whole suite: the ffi factory hands back the same
  // `:memory:` handle on every open, so a fresh open per test would silently
  // carry rows over from the previous test. The setUp below wipes the four
  // tables these tests write, which also rewinds the seq counter to its first
  // value so every test starts from a known queue state.
  late Database db;
  late DeviceMetaDao meta;
  late CategoryRepository categories;
  late AccountRepository accounts;
  late OpLogDao opLog;

  setUpAll(() async {
    db = await openTestDatabase();
    meta = DeviceMetaDao(db);
    categories = CategoryRepository(db: db, meta: meta);
    accounts = AccountRepository(db: db, meta: meta);
    opLog = OpLogDao(db);
  });

  setUp(() async {
    await db.delete('op_log');
    await db.delete('categories');
    await db.delete('accounts');
    await db.delete('device_meta');
  });

  /// The `next_seq` value as it sits on disk, read without allocating from it,
  /// so a rollback can be asserted by comparing the stored counter itself.
  Future<String?> storedNextSeq() => meta.getIn(db, DeviceMetaDao.nextSeqKey);

  /// A `create` builder for a category whose only business field is [name];
  /// id, write time and seq always come from the repository under test, which
  /// is the point of the builder callback (DESIGN §5.2).
  Category Function(String, DateTime, int) categoryNamed(String name) {
    return (id, at, seq) =>
        Category(id: id, name: name, updatedAt: at, seq: seq);
  }

  group('create', () {
    test('writes the row and queues exactly one create op', () async {
      final created = await categories.create(categoryNamed('Groceries'));

      final row = await categories.getById(created.id);
      // The row round-trips through epoch millis (row codec), so the stored
      // write time is the created one truncated to a millisecond. Compare
      // through the codec's own conversion — not a hand-rolled approximation
      // — so the assertion stays exact if the storage unit ever changes.
      expect(
        row,
        created.copyWith(
          updatedAt: millisToDateTime(dateTimeToMillis(created.updatedAt))!,
        ),
      );
      expect(row!.syncStatus, SyncStatus.pending);

      final ops = await opLog.getPendingBatch(10);
      expect(ops, hasLength(1));
      expect(ops.single.action, OpAction.create);
      expect(ops.single.entityType, 'categories');
      expect(ops.single.entityId, created.id);
      // The op and the row describe the same content from the same seq.
      expect(ops.single.seq, created.seq);
      expect(ops.single.payload, jsonEncode(created.toJsonApi()));
    });

    test('stamps the table name and JSON:API body on the op', () async {
      final created = await categories.create(categoryNamed('Transport'));
      final pending = await opLog.getPendingBatch(10);
      final payload =
          jsonDecode(pending.single.payload!) as Map<String, dynamic>;

      // entity_type doubles as the JSON:API type, so the queue and the body
      // can never disagree about what is being sent (DESIGN §6.3).
      expect(payload['type'], 'categories');
      // No server id yet, so jsonApiMember leaves the key out entirely.
      expect(payload['id'], isNull);
      expect(payload['attributes'], {'name': 'Transport'});
      expect(created.fireflyId, isNull);
    });

    test('mints a fresh id per call, so rows cannot collide', () async {
      final first = await categories.create(categoryNamed('A'));
      final second = await categories.create(categoryNamed('B'));

      expect(first.id, isNot(second.id));
      expect(await categories.count(), 2);
    });
  });

  group('seq allocation', () {
    test('starts at 1 and increases by one per write', () async {
      final seqs = <int>[];
      for (var i = 0; i < 5; i++) {
        final row = await categories.create(categoryNamed('n$i'));
        seqs.add(row.seq);
      }

      expect(seqs, [1, 2, 3, 4, 5]);
      // The queue keeps that order: a wall-clock tie breaks on seq
      // (DESIGN §6.6), so the batch a replay walks is the batch written here.
      final opSeqs = (await opLog.getPendingBatch(10)).map((o) => o.seq);
      expect(opSeqs, seqs);
    });

    test('a failed row write rolls back its op and its seq', () async {
      final created = await categories.create(categoryNamed('Doomed'));
      final counterAfterCreate = await storedNextSeq();

      // Vanish the row behind the repository's back: the commit's UPDATE then
      // changes 0 rows, which the writer must treat as a failure rather than
      // a no-op — otherwise the queue holds an edit to a row this device no
      // longer has, and every replay would be built from a stale payload.
      await db.delete('categories', where: 'id = ?', whereArgs: [created.id]);
      await expectLater(
        categories.update(
          created,
          (current, at, seq) => current.copyWith(updatedAt: at, seq: seq),
        ),
        throwsA(isA<StateError>()),
      );

      // Neither half of the transaction survived: still exactly the create
      // op, and the counter sits where the successful write left it.
      expect(await opLog.pendingCount(), 1);
      expect(await storedNextSeq(), counterAfterCreate);
      expect(await categories.getById(created.id), isNull);
    });
  });

  group('update', () {
    test('queues a create while the server has never seen the row', () async {
      final created = await categories.create(categoryNamed('Seed'));
      final edited = await categories.update(
        created,
        (current, at, seq) =>
            current.copyWith(name: 'Renamed', updatedAt: at, seq: seq),
      );

      expect(edited.name, 'Renamed');
      final ops = await opLog.getPendingBatch(10);
      expect(ops.map((o) => o.action), [OpAction.create, OpAction.create]);
      expect(ops.last.entityId, created.id);

      // Once the row carries a fireflyId the same call queues an update:
      // patching an id the server knows resolves, while replaying a create
      // against it would be refused (DESIGN §6.3b).
      final acked = await categories.update(
        edited.copyWith(fireflyId: '42'),
        (current, at, seq) =>
            current.copyWith(fireflyId: '42', updatedAt: at, seq: seq),
      );
      expect(acked.fireflyId, '42');
      final after = await opLog.getPendingBatch(10);
      expect(after.last.action, OpAction.update);
    });
  });

  group('delete', () {
    test('soft delete tombstones the row and hides it from lists', () async {
      final created = await categories.create(categoryNamed('Gone Soon'));
      await categories.softDelete(created.id);

      final row = await categories.getById(created.id);
      expect(row, isNotNull);
      expect(row!.deletedAt, isNotNull);
      expect(row.syncStatus, SyncStatus.pending);
      expect(await categories.getAll(), isEmpty);
      expect(await categories.getAll(includeDeleted: true), hasLength(1));
      // A tombstone is still work waiting to be pushed, so it stays pending.
      expect(await categories.getPending(), hasLength(1));
      // The tombstone was stamped with the seq its delete op was queued at.
      expect(row.seq, 2);

      final ops = await opLog.getPendingBatch(10);
      expect(ops, hasLength(2));
      expect(ops.last.action, OpAction.delete);
      expect(ops.last.entityId, created.id);
      // Deletes carry no payload: the entity id is all a replay needs.
      expect(ops.last.payload, isNull);
      expect(ops.last.seq, row.seq);
    });

    test('hard delete drops the row but still queues the delete', () async {
      final created = await categories.create(categoryNamed('Dust'));
      await categories.hardDelete(created.id);

      expect(await categories.getById(created.id), isNull);
      expect(await categories.count(includeDeleted: true), 0);

      final ops = await opLog.getPendingBatch(10);
      expect(ops, hasLength(2));
      expect(ops.last.action, OpAction.delete);
      expect(ops.last.entityId, created.id);
      expect(ops.last.payload, isNull);
    });
  });

  test('another entity type queues its own table name', () async {
    final account = await accounts.create(
      (id, at, seq) => Account(
        id: id,
        name: 'Checking',
        type: 'asset',
        updatedAt: at,
        seq: seq,
      ),
    );

    final op = (await opLog.getPendingBatch(10)).single;
    expect(op.entityType, 'accounts');
    expect(op.entityId, account.id);
    expect((await accounts.getById(account.id))!.type, 'asset');
  });

  test('CurrencyRepository offers reads and no write surface', () async {
    final repo = CurrencyRepository(db: db);
    expect(repo, isA<EntityReader<Currency>>());
    // Pull-only by design: it must not reach the queue at all, and a write
    // method that would throw at runtime is worse than an absent one.
    expect(repo, isNot(isA<SyncRepository<dynamic>>()));

    final currency = Currency(
      id: 'cur1',
      code: 'EUR',
      name: 'Euro',
      updatedAt: DateTime.now().toUtc(),
      seq: 1,
    );
    await db.insert('currencies', currency.toRow());

    expect((await repo.getById('cur1'))!.code, 'EUR');
    expect(await repo.count(), 1);
    expect(await opLog.pendingCount(), 0);
  });
}
