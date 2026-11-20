
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firefly_mobile/core/errors/failure.dart';
import 'package:firefly_mobile/core/settings/connection_settings.dart';
import 'package:firefly_mobile/core/utils/result.dart';
import 'package:firefly_mobile/domain/entities/json_api.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

/// Layer between the sync engine and Firefly III's HTTP API (P3.1, DESIGN §7).
///
/// Responsibilities:
///
/// * **Addressing** — every call is built as `{baseUrl}/api/v1/{path}` from the
///   current [ConnectionSettingsStore] (base URL) with a `Bearer` PAT header.
/// * **Wire shape** — responses are JSON:API documents wrapped in `data`
///   ([jsonApiData]/[jsonApiCollection]); request bodies are the *unwrapped*
///   member (`{type, attributes}`), which is what Firefly's request
///   FormRequest contracts expect (verified against the pinned 6.7.9
///   instance: a 422 envelope probe, plus the request fixtures in the tests).
/// * **Error taxonomy** — every non-2xx and every transport failure becomes a
///   typed [Failure] returned inside a [Result]; this class never throws for
///   server or network conditions.
/// * **Retry** — retryable failures (transport + 5xx) are re-sent with
///   exponential backoff 1 s / 2 s / 4 s / 8 s, max 5 attempts total
///   (DESIGN §7.1). Auth/validation/conflict/not-found are *not* retried:
///   they will not succeed on a second try within the same sync cycle.
///
/// The sync engine (P3.2+) maps entity types onto endpoint paths itself —
/// this client stays path-based and entity-agnostic (`list('categories')`,
/// `update('categories/3', member)`).

/// Backoff schedule for a retryable failure (DESIGN §7.1).
const List<Duration> apiRetryDelays = [
  Duration(seconds: 1),
  Duration(seconds: 2),
  Duration(seconds: 4),
  Duration(seconds: 8),
];

/// Total attempts per request = initial try + `apiRetryDelays.length` retries.
int get apiMaxAttempts => apiRetryDelays.length + 1;

/// Injectable sleep used by the retry loop so tests never wait in real time.
typedef ApiDelay = Future<void> Function(Duration duration);

/// One JSON:API member resource as returned under a document's `data`.
///
/// Keeps the raw [member] map because the entity models (DESIGN §3) consume
/// exactly that shape (`Tag.fromJsonApi(member, …)`); [id], [type] and
/// [attributes] are convenience views over it.
@immutable
class ApiResource {
  /// Builds a resource from one wire member object.
  const new({
    required this.member,
    required this.id,
    required this.type,
    required this.attributes,
  });

  /// Rebuilds from a parsed wire member (`{type, id, attributes}`).
  ///
  /// Firefly always sends an id for stored resources; an id-less member is
  /// malformed and surfaces one level up as a parse failure, so the empty
  /// fallbacks here never leak into the sync engine.
  factory fromMember(Map<String, dynamic> member) => ApiResource(
    member: member,
    id: jsonApiId(member) ?? '',
    type: member['type'] is String ? member['type'] as String : '',
    attributes: jsonApiAttributes(member),
  );

  /// The complete wire member, ready for an entity's `fromJsonApi`.
  final Map<String, dynamic> member;

  /// Server-assigned resource id (stringified; Firefly sends strings).
  final String id;

  /// JSON:API type, e.g. `categories`.
  final String type;

  /// The resource's attribute map (never null; empty when absent).
  final Map<String, dynamic> attributes;

  /// `updated_at` from attributes, UTC, or null when absent/unparseable.
  DateTime? get updatedAt => jsonApiUpdatedAt(attributes);
}

/// One page of a JSON:API collection, including its pagination block.
@immutable
class ApiCollection {
  /// Builds a collection page.
  const new({required this.resources, required this.pagination});

  /// The page's member resources, in server order.
  final List<ApiResource> resources;

  /// `meta.pagination` of the document (1-based page numbers).
  final PaginationMeta pagination;
}

