import 'package:firefly_mobile/data/dao/business_daos.dart';
import 'package:firefly_mobile/domain/entities/category.dart';
import 'package:firefly_mobile/domain/entities/sync_bookkeeping.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../db/app_database_test.dart';

/// Pins the generic `EntityDao` surface shared by all fourteen business
/// tables (DESIGN §5.1, plan P1.3).
///
/// The repository suite already drives insert/update/softDelete/hardDelete
/// through the write path; these tests exercise the DAO itself so the
/// primitives the repository does not reach are covered too — `upsert`
/// (pull-merge), `patch` (narrow bookkeeping writes), `getByFireflyId`
/// (server-id lookup) — and so the exact visibility rules of
/// `getAll`/`getPending`/`count` that list screens and the sync engine rely
/// on are pinned directly rather than incidentally.
void main() {
  setUpAll(sqfliteFfiInit);

  late Database db;
  late CategoryDao dao;

  setUpAll(() async {
    db = await openTestDatabase();
    dao = CategoryDao(db);
  });

  setUp(() => db.delete('categories'));

  /// A category pinned to exact millisecond timestamps so row round-trips
  /// compare with plain `==`. Built as UTC because `millisToDateTime`
  /// decodes rows with `isUtc: true` — a local-time [DateTime] with the
  /// same epoch would differ on the `isUtc` flag in `==`.
  Category category({
    required String id,
    required String name,
    int updatedAt = 1000,
    int seq = 1,
    String? fireflyId,
    SyncStatus syncStatus = SyncStatus.pending,
  }) {
    return Category(
      id: id,
      name: name,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAt, isUtc: true),
      seq: seq,
      fireflyId: fireflyId,
      syncStatus: syncStatus,
    );
  }

  group('insert', () {
    test('round-trips through getById', () async {
      final created = category(id: 'a', name: 'Groceries', fireflyId: 'ff-1');
      await dao.insert(created);

      expect(await dao.getById('a'), created);
    });

    test('a duplicate primary key throws instead of overwriting', () async {
      final row = category(id: 'a', name: 'Original');
      await dao.insert(row);

      // ConflictAlgorithm.abort: a second write to the same id must fail
      // loudly rather than clobber a row the user has not seen.
      await expectLater(
        dao.insert(row.copyWith(name: 'Clobber')),
        throwsA(isA<DatabaseException>()),
      );
      expect((await dao.getById('a'))!.name, 'Original');
    });
  });

  group('upsert', () {
    test('replaces an existing row with the same primary key', () async {
      final first = category(id: 'a', name: 'old');
      await dao.insert(first);

      await dao.upsert(first.copyWith(name: 'new', seq: 2));

      expect(await dao.count(), 1, reason: 'no duplicate row may appear');
      expect(await dao.getById('a'), first.copyWith(name: 'new', seq: 2));
    });

    test('inserts when no row carries the id', () async {
      final row = category(id: 'fresh', name: 'from-server');
      await dao.upsert(row);

      expect(await dao.getById('fresh'), row);
    });
  });

  group('update', () {
    test('returns 1 and rewrites the row it targeted', () async {
      final row = category(id: 'a', name: 'before');
      await dao.insert(row);

      final changed = await dao.update(row.copyWith(name: 'after'));

      expect(changed, 1);
      expect((await dao.getById('a'))!.name, 'after');
    });

    test('returns 0 for a missing id and writes nothing', () async {
      final ghost = category(id: 'ghost', name: 'phantom');

      expect(await dao.update(ghost), 0);
      expect(await dao.getById('ghost'), isNull);
    });
  });

  group('patch', () {
    test('rewrites only the named columns', () async {
      final before = category(id: 'a', name: 'before');
      await dao.insert(before);

      await dao.patch('a', <String, Object?>{'name': 'after'});

      // Everything the caller did not name — timestamps, seq, bookkeeping
      // — must be byte-identical to what was there before.
      expect(await dao.getById('a'), before.copyWith(name: 'after'));
    });
  });

  group('softDelete', () {
    test('stamps the tombstone columns and resets sync status', () async {
      await dao.insert(
        category(id: 'a', name: 'bye', syncStatus: SyncStatus.synced),
      );

      await dao.softDelete('a', atMillis: 7000, seq: 42);

      final row = (await dao.getById('a'))!;
      expect(
        row.deletedAt,
        DateTime.fromMillisecondsSinceEpoch(7000, isUtc: true),
      );
      // updated_at moves with the tombstone so list ordering reflects the
      // delete, and seq/sync_status make the row pending again for replay.
      expect(
        row.updatedAt,
        DateTime.fromMillisecondsSinceEpoch(7000, isUtc: true),
      );
      expect(row.seq, 42);
      expect(row.syncStatus, SyncStatus.pending);
    });
  });

  group('getById', () {
    test('returns null when the id is absent', () async {
      expect(await dao.getById('missing'), isNull);
    });
  });

  group('getByFireflyId', () {
    test('resolves the server id; never matches a local id', () async {
      final known = category(id: 'a', name: 'A', fireflyId: 'ff-1');
      final localOnly = category(id: 'b', name: 'B');
      await dao.insert(known);
      await dao.insert(localOnly);

      expect(await dao.getByFireflyId('ff-1'), known);
      expect(await dao.getByFireflyId('ff-2'), isNull);
      // 'b' exists as a local primary key but has no server id yet.
      expect(await dao.getByFireflyId('b'), isNull);
    });
  });

  group('getAll', () {
    setUp(() async {
      await dao.insert(category(id: 'a', name: 'A'));
      await dao.insert(category(id: 'b', name: 'B', updatedAt: 2000));
      await dao.insert(category(id: 'c', name: 'C', updatedAt: 3000));
      await dao.softDelete('c', atMillis: 4000, seq: 50);
    });

    test('hides tombstones by default, newest write first, honours limit',
        () async {
      expect(
        (await dao.getAll()).map((c) => c.id).toList(),
        ['b', 'a'],
      );
      expect((await dao.getAll(limit: 1)).map((c) => c.id), ['b']);
    });

    test('includeDeleted surfaces the tombstones, ASC reorders', () async {
      expect(
        (await dao.getAll(includeDeleted: true))
            .map((c) => c.id)
            .toList(),
        ['c', 'b', 'a'],
      );
      expect(
        (await dao.getAll(orderBy: 'updated_at ASC'))
            .map((c) => c.id)
            .toList(),
        ['a', 'b'],
      );
    });
  });

  group('getPending', () {
    test('excludes synced rows, keeps tombstones, oldest write first',
        () async {
      await dao.insert(category(id: 'a', name: 'A'));
      await dao.insert(
        category(
          id: 'b',
          name: 'B',
          updatedAt: 2000,
          syncStatus: SyncStatus.synced,
        ),
      );
      await dao.insert(
        category(
          id: 'c',
          name: 'C',
          updatedAt: 3000,
          syncStatus: SyncStatus.synced,
        ),
      );
      await dao.softDelete('c', atMillis: 4000, seq: 50);

      final pending = await dao.getPending();

      // 'b' is synced so it is out; 'c' is tombstoned but pending, which is
      // exactly what a pull-merge must not resurrect (DESIGN §6.4).
      expect(pending.map((c) => c.id).toList(), ['a', 'c']);
    });
  });

  group('count', () {
    test('excludes tombstones unless includeDeleted is set', () async {
      await dao.insert(category(id: 'a', name: 'A'));
      await dao.insert(category(id: 'b', name: 'B'));
      await dao.insert(category(id: 'c', name: 'C'));
      await dao.softDelete('c', atMillis: 4000, seq: 50);

      expect(await dao.count(), 2);
      expect(await dao.count(includeDeleted: true), 3);
    });
  });
}
