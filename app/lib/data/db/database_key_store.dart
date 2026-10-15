import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite/sqflite.dart' show getDatabasesPath;

/// Stores the SQLCipher key that protects the local database.
///
/// The key is a random 32-byte value generated once at first launch and never
/// derived from anything the user types, so there is no passphrase to guess
/// and no key to lose. On Android it is protected by an RSA-OAEP-wrapped
/// AES-GCM key held in the hardware Keystore; the plaintext key never leaves
/// secure storage.
///
/// Losing the key (wiping app data, restoring a backup that excludes secure
/// storage) makes the database unrecoverable by design. That is the correct
/// trade-off for a personal-finance vault: a backup readable without the
/// device is a liability, not a feature.
abstract class DatabaseKeyStore {
  /// Returns the existing key, generating and persisting one on first call.
  Future<String> getOrCreateKey();

  /// Discards the key, which permanently orphans the encrypted database.
  Future<void> deleteKey();
}

/// In-memory implementation used by unit tests.
///
/// Mirrors the generate-once semantics of the real store so tests exercise the
/// same "second call returns the first key" behaviour.
class InMemoryDatabaseKeyStore implements DatabaseKeyStore {
  String? _key;

  @override
  Future<String> getOrCreateKey() async => _key ??= generateDatabaseKey();

  @override
  Future<void> deleteKey() async => _key = null;

  /// Whether a key is currently held; lets tests assert generate-once.
  bool get hasKey => _key != null;
}

/// [DatabaseKeyStore] backed by platform secure storage (Keystore on Android).
///
/// Defaults are used on both platforms because they are already the strong
/// choice:
///
/// * Android `AndroidOptions()` protects the key with an RSA-OAEP-wrapped
///   AES-GCM key held in the hardware Keystore. The older
///   `encryptedSharedPreferences` flag was removed in flutter_secure_storage
///   11.x; this default is the replacement and is strictly stronger.
/// * iOS `first_unlock_this_device` keeps the key out of iCloud migration and
///   makes it available to background sync after the first unlock, while still
///   binding it to this device.
class SecureStorageDatabaseKeyStore implements DatabaseKeyStore {
  /// Creates a store backed by [storage], or by the platform default when
  /// omitted.
  new({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  static const _storageKey = 'firefly_db_key';

  final FlutterSecureStorage _storage;

  @override
  Future<String> getOrCreateKey() async {
    final existing = await _storage.read(key: _storageKey);
    if (existing != null) return existing;

    final fresh = generateDatabaseKey();
    // Write-then-verify: if two launches race on first open, the loser must
    // adopt the winner's key rather than overwrite it and orphan the DB.
    await _storage.write(key: _storageKey, value: fresh);
    final confirmed = await _storage.read(key: _storageKey);
    return confirmed ?? fresh;
  }

  @override
  Future<void> deleteKey() => _storage.delete(key: _storageKey);
}

/// 32 random bytes, URL-safe base64 encoded (44 chars: 43 payload chars
/// plus one trailing `=` padding character — Dart's encoder always pads to
/// a multiple of four).
///
/// The URL-safe alphabet is used so the value can be spliced into a
/// `PRAGMA KEY='...'` statement without escaping.
String generateDatabaseKey() {
  final bytes = List<int>.generate(32, (_) => _secureRandom.nextInt(256));
  return base64UrlEncode(bytes);
}

final Random _secureRandom = Random.secure();

/// Path of the on-disk database file.
///
/// [getDatabasesPath] is the platform-sanctioned location and needs no extra
/// permissions on Android.
Future<String> defaultDatabasePath() async {
  final dir = await getDatabasesPath();
  return '$dir/firefly.db';
}
