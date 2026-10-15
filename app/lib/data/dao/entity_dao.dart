import 'package:firefly_mobile/domain/entities/row_codec.dart';
import 'package:firefly_mobile/domain/entities/sync_bookkeeping.dart';
import 'package:sqflite_common/sqlite_api.dart';

/// Generic row-level CRUD shared by every business table (DESIGN §5.1).
///
/// All fourteen business tables carry the same seven sync-bookkeeping columns
/// and every entity exposes a `toRow`/`fromRow` pair, so the operations P1
/// requires per entity — insert, upsert, update, patch, soft-delete,
/// hard-delete, getById, getByFireflyId, getAll, getPending, count — differ
/// only by table name and codec. Writing them once is what stops fourteen
/// hand-maintained copies from drifting: a fix to `getPending` lands
/// everywhere at once.
///
/// This class is deliberately mechanical. It knows nothing about the clock,
/// about the op log, or about *when* `seq` must be allocated — those are
/// `SyncRepository`'s job, the only place a row write is paired with a queued
/// mutation. Every method takes an optional [DatabaseExecutor] so a caller
/// can drive a whole unit of work inside one transaction; when the argument is
/// omitted the DAO uses its own connection for a direct read.
class EntityDao<T> {
  /// Binds [table] to its entity codec.
  new({
    required this.db,
    required this.table,
    required this.decode,
    required this.encode,
  });

  /// Connection used when a method is called without an explicit executor.
  final DatabaseExecutor db;

  /// Physical table name, e.g. `categories`.
  final String table;

  /// Rebuilds an entity from one SQLite row.
  final T Function(Map<String, Object?> row) decode;

  /// Flattens an entity into the columns of [table].
  final Map<String, Object?> Function(T entity) encode;

  /// Inserts [entity] as a new row.
  ///
  /// The default `abort` conflict algorithm is deliberate: a duplicate primary
  /// key must throw rather than silently overwrite a row the user has not
  /// seen. Pull-merge code should use [upsert], which says the opposite.
  Future<void> insert(T entity, [DatabaseExecutor? executor]) {
    return (executor ?? db).insert(table, encode(entity));
  }

  /// Inserts [entity], replacing any row with the same primary key.
  ///
  /// Reserved for the pull path, where the server's copy wins for the row as a
  /// whole (DESIGN §7.4). Local mutations must go through [insert] or
  /// [update], which refuse to clobber.
  Future<void> upsert(T entity, [DatabaseExecutor? executor]) {
    return (executor ?? db).insert(
      table,
      encode(entity),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Rewrites the whole row whose primary key matches [entity].
  ///
  /// Returns the number of rows changed: 0 means the row this write targeted
  /// does not exist, which a caller pairing the write with a queued mutation
  /// must treat as a failure rather than a no-op — otherwise the queue records
  /// an edit to a row the device no longer has.
  Future<int> update(T entity, [DatabaseExecutor? executor]) {
    final row = encode(entity);
    return (executor ?? db).update(
      table,
      row,
      where: 'id = ?',
      whereArgs: <Object?>[row['id']! as String],
    );
  }

  /// Applies [columns] to row [id], leaving every other column untouched.
  ///
  /// The narrow write the sync bookkeeping changes use, so a `seq` bump cannot
  /// accidentally rewrite business fields the caller did not mention.
  Future<void> patch(
    String id,
    Map<String, Object?> columns, [
    DatabaseExecutor? executor,
  ]) async {
    await (executor ?? db).update(
      table,
      columns,
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  /// Tombstones row [id]: stamps `deleted_at` and queues it for replay.
  ///
  /// The row stays readable so a pull can still merge against it and so the
  /// replay loop can resolve it (DESIGN §6.4); only the sync engine's
  /// acknowledgement turns this into a hard delete.
  Future<void> softDelete(
    String id, {
    required int atMillis,
    required int seq,
    DatabaseExecutor? executor,
  }) {
    return patch(id, <String, Object?>{
      'deleted_at': atMillis,
      'updated_at': atMillis,
      'seq': seq,
      'sync_status': syncStatusToRow(SyncStatus.pending),
    }, executor);
  }

  /// Removes row [id] outright.
  ///
  /// The caller is responsible for having queued the matching `delete` op
  /// first — this method is a storage primitive, not a user-facing delete.
  Future<void> hardDelete(String id, [DatabaseExecutor? executor]) async {
    await (executor ?? db).delete(
      table,
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  /// Returns the row with primary key [id], or null when absent.
  Future<T?> getById(String id, [DatabaseExecutor? executor]) async {
    final rows = await (executor ?? db).query(
      table,
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return decode(rows.first);
  }

  /// Returns the row the server already knows as [fireflyId], or null.
  Future<T?> getByFireflyId(
    String fireflyId, [
    DatabaseExecutor? executor,
  ]) async {
    final rows = await (executor ?? db).query(
      table,
      where: 'firefly_id = ?',
      whereArgs: <Object?>[fireflyId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return decode(rows.first);
  }

  /// Every non-tombstoned row, newest write first unless [orderBy] says
  /// otherwise.
  ///
  /// Tombstones are hidden by default because this is the list screens read;
  /// a deleted row still visible in the UI would look like a failed delete.
  /// Pass `includeDeleted: true` only where the caller must reason about the
  /// tombstones themselves.
  Future<List<T>> getAll({
    bool includeDeleted = false,
    String orderBy = 'updated_at DESC',
    int? limit,
    int? offset,
    DatabaseExecutor? executor,
  }) async {
    final rows = await (executor ?? db).query(
      table,
      where: includeDeleted ? null : 'deleted_at IS NULL',
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
    return rows.map(decode).toList();
  }

  /// Rows the server has not acknowledged, oldest write first.
  ///
  /// Tombstones are *included*: a pending delete is exactly the kind of row a
  /// pull-merge must not resurrect and the push engine must still replay.
  /// [getPending] is therefore the union of "content changed" and "row
  /// removed", while `OpLogDao.getPendingBatch` is what the sync engine
  /// actually replays.
  Future<List<T>> getPending({
    String orderBy = 'updated_at ASC',
    int? limit,
    int? offset,
    DatabaseExecutor? executor,
  }) async {
    final rows = await (executor ?? db).query(
      table,
      where: "sync_status != 'synced'",
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
    return rows.map(decode).toList();
  }

  /// Number of rows matching [getAll]'s visibility rule.
  Future<int> count({
    bool includeDeleted = false,
    DatabaseExecutor? executor,
  }) async {
    final rows = await (executor ?? db).rawQuery(
      'SELECT COUNT(*) AS c FROM $table'
      '${includeDeleted ? '' : ' WHERE deleted_at IS NULL'}',
    );
    return rows.first['c']! as int;
  }
}
