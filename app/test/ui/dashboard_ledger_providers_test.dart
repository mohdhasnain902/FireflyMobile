// R27 regression pin: the dashboard's account balances and net worth are sums
// over the whole book, so they must not read the paged list providers.
//
// On the reference device the paged providers (newest 50 rows) put SadaPay at
// 7,102.53 instead of 4,041.00 and MCB at 89,069.00 instead of 2,012.28 while
// the server — and the same arithmetic over every row — agreed on the second
// number. These tests fail if the dashboard rows are ever wired back to the
// 50-row page.

import 'package:firefly_mobile/core/providers.dart';
import 'package:firefly_mobile/data/db/database_opener.dart';
import 'package:firefly_mobile/ui/models/dashboard_summary.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Opens a throwaway in-memory database on the host's native SQLite.
Future<Database> _openDb() => openAppDatabase(
      factory: databaseFactoryFfiNoIsolate,
      path: inMemoryDatabasePath,
    );

/// Inserts one asset account with [opening] balance.
Future<void> _insertAccount(
  Database db, {
  required String id,
  required String name,
  String opening = '0',
}) =>
    db.insert('accounts', {
      'id': id,
      'name': name,
      'type': 'asset',
      'currency_code': 'PKR',
      'opening_balance': opening,
      'updated_at': 1,
      'seq': 0,
      'sync_status': 'synced',
    });

/// Inserts one deposit of [amount] into [destId].
Future<void> _insertDeposit(
  Database db, {
  required String id,
  required String amount,
  required String destId,
  required int updatedAt,
}) =>
    db.insert('transactions', {
      'id': id,
      'type': 'deposit',
      'description': 'deposit $id',
      'date': '2024-01-15T10:00:00.000Z',
      'amount': amount,
      'currency_code': 'PKR',
      'dest_account_id': destId,
      'updated_at': updatedAt,
      'seq': updatedAt,
      'sync_status': 'synced',
    });

void main() {
  setUpAll(sqfliteFfiInit);

  late Database db;
  late ProviderContainer container;

  setUp(() async {
    db = await _openDb();
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWith((ref) async => db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('balances sum every transaction, not the newest 50', () async {
    await _insertAccount(db, id: 'acc-1', name: 'SadaPay');
    // 60 deposits of 10 into acc-1: true balance 600.
    for (var i = 0; i < 60; i++) {
      await _insertDeposit(
        db,
        id: 'tx-$i',
        amount: '10',
        destId: 'acc-1',
        updatedAt: 1000 + i,
      );
    }

    // The list itself is no longer a 50-row page (R28): it shows the whole
    // book so its order can match the website's.
    final listed = await container.read(transactionListProvider.future);
    expect(listed, hasLength(60));

    final ledger = await container.read(ledgerTransactionsProvider.future);
    expect(ledger, hasLength(60));

    final account =
        (await container.read(ledgerAccountsProvider.future)).single;
    expect(accountBalance(account, ledger), 600);
    // Summing one 50-row page instead reports 500 — the bug these fix.
    expect(accountBalance(account, ledger.take(50).toList()), isNot(600));
  });

  test('net worth sees all accounts, not the newest 50', () async {
    // 55 accounts with 1.00 opening balance each: 55.00 total.
    for (var i = 0; i < 55; i++) {
      await _insertAccount(
        db,
        id: 'acc-$i',
        name: 'Account $i',
        opening: '1',
      );
    }

    final paged = await container.read(accountListProvider.future);
    expect(paged, hasLength(50));

    final ledger = await container.read(ledgerAccountsProvider.future);
    expect(ledger, hasLength(55));
    final netWorth = ledger.fold<double>(
      0,
      (sum, a) => sum + accountBalance(a, const []),
    );
    expect(netWorth, 55);
  });
}
