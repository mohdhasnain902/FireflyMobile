import 'package:firefly_mobile/core/utils/id_generator.dart';
import 'package:sqflite_common/sqlite_api.dart';

/// Typed access to the `device_meta` key/value table (DESIGN §5.3).
///
/// This table is the app's only mutable metadata store. Two of its values are
/// load-bearing for correctness rather than mere settings:
///
/// * [deviceIdKey] — the stable per-install UUID stamped on every op-log entry.
/// * [nextSeqKey] — the monotonic per-device counter. It is the tie-breaker
///   that gives a total order to two ops written in the same millisecond.
///
/// Both are therefore allocated inside a transaction so concurrent writes
/// cannot observe the same value.
///
/// Every value method exists in two shapes: a plain one that uses this DAO's
/// own connection, and a `*In(executor, …)` one that runs on a caller-supplied
/// [DatabaseExecutor]. The variants are what let a repository allocate `seq`
/// and `device_id` *inside* the transaction that also writes the business row
/// and the op-log entry — the unit of work DESIGN §5.2 requires to be atomic.
/// A nested `db.transaction()` would fail, so the inner work must accept the
/// outer transaction instead.
class DeviceMetaDao {
  /// Wraps `db`, which must already have the schema applied.
  new(this._db);

  final Database _db;

  /// Key under which the stable per-install UUID is stored.
  static const deviceIdKey = 'device_id';

  /// Key under which the monotonic per-device sequence counter is stored.
  static const nextSeqKey = 'next_seq';

  /// Key under which the epoch-ms timestamp of the last successful sync is
  /// stored. Used to decide whether a background refresh is worth running.
  static const lastSyncTsKey = 'last_sync_ts';

  /// Key under which a human-readable summary of the last sync outcome is
  /// stored (`ok`, `error`, …) for the settings screen.
  static const lastSyncStatusKey = 'last_sync_status';

  /// Key under which the Firefly III base URL is stored.
  static const fireflyBaseUrlKey = 'firefly_base_url';

  /// Key under which a reference to the Firefly III personal access token is
  /// stored. The token itself lives in secure storage; this is only its key.
  static const fireflyPatRefKey = 'firefly_pat_ref';

  /// Key under which the PC backup sidecar's base URL is stored (P4
  /// backup). Non-secret like the Firefly URL, so it lives in `device_meta`.
  static const backupUrlKey = 'backup_url';

  /// Key under which a reference to the sidecar trigger token is stored.
  /// Follows the PAT split: only the ref lives here, the secret itself is in
  /// secure storage.
  static const backupTokenRefKey = 'backup_token_ref';

  /// ISO 4217 code of the preferred display/secondary currency for showing
  /// converted amounts alongside the original (e.g. PKR, USD). Empty/unset
  /// means no secondary display.
  static const displayCurrencyKey = 'display_currency';

  /// Cached exchange-rate payload (JSON) fetched from the rates API, keyed by
  /// base currency code in lowercase (fawazahmed0 schema: {date, <base>:{...}}).
  /// Stored as a JSON object mapping base->payload for quick local lookups.
  static const exchangeRatesCacheKey = 'exchange_rates_cache';

  /// Epoch-ms timestamp when [exchangeRatesCacheKey] was last refreshed.
  static const exchangeRatesFetchedAtKey = 'exchange_rates_fetched_at';

  /// Manually entered exchange rates, as JSON `{FROM: {TO: rate}}` where the
  /// rate means "1 FROM = rate TO".
  ///
  /// Kept apart from [exchangeRatesCacheKey] so a rates refresh never erases
  /// a hand-entered pair, and so both directions of a pair can be stored
  /// independently (a custom currency like BTC is routinely quoted as
  /// 1 BTC = 65,000 USD and 65,000.34 USD = 1 BTC — the inverses need not be
  /// exact reciprocals, and the user enters both).
  static const exchangeRatesManualKey = 'exchange_rates_manual';

  /// Returns the value stored under [key] on [executor], or null when unset.
  Future<String?> getIn(DatabaseExecutor executor, String key) async {
    final rows = await executor.query(
      'device_meta',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  /// Returns the value stored under [key], or null when unset.
  Future<String?> get(String key) => getIn(_db, key);

  /// Writes [value] under [key] on [executor], replacing any existing value.
  Future<void> setIn(DatabaseExecutor executor, String key, String value) {
    return executor.insert('device_meta', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Writes [value] under [key], overwriting any existing value.
  Future<void> set(String key, String value) => setIn(_db, key, value);

  /// Removes the entry under [key]. No-op if the key does not exist.
  Future<void> remove(String key) {
    return _db.delete('device_meta', where: 'key = ?', whereArgs: [key]);
  }

  /// Returns this install's device id on [executor], generating and persisting
  /// one on first use.
  ///
  /// Generated as UUIDv4 and never regenerated, because a changed device id
  /// would silently break the total order across that device's ops
  /// (DESIGN §6.3 orders by `wall_ts, device_id, seq`).
  ///
  /// The read and the write share [executor], so when the caller passes its
  /// own transaction the allocation is rolled back with the rest of that unit
  /// of work rather than surviving a failed write.
  Future<String> getOrCreateDeviceIdIn(DatabaseExecutor executor) async {
    final existing = await getIn(executor, deviceIdKey);
    if (existing != null) return existing;
    final fresh = newDeviceId();
    await setIn(executor, deviceIdKey, fresh);
    return fresh;
  }

  /// Returns this install's device id, generating and persisting one on first
  /// call.
  Future<String> getOrCreateDeviceId() =>
      _db.transaction(getOrCreateDeviceIdIn);

  /// Allocates the next value of the per-device sequence counter on
  /// [executor].
  ///
  /// The read-modify-write runs against [executor] alone. SQLite serialises
  /// writers, so two concurrent callers cannot read the same value; the second
  /// blocks until the first commits and then sees the updated row. This is
  /// what makes `seq` strictly increasing (DESIGN §6.6). When [executor] is an
  /// open transaction the increment commits with it — and rolls back with it —
  /// so a failed write never leaves a hole in the counter.
  Future<int> nextSeqIn(DatabaseExecutor executor) async {
    final rows = await executor.query(
      'device_meta',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [nextSeqKey],
      limit: 1,
    );

    final current = rows.isEmpty
        ? 0
        : int.parse(rows.first['value']! as String);
    final allocated = current + 1;

    await executor.insert('device_meta', {
      'key': nextSeqKey,
      'value': '$allocated',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return allocated;
  }

  /// Allocates and returns the next value of the per-device sequence counter.
  ///
  /// The read-modify-write happens inside a transaction (DESIGN §6.6).
  Future<int> nextSeq() => _db.transaction(nextSeqIn);
}
