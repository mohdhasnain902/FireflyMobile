import 'package:firefly_mobile/data/dao/entity_dao.dart';
import 'package:firefly_mobile/domain/entities/sync_bookkeeping.dart';
import 'package:sqflite_common/sqlite_api.dart';

/// The read side every repository shares (DESIGN §5.1).
///
/// Reads are pure delegation to [EntityDao]: no queue, no clock, no mutation,
/// so they need no transaction of their own and carry no replay consequence.
/// Holding them apart from the write layer is what lets a pull-only entity —
/// currencies, which the phone never writes (DESIGN §3.1) — expose a full read
/// surface while offering no mutation surface at all, rather than inheriting
/// write methods that must then be refused at runtime.
///
/// The type parameter is bounded by the bookkeeping mixin so every reader
/// speaks in terms of rows the sync engine can actually reason about: a local
/// `id`, an optional server `fireflyId`, and the bookkeeping columns that
/// decide where a row sits in the local-to-remote lifecycle.
class EntityReader<T extends SyncBookkeeping> {
  /// Binds the reader to [db] and to the [daoOf] factory that binds a DAO to a
  /// single connection or transaction.
  new({required this.db, required this.daoOf});

  /// The connection reads run on.
  ///
  /// Exposed rather than kept private because the write layer lives in another
  /// library and must open its transactions on this very same database — a
  /// reader and a writer pointing at different connections is the kind of split
  /// that only surfaces under a concurrent pull.
  final Database db;

  /// Builds a DAO bound to one connection or open transaction.
  ///
  /// Callers pass the transaction they are working in so that a mutation's row
  /// write joins that transaction; readers pass [db] instead.
  final EntityDao<T> Function(DatabaseExecutor executor) daoOf;

  /// Returns the row with primary key [id], or null when absent.
  Future<T?> getById(String id) => daoOf(db).getById(id);

  /// Returns the row the server already knows as [fireflyId], or null.
  Future<T?> getByFireflyId(String fireflyId) {
    return daoOf(db).getByFireflyId(fireflyId);
  }

  /// Every non-tombstoned row, newest write first unless [orderBy] overrides.
  Future<List<T>> getAll({
    bool includeDeleted = false,
    String orderBy = 'updated_at DESC',
    int? limit,
    int? offset,
  }) {
    return daoOf(db).getAll(
      includeDeleted: includeDeleted,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
  }

  /// Rows the server has not acknowledged, tombstones included.
  Future<List<T>> getPending({
    String orderBy = 'updated_at ASC',
    int? limit,
    int? offset,
  }) {
    return daoOf(db).getPending(orderBy: orderBy, limit: limit, offset: offset);
  }

  /// Number of rows visible to [getAll].
  Future<int> count({bool includeDeleted = false}) {
    return daoOf(db).count(includeDeleted: includeDeleted);
  }
}
