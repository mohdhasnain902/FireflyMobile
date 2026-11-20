import 'dart:convert';

import 'package:firefly_mobile/core/errors/failure.dart';
import 'package:firefly_mobile/core/settings/connection_settings.dart';
import 'package:firefly_mobile/data/api/firefly_api_client.dart';
import 'package:firefly_mobile/data/sync/pull_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../db/app_database_test.dart';

/// Unit tests for [PullEngine] (P3.3, DESIGN §7.2–7.5).
///
/// Driven through an in-memory SQLite database (the real schema the app uses)
/// and a [MockClient] so no real network is touched. Covers the diff matrix
/// (DESIGN §7.3) and the tombstone pass (§7.4):
///   * unknown entity type → ValidationFailure, no HTTP
///   * empty collection + no local rows → all-zero stats
///   * insert: server row absent locally → INSERT as synced
///   * LWW update: server newer than local remote_updated_at → overwrite
///   * LWW keeps local primary key; refreshes remote_updated_at; clears
///     an unpushed tombstone
///   * unchanged: server not newer → skippedUnchanged, row untouched
///   * null local remote_updated_at (never pushed) counts as older
///   * null server updated_at is never newer → local copy stands
///   * a still-listed pending row is never overwritten (local wins)
///   * tombstone: synced row absent from a full response → deleted_at set
///   * tombstone also reclaims `conflict` rows and resolves `pending` ones
///     whose server copy is gone (row + op_log dropped, R40)
///   * tombstone skipped for already-tombstoned / unpushed (no firefly_id) rows
///   * tombstone only after every page succeeded (partial pull leaves rows)
///   * pullAll continues after one entity fails, recording it in failures (R39)
///   * multi-page pagination: pages merged, then one tombstone pass
///   * budget_limits walks the nested budgets/{id}/limits path per budget
///   * stats aggregation across entities (+ operator, PullStats getters)
void main() {
  setUpAll(sqfliteFfiInit);

  late Database db;
  late List<http.Request> requests;

  /// Builds a PullEngine with a [MockClient] that records requests and runs
  /// [handler] on each one. [handler] is keyed off the request path.
  PullEngine buildEngine({
    required Future<http.Response> Function(http.Request request) handler,
  }) {
    final store = InMemoryConnectionSettingsStore(
      const ConnectionSettings(baseUrl: 'https://firefly.test', pat: 'tok'),
    );
    final mock = MockClient((request) {
      requests.add(request);
      return handler(request);
    });
    final client = FireflyApiClient(settings: store, httpClient: mock);
    return PullEngine(db: db, client: client);
  }

  /// A JSON:API collection document carrying [resources] and a pagination
  /// block for [page]/[totalPages]. Firefly's real shape.
  http.Response collectionResponse(
    List<Map<String, dynamic>> resources, {
    int page = 1,
    int totalPages = 1,
    int total = 0,
  }) {
    return http.Response(
      jsonEncode({
        'data': resources,
        'meta': {
          'pagination': {
            'total': total == 0 ? resources.length * totalPages : total,
            'count': resources.length,
            'per_page': 100,
            'current_page': page,
            'total_pages': totalPages,
            'links': <String, dynamic>{},
          },
        },
      }),
      200,
    );
  }

  /// A single JSON:API currency member. [updatedAt] is written into
  /// `attributes.updated_at`, which is what the engine compares against.
  Map<String, dynamic> currencyMember({
    required String id,
    required String code,
    DateTime? updatedAt,
  }) {
    return <String, dynamic>{
      'type': 'currencies',
      'id': id,
      'attributes': <String, dynamic>{
        'code': code,
        'name': 'Currency $code',
        'symbol': r'$',
        'enabled': true,
        'default': false,
        'rate': '1.0',
        'updated_at': updatedAt?.toIso8601String(),
      },
    };
  }

  /// Seeds a currencies row directly (bypassing the engine) so a test can
  /// control local bookkeeping exactly.
  Future<void> seedCurrency({
    required String id,
    required String code,
    String? fireflyId,
    int? remoteUpdatedAt,
    String syncStatus = 'synced',
    int? deletedAt,
  }) async {
    await db.insert('currencies', {
      'id': id,
      'code': code,
      'name': 'Seed $code',
      'symbol': r'$',
      'symbol_first': 0,
      'decimal_places': 2,
      'enabled': 1,
      'is_default': 0,
      'rate': '1.0',
      'firefly_id': fireflyId,
      'updated_at': 1000,
      'remote_updated_at': remoteUpdatedAt,
      'sync_status': syncStatus,
      'deleted_at': deletedAt,
      'seq': 1,
    });
  }

  /// A JSON:API recurrence member carrying a nested `repetitions[]` — the
  /// wire shape RecurrenceTransformer emits (children ride the parent).
  Map<String, dynamic> recurrenceMember({
    required String id,
    DateTime? updatedAt,
    List<Map<String, dynamic>> repetitions = const [],
  }) {
    return <String, dynamic>{
      'type': 'recurrences',
      'id': id,
      'attributes': <String, dynamic>{
        'title': 'Recurrence $id',
        'type': 'withdrawal',
        'description': null,
        'first_date': '2026-01-01',
        'repeat_until': null,
        'nr_of_repetitions': null,
        'active': true,
        'apply_rules': true,
        'transactions': <dynamic>[],
        'repetitions': repetitions,
        'updated_at': updatedAt?.toIso8601String(),
      },
    };
  }

  /// One wire repetition element (a child of [recurrenceMember]).
  Map<String, dynamic> repetition({
    required String type,
    String moment = '18:00:00',
  }) => <String, dynamic>{
    'type': type,
    'moment': moment,
    'skip': 0,
    'weekend': 1,
  };

  /// Seeds a recurrences parent + its children directly, so a test can
  /// control the pre-pull child set exactly.
  Future<void> seedRecurrence({
    required String id,
    String? fireflyId,
    int? remoteUpdatedAt,
    String syncStatus = 'synced',
    List<({int ord, String type, String moment})> children = const [],
  }) async {
    await db.insert('recurrences', {
      'id': id,
      'title': 'Seed recurrence',
      'type': 'withdrawal',
      'description': null,
      'first_date': null,
      'repeat_until': null,
      'nr_of_repetitions': null,
      'active': 1,
      'apply_rules': 1,
      'transactions_json': null,
      'latest_date': null,
      'firefly_id': fireflyId,
      'updated_at': 1000,
      'remote_updated_at': remoteUpdatedAt,
      'sync_status': syncStatus,
      'deleted_at': null,
      'seq': 1,
    });
    for (final child in children) {
      await db.insert('recurrence_repetitions', {
        'recurrence_id': id,
        'ord': child.ord,
        'repetition_type': child.type,
        'repetition_moment': child.moment,
        'repetition_skip': 0,
        'weekend': 1,
      });
    }
  }

  /// Reads all `recurrence_repetitions` children of one parent, ordered by
  /// ordinal.
  Future<List<Map<String, Object?>>> repetitionRows(
    String recurrenceId,
  ) {
    return db.query(
      'recurrence_repetitions',
      where: 'recurrence_id = ?',
      whereArgs: [recurrenceId],
      orderBy: 'ord',
    );
  }

  /// Reads one currencies row by its local primary key.
  Future<Map<String, Object?>> currencyRow(String id) async {
    final rows = await db.query(
      'currencies',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.first;
  }

  setUp(() async {
    db = await openTestDatabase();
    requests = [];
  });

  tearDown(() async {
    await db.close();
  });

  // ── Unknown entity type ────────────────────────────────────────────────────

  test('pullEntity(unknown) returns ValidationFailure and issues no HTTP',
      () async {
    final engine = buildEngine(
      handler: (r) async => collectionResponse([]),
    );

    final result = await engine.pullEntity('no_such_entity');

    expect(result.isOk, isFalse);
    expect(result.failureOrNull, isA<ValidationFailure>());
    expect(requests, isEmpty);
  });

  // ── Empty ─────────────────────────────────────────────────────────────────

  test('empty collection with empty local table yields all-zero stats',
      () async {
    final engine = buildEngine(
      handler: (r) async => collectionResponse([]),
    );

    final result = await engine.pullEntity('currencies');

    expect(result.isOk, isTrue);
    final stats = result.valueOrNull!;
    expect(stats.inserted, 0);
    expect(stats.updated, 0);
    expect(stats.skippedPending, 0);
    expect(stats.skippedUnchanged, 0);
    expect(stats.tombstoned, 0);
    expect(requests, hasLength(1));
    expect(requests.single.url.path, contains('/currencies'));
  });

  // ── Insert ────────────────────────────────────────────────────────────────

  test('server row absent locally is inserted as a synced row', () async {
    final engine = buildEngine(
      handler: (r) async => collectionResponse([
        currencyMember(
          id: '101',
          code: 'USD',
          updatedAt: DateTime.utc(2026),
        ),
      ]),
    );

    final result = await engine.pullEntity('currencies');

    expect(result.valueOrNull!.inserted, 1);
    final rows = await db.query('currencies');
    expect(rows, hasLength(1));
    final row = rows.first;
    expect(row['firefly_id'], '101');
    expect(row['code'], 'USD');
    expect(row['sync_status'], 'synced');
    // remote_updated_at is stored as epoch millis of the server timestamp.
    expect(
      row['remote_updated_at'],
      DateTime.utc(2026).millisecondsSinceEpoch,
    );
  });

  // ── LWW update ────────────────────────────────────────────────────────────

  test('server newer than local remote_updated_at overwrites via LWW',
      () async {
    await seedCurrency(
      id: 'local-1',
      code: 'OLD',
      fireflyId: '201',
      remoteUpdatedAt: DateTime.utc(2026).millisecondsSinceEpoch,
    );
    final engine = buildEngine(
      handler: (r) async => collectionResponse([
        currencyMember(
          id: '201',
          code: 'NEW',
          updatedAt: DateTime.utc(2026, 6),
        ),
      ]),
    );

    final result = await engine.pullEntity('currencies');

    expect(result.valueOrNull!.updated, 1);
    final row = await currencyRow('local-1');
    // Local primary key is preserved.
    expect(row['id'], 'local-1');
    expect(row['code'], 'NEW');
    expect(row['firefly_id'], '201');
    // P3.5.2: server-won overwrite marks the row `conflict` — the UI shows
    // the "Resolved by server" badge until the row is next pushed.
    expect(row['sync_status'], 'conflict');
    expect(
      row['remote_updated_at'],
      DateTime.utc(2026, 6).millisecondsSinceEpoch,
    );
  });

  test('LWW overwrite clears an unpushed local tombstone', () async {
    await seedCurrency(
      id: 'local-tomb',
      code: 'GONE',
      fireflyId: '301',
      remoteUpdatedAt: DateTime.utc(2026).millisecondsSinceEpoch,
      deletedAt: DateTime.utc(2026, 2).millisecondsSinceEpoch,
    );
    final engine = buildEngine(
      handler: (r) async => collectionResponse([
        currencyMember(
          id: '301',
          code: 'BACK',
          updatedAt: DateTime.utc(2026, 6),
        ),
      ]),
    );

    final result = await engine.pullEntity('currencies');

    expect(result.valueOrNull!.updated, 1);
    final row = await currencyRow('local-tomb');
    expect(row['deleted_at'], isNull);
    expect(row['code'], 'BACK');
    // Tombstone-clear goes through the same LWW overwrite path, so it also
    // lands in `conflict` (P3.5.2).
    expect(row['sync_status'], 'conflict');
  });

  test('a conflict row is still overwritten by a newer server copy', () async {
    // P3.5.2 regression pin: once a row is `conflict` (server won earlier),
    // the next *strictly newer* server copy must still merge — the merge
    // gate may only freeze `pending` rows (unsent local ops), or a conflict
    // row would be stuck at its first conflict forever.
    await seedCurrency(
      id: 'local-conflict',
      code: 'FIRST',
      fireflyId: '501',
      remoteUpdatedAt: DateTime.utc(2026).millisecondsSinceEpoch,
      syncStatus: 'conflict',
    );
    final engine = buildEngine(
      handler: (r) async => collectionResponse([
        currencyMember(
          id: '501',
          code: 'SECOND',
          updatedAt: DateTime.utc(2026, 6),
        ),
      ]),
    );

    final result = await engine.pullEntity('currencies');

    expect(result.valueOrNull!.updated, 1);
    final row = await currencyRow('local-conflict');
    expect(row['code'], 'SECOND');
    // Still conflict — the badge persists across successive server wins.
    expect(row['sync_status'], 'conflict');
  });

  // ── Unchanged ─────────────────────────────────────────────────────────────

  test('server not newer than local is left unchanged', () async {
    await seedCurrency(
      id: 'local-eq',
      code: 'SAME',
      fireflyId: '401',
      remoteUpdatedAt: DateTime.utc(2026, 6).millisecondsSinceEpoch,
    );
    final engine = buildEngine(
      handler: (r) async => collectionResponse([
        currencyMember(
          id: '401',
          code: 'OLD',
          // Equal to local remote_updated_at → not strictly newer.
          updatedAt: DateTime.utc(2026, 6),
        ),
      ]),
    );

    final result = await engine.pullEntity('currencies');

    expect(result.valueOrNull!.skippedUnchanged, 1);
    final row = await currencyRow('local-eq');
    expect(row['code'], 'SAME');
  });

  test('an overwrite with identical content leaves the row synced', () async {
    // A forced full re-merge (e.g. the first pull after a new column was
    // added) rewrites every row from the server even when nothing changed.
    // Those rows must not end up badged `conflict` — the badge means "the
    // server replaced different local data".
    final payload = [
      currencyMember(
        id: '701',
        code: 'SAME',
        updatedAt: DateTime.utc(2026, 6),
      ),
    ];
    await buildEngine(handler: (r) async => collectionResponse(payload))
        .pullEntity('currencies');
    // Simulate the stale bookkeeping that forces the overwrite.
    await db.update(
      'currencies',
      {
        'remote_updated_at': DateTime.utc(2026, 1).millisecondsSinceEpoch,
        'sync_status': 'conflict',
      },
      where: 'firefly_id = ?',
      whereArgs: ['701'],
    );

    final result = await buildEngine(
      handler: (r) async => collectionResponse(payload),
    ).pullEntity('currencies');

    expect(result.valueOrNull!.updated, 1);
    final rows = await db.query('currencies', where: 'firefly_id = ?',
        whereArgs: ['701']);
    expect(rows.single['code'], 'SAME');
    expect(rows.single['sync_status'], 'synced');
    expect(
      rows.single['remote_updated_at'],
      DateTime.utc(2026, 6).millisecondsSinceEpoch,
    );
  });

  test('a stale conflict badge is cleared when the server agrees', () async {
    final payload = [
      currencyMember(
        id: '801',
        code: 'AGREE',
        updatedAt: DateTime.utc(2026, 6),
      ),
    ];
    await buildEngine(handler: (r) async => collectionResponse(payload))
        .pullEntity('currencies');
    // The server still reports the version already stored, so the pull leaves
    // the content alone — but the informational badge must not stick forever.
    await db.update('currencies', {'sync_status': 'conflict'},
        where: 'firefly_id = ?', whereArgs: ['801']);

    final result = await buildEngine(
      handler: (r) async => collectionResponse(payload),
    ).pullEntity('currencies');

    expect(result.valueOrNull!.skippedUnchanged, 1);
    final rows = await db.query('currencies', where: 'firefly_id = ?',
        whereArgs: ['801']);
    expect(rows.single['sync_status'], 'synced');
  });

  test('null local remote_updated_at (never pushed) counts as older',
      () async {
    await seedCurrency(id: 'local-null', code: 'A', fireflyId: '501');
    final engine = buildEngine(
      handler: (r) async => collectionResponse([
        currencyMember(
          id: '501',
          code: 'B',
          updatedAt: DateTime.utc(2026, 6),
        ),
      ]),
    );

    final result = await engine.pullEntity('currencies');

    expect(result.valueOrNull!.updated, 1);
    final row = await currencyRow('local-null');
    expect(row['code'], 'B');
  });

  test('null server updated_at is never newer; local copy stands', () async {
    await seedCurrency(
      id: 'local-keep',
      code: 'KEEP',
      fireflyId: '601',
      remoteUpdatedAt: DateTime.utc(2026).millisecondsSinceEpoch,
    );
    final engine = buildEngine(
      handler: (r) async => collectionResponse([
        currencyMember(id: '601', code: 'SERVER'),
      ]),
    );

    final result = await engine.pullEntity('currencies');

    expect(result.valueOrNull!.skippedUnchanged, 1);
    final row = await currencyRow('local-keep');
    expect(row['code'], 'KEEP');
  });

  // ── Pending wins ──────────────────────────────────────────────────────────

  test('pending local row is never overwritten even when server is newer',
      () async {
    await seedCurrency(
      id: 'local-pending',
      code: 'LOCAL',
      fireflyId: '701',
      remoteUpdatedAt: DateTime.utc(2026).millisecondsSinceEpoch,
      syncStatus: 'pending',
    );
    final engine = buildEngine(
      handler: (r) async => collectionResponse([
        currencyMember(
          id: '701',
          code: 'SERVER',
          updatedAt: DateTime.utc(2026, 12, 31),
        ),
      ]),
    );

    final result = await engine.pullEntity('currencies');

    expect(result.valueOrNull!.skippedPending, 1);
    final row = await currencyRow('local-pending');
    expect(row['code'], 'LOCAL');
    expect(row['sync_status'], 'pending');
  });

  // ── Tombstone ─────────────────────────────────────────────────────────────

  test('synced local row absent from a full response is tombstoned', () async {
    await seedCurrency(
      id: 'local-gone',
      code: 'DEAD',
      fireflyId: '801',
      remoteUpdatedAt: DateTime.utc(2026).millisecondsSinceEpoch,
    );
    // Response lists only a different row, so 801 is unseen.
    final engine = buildEngine(
      handler: (r) async => collectionResponse([
        currencyMember(
          id: '802',
          code: 'ALIVE',
          updatedAt: DateTime.utc(2026, 6),
        ),
      ]),
    );

    final result = await engine.pullEntity('currencies');

    expect(result.valueOrNull!.tombstoned, 1);
    final row = await currencyRow('local-gone');
    expect(row['deleted_at'], isNotNull);
  });

  test('tombstone leaves unpushed rows and already-tombstoned rows alone',
      () async {
    await seedCurrency(
      id: 'already',
      code: 'X',
      fireflyId: '901',
      deletedAt: DateTime.utc(2026).millisecondsSinceEpoch,
    );
    // A local-only create: the server has never heard of it, so its absence
    // from the list means nothing.
    await seedCurrency(id: 'unpushed', code: 'Z');
    final engine = buildEngine(
      handler: (r) async => collectionResponse([]),
    );

    final result = await engine.pullEntity('currencies');

    expect(result.valueOrNull!.tombstoned, 0);
    expect(await currencyRow('already'), isNotNull);
    expect((await currencyRow('already'))['deleted_at'], isNotNull);
    expect(await currencyRow('unpushed'), isNotNull);
    expect((await currencyRow('unpushed'))['deleted_at'], isNull);
  });

  test('a conflict row disappears when the server no longer lists it (R40)',
      () async {
    await seedCurrency(
      id: 'badged',
      code: 'GONE',
      fireflyId: '903',
      syncStatus: 'conflict',
      remoteUpdatedAt: DateTime.utc(2026).millisecondsSinceEpoch,
    );
    final engine = buildEngine(
      handler: (r) async => collectionResponse([]),
    );

    final result = await engine.pullEntity('currencies');

    expect(result.valueOrNull!.tombstoned, 1);
    // Hidden from every list screen: the row is still readable for the sync
    // engine, but `getAll` filters it out.
    expect((await currencyRow('badged'))['deleted_at'], isNotNull);
  });

  test('a pending row whose server copy is gone is dropped with its ops (R40)',
      () async {
    await seedCurrency(
      id: 'stuck',
      code: 'STUCK',
      fireflyId: '904',
      syncStatus: 'pending',
    );
    await db.insert('op_log', {
      'op_id': 'op-stuck',
      'entity_type': 'currencies',
      'entity_id': 'stuck',
      'action': 'update',
      'payload': jsonEncode({
        'type': 'currencies',
        'attributes': {'code': 'STUCK'},
      }),
      'wall_ts': 1000,
      'device_id': 'dev-1',
      'seq': 1,
      'created_at': 1000,
      'attempts': 3,
      'last_error': '404: gone',
    });
    final engine = buildEngine(
      handler: (r) async => collectionResponse([]),
    );

    final result = await engine.pullEntity('currencies');

    expect(result.valueOrNull!.tombstoned, 1);
    // The row cannot be pushed (its server id no longer exists), so keeping it
    // and its op queued wedged every future push on a permanent 404/422.
    expect(
      await db.query('currencies', where: "id = 'stuck'"),
      isEmpty,
    );
    expect(await db.query('op_log'), isEmpty);
  });

  test('pullAll keeps pulling other entities after one fails (R39)', () async {
    await seedCurrency(
      id: 'local-cur',
      code: 'KEEP',
      fireflyId: '905',
      remoteUpdatedAt: DateTime.utc(2026).millisecondsSinceEpoch,
    );
    final engine = buildEngine(
      handler: (r) async {
        if (r.url.path.endsWith('/currencies')) {
          return http.Response('{"message":"boom"}', 500);
        }
        return collectionResponse([]);
      },
    );

    final result = await engine.pullAll();

    final stats = result.valueOrNull!;
    expect(stats.hasFailures, isTrue);
    expect(stats.failures.keys, contains('currencies'));
    // Every other entity still ran: the account list in particular must be
    // pulled, because that is what makes a website-side account deletion
    // visible on the phone.
    expect(stats.entities.keys, contains('accounts'));
    expect(stats.entities.keys, contains('transactions'));
    // The failed entity's rows were left untouched (no tombstone on a failed
    // list), and the entities after it were still merged.
    expect((await currencyRow('local-cur'))['deleted_at'], isNull);
  });

  test('no tombstone when a later page fails (partial pull is not final)',
      () async {
    await seedCurrency(
      id: 'partial',
      code: 'SAFE',
      fireflyId: '1001',
      remoteUpdatedAt: DateTime.utc(2026).millisecondsSinceEpoch,
    );
    // Page 1 succeeds and is merged; page 2 fails → no tombstone pass.
    final engine = buildEngine(handler: (r) {
      final page = r.url.queryParameters['page'];
      if (page == '1') {
        return Future.value(
          collectionResponse([
            currencyMember(
              id: '1002',
              code: 'NEW',
              updatedAt: DateTime.utc(2026, 6),
            ),
          ], totalPages: 2, total: 200),
        );
      }
      return Future.value(http.Response('{"message":"boom"}', 500));
    });

    final result = await engine.pullEntity('currencies');

    expect(result.isOk, isFalse);
    // Page-1 insert persisted (idempotent merge), but the page-1 unseen row
    // must NOT have been tombstoned because the pull never completed.
    final rows = await db.query('currencies');
    expect(rows, hasLength(2));
    expect((await currencyRow('partial'))['deleted_at'], isNull);
  });

  test('an incomplete list never tombstones (full page, lying total_pages)',
      () async {
    await seedCurrency(
      id: 'still-here',
      code: 'KEEP',
      fireflyId: '1101',
      remoteUpdatedAt: DateTime.utc(2026).millisecondsSinceEpoch,
    );
    // The classic truncated read: the page is *full* (100 members, per_page
    // 100) but `total` says 250 and `total_pages` says 1. Concluding "deleted"
    // from that would hide real data, so the deletion pass must be skipped.
    final engine = buildEngine(
      handler: (r) async => collectionResponse([
        for (var i = 0; i < 100; i++)
          currencyMember(
            id: '${1200 + i}',
            code: 'C$i',
            updatedAt: DateTime.utc(2026, 6),
          ),
      ], total: 250),
    );

    final result = await engine.pullEntity('currencies');

    expect(result.isOk, isFalse);
    expect(result.failureOrNull!.code, 'pull.incomplete-list');
    expect((await currencyRow('still-here'))['deleted_at'], isNull);
    // The pages that did arrive are still merged (idempotent).
    expect(await db.query('currencies'), hasLength(101));
  });

  test('a short last page with an inflated total still tombstones (Firefly\'s own count)',
      () async {
    await seedCurrency(
      id: 'gone',
      code: 'DEAD',
      fireflyId: '1301',
      remoteUpdatedAt: DateTime.utc(2026).millisecondsSinceEpoch,
    );
    // `/transactions` on the reference book reports `total: 551` while only
    // 549 groups exist, and its last page is short. That must still be treated
    // as a complete read, or deletions would never be applied there.
    final engine = buildEngine(
      handler: (r) async => collectionResponse([
        currencyMember(
          id: '1302',
          code: 'ALIVE',
          updatedAt: DateTime.utc(2026, 6),
        ),
      ], total: 5),
    );

    final result = await engine.pullEntity('currencies');

    expect(result.isOk, isTrue);
    expect(result.valueOrNull!.tombstoned, 1);
    expect((await currencyRow('gone'))['deleted_at'], isNotNull);
  });

  // ── Pagination ────────────────────────────────────────────────────────────

  test('multiple pages are merged then tombstoned once', () async {
    final engine = buildEngine(handler: (r) {
      final page = r.url.queryParameters['page'];
      if (page == '1') {
        return Future.value(
          collectionResponse(
            [
              currencyMember(
                id: '2001',
                code: 'P1',
                updatedAt: DateTime.utc(2026, 6),
              ),
            ],
            totalPages: 2,
            total: 2,
          ),
        );
      }
      return Future.value(
        collectionResponse(
          [
            currencyMember(
              id: '2002',
              code: 'P2',
              updatedAt: DateTime.utc(2026, 6),
            ),
          ],
          page: 2,
          totalPages: 2,
          total: 2,
        ),
      );
    });

    final result = await engine.pullEntity('currencies');

    expect(result.valueOrNull!.inserted, 2);
    expect(requests, hasLength(2));
    final rows = await db.query('currencies');
    expect(rows, hasLength(2));
  });

  // ── budget_limits nested path ─────────────────────────────────────────────

  test('budget_limits walks the nested per-budget path', () async {
    // Two pushed budgets; the engine should hit budgets/{id}/limits for each.
    await db.insert('budgets', {
      'id': 'b-local-1',
      'name': 'Budget 1',
      'firefly_id': 'b-301',
      'updated_at': 1000,
      'sync_status': 'synced',
      'seq': 1,
    });
    await db.insert('budgets', {
      'id': 'b-local-2',
      'name': 'Budget 2',
      'firefly_id': 'b-302',
      'updated_at': 1000,
      'sync_status': 'synced',
      'seq': 2,
    });

    Map<String, dynamic> limitMember(String id, String budgetId) =>
        <String, dynamic>{
          'type': 'budget_limits',
          'id': id,
          'attributes': <String, dynamic>{
            'budget_id': budgetId,
            'start': '2026-01-01',
            'end': '2026-01-31',
            'amount': '100.00',
            'currency_code': 'USD',
            'updated_at': DateTime.utc(2026, 6).toIso8601String(),
          },
        };

    final engine = buildEngine(handler: (r) {
      if (r.url.path.contains('budgets/b-301/limits')) {
        return Future.value(
          collectionResponse([limitMember('L1', 'b-301')]),
        );
      }
      if (r.url.path.contains('budgets/b-302/limits')) {
        return Future.value(
          collectionResponse([limitMember('L2', 'b-302')]),
        );
      }
      return Future.value(http.Response('{"message":"not found"}', 404));
    });

    final result = await engine.pullEntity('budget_limits');

    expect(result.isOk, isTrue);
    expect(result.valueOrNull!.inserted, 2);
    // Both nested endpoints were hit; the un-pushed budget would be skipped.
    expect(requests, hasLength(2));
    final rows = await db.query('budget_limits');
    expect(rows, hasLength(2));
  });

  // ── Recurrence repetitions ride the parent pull (Story 5 hardening) ───────

  test('insert writes the nested repetitions[] as child rows', () async {
    final engine = buildEngine(
      handler: (request) async => collectionResponse([
        recurrenceMember(
          id: 'srv-1',
          updatedAt: DateTime.utc(2026),
          repetitions: [
            repetition(type: 'daily'),
            repetition(type: 'monthly', moment: '09:00:00'),
          ],
        ),
      ]),
    );

    final result = await engine.pullEntity('recurrences');

    expect(result.isOk, isTrue);
    expect(result.valueOrNull!.inserted, 1);
    // Parent row keyed by a fresh local id.
    final parents = await db.query(
      'recurrences',
      where: 'firefly_id = ?',
      whereArgs: ['srv-1'],
      limit: 1,
    );
    expect(parents, hasLength(1));
    final localId = parents.first['id']! as String;
    // Children re-keyed to that local id, ordinals following array order.
    final children = await repetitionRows(localId);
    expect(children, hasLength(2));
    expect(children[0]['repetition_type'], 'daily');
    expect(children[0]['ord'], 0);
    expect(children[1]['repetition_type'], 'monthly');
    expect(children[1]['repetition_moment'], '09:00:00');
  });

  test('LWW overwrite rewrites the children (stale schedule is replaced)',
      () async {
    // Local copy already synced (older remote stamp) with a stale one-row
    // schedule that no longer matches the server.
    await seedRecurrence(
      id: 'loc-1',
      fireflyId: 'srv-1',
      remoteUpdatedAt: 1000,
      children: [(ord: 0, type: 'daily', moment: '08:00:00')],
    );
    final engine = buildEngine(
      handler: (request) async => collectionResponse([
        recurrenceMember(
          id: 'srv-1',
          updatedAt: DateTime.utc(2026, 6),
          repetitions: [
            repetition(type: 'weekly', moment: '12:00:00'),
            repetition(type: 'yearly', moment: '13:00:00'),
          ],
        ),
      ]),
    );

    final result = await engine.pullEntity('recurrences');

    expect(result.isOk, isTrue);
    expect(result.valueOrNull!.updated, 1);
    // Same local primary key, but the schedule is the server's — the stale
    // daily 08:00 row must be gone, not orphaned alongside the new ones.
    final children = await repetitionRows('loc-1');
    expect(children, hasLength(2));
    expect(children[0]['repetition_type'], 'weekly');
    expect(children[1]['repetition_type'], 'yearly');
  });

  test('pending local recurrence is skipped and keeps its children', () async {
    await seedRecurrence(
      id: 'loc-1',
      fireflyId: 'srv-1',
      remoteUpdatedAt: 1000,
      syncStatus: 'pending',
      children: [(ord: 0, type: 'daily', moment: '08:00:00')],
    );
    final engine = buildEngine(
      handler: (request) async => collectionResponse([
        recurrenceMember(
          id: 'srv-1',
          updatedAt: DateTime.utc(2026, 6),
          repetitions: [repetition(type: 'weekly')],
        ),
      ]),
    );

    final result = await engine.pullEntity('recurrences');

    expect(result.isOk, isTrue);
    expect(result.valueOrNull!.skippedPending, 1);
    // Parent untouched → its child rewrite must not have run.
    final children = await repetitionRows('loc-1');
    expect(children, hasLength(1));
    expect(children[0]['repetition_type'], 'daily');
  });

  // ── Stats aggregation ─────────────────────────────────────────────────────

  test('PullEntityStats + operator and PullStats getters aggregate', () {
    const a = PullEntityStats(
      inserted: 1,
      updated: 2,
      skippedPending: 3,
      skippedUnchanged: 4,
      tombstoned: 5,
    );
    const b = PullEntityStats(
      inserted: 10,
      updated: 20,
      skippedPending: 30,
      skippedUnchanged: 40,
      tombstoned: 50,
    );
    final sum = a + b;
    expect(sum.inserted, 11);
    expect(sum.updated, 22);
    expect(sum.skippedPending, 33);
    expect(sum.skippedUnchanged, 44);
    expect(sum.tombstoned, 55);

    const stats = PullStats({
      'currencies': a,
      'accounts': b,
    });
    expect(stats.inserted, 11);
    expect(stats.updated, 22);
    expect(stats.skippedPending, 33);
    expect(stats.skippedUnchanged, 44);
    expect(stats.tombstoned, 55);
  });
}
