import 'dart:async';

import 'package:firefly_mobile/core/settings/connection_probe.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Unit tests for [probeFirefly] (P2.4), driven through an injected mock
/// `http.Client` so no real network is touched. Covers all four outcomes and
/// the auth-header behaviour.
void main() {
  /// Builds a mock client that answers every request with [status].
  http.Client clientOfStatus(int status) =>
      MockClient((request) async => http.Response('{"ok":true}', status));

  test('2xx is ok', () async {
    final result = await probeFirefly(
      baseUrl: 'https://firefly.example',
      pat: 'tok',
      client: clientOfStatus(200),
    );
    expect(result.status, ProbeStatus.ok);
    expect(result.isOk, isTrue);
  });

  test('401 is unauthorized', () async {
    final result = await probeFirefly(
      baseUrl: 'https://firefly.example',
      pat: 'bad',
      client: clientOfStatus(401),
    );
    expect(result.status, ProbeStatus.unauthorized);
    expect(result.statusCode, 401);
    expect(result.isOk, isFalse);
  });

  test('403 is unauthorized', () async {
    final result = await probeFirefly(
      baseUrl: 'https://firefly.example',
      pat: null,
      client: clientOfStatus(403),
    );
    expect(result.status, ProbeStatus.unauthorized);
  });

  test('500 is unexpectedStatus', () async {
    final result = await probeFirefly(
      baseUrl: 'https://firefly.example',
      pat: 'tok',
      client: clientOfStatus(500),
    );
    expect(result.status, ProbeStatus.unexpectedStatus);
    expect(result.statusCode, 500);
  });

  test('client exception is unreachable', () async {
    final client = MockClient((_) async {
      throw http.ClientException('connection refused');
    });
    final result = await probeFirefly(
      baseUrl: 'https://firefly.example',
      pat: 'tok',
      client: client,
    );
    expect(result.status, ProbeStatus.unreachable);
    expect(result.detail, 'connection refused');
  });

  test('timeout is unreachable', () async {
    final client = MockClient((_) async {
      await Completer<void>().future; // never completes
      return http.Response('', 200);
    });
    final result = await probeFirefly(
      baseUrl: 'https://firefly.example',
      pat: 'tok',
      timeout: const Duration(milliseconds: 10),
      client: client,
    );
    expect(result.status, ProbeStatus.unreachable);
    expect(result.detail, 'timeout');
  });

  test('sends Authorization only when a token is present', () async {
    String? seenAuth;
    final client = MockClient((request) async {
      seenAuth = request.headers['Authorization'];
      return http.Response('{}', 200);
    });

    await probeFirefly(
      baseUrl: 'https://firefly.example',
      pat: 'abc123',
      client: client,
    );
    expect(seenAuth, 'Bearer abc123');

    await probeFirefly(
      baseUrl: 'https://firefly.example',
      pat: null,
      client: client,
    );
    expect(seenAuth, isNull);
  });

  test('hits the /api/v1/about endpoint on the given base URL', () async {
    Uri? seenUri;
    final client = MockClient((request) async {
      seenUri = request.url;
      return http.Response('{}', 200);
    });

    await probeFirefly(
      baseUrl: 'https://firefly.example',
      pat: 'tok',
      client: client,
    );
    expect(seenUri, Uri.parse('https://firefly.example/api/v1/about'));
  });
}
