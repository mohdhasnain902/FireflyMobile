import 'package:firefly_mobile/data/dao/business_daos.dart';
import 'package:firefly_mobile/domain/entities/recurrence.dart';
import 'package:firefly_mobile/domain/entities/recurrence_repetition.dart';
import 'package:firefly_mobile/domain/entities/sync_bookkeeping.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../db/app_database_test.dart';

/// Pins `RecurrenceDao`'s 1:N schedule plumbing (DESIGN §3.1, plan P1).
///
/// The generic `EntityDao` suite covers the shared parent-row primitives for a
/// flat table; it cannot see the child `recurrence_repetitions` behaviour that
/// only this DAO adds. Every one of these paths silently loses or duplicates a
/// recurrence's schedule when wrong, and none of them fails loudly:
///
///  * reads must re-join children (`getAll`/`getPending`/`getById`), otherwise
///    `toJsonApi` pushes a recurrence with no schedule;
///  * writes must rewrite children wholesale from the in-memory list;
///  * an **empty** list must be a no-op (the server ignores `repetitions: []`
///    on update — a half-loaded entity must never wipe a real schedule);
///  * `hardDelete` must cascade, because the child table has no FK clause.
void main() {
  setUpAll(sqfliteFfiInit);

  late Database db;
  late RecurrenceDao dao;

  setUpAll(() async {
    db = await openTestDatabase();
    dao = RecurrenceDao(db);
  });

  // Both tables: the suite reuses one `:memory:` handle, so a recurrence row
  // left by a previous test would make the next test's child-rewrite look like
  // a duplicate-key failure instead of the assertion it is meant to be.
  setUp(() async {
    await db.delete('recurrence_repetitions');
    await db.delete('recurrences');
  });

  /// A recurrence pinned to exact UTC millisecond timestamps so `==` on the
  /// round-tripped model compares cleanly (rows decode as `isUtc: true`).
  Recurrence recurrence({
    required String id,
    String title = 'Salary',
    int updatedAt = 1000,
    int seq = 1,
    String? fireflyId,
    SyncStatus syncStatus = SyncStatus.pending,
    List<RecurrenceRepetition> repetitions = const [],
  }) {
    return Recurrence(
      id: id,
      title: title,
      type: 'deposit',
      updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAt, isUtc: true),
      seq: seq,
      fireflyId: fireflyId,
      syncStatus: syncStatus,
      repetitions: repetitions,
    );
  }

  /// One schedule child keyed to [parentId]; [ord] distinguishes rows inside
  /// the same schedule.
  RecurrenceRepetition repetition({
    required String parentId,
    required int ord,
    String type = 'monthly',
    String moment = '17',
    int skip = 0,
    RecurrenceWeekend weekend = RecurrenceWeekend.doNothing,
  }) {
    return RecurrenceRepetition(
      recurrenceId: parentId,
      ord: ord,
      repetitionType: type,
      repetitionMoment: moment,
      repetitionSkip: skip,
      weekend: weekend,
    );
  }

  /// Raw child rows for [parentId], ordered like the DAO's own join.
  Future<List<Map<String, Object?>>> childRows(String parentId) {
    return db.query(
      'recurrence_repetitions',
      where: 'recurrence_id = ?',
      whereArgs: <Object?>[parentId],
      orderBy: 'ord',
    );
  }

  group('insert', () {
    test('round-trips the parent and its schedule through getById', () async {
      final entity = recurrence(
        id: 'r-1',
        fireflyId: 'ff-1',
        repetitions: [
          repetition(parentId: 'r-1', ord: 0),
          repetition(
            parentId: 'r-1',
            ord: 1,
            type: 'weekly',
            moment: '2,5',
            skip: 1,
            weekend: RecurrenceWeekend.toFriday,
          ),
        ],
      );
      await dao.insert(entity);

      expect(await dao.getById('r-1'), entity);
      expect((await childRows('r-1')).length, 2);
    });

    test('a parent with no schedule reads back with an empty list', () async {
      final entity = recurrence(id: 'r-1');
      await dao.insert(entity);

      expect(await dao.getById('r-1'), entity);
      expect(await childRows('r-1'), isEmpty);
    });
  });

  group('update', () {
    test('a non-empty list rewrites children wholesale, not appends', () async {
      await dao.insert(
        recurrence(
          id: 'r-1',
          repetitions: [
            repetition(parentId: 'r-1', ord: 0),
            repetition(parentId: 'r-1', ord: 1),
          ],
        ),
      );

      await dao.update(
        recurrence(
          id: 'r-1',
          seq: 2,
          repetitions: [repetition(parentId: 'r-1', ord: 0, type: 'yearly')],
        ),
      );

      final rows = await childRows('r-1');
      expect(rows, hasLength(1));
      expect(rows.single['repetition_type'], 'yearly');
    });

    test('an EMPTY list leaves existing children untouched (server parity)',
        () async {
      // Firefly's RecurrenceUpdateService ignores `repetitions: []` on update.
      // Locally the same rule means a half-loaded entity — pulled without its
      // schedule, or built by a form that never edited it — must never be able
      // to wipe a schedule that is really there.
      final original = recurrence(
        id: 'r-1',
        repetitions: [repetition(parentId: 'r-1', ord: 0)],
      );
      await dao.insert(original);

      await dao.update(recurrence(id: 'r-1', seq: 2));

      expect(await childRows('r-1'), hasLength(1));
    });

    test('zero changed rows skips the child rewrite entirely', () async {
      // The parent is gone, so writing schedule rows would create orphans for
      // a row the device no longer has.
      await dao.update(recurrence(id: 'ghost', repetitions: [
        repetition(parentId: 'ghost', ord: 0),
      ]));

      expect(await childRows('ghost'), isEmpty);
    });
  });

  group('upsert (pull path)', () {
    test('replaces the schedule of a row the server already sent', () async {
      await dao.upsert(
        recurrence(
          id: 'r-1',
          fireflyId: 'ff-1',
          repetitions: [
            repetition(parentId: 'r-1', ord: 0),
            repetition(parentId: 'r-1', ord: 1),
            repetition(parentId: 'r-1', ord: 2),
          ],
        ),
      );
      // Second pull brings a shortened schedule; the old ord=2 row must go.
      await dao.upsert(
        recurrence(
          id: 'r-1',
          fireflyId: 'ff-1',
          seq: 2,
          repetitions: [repetition(parentId: 'r-1', ord: 0, type: 'daily')],
        ),
      );

      final rows = await childRows('r-1');
      expect(rows, hasLength(1));
      expect(rows.single['repetition_type'], 'daily');
      expect(await dao.getById('r-1'), recurrence(
        id: 'r-1',
        fireflyId: 'ff-1',
        seq: 2,
        repetitions: [repetition(parentId: 'r-1', ord: 0, type: 'daily')],
      ));
    });
  });

  group('hardDelete', () {
    test('cascades to children (no FK clause on the child table)', () async {
      await dao.insert(
        recurrence(
          id: 'r-1',
          repetitions: [
            repetition(parentId: 'r-1', ord: 0),
            repetition(parentId: 'r-1', ord: 1),
          ],
        ),
      );

      await dao.hardDelete('r-1');

      expect(await dao.getById('r-1'), isNull);
      expect(await childRows('r-1'), isEmpty);
    });

    test("leaves another recurrence's schedule alone", () async {
      await dao.insert(
        recurrence(
          id: 'r-1',
          repetitions: [repetition(parentId: 'r-1', ord: 0)],
        ),
      );
      await dao.insert(
        recurrence(
          id: 'r-2',
          repetitions: [repetition(parentId: 'r-2', ord: 0)],
        ),
      );

      await dao.hardDelete('r-1');

      expect(await childRows('r-2'), hasLength(1));
    });
  });

  group('read fan-out (no N+1, no cross-parent bleed)', () {
    test('getAll attaches each parent its own children in one pass', () async {
      await dao.insert(
        recurrence(
          id: 'r-1',
          repetitions: [repetition(parentId: 'r-1', ord: 0)],
        ),
      );
      await dao.insert(
        recurrence(
          id: 'r-2',
          title: 'Rent',
          updatedAt: 2000,
          repetitions: [
            repetition(parentId: 'r-2', ord: 0, type: 'weekly'),
            repetition(parentId: 'r-2', ord: 1, type: 'weekly'),
          ],
        ),
      );

      final loaded = await dao.getAll();
      final byId = {for (final e in loaded) e.id: e};

      expect(byId['r-1']!.repetitions, hasLength(1));
      expect(byId['r-2']!.repetitions, hasLength(2));
      // The join is one shared `IN (...)` query, so `loadRepetitions`'s
      // per-parent filter is what stops r-2's rows landing on r-1.
      for (final parent in loaded) {
        for (final child in parent.repetitions) {
          expect(
            child.recurrenceId,
            parent.id,
            reason: 'cross-parent bleed in the shared child join',
          );
        }
      }
    });

    test('getAll still returns a schedule-less parent with []', () async {
      await dao.insert(recurrence(id: 'r-1'));
      await dao.insert(
        recurrence(
          id: 'r-2',
          updatedAt: 2000,
          repetitions: [repetition(parentId: 'r-2', ord: 0)],
        ),
      );

      final loaded = await dao.getAll();
      final bare = loaded.singleWhere((e) => e.id == 'r-1');
      expect(bare.repetitions, isEmpty);
    });

    test('getPending attaches children too (sync push path)', () async {
      await dao.insert(
        recurrence(
          id: 'r-1',
          repetitions: [
            repetition(parentId: 'r-1', ord: 0),
            repetition(parentId: 'r-1', ord: 1),
          ],
        ),
      );

      final pending = await dao.getPending();
      expect(pending.single.repetitions, hasLength(2));
    });
  });
}
