import 'dart:async';

import 'package:firefly_mobile/core/errors/failure.dart';
import 'package:firefly_mobile/core/settings/connection_settings.dart';
import 'package:firefly_mobile/data/sync/backup_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Unit tests for [BackupClient] (P4.1, DESIGN §8.2).
///
/// Transport contract of the PC backup sidecar trigger. Every request goes
/// through a [MockClient] — no real network, no sidecar process. Covers:
///   * disabled (no backup URL) → Ok+isDisabled, zero HTTP issued
///   * success → POST {url}/backup with Bearer header, report fields parsed
///   * 401 → AuthFailure, 500 → ServerFailure (HTTP status surface)
///   * sidecar ok:false ×4 → ServerFailure with the four distinct messages
///     (snapshot_error / csv_error / csv_failed list / bare fallback)
///   * http.ClientException → NetworkFailure (connection refused/DNS)
///   * timeout → NetworkFailure (hung PC bounded by the injectable timeout)
void main() {
  /// Builds a client over an in-memory store holding [settings]; [handler]
  /// serves every outbound request.
  BackupClient build(
    ConnectionSettings settings,
    Future<http.Response> Function(http.Request request) handler, {
    Duration timeout = const Duration(seconds: 2),
  }) {
    return BackupClient(
      settings: InMemoryConnectionSettingsStore(settings),
      httpClient: MockClient(handler),
      timeout: timeout,
    );
  }

  const configured = ConnectionSettings(
    baseUrl: 'https://firefly.test',
    backupUrl: 'http://pc:8095',
    backupToken: 'sidecar-tok',
  );

  test('no backup URL → Ok disabled, no HTTP issued', () async {
    var calls = 0;
    final client = build(
      const ConnectionSettings(baseUrl: 'https://firefly.test'),
      (_) async {
        calls++;
        return http.Response('{}', 200);
      },
    );

    final result = await client.trigger();

    expect(result.failureOrNull, isNull);
    final report = result.valueOrNull!;
    expect(report.isDisabled, isTrue);
    expect(calls, 0, reason: 'feature off must never hit the network');
  });

  test('success → POST /backup with Bearer token, report parsed', () async {
    final seen = <http.Request>[];
    final client = build(configured, (request) async {
      seen.add(request);
      return http.Response(
        '{"ok":true,"time":"20261019T103129Z",'
        '"snapshot":"/mnt/data/firefly-backups/firefly-20261019T103129Z.sqlite"}',
        200,
      );
    });

    final result = await client.trigger();

    expect(result.failureOrNull, isNull);
    final report = result.valueOrNull!;
    expect(report.isDisabled, isFalse);
    expect(report.time, '20261019T103129Z');
    expect(
      report.snapshot,
      '/mnt/data/firefly-backups/firefly-20261019T103129Z.sqlite',
    );

    final req = seen.single;
    expect(req.method, 'POST');
    expect(req.url.toString(), 'http://pc:8095/backup');
    expect(req.headers['Authorization'], 'Bearer sidecar-tok');
    expect(req.headers['Content-Type'], contains('application/json'));
    expect(req.body, '{}');
  });

  test('HTTP 401 → AuthFailure with the status in the message', () async {
    final client = build(
      configured,
      (_) async => http.Response('{"message":"Unauthenticated."}', 401),
    );

    final result = await client.trigger();

    final failure = result.failureOrNull;
    expect(failure, isA<AuthFailure>());
    expect(failure!.message, contains('HTTP 401'));
  });

  test('HTTP 500 → ServerFailure with the status in the message', () async {
    final client = build(
      configured,
      (_) async => http.Response('boom', 500),
    );

    final result = await client.trigger();

    final failure = result.failureOrNull;
    expect(failure, isA<ServerFailure>());
    expect(failure!.message, contains('HTTP 500'));
  });

  test('ok:false + snapshot_error → ServerFailure names the '
      'snapshot cause', () async {
    final client = build(
      configured,
      (_) async => http.Response(
        '{"ok":false,"snapshot_error":"disk full"}',
        200,
      ),
    );

    final result = await client.trigger();

    final failure = result.failureOrNull;
    expect(failure, isA<ServerFailure>());
    expect(failure!.message, 'Backup failed on PC: disk full');
  });

  test('ok:false + csv_error → ServerFailure names the CSV cause', () async {
    final client = build(
      configured,
      (_) async => http.Response(
        '{"ok":false,"csv_error":"endpoint 404"}',
        200,
      ),
    );

    final result = await client.trigger();

    final failure = result.failureOrNull;
    expect(failure, isA<ServerFailure>());
    expect(
      failure!.message,
      'Backup CSV export failed on PC: endpoint 404',
    );
  });

  test('ok:false + csv_failed list → ServerFailure counts the '
      'failures', () async {
    final client = build(
      configured,
      (_) async => http.Response(
        '{"ok":false,"csv_failed":["accounts","tags"]}',
        200,
      ),
    );

    final result = await client.trigger();

    final failure = result.failureOrNull;
    expect(failure, isA<ServerFailure>());
    expect(failure!.message, 'Backup ran on PC but 2 CSV export(s) failed');
  });

  test('ok:false bare → ServerFailure generic fallback message', () async {
    final client = build(
      configured,
      (_) async => http.Response('{"ok":false}', 200),
    );

    final result = await client.trigger();

    final failure = result.failureOrNull;
    expect(failure, isA<ServerFailure>());
    expect(failure!.message, 'Backup reported failure on PC');
  });

  test('connection refused (ClientException) → NetworkFailure', () async {
    final client = build(
      configured,
      (_) async => throw http.ClientException('Connection refused'),
    );

    final result = await client.trigger();

    final failure = result.failureOrNull;
    expect(failure, isA<NetworkFailure>());
    expect(failure!.message, contains('Backup PC unreachable'));
    expect(failure.message, contains('Connection refused'));
  });

  test('hung PC → timeout becomes NetworkFailure within the bound', () async {
    // Never-completing response: only the client's timeout can settle it.
    final client = build(
      configured,
      (_) => Completer<http.Response>().future,
      timeout: const Duration(milliseconds: 100),
    );

    final result = await client.trigger();

    final failure = result.failureOrNull;
    expect(failure, isA<NetworkFailure>());
    expect(failure!.message, contains('did not answer within'));
    expect(failure.message, contains('http://pc:8095'));
  });
}
