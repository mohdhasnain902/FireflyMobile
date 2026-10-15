import 'package:firefly_mobile/core/utils/id_generator.dart';
import 'package:firefly_mobile/data/dao/device_meta_dao.dart';
import 'package:firefly_mobile/data/repositories/entity_reader.dart';
import 'package:firefly_mobile/data/repositories/op_log_writer.dart';
import 'package:firefly_mobile/domain/entities/op_log_entry.dart';
import 'package:firefly_mobile/domain/entities/sync_bookkeeping.dart';

/// One entity type's local write path (DESIGN §5.2, §6.3).
///
/// Every mutation here runs in a single SQLite transaction that performs, in
/// this order:
///
/// 1. allocate the next `seq` from `device_meta`,
/// 2. append the op to `op_log`,
/// 3. write the business row.
///
/// Because all three share one transaction they commit together. If step 3
/// throws — a NOT NULL violation, a row that has gone missing — steps 1 and 2
/// roll back too, so the queue never records work that did not happen and the
/// sequence counter never burns a value on a failed write. Writing the row
/// *first* would leave an unsyncable row behind on failure.
///
/// Reads are inherited from the reader base, which does not touch the queue.
class SyncRepository<T extends SyncBookkeeping> extends EntityReader<T> {
  /// Wires the repository to the database it manages.
  ///
  /// [entityType] is the business table name, which is also the JSON:API `type`
  /// the entity emits — `categories`, `piggy_banks`, … — and is what the replay
  /// engine maps onto a Firefly URL. [payloadOf] serialises an entity into
  /// `op_log.payload`. [daoOf] hands out a DAO bound to whichever executor the
  /// current transaction provides, so a mutation's row write joins the very
  /// transaction that allocates its `seq`.
  new({
    required super.db,
    required DeviceMetaDao meta,
    required this.entityType,
    required this.payloadOf,
    required super.daoOf,
  }) : meta = meta,
       writer = OpLogWriter(meta: meta);

  /// Allocates `seq` and stamps the stable device identity for each mutation.
  final DeviceMetaDao meta;

  /// The table name, doubling as the JSON:API type and the op's entity type.
  final String entityType;

  /// Serialises an entity for the queued op's payload.
  final String Function(T entity) payloadOf;

  /// Appends ops inside the caller's transaction.
  final OpLogWriter writer;

  /// Queues and persists a brand-new row.
  ///
  /// [build] receives the id, write time and `seq` this call has reserved, so
  /// the entity cannot be constructed with bookkeeping that disagrees with the
  /// op recorded for it. The id is minted here rather than accepted from the
  /// caller so it cannot collide with a row already on disk.
  Future<T> create(T Function(String id, DateTime updatedAt, int seq) build) {
    final id = newEntityId();
    return _commit(
      action: OpAction.create,
      mode: _RowMode.insert,
      id: id,
      build: (at, seq) => build(id, at, seq),
    );
  }

  /// Queues and persists an edit to [existing].
  ///
  /// An edit to a row the server has never seen is queued as a `create`, not an
  /// `update`: replaying a patch against an id the server does not know would
  /// 404, while creating the same payload succeeds and the response fills in
  /// `fireflyId`. DESIGN §6.3b flags that case for the replay loop; deciding it
  /// here means the queued op is already the one that will work.
  Future<T> update(
    T existing,
    T Function(T current, DateTime updatedAt, int seq) build,
  ) {
    return _commit(
      action: existing.fireflyId == null ? OpAction.create : OpAction.update,
      mode: _RowMode.overwrite,
      id: existing.id,
      build: (at, seq) => build(existing, at, seq),
    );
  }

  /// Tombstones row [id] and queues its deletion (DESIGN §6.4).
  ///
  /// The row survives so a later pull can still merge against it; only the sync
  /// engine's acknowledgement turns it into a [hardDelete].
  Future<void> softDelete(String id) {
    return db.transaction((txn) async {
      final at = DateTime.now().toUtc();
      final seq = await meta.nextSeqIn(txn);
      await writer.append(
        txn,
        entityType: entityType,
        entityId: id,
        action: OpAction.delete,
        seq: seq,
      );
      await daoOf(txn)
          .softDelete(id, atMillis: at.millisecondsSinceEpoch, seq: seq);
    });
  }

  /// Removes row [id] outright and queues its deletion.
  ///
  /// This is the post-acknowledgement form: the op has already told the server
  /// to drop its copy, or the row was never sent in the first place. Row and op
  /// are still written in one transaction, so an interrupted delete cannot
  /// leave a row the queue believes is gone.
  Future<void> hardDelete(String id) {
    return db.transaction((txn) async {
      final seq = await meta.nextSeqIn(txn);
      await writer.append(
        txn,
        entityType: entityType,
        entityId: id,
        action: OpAction.delete,
        seq: seq,
      );
      await daoOf(txn).hardDelete(id);
    });
  }

  /// Runs one `seq`-allocating, op-appending, row-writing unit of work.
  Future<T> _commit({
    required OpAction action,
    required _RowMode mode,
    required String id,
    required T Function(DateTime at, int seq) build,
  }) {
    return db.transaction((txn) async {
      final at = DateTime.now().toUtc();
      final seq = await meta.nextSeqIn(txn);
      final entity = build(at, seq);

      // The op goes down before the row. If the row write then fails, the
      // transaction discards both — the invariant the P1.4 atomicity test
      // asserts: no op may outlive the row it describes.
      await writer.append(
        txn,
        entityType: entityType,
        entityId: id,
        action: action,
        seq: seq,
        payload: payloadOf(entity),
      );

      final dao = daoOf(txn);
      if (mode == _RowMode.insert) {
        await dao.insert(entity);
      } else {
        final written = await dao.update(entity);
        if (written == 0) {
          // Otherwise the queue holds an op describing a row this device no
          // longer has, and every replay of it would be built from a payload
          // that disagrees with local state.
          throw StateError('$entityType row ${entity.id} is gone');
        }
      }
      return entity;
    });
  }
}

/// How a commit writes its row, independently of what the op records.
///
/// The two axes differ: an edit to a row the server has never seen is a
/// `create` op against a row that already exists locally, so neither the action
/// nor the id alone says whether to insert or overwrite.
enum _RowMode {
  /// The row does not exist locally yet.
  insert,

  /// The row exists and is rewritten wholesale.
  overwrite,
}
