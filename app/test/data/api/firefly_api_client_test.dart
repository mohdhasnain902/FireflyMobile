import 'dart:async';
import 'dart:io';

import 'package:firefly_mobile/core/errors/failure.dart';
import 'package:firefly_mobile/core/settings/connection_settings.dart';
import 'package:firefly_mobile/data/api/firefly_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Unit tests for [FireflyApiClient] (P3.1), driven through an injected mock
/// [MockClient] so no real network is touched. Covers:
///   * URL building from `ConnectionSettingsStore` (base URL + /api/v1 prefix)
///   * Bearer PAT header (present when set, absent when null/empty)
///   * Unconfigured store → `sync.not_configured` (no request sent)
///   * All status→Failure mappings (401, 404, 409, 422, 5xx)
///   * Retryable failures (network, 5xx) re-sent with 1-2-4-8 s backoff
///   * Non-retryable failures (auth, validation, conflict, not-found) sent once
///   * JSON:API parsing: single resource, collection + pagination, flat
///     POST body (Firefly request contract vs wrapped response contract)
void main() {
  /// ConnectionSettingsStore backed by an [InMemoryConnectionSettingsStore]
  /// seeded with [baseUrl] and [pat].
  ConnectionSettingsStore storeOf({String baseUrl = 'https://firefly.test', String? pat}) =>
      InMemoryConnectionSettingsStore(ConnectionSettings(baseUrl: baseUrl, pat: pat));

  /// Builds a client with a [MockClient] that runs [handler] on each request,
  /// an in-memory delay recorder, and the given settings store.
  ({
    FireflyApiClient client,
    List<Duration> delays,
    List<http.Request> requests,
  }) buildClient({
    required ConnectionSettingsStore settings,
    required Future<http.Response> Function(http.Request request) handler,
  }) {
    final delays = <Duration>[];
    final requests = <http.Request>[];
    final mock = MockClient((request) async {
      requests.add(request);
      return handler(request);
    });
    final client = FireflyApiClient(
      settings: settings,
      httpClient: mock,
      delay: (d) async => delays.add(d),
    );
    return (client: client, delays: delays, requests: requests);
  }

  // ── URL building & auth header ─────────────────────────────────────────────

  test('list() hits {base}/api/v1/{path}?page=N&limit=M', () async {
    final store = storeOf();
    final built = buildClient(
      settings: store,
      handler: (request) async => http.Response(
        '{"data": [], "meta": {"pagination": {"total": 0, "total_pages": 1, "current_page": 1, "per_page": 100}}}',
        200,
      ),
    );
    final client = built.client;
    final requests = built.requests;

    await client.list('categories', page: 3, limit: 50);

    expect(requests.single.url, Uri.parse('https://firefly.test/api/v1/categories?page=3&limit=50'));
  });

  test('fetch() includes the resource id in the path', () async {
    final store = storeOf();
    final built = buildClient(
      settings: store,
      handler: (request) async => http.Response(
        '{"data": {"type": "categories", "id": "7", "attributes": {}}}',
        200,
      ),
    );
    final client = built.client;
    final requests = built.requests;

    await client.fetch('categories/7');

    expect(requests.single.url, Uri.parse('https://firefly.test/api/v1/categories/7'));
  });

  test('sends Authorization: Bearer when PAT is set', () async {
    final store = storeOf(pat: 'secret-token');
    final built = buildClient(
      settings: store,
      handler: (request) async => http.Response(
        '{"data": {"type": "categories", "id": "1", "attributes": {}}}',
        200,
      ),
    );
    final client = built.client;
    final requests = built.requests;

    await client.fetch('categories/1');

    expect(requests.single.headers['Authorization'], 'Bearer secret-token');
  });

  test('omits Authorization header when PAT is null', () async {
    final store = storeOf();
    final built = buildClient(
      settings: store,
      handler: (request) async => http.Response(
        '{"data": {"type": "categories", "id": "1", "attributes": {}}}',
        200,
      ),
    );
    final client = built.client;
    final requests = built.requests;

    await client.fetch('categories/1');

    expect(requests.single.headers.containsKey('Authorization'), isFalse);
  });

  test('omits Authorization header when PAT is empty string', () async {
    final store = storeOf(pat: '');
    final built = buildClient(
      settings: store,
      handler: (request) async => http.Response(
        '{"data": {"type": "categories", "id": "1", "attributes": {}}}',
        200,
      ),
    );
    final client = built.client;
    final requests = built.requests;

    await client.fetch('categories/1');

    expect(requests.single.headers.containsKey('Authorization'), isFalse);
  });

  test('unconfigured store returns sync.not_configured without sending a request', () async {
    final store = storeOf(baseUrl: '');
    final built = buildClient(
      settings: store,
      handler: (request) async => http.Response('{}', 200),
    );
    final client = built.client;
    final requests = built.requests;

    final result = await client.fetch('categories/1');

    expect(result.isOk, isFalse);
    expect(result.failureOrNull, isA<ValidationFailure>());
    expect(result.failureOrNull!.code, 'sync.not_configured');
    expect(requests, isEmpty);
  });

  // ── Status → Failure mapping ───────────────────────────────────────────────

  test('401 maps to AuthFailure and is not retried', () async {
    var callCount = 0;
    final store = storeOf(pat: 'expired');
    final built = buildClient(
      settings: store,
      handler: (request) async {
        callCount++;
        return http.Response('', 401);
      },
    );
    final client = built.client;
    final delays = built.delays;
    final requests = built.requests;

    final result = await client.fetch('categories/1');

    expect(result.isOk, isFalse);
    expect(result.failureOrNull, isA<AuthFailure>());
    expect(callCount, 1);
    expect(delays, isEmpty);
    expect(requests, hasLength(1));
  });

  test('403 maps to AuthFailure and is not retried', () async {
    final store = storeOf(pat: 'no-scope');
    final built = buildClient(
      settings: store,
      handler: (request) async => http.Response('', 403),
    );
    final client = built.client;
    final delays = built.delays;

    final result = await client.fetch('categories/1');

    expect(result.failureOrNull, isA<AuthFailure>());
    expect(delays, isEmpty);
  });

  test('404 maps to NotFoundFailure and is not retried', () async {
    final store = storeOf();
    final built = buildClient(
      settings: store,
      handler: (request) async => http.Response('', 404),
    );
    final client = built.client;
    final delays = built.delays;

    final result = await client.fetch('categories/999');

    expect(result.failureOrNull, isA<NotFoundFailure>());
    expect(delays, isEmpty);
  });

  test('409 maps to ConflictFailure and is not retried', () async {
    final store = storeOf();
    final built = buildClient(
      settings: store,
      handler: (request) async => http.Response(
        '{"message": "Resource already exists."}',
        409,
      ),
    );
    final client = built.client;
    final delays = built.delays;

    final result = await client.create('categories', {
      'type': 'categories',
      'attributes': {'name': 'Duplicate'},
    });

    expect(result.failureOrNull, isA<ConflictFailure>());
    expect(delays, isEmpty);
  });

  test('422 maps to ValidationFailure carrying the server message', () async {
    final store = storeOf();
    final built = buildClient(
      settings: store,
      handler: (request) async => http.Response(
        '{"message": "Validation failed", "errors": {"name": ["The name field is required."]}}',
        422,
      ),
    );
    final client = built.client;
    final delays = built.delays;

    final result = await client.create('categories', {
      'type': 'categories',
      'attributes': <String, dynamic>{},
    });

    expect(result.failureOrNull, isA<ValidationFailure>());
    // Preferred: the flat "message" field.
    expect(result.failureOrNull!.message, 'Validation failed');
    expect(delays, isEmpty);
  });

  test('422 without a "message" field falls back to the first error entry', () async {
    final store = storeOf();
    final built = buildClient(
      settings: store,
      handler: (request) async => http.Response(
        '{"errors": {"amount": ["The amount must be a number."]}}',
        422,
      ),
    );
    final client = built.client;

    final result = await client.create('transactions', {
      'type': 'transactions',
      'attributes': <String, dynamic>{},
    });

    expect(result.failureOrNull, isA<ValidationFailure>());
    expect(result.failureOrNull!.message, 'The amount must be a number.');
  });

  test('500 maps to ServerFailure and is retried with 1-2-4-8 s backoff, max 5 attempts', () async {
    var callCount = 0;
    final store = storeOf();
    final built = buildClient(
      settings: store,
      handler: (request) async {
        callCount++;
        return http.Response('', 500);
      },
    );
    final client = built.client;
    final delays = built.delays;

    final result = await client.fetch('categories/1');

    expect(result.failureOrNull, isA<ServerFailure>());
    expect(callCount, 5);
    expect(delays, [
      const Duration(seconds: 1),
      const Duration(seconds: 2),
      const Duration(seconds: 4),
      const Duration(seconds: 8),
    ]);
  });

  test('SocketException maps to NetworkFailure and is retried', () async {
    var callCount = 0;
    final store = storeOf();
    final mock = MockClient((request) async {
      callCount++;
      throw const SocketException('connection refused');
    });
    final delays = <Duration>[];
    final client = FireflyApiClient(
      settings: store,
      httpClient: mock,
      delay: (d) async => delays.add(d),
    );

    final result = await client.fetch('categories/1');

    expect(result.failureOrNull, isA<NetworkFailure>());
    expect(callCount, 5);
    expect(delays, hasLength(4));
  });

  test('timeout maps to NetworkFailure with code network.timeout', () async {
    final store = storeOf();
    final mock = MockClient((request) async {
      await Completer<void>().future; // never completes
      return http.Response('', 200);
    });
    final client = FireflyApiClient(
      settings: store,
      httpClient: mock,
      delay: (d) async {},
      timeout: const Duration(milliseconds: 10),
    );

    final result = await client.fetch('categories/1');

    expect(result.failureOrNull, isA<NetworkFailure>());
    expect(result.failureOrNull!.code, 'network.timeout');
  });

  test('retry succeeds on 3rd attempt (2 failures then 200)', () async {
    var callCount = 0;
    final store = storeOf();
    final built = buildClient(
      settings: store,
      handler: (request) async {
        callCount++;
        if (callCount < 3) return http.Response('', 500);
        return http.Response(
          '{"data": {"type": "categories", "id": "5", "attributes": {"name": "Recovered"}}}',
          200,
        );
      },
    );
    final client = built.client;
    final delays = built.delays;

    final result = await client.fetch('categories/5');

    expect(result.isOk, isTrue);
    expect(callCount, 3);
    // Two retries before success: 1 s then 2 s.
    expect(delays, [const Duration(seconds: 1), const Duration(seconds: 2)]);
  });

  // ── JSON:API parsing ───────────────────────────────────────────────────────

  test('list() parses a collection page with resources + pagination', () async {
    final store = storeOf();
    final built = buildClient(
      settings: store,
      handler: (request) async => http.Response(
        '{"data": ['
        '{"type": "categories", "id": "1", "attributes": {"name": "Rent", "updated_at": "2026-10-15T08:00:00Z"}},'
        '{"type": "categories", "id": "2", "attributes": {"name": "Utilities", "updated_at": "2026-10-16T10:00:00Z"}}'
        '],'
        '"meta": {"pagination": {"count": 2, "current_page": 1, "per_page": 100, "total": 42, "total_pages": 1}}'
        '}',
        200,
      ),
    );
    final client = built.client;

    final result = await client.list('categories');

    expect(result.isOk, isTrue);
    final collection = result.valueOrNull!;
    expect(collection.resources, hasLength(2));
    expect(collection.resources[0].id, '1');
    expect(collection.resources[0].attributes['name'], 'Rent');
    expect(collection.resources[0].updatedAt, DateTime.utc(2026, 10, 15, 8));
    expect(collection.pagination.total, 42);
    expect(collection.pagination.totalPages, 1);
  });

  test('fetch() parses a single resource document', () async {
    final store = storeOf();
    final built = buildClient(
      settings: store,
      handler: (request) async => http.Response(
        '{"data": {"type": "categories", "id": "42", "attributes": {"name": "Groceries", "updated_at": "2026-10-16T09:30:00Z"}}}',
        200,
      ),
    );
    final client = built.client;

    final result = await client.fetch('categories/42');

    expect(result.isOk, isTrue);
    final resource = result.valueOrNull!;
    expect(resource.id, '42');
    expect(resource.type, 'categories');
    expect(resource.attributes['name'], 'Groceries');
    expect(resource.updatedAt, DateTime.utc(2026, 10, 16, 9, 30));
  });

  test('create() sends flat attributes body (Firefly request contract)', () async {
    final store = storeOf();
    String? seenBody;
    final built = buildClient(
      settings: store,
      handler: (request) async {
        seenBody = request.body;
        return http.Response(
          '{"data": {"type": "categories", "id": "10", "attributes": {"name": "New Category"}}}',
          201,
        );
      },
    );
    final client = built.client;
    final requests = built.requests;

    final result = await client.create('categories', {
      'type': 'categories',
      'attributes': {'name': 'New Category'},
    });

    // Firefly request contract: the *attributes object* sits at the top
    // level. Sending the JSON:API member here is rejected live with 422
    // `{"name": ["The name field is required."]}` (regression R21).
    // Responses still wrap under "data" and are parsed that way.
    expect(seenBody, '{"name":"New Category"}');
    expect(requests.single.method, 'POST');
    expect(requests.single.headers['Content-Type'], 'application/json');
    expect(result.isOk, isTrue);
    expect(result.valueOrNull!.id, '10');
  });

  test('update() sends PUT with flat attributes body and returns the rep', () async {
    final store = storeOf();
    String? seenBody;
    final built = buildClient(
      settings: store,
      handler: (request) async {
        seenBody = request.body;
        return http.Response(
          '{"data": {"type": "categories", "id": "3", "attributes": {"name": "Renamed"}}}',
          200,
        );
      },
    );
    final client = built.client;
    final requests = built.requests;

    final result = await client.update('categories/3', {
      'type': 'categories',
      'attributes': {'name': 'Renamed'},
    });

    expect(requests.single.method, 'PUT');
    expect(seenBody, '{"name":"Renamed"}');
    expect(result.isOk, isTrue);
    expect(result.valueOrNull!.attributes['name'], 'Renamed');
  });

  test('create() passes a plain body through unchanged', () async {
    // Defensive branch: an already-flat body (no `{type, attributes}`) must
    // reach the wire unchanged rather than being dropped or re-wrapped.
    final store = storeOf();
    String? seenBody;
    final built = buildClient(
      settings: store,
      handler: (request) async {
        seenBody = request.body;
        return http.Response(
          '{"data": {"type": "categories", "id": "11", "attributes": {}}}',
          201,
        );
      },
    );

    final result = await built.client.create('categories', {'name': 'Flat'});

    expect(seenBody, '{"name":"Flat"}');
    expect(result.isOk, isTrue);
    expect(result.valueOrNull!.id, '11');
  });

  test('delete() returns Ok(true) on 204', () async {
    final store = storeOf();
    final built = buildClient(
      settings: store,
      handler: (request) async => http.Response('', 204),
    );
    final client = built.client;
    final requests = built.requests;

    final result = await client.delete('categories/3');

    expect(result.isOk, isTrue);
    expect(result.valueOrNull, isTrue);
    expect(requests.single.method, 'DELETE');
  });

  test('undecodable JSON on 200 maps to UnknownFailure', () async {
    final store = storeOf();
    final built = buildClient(
      settings: store,
      handler: (request) async => http.Response('not-json{{', 200),
    );
    final client = built.client;
    final delays = built.delays;

    final result = await client.fetch('categories/1');

    expect(result.failureOrNull, isA<UnknownFailure>());
    // Malformed body is not retryable.
    expect(delays, isEmpty);
  });

  test('a 200 body without a "data" member maps to UnknownFailure', () async {
    final store = storeOf();
    final built = buildClient(
      settings: store,
      handler: (request) async => http.Response('{"unexpected": true}', 200),
    );
    final client = built.client;

    final result = await client.fetch('categories/1');

    expect(result.failureOrNull, isA<UnknownFailure>());
    expect(result.failureOrNull!.message, contains('data'));
  });
}
