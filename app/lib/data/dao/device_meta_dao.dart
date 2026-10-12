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

  /// Returns the value stored under [key], or null when unset.
  Future<String?> get(String key) async {
    final rows = await _db.query(
      'device_meta',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  /// Writes [value] under [key], overwriting any existing value.
  Future<void> set(String key, String value) {
    return _db.insert(
      'device_meta',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Removes the entry under [key]. No-op if the key does not exist.
  Future<void> remove(String key) {
    return _db.delete('device_meta', where: 'key = ?', whereArgs: [key]);
  }

  /// Returns this install's device id, generating and persisting one on first
  /// call.
  ///
  /// Generated as UUIDv4 and never regenerated, because a changed device id
  /// would silently break the total order across that device's ops
  /// (DESIGN §6.3 orders by `wall_ts, device_id, seq`).
  Future<String> getOrCreateDeviceId() async {
    final existing = await get(deviceIdKey);
    if (existing != null) return existing;
    final fresh = newDeviceId();
    await set(deviceIdKey, fresh);
    return fresh;
  }

  /// Allocates and returns the next value of the per-device sequence counter.
  ///
  /// The read-modify-write happens inside a transaction. SQLite serialises
  /// writers, so two concurrent callers cannot read the same value; the second
  /// blocks until the first commits and then sees the updated row. This is
  /// what makes `seq` strictly increasing (DESIGN §6.6).
  Future<int> nextSeq() {
    return _db.transaction((txn) async {
      final rows = await txn.query(
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

      await txn.insert(
        'device_meta',
        {'key': nextSeqKey, 'value': '$allocated'},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return allocated;
    });
  }
}
