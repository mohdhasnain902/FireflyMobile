import 'dart:convert';
import 'dart:io';

import 'package:firefly_mobile/core/settings/connection_settings.dart';
import 'package:firefly_mobile/data/api/firefly_api_client.dart';
import 'package:firefly_mobile/data/dao/entity_dao.dart';
import 'package:firefly_mobile/data/sync/pull_engine.dart';
import 'package:firefly_mobile/domain/entities/transaction.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

import '../db/app_database_test.dart';

/// End-to-end proof that a **website-side deletion reaches the phone** (R42).
///
/// Driven by the committed, verbatim Firefly fixtures in `test/fixtures/api/`
/// (captured from the real instance), through the real [FireflyApiClient] and
/// the real schema: this is the exact path the reported bug took — an account
/// deleted in the Firefly UI, then "Get from website" on the phone.
///
/// The user-visible requirement: after the pull, the deleted account (and every
/// transaction leg that lived on it) is gone from every list screen, while the
/// rows the server still has are untouched.
void main() {
  setUpAll(sqfliteFfiInit);

  late Database db;

  setUp(() async {
    db = await openTestDatabase();
  });

  tearDown(() async {
    await db.close();
  });

  /// Loads one committed API fixture as decoded JSON.
  Map<String, dynamic> fixture(String name) =>
      jsonDecode(File('test/fixtures/api/$name.json').readAsStringSync())
          as Map<String, dynamic>;

  /// The fixture members as a mutable list (the server's first answer).
  List<Map<String, dynamic>> membersOf(String name) =>
      (fixture(name)['data'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();

  /// Serves [members] as a JSON:API collection for every list path.
  PullEngine engineServing(List<Map<String, dynamic>> members) {
    final store = InMemoryConnectionSettingsStore(
      const ConnectionSettings(baseUrl: 'https://firefly.test', pat: 'tok'),
    );
    final mock = MockClient((request) async {
      if (request.method != 'GET') return http.Response('{}', 405);
      // Bytes + an explicit UTF-8 content type: the fixtures carry `€`, which
      // the latin1 default of `http.Response(String, …)` rejects.
      return http.Response.bytes(
        utf8.encode(
          jsonEncode(<String, dynamic>{
            'data': members,
            'meta': <String, dynamic>{
              'pagination': <String, dynamic>{
                'total': members.length,
                'count': members.length,
                'per_page': 100,
                'current_page': 1,
                'total_pages': 1,
                'links': <String, dynamic>{},
              },
            },
          }),
        ),
        200,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );
    });
    return PullEngine(
      db: db,
      client: FireflyApiClient(settings: store, httpClient: mock),
    );
  }

  /// The production visibility rule every list screen uses (`getAll` hides
  /// tombstones), over raw rows so the test asserts existence only.
  EntityDao<Map<String, Object?>> rowsOf(String table) => EntityDao(
    db: db,
    table: table,
    decode: (row) => row,
    encode: (row) => row,
  );

  test('an account deleted on the website disappears from the phone', () async {
    final accounts = membersOf('accounts');
    expect(accounts.length, greaterThanOrEqualTo(2));

    // 1. First pull: the website still lists every account.
    final first = await engineServing(accounts).pullEntity('accounts');
    expect(first.valueOrNull!.inserted, accounts.length);
    final visibleBefore = await rowsOf('accounts').getAll();
    expect(visibleBefore, hasLength(accounts.length));

    // 2. The user deletes one account in the Firefly UI; the list no longer
    //    contains it.
    final removed = accounts.first['id'] as String;
    final remaining =
        accounts.where((m) => m['id'] != removed).toList(growable: false);

    final second = await engineServing(remaining).pullEntity('accounts');

    expect(second.valueOrNull!.tombstoned, 1);
    // Gone from every list screen…
    final visibleAfter = await rowsOf('accounts').getAll();
    expect(visibleAfter, hasLength(remaining.length));
    expect(
      visibleAfter.map((r) => r['firefly_id']),
      isNot(contains(removed)),
    );
    // …but still readable by the sync engine, so a re-appearance on the server
    // restores the same row instead of duplicating it.
    final all = await rowsOf('accounts').getAll(includeDeleted: true);
    expect(all, hasLength(accounts.length));
  });

  test('a transaction deleted with its account is tombstoned leg by leg',
      () async {
    final groups = membersOf('transactions');
    expect(groups.length, greaterThanOrEqualTo(2));

    final first = await engineServing(groups).pullEntity('transactions');
    final inserted = first.valueOrNull!.inserted;
    expect(inserted, greaterThanOrEqualTo(2));

    // The server now returns only the first group (the account and its
    // transaction were deleted together in the Firefly UI).
    final kept = <Map<String, dynamic>>[groups.first];
    final second = await engineServing(kept).pullEntity('transactions');

    expect(second.valueOrNull!.tombstoned, inserted - 1);
    final visible = await rowsOf('transactions').getAll();
    final keptLegs = Transaction.journalCount(kept.first);
    expect(visible, hasLength(keptLegs <= 0 ? 1 : keptLegs));
  });
}
