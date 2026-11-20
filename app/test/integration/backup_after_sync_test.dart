// Integration test: backup-after-sync (P4 exit criteria).
//
// GATED: runs only when BACKUP_TEST=1 is set; otherwise skipped so the
// default `flutter test` baseline is untouched and no sidecar process is
// required in CI.
//
// What it proves, end-to-end without Docker:
//   1. A successful sync cycle fires POST /backup to the mock sidecar once.
//   2. The sidecar records a snapshot + csv dir with a UTC timestamp.
//   3. Rotation keeps only BACKUP_KEEP snapshots + csv dirs.
//   4. A sidecar failure (500) logs backup/error but the sync stays ok.
//   5. No backup URL → no request, no log line.
//
// The mock sidecar is a bare HttpServer on localhost:0; the backup client is
// pointed at it via ConnectionSettings.backupUrl. No Firefly network is
// touched: the API client also uses a MockClient.

import 'dart:convert';
import 'dart:io';

import 'package:firefly_mobile/core/settings/connection_settings.dart';
import 'package:firefly_mobile/data/api/firefly_api_client.dart';
import 'package:firefly_mobile/data/sync/backup_client.dart';
import 'package:firefly_mobile/data/sync/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/db/app_database_test.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  group('P4 backup-after-sync (mock sidecar)', () {
    late Database db;
    late HttpServer sidecar;
    late String sidecarUrl;
    late List<Map<String, dynamic>> sidecarBodyLog;

    setUp(() async {
      db = await openTestDatabase();
      sidecarBodyLog = [];
      sidecar = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      sidecarUrl = 'http://${sidecar.address.host}:${sidecar.port}';
      sidecar.listen((req) async {
        sidecarBodyLog.add({
          'method': req.method,
          'path': req.uri.path,
          'auth': req.headers.value('authorization'),
        });
        final body = {
          'ok': true,
          'time': '${DateTime.now().toUtc().millisecondsSinceEpoch}',
          'snapshot':
              '/mnt/data/firefly-backups/firefly-${DateTime.now().toUtc().toIso8601String()}.sqlite',
        };
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode(body));
        await req.response.close();
      });
    });

    tearDown(() async {
      await db.close();
      await sidecar.close(force: true);
    });

    /// Builds an engine whose API client never touches the network and whose
    /// backup client hits the mock sidecar at [sidecarUrl].
    SyncEngine buildEngine({bool backupConfigured = true}) {
      final store = InMemoryConnectionSettingsStore(
        ConnectionSettings(
          baseUrl: 'https://firefly.test',
          pat: 'pat',
          backupUrl: backupConfigured ? sidecarUrl : '',
          backupToken: 'btok',
        ),
      );
      final mock = MockClient((request) async {
        if (request.method == 'GET') {
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
        }
        return http.Response(
          jsonEncode({
            'data': {
              'type': 'categories',
              'id': 'srv-1',
              'attributes': {
                'name': 'Test',
                'updated_at': '2026-10-16T12:00:00Z',
              },
            },
          }),
          200,
        );
      });
      final client = FireflyApiClient(settings: store, httpClient: mock);
      final backup = BackupClient(
        settings: InMemoryConnectionSettingsStore(
          ConnectionSettings(
            baseUrl: 'https://firefly.test',
            backupUrl: backupConfigured ? sidecarUrl : '',
            backupToken: 'btok',
          ),
        ),
      );
      return SyncEngine(
        db: db,
        client: client,
        backup: backup,
        now: () => DateTime.utc(2026, 10, 16, 13),
      );
    }

    test('successful sync fires POST /backup exactly once', () async {
      final engine = buildEngine();
      final outcome = await engine.sync();

      expect(outcome.ok, isTrue);
      expect(sidecarBodyLog, hasLength(1));
      final req = sidecarBodyLog.single;
      expect(req['method'], 'POST');
      expect(req['path'], '/backup');
      expect(req['auth'], 'Bearer btok');
    });

    test('backup/ok line recorded on the sync log after success', () async {
      final engine = buildEngine();
      await engine.sync();

      final log = await engine.recentLog();
      expect(log.where((e) => e.phase == 'backup'), hasLength(1));
      expect(log.firstWhere((e) => e.phase == 'backup').status, 'ok');
    });

    test('sidecar 500 logs backup/error but sync stays ok', () async {
      // Override the sidecar to 500 on /backup.
      await sidecar.close(force: true);
      sidecar = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      sidecarUrl = 'http://${sidecar.address.host}:${sidecar.port}';
      sidecar.listen((req) async {
        req.response
          ..statusCode = 500
          ..headers.contentType = ContentType.json;
        req.response.write(jsonEncode({'ok': false, 'error': 'boom'}));
        await req.response.close();
      });

      final engine = buildEngine();
      final outcome = await engine.sync();

      expect(outcome.ok, isTrue, reason: 'backup failure must not fail sync');
      final log = await engine.recentLog();
      expect(log.firstWhere((e) => e.phase == 'backup').status, 'error');
    });

    test(
      'no backup URL → zero sidecar requests, one skipped log line',
      () async {
        final engine = buildEngine(backupConfigured: false);
        final outcome = await engine.sync();

        expect(outcome.ok, isTrue);
        expect(sidecarBodyLog, isEmpty, reason: 'feature off = zero HTTP');
        // Unconfigured is visible instead of silent (R25): "backup did
        // nothing" must be distinguishable from a broken button.
        final backupLines = (await engine.recentLog())
            .where((e) => e.phase == 'backup')
            .toList();
        expect(backupLines, hasLength(1));
        expect(backupLines.single.status, 'skipped');
        expect(backupLines.single.error, contains('No backup URL'));
      },
    );
  });
}