/// The `meta.pagination` block of a JSON:API collection document.
@immutable
class PaginationMeta {
  /// Builds a pagination snapshot.
  const new({
    required this.total,
    required this.totalPages,
    required this.currentPage,
    required this.perPage,
  });

  /// Reads pagination from a parsed document, tolerating a missing block
  /// (a list response may omit `meta` on a single empty page).
  factory fromDocument(Map<String, dynamic> document) {
    final meta = document['meta'];
    final pagination = meta is Map ? meta['pagination'] : null;
    if (pagination is! Map) {
      return const PaginationMeta(
        total: 0,
        totalPages: 1,
        currentPage: 1,
        perPage: 100,
      );
    }
    int read(String key, int orElse) {
      final raw = pagination[key];
      if (raw is int) return raw;
      if (raw is num) return raw.toInt();
      return orElse;
    }

    return PaginationMeta(
      total: read('total', 0),
      totalPages: read('total_pages', 1),
      currentPage: read('current_page', 1),
      perPage: read('per_page', 100),
    );
  }

  /// Total rows on the server across all pages.
  final int total;

  /// Total number of pages at the requested page size.
  final int totalPages;

  /// The page this response represents (1-based).
  final int currentPage;

  /// Rows per page the server actually applied.
  final int perPage;
}

/// Typed HTTP client for Firefly III's `/api/v1` JSON:API (P3.1).
class FireflyApiClient {
  /// Creates a client.
  ///
  /// [_settings] is read fresh on every request so a URL/token change on the
  /// settings screen takes effect without rebuilding the client.
  /// [httpClient] and [delay] are injectable for tests; [_timeout] applies to
  /// each individual attempt (DESIGN has no hard timeout budget — 30 s is a
  /// generous ceiling for a 100-row page over a phone hotspot).
  new({
    required this._settings,
    http.Client? httpClient,
    ApiDelay? delay,
    this._timeout = const Duration(seconds: 30),
  }) : _client = httpClient ?? http.Client(),
       _ownsClient = httpClient == null,
       _delay = delay ?? _realDelay;

  final ConnectionSettingsStore _settings;
  final http.Client _client;
  final bool _ownsClient;
  final ApiDelay _delay;
  final Duration _timeout;

  static Future<void> _realDelay(Duration duration) =>
      Future<void>.delayed(duration);

  /// Releases the underlying HTTP client when this instance owns it.
  ///
  /// Callers that injected their own `httpClient` do not need this.
  void close() {
    if (_ownsClient) _client.close();
  }

  /// Lists a collection: `GET /api/v1/{path}?page={page}&limit={limit}`.
  ///
  /// [path] is relative to `/api/v1` and may contain sub-segments
  /// (`budgets/3/limits`). Page size defaults to the 100 the pull algorithm
  /// assumes (DESIGN §7.2).
  Future<Result<ApiCollection>> list(
    String path, {
    int page = 1,
    int limit = 100,
  }) async {
    final result = await _withRetry(
      () => _send('GET', path, query: {'page': '$page', 'limit': '$limit'}),
    );
    return result.fold<Result<ApiCollection>>(
      _parseCollection,
      Err<ApiCollection>.new,
    );
  }

  /// Fetches one resource: `GET /api/v1/{path}` (e.g. `categories/3`).
  Future<Result<ApiResource>> fetch(String path) async {
    final result = await _withRetry(() => _send('GET', path));
    return result.fold<Result<ApiResource>>(
      _parseResource,
      Err<ApiResource>.new,
    );
  }

  /// Creates a resource: `POST /api/v1/{path}` with a flat attributes body.
  ///
  /// [member] keeps the app-wide JSON:API shape `{type, attributes}`, but
  /// Firefly's *request* validators accept only the flat attributes object:
  /// a member body is rejected with 422 `{"name": ["The name field is
  /// required."]}` (verified live 2026-10-21). The body sent on the wire is
  /// therefore `member['attributes']` (see [_requestBody]); responses stay
  /// wrapped under `data` and are parsed as such. On success the parsed
  /// server representation is returned so the caller can adopt the assigned
  /// id.
  Future<Result<ApiResource>> create(
    String path,
    Map<String, dynamic> member,
  ) async {
    final result = await _withRetry(
      () => _send('POST', path, body: _requestBody(member)),
    );
    return result.fold<Result<ApiResource>>(
      _parseResource,
      Err<ApiResource>.new,
    );
  }

