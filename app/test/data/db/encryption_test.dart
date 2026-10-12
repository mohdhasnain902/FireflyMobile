import 'dart:io';

import 'package:firefly_mobile/data/db/database_opener.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(sqfliteFfiInit);

  test(
    'opens with correct key; fails without key',
    () async {
      final dir = await Directory.systemTemp.createTemp('firefly_enc_');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/enc.db';
      const key = 'correct horse battery staple';

      // 1. Create + write with the correct key.
      final db = await openAppDatabase(
        factory: databaseFactoryFfiNoIsolate,
        path: path,
        password: key,
      );
      await db.execute(
        "INSERT INTO device_meta (key, value) VALUES ('probe', 'v1')",
      );
      final rows = await db.rawQuery(
        "SELECT value FROM device_meta WHERE key = 'probe'",
      );
      expect(rows.single['value'], 'v1');
      await db.close();

      // 2. Reopen with the SAME key succeeds.
      final db2 = await openAppDatabase(
        factory: databaseFactoryFfiNoIsolate,
        path: path,
        password: key,
      );
      final rows2 = await db2.rawQuery(
        "SELECT value FROM device_meta WHERE key = 'probe'",
      );
      expect(rows2.single['value'], 'v1');
      await db2.close();

      // 3. Reopen with a WRONG key must fail.
      await expectLater(
        openAppDatabase(
          factory: databaseFactoryFfiNoIsolate,
          path: path,
          password: 'wrong key',
        ),
        throwsA(anything),
      );

      // 4. Reopen with NO key must fail (file is encrypted).
      await expectLater(
        openAppDatabase(
          factory: databaseFactoryFfiNoIsolate,
          path: path,
        ),
        throwsA(anything),
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
