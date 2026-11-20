// Live end-to-end convergence test for the sync engine (P3 exit criterion:
// "End-to-end convergence proven on real Firefly III (pinned instance)").
//
// GATED: runs only when FIREFLY_LIVE=1 is set in the environment; otherwise
// every test in this file reports as skipped so the default `flutter test`
// baseline (465 pass) is untouched and no network is required in CI.
//
// Credentials (never hard-coded here, never printed to output):
//   FIREFLY_BASE_URL — defaults to http://127.0.0.1:8080 (pinned dev instance)
//   FIREFLY_PAT      — falls back to FIIII_PAT in
//                      ../infra/firefly/.credentials (CWD = package root)
//
// What it proves, in one cycle, against the real API:
//   1. push: a locally-seeded pending category is created on the server and
//      acked (firefly_id set, sync_status='synced', op_log row acknowledged);
//   2. independent server-side verification: a direct GET of the collection
//      (not the app's pull path) contains the same row with the same id;
//   3. restore-drill parity (P4.4): restoreFromServer() wipes local state and
//      re-downloads the same firefly_id + name.
// Cleanup deletes the server row so repeated runs don't accumulate junk.
//
// Timeout is generous (2 min): the API client retries transport/5xx with
// 1+2+4+8 s backoff, and a cold Firefly container can take a few seconds on
// its first request after idle.

import 'dart:convert';
import 'dart:io';

import 'package:firefly_mobile/core/settings/connection_settings.dart';
import 'package:firefly_mobile/data/api/firefly_api_client.dart';
import 'package:firefly_mobile/data/sync/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/db/app_database_test.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  final live = Platform.environment['FIREFLY_LIVE'] == '1';

  /// Base URL under test; overridable for non-default instances.
  final baseUrl =
      Platform.environment['FIREFLY_BASE_URL'] ?? 'http://127.0.0.1:8080';

  /// Resolves the PAT: env var wins, then the pinned .credentials file.
  /// Never returns or logs the token itself — only used to build the client.
  String resolvePat() {
    final fromEnv = Platform.environment['FIREFLY_PAT'];
    if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
    final file = File('../infra/firefly/.credentials');
    if (!file.existsSync()) {
      fail(
        'FIREFLY_LIVE=1 but no PAT: set FIREFLY_PAT or provide '
        '${file.path}',
      );
    }
    for (final line in file.readAsLinesSync()) {
      if (line.startsWith('FIIII_PAT=')) {
        return line.substring('FIIII_PAT='.length).trim();
      }
    }
    fail('FIIII_PAT not found in ${file.path}');
  }

  test(
    'live: create → sync → server has row → restore parity',
    () async {
      final pat = resolvePat();
      final store = InMemoryConnectionSettingsStore(
        ConnectionSettings(baseUrl: baseUrl, pat: pat),
      );
      final client = FireflyApiClient(settings: store);

      // ---- Pre-flight: instance reachable AND PAT valid -------------------
      // Fail fast with a clear (token-free) message rather than surfacing a
      // retry-exhausted failure from deep inside the sync cycle.
      final about = await client.fetch('about');
      final aboutFailure = about.failureOrNull;
      if (aboutFailure != null) {
        fail(
          'live Firefly pre-flight failed at $baseUrl '
          '(${aboutFailure.code}: ${aboutFailure.message}). '
          'Is the pinned instance up and the PAT valid?',
        );
      }

      final db = await openTestDatabase();
      addTearDown(db.close);

      // Unique name per run so repeated runs don't collide with a leftover.
      final name = 'ffe2e-${DateTime.now().millisecondsSinceEpoch}';
      const localId = 'loc-live-1';

      // ---- Seed one pending category create (same shape the unit tests use)
      await db.insert('categories', {
        'id': localId,
        'name': name,
        'notes': 'live e2e ${DateTime.now().toUtc().toIso8601String()}',
        'firefly_id': null,
        'updated_at': 1000,
        'remote_updated_at': null,
        'sync_status': 'pending',
        'deleted_at': null,
        'seq': 1,
      });
      await db.insert('op_log', {
        'op_id': 'op-live-1',
        'entity_type': 'categories',
        'entity_id': localId,
        'action': 'create',
        'payload': jsonEncode({
          'type': 'categories',
          'attributes': {'name': name},
        }),
        'wall_ts': 1000,
        'device_id': 'dev-live-1',
        'seq': 1,
        'created_at': 1000,
        'attempts': 0,
      });

      // ---- 1. Push+pull through the real engine ----------------------------
      final engine = SyncEngine(db: db, client: client);
      final outcome = await engine.sync();
      expect(
        outcome.ok,
        isTrue,
        reason: 'sync cycle failed: ${outcome.failure?.message}',
      );
      // Engine counts a whole batch per acked batch (see SyncEngine.sync).
      expect(outcome.pushedOps, greaterThan(0));

      // Local bookkeeping: row acked, queue drained.
      final row = (await db.query('categories', where: 'id = ?', whereArgs: [
        localId,
      ]))
          .single;
      expect(row['firefly_id'], isNotNull, reason: 'push did not assign id');
      expect(row['sync_status'], 'synced');
      final queue = await db.query('op_log');
      expect(queue, isEmpty, reason: 'op not acknowledged after clean push');
      final fireflyId = row['firefly_id']! as String;

      // ---- 2. Independent server-side verification (direct fetch, not pull)
      final fetched = await client.fetch('categories/$fireflyId');
      final fetchFailure = fetched.failureOrNull;
      expect(
        fetchFailure,
        isNull,
        reason: 'server fetch of created id failed: $fetchFailure',
      );
      expect(fetched.valueOrNull!.id, fireflyId);
      expect(
        fetched.valueOrNull!.attributes['name'] as String?,
        name,
        reason: 'server-side name mismatch',
      );

      // ---- 3. Restore-drill parity (P4.4: wipe local → re-download) -------
      final restore = await engine.restoreFromServer();
      final restoreFailure = restore.failureOrNull;
      expect(
        restoreFailure,
        isNull,
        reason: 'restore failed: ${restoreFailure?.message}',
      );
      expect(
        restore.valueOrNull!.inserted,
        greaterThanOrEqualTo(1),
        reason: 'restore pulled nothing',
      );
      final restored = (await db.query(
        'categories',
        where: 'firefly_id = ?',
        whereArgs: [fireflyId],
      ))
          .single;
      expect(restored['name'], name, reason: 'restored name mismatch');
      expect(restored['sync_status'], 'synced');
      // The restored row must be fully server-owned: no local-only leftovers.
      final restoredQueue = await db.query('op_log');
      expect(restoredQueue, isEmpty, reason: 'restore left queued ops');

      // ---- Cleanup: remove the server row so runs stay idempotent ---------
      // Best-effort: a failed delete must not fail the test (the assertions
      // above already proved convergence; a leftover category is harmless).
      try {
        await client.delete('categories/$fireflyId');
      } on Object {
        // ignore — documented best-effort
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
    skip: live
        ? false
        : 'set FIREFLY_LIVE=1 (with the pinned instance up) to run live e2e',
  );
}