  /// Updates a resource: `PUT /api/v1/{path}` (e.g. `categories/3`).
  ///
  /// Same body contract as [create] (flat attributes on the wire, member
  /// accepted from callers). Returns the server's new representation.
  Future<Result<ApiResource>> update(
    String path,
    Map<String, dynamic> member,
  ) async {
    final result = await _withRetry(
      () => _send('PUT', path, body: _requestBody(member)),
    );
    return result.fold<Result<ApiResource>>(
      _parseResource,
      Err<ApiResource>.new,
    );
  }

  /// Deletes a resource: `DELETE /api/v1/{path}` (204 on success).
  ///
  /// Returns `Ok(true)`; there is no body to surface.
  Future<Result<bool>> delete(String path) async {
    final result = await _withRetry(() => _send('DELETE', path));
    return result.fold<Result<bool>>((_) => const Ok(true), Err<bool>.new);
  }

  // -------------------------------------------------------------------------
  // Transport
  // -------------------------------------------------------------------------

  /// Runs [attempt] and re-sends it while the failure is retryable,
  /// sleeping `apiRetryDelays[i]` between attempt i and i+1.
  Future<Result<http.Response>> _withRetry(
    Future<Result<http.Response>> Function() attempt,
  ) async {
    for (var i = 0;; i++) {
      final result = await attempt();
      final failure = result.failureOrNull;
      if (failure == null) return result;
      if (!_isRetryable(failure) || i >= apiRetryDelays.length) {
        return Err(failure);
      }
      await _delay(apiRetryDelays[i]);
    }
  }

  /// Transport-level failures and 5xx are worth re-sending; everything else
  /// (auth, validation, conflict, not-found, malformed body) is deterministic
  /// for the lifetime of one sync cycle.
  static bool _isRetryable(Failure failure) =>
      failure is NetworkFailure || failure is ServerFailure;

  /// Wire body for create/update: Firefly request validators take the flat
  /// attributes object (`{"name": ...}`), not the JSON:API member — so a
  /// member carrying `attributes` is unwrapped here and callers keep the
  /// app-wide `{type, attributes}` contract. A body without an `attributes`
  /// map passes through unchanged (already-flat payloads stay flat).
  static Map<String, dynamic> _requestBody(Map<String, dynamic> member) {
    final attributes = member['attributes'];
    if (attributes is Map) return Map<String, dynamic>.from(attributes);
    return member;
  }

  /// One HTTP attempt. Non-2xx becomes an [Err] with the matching [Failure];
  /// 2xx returns the raw response for the caller to parse.
  Future<Result<http.Response>> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    final settings = await _settings.read();
    if (!settings.isConfigured) {
      return const Err(
        ValidationFailure(
          'Firefly URL is not configured yet.',
          code: 'sync.not_configured',
        ),
      );
    }
    var uri = Uri.parse('${settings.baseUrl}/api/v1/$path');
    if (query != null) uri = uri.replace(queryParameters: query);

