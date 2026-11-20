import 'dart:convert';

import 'package:firefly_mobile/core/settings/connection_settings.dart';
import 'package:firefly_mobile/data/api/firefly_api_client.dart';
import 'package:firefly_mobile/data/sync/op_log_pusher.dart';
import 'package:firefly_mobile/domain/entities/op_log_entry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../db/app_database_test.dart';

/// Unit tests for [OpLogPusher] (P3.2, DESIGN §6.3).
///
/// Driven through an in-memory SQLite database (same schema the app uses)
/// and a [MockClient] so no real network is touched. Covers:
///   * Empty queue → [PushOutcome.empty]
///   * Create success → POST, store firefly_id, set synced, delete op
///   * Create skipped when firefly_id already set (idempotent replay)
///   * Create on a missing local row → acknowledge without hitting the network
///   * Update success → PUT, set remote_updated_at, delete op
///   * Update with firefly_id null → falls back to create
///   * Delete with firefly_id → DELETE, hard-delete row, delete op
///   * Delete 404 → still hard-delete + ack (server already gone)
///   * Delete of a local-only row (firefly_id null) → hard-delete, no HTTP
///   * Failure mid-batch → attempts+1, last_error, break, remaining ops stay
///   * URL mapping: underscore→hyphen (piggy_banks → piggy-banks) and
///     budget_limits nested path (budgets/{budget_id}/limits[/{id}])
///   * Batch ordering follows wall_ts / device_id / seq
void main() {
  setUpAll(sqfliteFfiInit);

  late Database db;
  late List<http.Request> requests;

  /// Builds an OpLogPusher with a [MockClient] that records requests and
  /// runs [handler] on each one.
  OpLogPusher buildPusher({
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
    return OpLogPusher(db: db, client: client);
  }

  /// A 2xx JSON:API response for a create/update, with [id] and optional
  /// updated_at so the pusher can store remote_updated_at.
  http.Response resourceResponse(String type, String id, {String? updatedAt}) {
    final attrs = <String, dynamic>{
      'name': 'Test',
      'updated_at': ?updatedAt,
    };
    return http.Response(
      jsonEncode({
        'data': {'type': type, 'id': id, 'attributes': attrs},
      }),
      200,
    );
  }

  /// Inserts a minimal category row with the given bookkeeping state.
  Future<void> seedCategory(
    String id, {
    String? fireflyId,
    String syncStatus = 'pending',
    int seq = 1,
  }) async {
    await db.insert('categories', {
      'id': id,
      'name': 'Cat-$id',
      'firefly_id': fireflyId,
      'updated_at': 1000,
      'sync_status': syncStatus,
      'seq': seq,
    });
  }

  /// Appends an op_log entry with the given fields.
  Future<void> seedOp(
    String opId, {
    required String entityType,
    required String entityId,
    required OpAction action,
    String? payload,
    int wallTs = 1000,
    String deviceId = 'device-a',
    int seq = 1,
  }) async {
    await db.insert('op_log', {
      'op_id': opId,
      'entity_type': entityType,
      'entity_id': entityId,
      'action': action.name,
      'payload': payload,
      'wall_ts': wallTs,
      'device_id': deviceId,
      'seq': seq,
      'created_at': wallTs,
      'attempts': 0,
    });
  }

  setUp(() async {
    db = await openTestDatabase();
    requests = [];
  });

  tearDown(() async {
    await db.close();
  });

  // ── Empty queue ────────────────────────────────────────────────────────────

  test('empty queue returns PushOutcome.empty without hitting the network',
      () async {
    final pusher = buildPusher(handler: (_) async => http.Response('{}', 500));

    final result = await pusher.pushBatch();

    expect(result.isOk, isTrue);
    expect(result.valueOrNull, PushOutcome.empty);
    expect(requests, isEmpty);
  });

  // ── Create ─────────────────────────────────────────────────────────────────

  test('create success: POST, store firefly_id, set synced, delete op',
      () async {
    await seedCategory('local-1');
    await seedOp(
      'op-1',
      entityType: 'categories',
      entityId: 'local-1',
      action: OpAction.create,
      payload: jsonEncode({
        'type': 'categories',
        'attributes': {'name': 'Cat'},
      }),
    );

    final pusher = buildPusher(
      handler: (request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/categories');
        return resourceResponse('categories', '42');
      },
    );

    final result = await pusher.pushBatch();

    expect(result.valueOrNull, PushOutcome.allOk);
    final row = (await db.query('categories', where: 'id = ?',
        whereArgs: ['local-1'])).single;
    expect(row['firefly_id'], '42');
    expect(row['sync_status'], 'synced');
    expect(await db.query('op_log'), isEmpty);
  });

  test('create is skipped when firefly_id already set (idempotent replay)',
      () async {
    await seedCategory('local-2', fireflyId: '99');
    await seedOp(
      'op-2',
      entityType: 'categories',
      entityId: 'local-2',
      action: OpAction.create,
      payload: jsonEncode({
        'type': 'categories',
        'attributes': {'name': 'Cat'},
      }),
    );

    final pusher = buildPusher(handler: (_) async => http.Response('{}', 500));

    final result = await pusher.pushBatch();

    expect(result.valueOrNull, PushOutcome.allOk);
    expect(requests, isEmpty);
    expect(await db.query('op_log'), isEmpty);
  });

  test('create on a missing local row acknowledges without hitting network',
      () async {
    await seedOp(
      'op-3',
      entityType: 'categories',
      entityId: 'ghost',
      action: OpAction.create,
      payload: jsonEncode({
        'type': 'categories',
        'attributes': {'name': 'Cat'},
      }),
    );

    final pusher = buildPusher(handler: (_) async => http.Response('{}', 500));

    final result = await pusher.pushBatch();

    expect(result.valueOrNull, PushOutcome.allOk);
    expect(requests, isEmpty);
    expect(await db.query('op_log'), isEmpty);
  });

  // ── Update ─────────────────────────────────────────────────────────────────

  test('update success: PUT, set remote_updated_at + synced, delete op',
      () async {
    await seedCategory('local-3', fireflyId: '10');
    await seedOp(
      'op-4',
      entityType: 'categories',
      entityId: 'local-3',
      action: OpAction.update,
      payload: jsonEncode({
        'type': 'categories',
        'attributes': {'name': 'Renamed'},
      }),
    );

    final pusher = buildPusher(
      handler: (request) async {
        expect(request.method, 'PUT');
        expect(request.url.path, '/api/v1/categories/10');
        return resourceResponse(
          'categories',
          '10',
          updatedAt: '2026-10-13T09:00:00Z',
        );
      },
    );

    final result = await pusher.pushBatch();

    expect(result.valueOrNull, PushOutcome.allOk);
    final row = (await db.query('categories', where: 'id = ?',
        whereArgs: ['local-3'])).single;
    expect(row['sync_status'], 'synced');
    expect(row['remote_updated_at'], isNotNull);
    expect(await db.query('op_log'), isEmpty);
  });

  test('update 404 drops the local row + its ops (deleted on the website, R41)',
      () async {
    await seedCategory('local-gone', fireflyId: '404');
    await seedOp(
      'op-gone',
      entityType: 'categories',
      entityId: 'local-gone',
      action: OpAction.update,
      payload: jsonEncode({
        'type': 'categories',
        'attributes': {'name': 'Renamed'},
      }),
    );

    final pusher = buildPusher(
      handler: (_) async => http.Response('{"message":"Not found"}', 404),
    );

    final result = await pusher.pushBatch();

    // Not a failure: the op is resolved, so the batch continues and the queue
    // is not wedged on a permanent 404.
    expect(result.valueOrNull, PushOutcome.allOk);
    expect(await db.query('categories'), isEmpty);
    expect(await db.query('op_log'), isEmpty);
  });

  test('update with firefly_id null falls back to create (POST)',
      () async {
    await seedCategory('local-4');
    await seedOp(
      'op-5',
      entityType: 'categories',
      entityId: 'local-4',
      action: OpAction.update,
      payload: jsonEncode({
        'type': 'categories',
        'attributes': {'name': 'Edited'},
      }),
    );

    final pusher = buildPusher(
      handler: (request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/categories');
        return resourceResponse('categories', '77');
      },
    );

    final result = await pusher.pushBatch();

    expect(result.valueOrNull, PushOutcome.allOk);
    final row = (await db.query('categories', where: 'id = ?',
        whereArgs: ['local-4'])).single;
    expect(row['firefly_id'], '77');
    expect(row['sync_status'], 'synced');
  });

  // ── Delete ─────────────────────────────────────────────────────────────────

  test('delete with firefly_id: DELETE, hard-delete row, delete op', () async {
    await seedCategory('local-5', fireflyId: '55');
    await seedOp(
      'op-6',
      entityType: 'categories',
      entityId: 'local-5',
      action: OpAction.delete,
    );

    final pusher = buildPusher(
      handler: (request) async {
        expect(request.method, 'DELETE');
        expect(request.url.path, '/api/v1/categories/55');
        return http.Response('', 204);
      },
    );

    final result = await pusher.pushBatch();

    expect(result.valueOrNull, PushOutcome.allOk);
    expect(await db.query('categories', where: 'id = ?',
        whereArgs: ['local-5']), isEmpty);
    expect(await db.query('op_log'), isEmpty);
  });

  test('delete 404 still hard-deletes + acks (server already gone)', () async {
    await seedCategory('local-6', fireflyId: '66');
    await seedOp(
      'op-7',
      entityType: 'categories',
      entityId: 'local-6',
      action: OpAction.delete,
    );

    final pusher = buildPusher(handler: (_) async => http.Response('', 404));

    final result = await pusher.pushBatch();

    expect(result.valueOrNull, PushOutcome.allOk);
    expect(await db.query('categories', where: 'id = ?',
        whereArgs: ['local-6']), isEmpty);
    expect(await db.query('op_log'), isEmpty);
  });

  test('delete of a local-only row (firefly_id null) skips HTTP entirely',
      () async {
    await seedCategory('local-7');
    await seedOp(
      'op-8',
      entityType: 'categories',
      entityId: 'local-7',
      action: OpAction.delete,
    );

    final pusher = buildPusher(handler: (_) async => http.Response('{}', 500));

    final result = await pusher.pushBatch();

    expect(result.valueOrNull, PushOutcome.allOk);
    expect(requests, isEmpty);
    expect(await db.query('categories', where: 'id = ?',
        whereArgs: ['local-7']), isEmpty);
  });

  // ── Failure mid-batch ──────────────────────────────────────────────────────

  test('failure stops the batch: attempts+1, last_error, remaining ops stay',
      () async {
    // Two ops; first fails with 422, second must not be attempted.
    await seedCategory('local-a');
    await seedCategory('local-b');
    await seedOp(
      'op-a',
      entityType: 'categories',
      entityId: 'local-a',
      action: OpAction.create,
      payload: jsonEncode({
        'type': 'categories',
        'attributes': {'name': 'A'},
      }),
    );
    await seedOp(
      'op-b',
      entityType: 'categories',
      entityId: 'local-b',
      action: OpAction.create,
      payload: jsonEncode({
        'type': 'categories',
        'attributes': {'name': 'B'},
      }),
      wallTs: 2000,
      seq: 2,
    );

    final pusher = buildPusher(
      handler: (_) async => http.Response(
        jsonEncode({'message': 'The given data was invalid.'}),
        422,
      ),
    );

    final result = await pusher.pushBatch();

    expect(result.valueOrNull, PushOutcome.stopped);
    // Only one HTTP call — the second op was never sent.
    expect(requests, hasLength(1));

    final ops = await db.query('op_log', orderBy: 'seq ASC');
    expect(ops, hasLength(2));
    expect(ops.first['op_id'], 'op-a');
    expect(ops.first['attempts'], 1);
    expect(ops.first['last_error'], contains('validation.server'));
    // The second op is untouched.
    expect(ops.last['op_id'], 'op-b');
    expect(ops.last['attempts'], 0);
    expect(ops.last['last_error'], isNull);
  });

  // ── URL mapping ────────────────────────────────────────────────────────────

  test('underscore entity_type maps to hyphenated path (piggy-banks)',
      () async {
    // piggy_banks table exists in the schema; seed a minimal row.
    await db.insert('piggy_banks', {
      'id': 'p1',
      'name': 'Piggy',
      'target_amount': '100',
      'account_id': null,
      'updated_at': 1000,
      'sync_status': 'pending',
      'seq': 1,
    });
    await seedOp(
      'op-p',
      entityType: 'piggy_banks',
      entityId: 'p1',
      action: OpAction.create,
      payload: jsonEncode({
        'type': 'piggy_banks',
        'attributes': {'name': 'Piggy'},
      }),
    );

    final pusher = buildPusher(
      handler: (request) async {
        expect(request.url.path, '/api/v1/piggy-banks');
        return resourceResponse('piggy_banks', '3');
      },
    );

    final result = await pusher.pushBatch();
    expect(result.valueOrNull, PushOutcome.allOk);
  });

  test('budget_limits create posts to budgets/{budget_id}/limits', () async {
    await db.insert('budget_limits', {
      'id': 'bl1',
      'budget_id': 'bgt-9',
      'start': '2026-10-01',
      'end': '2026-10-31',
      'amount': '500',
      'updated_at': 1000,
      'sync_status': 'pending',
      'seq': 1,
    });
    await seedOp(
      'op-bl',
      entityType: 'budget_limits',
      entityId: 'bl1',
      action: OpAction.create,
      payload: jsonEncode({
        'type': 'budget_limits',
        'attributes': {'amount': '500'},
      }),
    );

    final pusher = buildPusher(
      handler: (request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/budgets/bgt-9/limits');
        return resourceResponse('budget_limits', '8');
      },
    );

    final result = await pusher.pushBatch();
    expect(result.valueOrNull, PushOutcome.allOk);
  });

  test('budget_limits update PUTs to budgets/{budget_id}/limits/{id}', () async {
    await db.insert('budget_limits', {
      'id': 'bl2',
      'budget_id': 'bgt-9',
      'start': '2026-10-01',
      'end': '2026-10-31',
      'amount': '600',
      'firefly_id': '55',
      'updated_at': 1000,
      'sync_status': 'pending',
      'seq': 1,
    });
    await seedOp(
      'op-bl2',
      entityType: 'budget_limits',
      entityId: 'bl2',
      action: OpAction.update,
      payload: jsonEncode({
        'type': 'budget_limits',
        'attributes': {'amount': '600'},
      }),
    );

    final pusher = buildPusher(
      handler: (request) async {
        expect(request.method, 'PUT');
        expect(request.url.path, '/api/v1/budgets/bgt-9/limits/55');
        return resourceResponse('budget_limits', '55');
      },
    );

    final result = await pusher.pushBatch();
    expect(result.valueOrNull, PushOutcome.allOk);
  });

  // ── Batch ordering ─────────────────────────────────────────────────────────

  test('ops replay in wall_ts order (oldest first)', () async {
    await seedCategory('c1');
    await seedCategory('c2');
    await seedCategory('c3');
    // Insert out of order; the DAO's ORDER BY must sort them.
    await seedOp(
      'op-late',
      entityType: 'categories',
      entityId: 'c3',
      action: OpAction.create,
      payload: jsonEncode({
        'type': 'categories',
        'attributes': {'name': 'C'},
      }),
      wallTs: 3000,
      seq: 3,
    );
    await seedOp(
      'op-early',
      entityType: 'categories',
      entityId: 'c1',
      action: OpAction.create,
      payload: jsonEncode({
        'type': 'categories',
        'attributes': {'name': 'A'},
      }),
    );
    await seedOp(
      'op-mid',
      entityType: 'categories',
      entityId: 'c2',
      action: OpAction.create,
      payload: jsonEncode({
        'type': 'categories',
        'attributes': {'name': 'B'},
      }),
      wallTs: 2000,
      seq: 2,
    );

    final pusher = buildPusher(
      handler: (request) async {
        // Wire body is the flat attributes object (regression R21): the
        // client unwraps the op-log member before sending.
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final name = body['name'] as String;
        return resourceResponse('categories', 'id-$name');
      },
    );

    final result = await pusher.pushBatch();

    expect(result.valueOrNull, PushOutcome.allOk);
    expect(requests, hasLength(3));
    final names = requests
        .map((r) {
          final body = jsonDecode(r.body) as Map<String, dynamic>;
          return body['name']! as String;
        })
        .toList();
    expect(names, ['A', 'B', 'C']);
  });

  // ── Reference resolution (R29) ─────────────────────────────────────────────

  /// Inserts a minimal account row with the given bookkeeping state.
  Future<void> seedAccount(
    String id, {
    String? fireflyId,
    String name = 'Acc',
    String syncStatus = 'synced',
  }) async {
    await db.insert('accounts', {
      'id': id,
      'name': name,
      'type': 'asset',
      'active': 1,
      'firefly_id': fireflyId,
      'updated_at': 1000,
      'sync_status': syncStatus,
      'seq': 1,
    });
  }

  /// Inserts a local transfer leg that references both accounts by local id.
  Future<void> seedLocalTransfer(
    String id, {
    required String sourceId,
    required String destId,
  }) async {
    await db.insert('transactions', {
      'id': id,
      'type': 'transfer',
      'description': 'Parity M2W 001',
      'date': '2026-11-18T00:00:00.000Z',
      'amount': '25',
      'currency_code': 'USD',
      'source_account_id': sourceId,
      'dest_account_id': destId,
      'foreign_amount': '23',
      'foreign_currency_code': 'EUR',
      'reconciled': 0,
      'updated_at': 1000,
      'sync_status': 'pending',
      'seq': 1,
    });
  }

  /// The create payload a phone-side form would enqueue: local ids, verbatim.
  String transferPayload(String sourceId, String destId) => jsonEncode({
    'type': 'transactions',
    'attributes': {
      'transactions': [
        {
          'type': 'transfer',
          'description': 'Parity M2W 001',
          'date': '2026-11-18T00:00:00.000Z',
          'amount': '25',
          'currency_code': 'USD',
          'source_id': sourceId,
          'destination_id': destId,
          'foreign_amount': '23',
          'foreign_currency_code': 'EUR',
        },
      ],
    },
  });

  test('pushes local account ids as Firefly numeric ids', () async {
    await seedAccount('01a1ec0d-local-usd', fireflyId: '200', name: 'USD');
    await seedAccount('01a1eef2-local-eur', fireflyId: '202', name: 'EUR');
    await seedLocalTransfer(
      'txn-1',
      sourceId: '01a1ec0d-local-usd',
      destId: '01a1eef2-local-eur',
    );
    await seedOp(
      'op-1',
      entityType: 'transactions',
      entityId: 'txn-1',
      action: OpAction.create,
      payload: transferPayload('01a1ec0d-local-usd', '01a1eef2-local-eur'),
    );

    final pusher = buildPusher(
      handler: (request) async => resourceResponse('transactions', '3490'),
    );

    final result = await pusher.pushBatch();

    expect(result.valueOrNull, PushOutcome.allOk);
    expect(requests, hasLength(1));
    final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
    final leg = (body['transactions'] as List).single as Map<String, dynamic>;
    // A local UUID here is what the API rejected with
    // "The transactions.0.source_id must be a number."
    expect(leg['source_id'], '200');
    expect(leg['destination_id'], '202');

    // The row is rewritten to the same ids the server stores, so the device
    // and the website agree field for field.
    final rows = await db.query('transactions', where: "id = 'txn-1'");
    expect(rows.single['source_account_id'], '200');
    expect(rows.single['dest_account_id'], '202');
    expect(rows.single['firefly_id'], '3490');
  });

  test('leaves an already numeric reference untouched', () async {
    await seedLocalTransfer('txn-2', sourceId: '202', destId: '200');
    await seedOp(
      'op-2',
      entityType: 'transactions',
      entityId: 'txn-2',
      action: OpAction.update,
      payload: transferPayload('202', '200'),
    );
    await db.update(
      'transactions',
      {'firefly_id': '3400', 'sync_status': 'pending'},
      where: "id = 'txn-2'",
    );

    final pusher = buildPusher(
      handler: (request) async => resourceResponse('transactions', '3400'),
    );

    final result = await pusher.pushBatch();

    expect(result.valueOrNull, PushOutcome.allOk);
    final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
    final leg = (body['transactions'] as List).single as Map<String, dynamic>;
    expect(leg['source_id'], '202');
    expect(leg['destination_id'], '200');
  });

  test('keeps an unpushed reference when the account has no firefly_id',
      () async {
    await seedAccount('01a1ffff-local-gbp', name: 'GBP', syncStatus: 'pending');
    await seedAccount('01a1ec0d-local-usd', fireflyId: '200');
    await seedLocalTransfer(
      'txn-3',
      sourceId: '01a1ffff-local-gbp',
      destId: '01a1ec0d-local-usd',
    );
    await seedOp(
      'op-3',
      entityType: 'transactions',
      entityId: 'txn-3',
      action: OpAction.create,
      payload: transferPayload('01a1ffff-local-gbp', '01a1ec0d-local-usd'),
    );

    final pusher = buildPusher(
      handler: (request) async => resourceResponse('transactions', '3491'),
    );
    await pusher.pushBatch();

    final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
    final leg = (body['transactions'] as List).single as Map<String, dynamic>;
    // Unresolvable: the account create op must be replayed first.
    expect(leg['source_id'], '01a1ffff-local-gbp');
    expect(leg['destination_id'], '200');
  });
}
