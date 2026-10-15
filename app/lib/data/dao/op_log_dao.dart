import 'package:firefly_mobile/domain/entities/op_log_entry.dart';
import 'package:sqflite_common/sqlite_api.dart';

/// Read/write access to the `op_log` queue (DESIGN §5.2, §6.3).
///
/// The op log is append-only from the writer's perspective: an entry is
/// appended when a mutation happens and removed only when the server has
/// acknowledged it or the mutation has been determined to be local-only. It is
/// never edited in place except to bump [OpLogEntry.attempts] and record the
/// failure reason, which are observability fields the user sees in the sync
/// log.
class OpLogDao {
  /// Wraps `db`, which must already have the schema applied.
  ///
  /// The field is a [DatabaseExecutor] rather than a [Database] so the writer
  /// can be handed the open transaction that also holds the business row: the
  /// row and its queued op then commit or roll back together (DESIGN §5.2).
  /// Every method here only uses `insert`/`query`/`delete`/`rawUpdate`, all of
  /// which the executor interface already exposes.
  new(this._db);

  final DatabaseExecutor _db;

  /// Records a mutation.
  ///
  /// [ConflictAlgorithm.ignore] makes this idempotent: replaying the same
  /// `op_id` (a crash between write and ack) leaves the original entry in
  /// place instead of failing or duplicating.
  Future<void> append(OpLogEntry entry) {
    return _db.insert(
      'op_log',
      entry.toRow(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Oldest pending ops in total order, ready for replay.
  ///
  /// Ordering is `wall_ts, device_id, seq` exactly as DESIGN §6.3 specifies,
  /// so the batch handed to the sync engine is already deterministic.
  Future<List<OpLogEntry>> getPendingBatch(int limit) async {
    final rows = await _db.query(
      'op_log',
      orderBy: 'wall_ts ASC, device_id ASC, seq ASC',
      limit: limit,
    );
    return rows.map(OpLogEntry.fromRow).toList();
  }

  /// Number of ops still waiting to be pushed; drives the sync badge.
  Future<int> pendingCount() async {
    final rows = await _db.rawQuery('SELECT COUNT(*) AS c FROM op_log');
    return rows.first['c']! as int;
  }

  /// Removes an op after the server has acknowledged it (or after a
  /// local-only delete has been resolved).
  Future<void> acknowledge(String opId) {
    return _db.delete('op_log', where: 'op_id = ?', whereArgs: [opId]);
  }

  /// Marks a failed attempt without dropping the op.
  ///
  /// The op stays queued — a network blip must not lose the user's edit — but
  /// the attempt count and message are persisted so the settings sync log can
  /// explain why something is stuck.
  Future<void> recordFailure(String opId, String error) {
    return _db.rawUpdate(
      'UPDATE op_log SET attempts = attempts + 1, last_error = ? '
      'WHERE op_id = ?',
      [error, opId],
    );
  }

  /// Clears the failure state, e.g. after a successful replay or a manual
  /// retry that the user initiated.
  Future<void> clearFailure(String opId) {
    return _db.rawUpdate(
      'UPDATE op_log SET last_error = NULL WHERE op_id = ?',
      [opId],
    );
  }
}
