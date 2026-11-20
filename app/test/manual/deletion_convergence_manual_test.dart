import 'dart:io';

import 'package:firefly_mobile/core/settings/connection_settings.dart';
import 'package:firefly_mobile/data/api/firefly_api_client.dart';
import 'package:firefly_mobile/data/sync/pull_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

/// **Manual** verification harness — not part of the offline suite.
///
/// It proves that a real device database converges to the live Firefly book
/// after a website-side deletion, by running the real `PullEngine.pullAll()`
/// (the code path behind "Get from website") against the configured server.
///
/// Skipped unless `VERIFY_DB` points at a database file, so `flutter test`
/// stays offline:
///
/// ```
/// VERIFY_DB=/tmp/par13/db2/firefly.db flutter test \
///   test/manual/deletion_convergence_manual_test.dart
/// ```
void main() {
  final source = Platform.environment['VERIFY_DB'];
  final tokenFile = Platform.environment['VERIFY_TOKEN_FILE'] ??
      '/home/arcore/Documents/accounts transactions/token.txt';
  final baseUrl =
      Platform.environment['VERIFY_BASE_URL'] ?? 'http://localhost:8080';

  test('a stale device database converges to the live book', () async {
    sqfliteFfiInit();
    final target = '${Directory.systemTemp.path}/verify_phone.db';
    File(source!).copySync(target);
    final token = File(tokenFile).readAsStringSync().trim();

    final db = await databaseFactoryFfi.openDatabase(target);
    try {
      Future<Map<String, Object?>> snapshot() async {
        final accounts = await db.rawQuery(
          'SELECT COUNT(*) AS c FROM accounts WHERE deleted_at IS NULL',
        );
        final legs = await db.rawQuery(
          'SELECT COUNT(*) AS c FROM transactions WHERE deleted_at IS NULL',
        );
        final groups = await db.rawQuery(
          'SELECT COUNT(DISTINCT journal_id) AS c FROM transactions '
          'WHERE deleted_at IS NULL',
        );
        return {
          'accounts': accounts.first['c'],
          'legs': legs.first['c'],
          'groups': groups.first['c'],
        };
      }

      // ignore: avoid_print
      print('before: ${await snapshot()}');

      final client = FireflyApiClient(
        settings: InMemoryConnectionSettingsStore(
          ConnectionSettings(baseUrl: baseUrl, pat: token),
        ),
      );
      final result = await PullEngine(db: db, client: client).pullAll();
      final failure = result.failureOrNull;
      if (failure != null) {
        // ignore: avoid_print
        print('pull failed: ${failure.code} ${failure.message}');
      }
      final stats = result.valueOrNull!;
      for (final entry in stats.entities.entries) {
        // ignore: avoid_print
        print('${entry.key}: ${entry.value}');
      }
      if (stats.hasFailures) {
        for (final entry in stats.failures.entries) {
          // ignore: avoid_print
          print('FAILED ${entry.key}: ${entry.value.code} ${entry.value.message}');
        }
      }

      // ignore: avoid_print
      print('after: ${await snapshot()}');
      final goneAccounts = await db.rawQuery(
        'SELECT firefly_id, name FROM accounts WHERE deleted_at IS NOT NULL '
        'ORDER BY name',
      );
      final goneLegs = await db.rawQuery(
        'SELECT journal_id, description FROM transactions '
        'WHERE deleted_at IS NOT NULL ORDER BY journal_id',
      );
      // ignore: avoid_print
      print('tombstoned accounts: ${goneAccounts.length} $goneAccounts');
      // ignore: avoid_print
      print('tombstoned legs: ${goneLegs.length} $goneLegs');

      expect(failure, isNull, reason: 'the live pull must complete cleanly');
    } finally {
      await db.close();
    }
  },
      skip: source == null
          ? 'set VERIFY_DB to a device database file to run this live check'
          : false);
}
