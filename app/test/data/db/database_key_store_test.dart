import 'dart:convert';
import 'dart:io';

import 'package:firefly_mobile/data/db/database_key_store.dart';
import 'package:firefly_mobile/data/db/database_opener.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Covers the SQLCipher key lifecycle (DESIGN §4, plan P1 exit criterion 3:
/// "key stored in Keystore; DB opens with key; fails without key").
///
/// `FlutterSecureStorage.setMockInitialValues` swaps in the package's
/// in-memory platform, so `SecureStorageDatabaseKeyStore` runs its real
/// read/write/adopt logic without a device Keystore. The final group ties
/// the criterion together end to end: the key the store mints opens the
/// encrypted database, survives a simulated relaunch, and a wrong key is
/// rejected.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(sqfliteFfiInit);

  group('generateDatabaseKey', () {
    test('encodes 32 random bytes as 44 URL-safe base64 characters', () {
      final key = generateDatabaseKey();

      expect(key, hasLength(44));
      expect(RegExp(r'^[A-Za-z0-9_-]{43}=$').hasMatch(key), isTrue);
      expect(base64Url.decode(key), hasLength(32));
    });

    test('never returns the same value twice', () {
      final keys = <String>{
        for (var i = 0; i < 50; i++) generateDatabaseKey(),
      };

      expect(keys, hasLength(50));
    });
  });

  group('InMemoryDatabaseKeyStore', () {
    test('generates once and reuses the held key', () async {
      final store = InMemoryDatabaseKeyStore();

      expect(store.hasKey, isFalse);
      final first = await store.getOrCreateKey();
      expect(store.hasKey, isTrue);
      expect(await store.getOrCreateKey(), first);
    });

    test('deleteKey discards the key so the next call regenerates', () async {
      final store = InMemoryDatabaseKeyStore();
      final first = await store.getOrCreateKey();

      await store.deleteKey();

      expect(store.hasKey, isFalse);
      expect(await store.getOrCreateKey(), isNot(first));
    });
  });

  group('SecureStorageDatabaseKeyStore', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues({}));

    test('generates once and persists the key', () async {
      final store = SecureStorageDatabaseKeyStore();

      final first = await store.getOrCreateKey();
      expect(first, matches(RegExp(r'^[A-Za-z0-9_-]{43}=$')));
      expect(await store.getOrCreateKey(), first);
    });

    test('a fresh store instance adopts the persisted key', () async {
      final first = await SecureStorageDatabaseKeyStore().getOrCreateKey();

      // A new instance models a relaunch: the key must come from secure
      // storage, not from a fresh generation.
      final relaunched = SecureStorageDatabaseKeyStore();
      expect(await relaunched.getOrCreateKey(), first);
    });

    test('adopts a pre-seeded key instead of regenerating', () async {
      final seeded = generateDatabaseKey();
      FlutterSecureStorage.setMockInitialValues({
        'firefly_db_key': seeded,
      });

      expect(await SecureStorageDatabaseKeyStore().getOrCreateKey(), seeded);
    });

    test('deleteKey clears the stored key so the next call regenerates',
        () async {
      final store = SecureStorageDatabaseKeyStore();
      final first = await store.getOrCreateKey();

      await store.deleteKey();

      expect(await store.getOrCreateKey(), isNot(first));
    });
  });

  group('stored key drives database encryption', () {
    test(
      'store key opens the DB across relaunches; a wrong key fails',
      () async {
        FlutterSecureStorage.setMockInitialValues({});
        final dir = await Directory.systemTemp.createTemp('firefly_ks_');
        addTearDown(() => dir.delete(recursive: true));
        final path = '${dir.path}/keystore.db';

        // First launch: the store mints the key and the DB is created
        // with it.
        final key = await SecureStorageDatabaseKeyStore().getOrCreateKey();
        final db = await openAppDatabase(
          factory: databaseFactoryFfiNoIsolate,
          path: path,
          password: key,
        );
        await db.execute(
          "INSERT INTO device_meta (key, value) VALUES ('probe', 'v1')",
        );
        await db.close();

        // Simulated relaunch: a new store instance must hand back the
        // SAME persisted key, and that key must open the existing file.
        final store2 = SecureStorageDatabaseKeyStore();
        final relaunchedKey = await store2.getOrCreateKey();
        expect(relaunchedKey, key);
        final db2 = await openAppDatabase(
          factory: databaseFactoryFfiNoIsolate,
          path: path,
          password: relaunchedKey,
        );
        final rows = await db2.rawQuery(
          "SELECT value FROM device_meta WHERE key = 'probe'",
        );
        expect(rows.single['value'], 'v1');
        await db2.close();

        // A different key must not open the file.
        await expectLater(
          openAppDatabase(
            factory: databaseFactoryFfiNoIsolate,
            path: path,
            password: generateDatabaseKey(),
          ),
          throwsA(anything),
        );
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );
  });
}
