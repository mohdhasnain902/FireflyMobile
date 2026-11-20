// R28 regression pin: the Transactions list must render the book in the
// website's own order — `date DESC`, ties broken by journal id descending.
//
// The list used to load `ORDER BY updated_at DESC LIMIT 50`. Every row a pull
// writes shares one `updated_at`, so the page was an arbitrary 50 rows (Feb
// 2024 instead of Nov 2026 on the reference book) and same-day rows appeared
// in random order.

import 'package:firefly_mobile/core/providers.dart';
import 'package:firefly_mobile/data/db/database_opener.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> _insert(
  Database db, {
  required String id,
  required String date,
  String? journalId,
}) =>
    db.insert('transactions', {
      'id': id,
      'journal_id': journalId,
      'type': 'transfer',
      'description': id,
      'date': date,
      'amount': '10',
      'updated_at': 1,
      'seq': 0,
      'sync_status': 'synced',
    });

void main() {
  setUpAll(sqfliteFfiInit);

  late Database db;
  late ProviderContainer container;

  setUp(() async {
    db = await openAppDatabase(
      factory: databaseFactoryFfiNoIsolate,
      path: inMemoryDatabasePath,
    );
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWith((ref) async => db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('list follows date DESC then journal id DESC, and is not truncated',
      () async {
    await _insert(db,
        id: 'a', date: '2024-01-02T00:00:00.000Z', journalId: '999');
    await _insert(db,
        id: 'b', date: '2024-01-02T00:00:00.000Z', journalId: '1000');
    await _insert(db,
        id: 'c', date: '2024-01-03T00:00:00.000Z', journalId: '5');
    await _insert(db,
        id: 'd', date: '2024-01-01T00:00:00.000Z', journalId: '1001');
    await _insert(db, id: 'e', date: '2024-01-03T00:00:00.000Z');

    final rows = await container.read(transactionListProvider.future);
    expect(rows.map((t) => t.id), ['c', 'e', 'b', 'a', 'd']);
    // 1000 must beat 999: a text sort would put '1000' first.
    expect(rows[2].journalId, '1000');
  });

  test('a book larger than the old page renders in full', () async {
    for (var i = 0; i < 60; i++) {
      await _insert(
        db,
        id: 'tx-$i',
        date: '2024-02-${(i % 28 + 1).toString().padLeft(2, '0')}'
            'T00:00:00.000Z',
        journalId: '${1000 + i}',
      );
    }
    final rows = await container.read(transactionListProvider.future);
    expect(rows, hasLength(60));
    for (var i = 1; i < rows.length; i++) {
      expect(
        rows[i - 1].date.isBefore(rows[i].date),
        isFalse,
        reason: 'dates are newest-first',
      );
    }
  });
}
