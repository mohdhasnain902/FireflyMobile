import 'package:firefly_mobile/core/utils/id_generator.dart';
import 'package:firefly_mobile/data/dao/device_meta_dao.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the app points at Firefly and how it authenticates there (P2 §4).
///
/// The two halves are stored deliberately differently, following the split
/// DESIGN §"PAT storage" already fixes for the app: the base URL is ordinary
/// non-secret configuration and lives in SQLite `device_meta`
/// ([DeviceMetaDao.fireflyBaseUrlKey]); the personal access token is a
/// credential and lives only in platform secure storage (Keystore on Android).
/// `device_meta` holds at most a *reference* key pointing at the secure-storage
/// entry ([DeviceMetaDao.fireflyPatRefKey]) — never the token itself — so a
/// database dump or a sync of `device_meta` cannot leak it.
class ConnectionSettings {
  /// Creates a settings snapshot.
  const new({
    required this.baseUrl,
    this.pat,
    this.backupUrl = '',
    this.backupToken,
  });

  /// Configured Firefly base origin, no trailing slash.
  ///
  /// Empty string when the user has never saved a URL — kept as `''` rather
  /// than null so the type cannot smuggle an "unset but non-empty" state.
  final String baseUrl;

  /// The personal access token, or null when none has been stored.
  final String? pat;

  /// PC backup sidecar origin (`http://192.168.1.10:8095`), no trailing
  /// slash. `''` when the user never configured a backup target — same
  /// empty-string convention as [baseUrl].
  final String backupUrl;

  /// The sidecar trigger token, or null when none has been stored.
  ///
  /// Same PAT discipline: secure storage only, never `device_meta`.
  final String? backupToken;

  /// Whether enough is configured to attempt a server call.
  bool get isConfigured => baseUrl.isNotEmpty;

  /// Whether a PC backup target is configured (P4). The trigger token is
  /// deliberately NOT required here: a sidecar with an empty token file would
  /// still accept the call, and a missing token is better surfaced as a 401
  /// log line than as a silently disabled feature.
  bool get isBackupConfigured => backupUrl.isNotEmpty;
}

/// Normalises and validates a user-entered Firefly base URL.
///
/// Returns the trimmed origin with trailing slashes removed, or null when the
/// input cannot be a base URL at all. Accepting only an `http(s)` scheme with
/// a non-empty host mirrors what an API client actually needs: no path, no
/// query, no credentials — anything after the host is dropped, because every
/// endpoint the app calls is built as `{base}/api/v1/...`.
String? normalizeBaseUrl(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed.contains(RegExp(r'\s'))) return null;
  if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
    return null;
  }
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasAuthority || uri.host.isEmpty) return null;
  // Scheme + host only: drop any path/query the user pasted in.
  // `hasPort` is false for an omitted port AND for an explicit default
  // (":443"/":80"), so we only re-append a genuinely non-default port.
  return '${uri.scheme}://${uri.host}'
      '${uri.hasPort ? ':${uri.port}' : ''}';
}

/// Reads and writes the device's [ConnectionSettings].
///
/// Two implementations exist for the same reason the database key store has
/// two: a platform-backed one for the running app, and an in-memory one so
/// widget tests never touch Keystore.
abstract class ConnectionSettingsStore {
  /// The currently stored settings (never throws; unset fields come back
  /// empty/null).
  Future<ConnectionSettings> read();

  /// Persists [baseUrl], already expected to be normalized.
  Future<void> setBaseUrl(String baseUrl);

  /// Stores [pat] in secure storage under a fresh reference recorded in
  /// `device_meta`, replacing any previous token.
  Future<void> setPat(String pat);

  /// Removes the stored token; the base URL is untouched.
  Future<void> clearPat();

  /// Persists the PC backup sidecar origin, already normalized
  /// (see [normalizeBaseUrl] — same rules as the Firefly URL).
  Future<void> setBackupUrl(String backupUrl);

  /// Stores the sidecar trigger token in secure storage under a fresh
  /// reference recorded in `device_meta`, replacing any previous one.
  Future<void> setBackupToken(String token);

  /// Removes the stored backup token; the backup URL is untouched.
  Future<void> clearBackupToken();
}

