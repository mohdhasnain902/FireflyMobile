import 'dart:async';
import 'dart:convert';

import 'package:firefly_mobile/core/settings/connection_probe.dart';
import 'package:firefly_mobile/core/settings/connection_settings.dart';
import 'package:firefly_mobile/data/api/firefly_api_client.dart';
import 'package:firefly_mobile/data/sync/sync_controller.dart';
import 'package:firefly_mobile/data/sync/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../db/app_database_test.dart';

/// Unit tests for [SyncController] (P3.2/P3.6 gate + coalescing).
///
/// The real [SyncEngine] runs over an in-memory database and a [MockClient]
/// (the `sync_engine_test.dart` harness); only the three controller seams —
/// `engine`, `isConfigured`, `probe` — are injected. Covers:
///   * gate skips (not configured / unreachable / unauthorized / wrong URL)
///     never build the engine and never issue a request
///   * probe ok → cycle runs to an ok outcome
///   * two concurrent runNow() calls coalesce into ONE cycle
///   * a finished cycle allows the next runNow() to run again
///   * restore: gate skip → Err with `sync.skipped.<reason>`; busy while a
///     cycle runs; busy flag observable to the UI
void main() {
  setUpAll(sqfliteFfiInit);

  late Database db;
  late List<http.Request> requests;
  late int engineBuilds;

  /// Empty-queue, empty-server mock: GET → empty collection, else → 200.
  SyncEngine buildEngine() {
    final store = InMemoryConnectionSettingsStore(
      const ConnectionSettings(baseUrl: 'https://firefly.test', pat: 'tok'),
    );
    final mock = MockClient((request) async {
      requests.add(request);
      return http.Response(
        jsonEncode({
          'data': <dynamic>[],
          'meta': {
            'pagination': {
              'total': 0,
              'count': 0,
              'per_page': 100,
              'current_page': 1,
              'total_pages': 1,
              'links': <String, dynamic>{},
            },
          },
        }),
        200,
      );
    });
    final client = FireflyApiClient(settings: store, httpClient: mock);
    return SyncEngine(db: db, client: client);
  }

  /// Controller with the default seams: configured + probe-ok + real engine.
  /// [isConfigured]/[probe] can be swapped per test.
  SyncController buildController({
    Future<bool> Function()? isConfigured,
    Future<ProbeResult> Function()? probe,
  }) {
    return SyncController(
      engine: () async {
        engineBuilds++;
        return buildEngine();
      },
      isConfigured: isConfigured ?? () async => true,
      probe: probe ?? () async => const ProbeResult(ProbeStatus.ok),
    );
  }

  setUp(() async {
    db = await openTestDatabase();
    requests = [];
    engineBuilds = 0;
  });

  tearDown(() => db.close());

  group('gate skips (no engine, no request)', () {
    test('not configured → skips without even probing', () async {
      var probes = 0;
      final controller = buildController(
        isConfigured: () async => false,
        probe: () async {
          probes++;
          return const ProbeResult(ProbeStatus.ok);
        },
      );

      final attempt = await controller.runNow();

      expect(attempt.ran, isFalse);
      expect(attempt.skipped, SyncSkipReason.notConfigured);
      expect(attempt.skipped!.message, isNotEmpty);
      expect(probes, 0, reason: 'probe must not run unconfigured');
      expect(engineBuilds, 0);
      expect(requests, isEmpty);
    });

    test('probe unreachable → skips with the unreachable message', () async {
      final controller = buildController(
        probe: () async =>
            const ProbeResult(ProbeStatus.unreachable, detail: 'timeout'),
      );

      final attempt = await controller.runNow();

      expect(attempt.skipped, SyncSkipReason.unreachable);
      expect(attempt.skipped!.message, contains('unreachable'));
      expect(engineBuilds, 0);
      expect(requests, isEmpty);
    });

    test('probe 401 → skips with unauthorized', () async {
      final controller = buildController(
        probe: () async => const ProbeResult(ProbeStatus.unauthorized),
      );

      final attempt = await controller.runNow();

      expect(attempt.skipped, SyncSkipReason.unauthorized);
      expect(engineBuilds, 0);
      expect(requests, isEmpty);
    });

    test('probe unexpectedStatus → skips with wrongEndpoint', () async {
      final controller = buildController(
        probe: () async =>
            const ProbeResult(ProbeStatus.unexpectedStatus, statusCode: 404),
      );

      final attempt = await controller.runNow();

      expect(attempt.skipped, SyncSkipReason.wrongEndpoint);
      expect(engineBuilds, 0);
      expect(requests, isEmpty);
    });
  });

  test('probe ok → cycle runs, outcome ok, requests issued', () async {
    final controller = buildController();

    final attempt = await controller.runNow();

    expect(attempt.ran, isTrue);
    expect(attempt.skipped, isNull);
    expect(attempt.ok, isTrue);
    expect(attempt.outcome!.pushedOps, 0, reason: 'empty queue');
    expect(engineBuilds, 1);
    expect(requests, isNotEmpty, reason: 'pull issued GETs');
    expect(controller.busy, isFalse, reason: 'lock released after the cycle');
  });

  test('two concurrent runNow() calls coalesce into ONE cycle', () async {
    final gate = Completer<void>();
    final controller = buildController(
      probe: () async {
        await gate.future;
        return const ProbeResult(ProbeStatus.ok);
      },
    );

    // Both calls arrive before the gate opens: the second must join.
    final first = controller.runNow();
    final second = controller.runNow();
    expect(controller.busy, isTrue);

    gate.complete();
    final a = await first;
    final b = await second;

    expect(a.ran, isTrue);
    expect(identical(a, b), isTrue, reason: 'joiner gets the same attempt');
    expect(engineBuilds, 1, reason: 'one cycle total');
    // One cycle's pull GETs only — a second cycle would have doubled them.
    final afterFirst = requests.length;
    expect(afterFirst, greaterThan(0));

    // Post-conditions: lock released, next call runs a fresh cycle.
    expect(controller.busy, isFalse);
    await controller.runNow();
    expect(engineBuilds, 2);
    expect(requests.length, afterFirst * 2);
  });

  group('restore()', () {
    test('gate skip → Err with sync.skipped.<reason>, no requests', () async {
      final controller = buildController(
        probe: () async =>
            const ProbeResult(ProbeStatus.unreachable, detail: 'down'),
      );

      final result = await controller.restore();

      expect(result.isOk, isFalse);
      expect(result.failureOrNull!.code, 'sync.skipped.unreachable');
      expect(result.failureOrNull!.message, contains('unreachable'));
      expect(engineBuilds, 0);
      expect(requests, isEmpty);
    });

    test('busy while a cycle runs → immediate Err, no second probe', () async {
      final gate = Completer<void>();
      var probes = 0;
      final controller = buildController(
        probe: () async {
          probes++;
          await gate.future;
          return const ProbeResult(ProbeStatus.ok);
        },
      );

      final cycle = controller.runNow();
      // Give runNow() a microtask to reach the (blocked) probe.
      await Future<void>.delayed(Duration.zero);
      expect(controller.busy, isTrue);

      final restore = await controller.restore();
      expect(restore.isOk, isFalse);
      expect(restore.failureOrNull!.code, 'sync.skipped.busy');
      expect(probes, 1, reason: 'restore did not probe while busy');
      expect(controller.busy, isTrue, reason: 'cycle still holds the lock');

      gate.complete();
      final attempt = await cycle;
      expect(attempt.ran, isTrue);
      expect(controller.busy, isFalse);
    });
  });
}