    final request = http.Request(method, uri);
    // No PAT header when unset — the server then answers 401, which is a
    // truthful and cheap way to surface "not signed in" (same rule the
    // connection probe applies).
    if (settings.pat != null && settings.pat!.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer ${settings.pat}';
    }
    request.headers['Accept'] = 'application/vnd.api+json';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.bodyBytes = utf8.encode(jsonEncode(body));
    }

    try {
      final streamed = await _client.send(request).timeout(_timeout);
      final response = await http.Response.fromStream(streamed);
      return _interpret(response);
    } on TimeoutException {
      return Err(
        NetworkFailure(
          'Firefly did not answer within ${_timeout.inSeconds}s.',
          code: 'network.timeout',
        ),
      );
    } on SocketException catch (e) {
      return Err(
        NetworkFailure('Cannot reach Firefly: ${e.message}', cause: e),
      );
    } on TlsException catch (e) {
      return Err(
        NetworkFailure('TLS to Firefly failed: ${e.message}', cause: e),
      );
    } on http.ClientException catch (e) {
      return Err(NetworkFailure('HTTP client error: ${e.message}', cause: e));
    }
  }

  /// Maps an HTTP status onto the typed error surface (P3.1 task 3).
  Result<http.Response> _interpret(http.Response response) {
    final status = response.statusCode;
    if (status >= 200 && status < 300) return Ok(response);

    final detail = _errorDetail(response.body);
    final failure = switch (status) {
      401 || 403 => AuthFailure(
        'Firefly rejected the access token (HTTP $status).',
        cause: detail,
      ),
      404 => NotFoundFailure(
        'Firefly has no such resource (HTTP 404).',
        cause: detail,
      ),
      409 => ConflictFailure(
        'Firefly refused the write because of a conflicting state.',
        cause: detail,
      ),
      422 => ValidationFailure(
        detail ?? 'Firefly rejected the payload (HTTP 422).',
        code: 'validation.server',
        cause: detail,
      ),
      >= 500 => ServerFailure(
        'Firefly failed internally (HTTP $status).',
        cause: detail,
      ),
      _ => UnknownFailure('Unexpected HTTP status $status.', cause: detail),
    };
    return Err(failure);
  }

  /// Extracts a human-readable message from a Firefly error body.
  ///
  /// Firefly returns `{"message": "…"}` and, for 422, additionally
  /// `{"errors": {"field": ["…"]}}`; the flat message is preferred and the
  /// first validation error is the fallback.
  static String? _errorDetail(String body) {
    if (body.isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      final message = decoded['message'];
      if (message is String && message.isNotEmpty) return message;
      final errors = decoded['errors'];
      if (errors is Map) {
        for (final value in errors.values) {
          if (value is List && value.isNotEmpty && value.first is String) {
            return value.first as String;
          }
        }
      }
      return null;
    } on FormatException {
      // A proxy error page (HTML) — keep a short snippet for logs only.
      return body.length > 200 ? '${body.substring(0, 200)}…' : body;
    }
  }

  // -------------------------------------------------------------------------
  // Parsing (2xx bodies)
  // -------------------------------------------------------------------------

  /// Decodes a 2xx body into a JSON object and hands it to [parse].
  ///
  /// A non-object or undecodable body becomes [UnknownFailure] instead of an
  /// exception reaching the sync engine.
  static Result<T> _parseDocument<T>(
    http.Response response,
    Result<T> Function(Map<String, dynamic> document) parse,
  ) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) return parse(decoded);
      if (decoded is Map) return parse(Map<String, dynamic>.from(decoded));
      return const Err(
        UnknownFailure('Firefly returned a non-object JSON document.'),
      );
    } on FormatException catch (e) {
      return Err(
        UnknownFailure('Firefly returned undecodable JSON.', cause: e),
      );
    }
  }

  /// Parses one collection page (resources + pagination).
  static Result<ApiCollection> _parseCollection(http.Response response) =>
      _parseDocument(response, (document) {
        try {
          final members = jsonApiCollection(document);
          return Ok(
            ApiCollection(
              resources: members.map(ApiResource.fromMember).toList(),
              pagination: PaginationMeta.fromDocument(document),
            ),
          );
        } on FormatException catch (e) {
          return Err(
            UnknownFailure('Malformed JSON:API collection.', cause: e),
          );
        }
      });

  /// Parses a single-resource document (`data` as an object).
  static Result<ApiResource> _parseResource(http.Response response) =>
      _parseDocument(response, (document) {
        try {
          return Ok(ApiResource.fromMember(jsonApiData(document)));
        } on FormatException catch (e) {
          return Err(
            UnknownFailure(
              'Malformed JSON:API resource: ${e.message}',
              cause: e,
            ),
          );
        }
      });
}