/// Production store: base URL in `device_meta`, token in secure storage.
class DeviceConnectionSettingsStore implements ConnectionSettingsStore {
  /// Binds the store to [meta] (device_meta table) and optional [storage]
  /// (defaults to the same platform configuration the DB key uses).
  new({
    required this.meta,
    FlutterSecureStorage? storage,
  }) : _storage = storage ??
            const FlutterSecureStorage(
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  /// Metadata table access for the URL and the token reference.
  final DeviceMetaDao meta;

  final FlutterSecureStorage _storage;

  /// Secure-storage key used when no reference has been recorded yet.
  static const _defaultRef = 'firefly_pat';

  /// Secure-storage key used for the backup token before any ref exists.
  static const _defaultBackupRef = 'firefly_backup_token';

  @override
  Future<ConnectionSettings> read() async {
    final baseUrl = await meta.get(DeviceMetaDao.fireflyBaseUrlKey) ?? '';
    final ref =
        await meta.get(DeviceMetaDao.fireflyPatRefKey) ?? _defaultRef;
    final pat = await _storage.read(key: ref);
    final backupUrl =
        await meta.get(DeviceMetaDao.backupUrlKey) ?? '';
    final backupRef =
        await meta.get(DeviceMetaDao.backupTokenRefKey) ?? _defaultBackupRef;
    final backupToken = await _storage.read(key: backupRef);
    return ConnectionSettings(
      baseUrl: baseUrl,
      pat: pat,
      backupUrl: backupUrl,
      backupToken: backupToken,
    );
  }

  @override
  Future<void> setBaseUrl(String baseUrl) =>
      meta.set(DeviceMetaDao.fireflyBaseUrlKey, baseUrl);

  @override
  Future<void> setPat(String pat) async {
    final ref = await meta.get(DeviceMetaDao.fireflyPatRefKey) ?? newDeviceId();
    await _storage.write(key: ref, value: pat);
    // Record the reference only after the token landed, so a crash between the
    // two writes can never leave a reference pointing at nothing.
    await meta.set(DeviceMetaDao.fireflyPatRefKey, ref);
  }

  @override
  Future<void> clearPat() async {
    final ref = await meta.get(DeviceMetaDao.fireflyPatRefKey);
    if (ref != null) await _storage.delete(key: ref);
  }

  @override
  Future<void> setBackupUrl(String backupUrl) =>
      meta.set(DeviceMetaDao.backupUrlKey, backupUrl);

  @override
  Future<void> setBackupToken(String token) async {
    final ref =
        await meta.get(DeviceMetaDao.backupTokenRefKey) ?? newDeviceId();
    await _storage.write(key: ref, value: token);
    // Same order rule as [setPat]: value first, reference second, so a crash
    // between the writes never leaves a ref pointing at nothing.
    await meta.set(DeviceMetaDao.backupTokenRefKey, ref);
  }

  @override
  Future<void> clearBackupToken() async {
    final ref = await meta.get(DeviceMetaDao.backupTokenRefKey);
    if (ref != null) await _storage.delete(key: ref);
  }
}

/// In-memory store for widget tests — same behaviour, no Keystore.
class InMemoryConnectionSettingsStore implements ConnectionSettingsStore {
  /// Starts with an empty base URL and no token; pass a snapshot to seed it.
  new([
    this._value = const ConnectionSettings(baseUrl: ''),
  ]);

  ConnectionSettings _value;

  @override
  Future<ConnectionSettings> read() async => _value;

  @override
  Future<void> setBaseUrl(String baseUrl) async {
    _value = ConnectionSettings(
      baseUrl: baseUrl,
      pat: _value.pat,
      backupUrl: _value.backupUrl,
      backupToken: _value.backupToken,
    );
  }

  @override
  Future<void> setPat(String pat) async {
    _value = ConnectionSettings(
      baseUrl: _value.baseUrl,
      pat: pat,
      backupUrl: _value.backupUrl,
      backupToken: _value.backupToken,
    );
  }

  @override
  Future<void> clearPat() async {
    _value = ConnectionSettings(
      baseUrl: _value.baseUrl,
      backupUrl: _value.backupUrl,
      backupToken: _value.backupToken,
    );
  }

  @override
  Future<void> setBackupUrl(String backupUrl) async {
    _value = ConnectionSettings(
      baseUrl: _value.baseUrl,
      pat: _value.pat,
      backupUrl: backupUrl,
      backupToken: _value.backupToken,
    );
  }

  @override
  Future<void> setBackupToken(String token) async {
    _value = ConnectionSettings(
      baseUrl: _value.baseUrl,
      pat: _value.pat,
      backupUrl: _value.backupUrl,
      backupToken: token,
    );
  }

  @override
  Future<void> clearBackupToken() async {
    _value = ConnectionSettings(
      baseUrl: _value.baseUrl,
      pat: _value.pat,
      backupUrl: _value.backupUrl,
    );
  }
}
