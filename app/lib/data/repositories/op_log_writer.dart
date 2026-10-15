import 'package:firefly_mobile/core/utils/id_generator.dart';
import 'package:firefly_mobile/data/dao/device_meta_dao.dart';
import 'package:firefly_mobile/data/dao/op_log_dao.dart';
import 'package:firefly_mobile/domain/entities/op_log_entry.dart';
import 'package:sqflite_common/sqlite_api.dart';

/// Appends one queued mutation to an open transaction (DESIGN §5.2).
///
/// Kept separate from `SyncRepository` because every mutation needs the same
/// three steps — allocate `seq`, resolve the stable `device_id`, insert the
/// entry — and because the *ordering* of those steps belongs in exactly one
/// place: the op is appended **before** the row it describes is written, so a
/// row can never exist without its op, and a rolled-back row takes its op with
/// it (DESIGN §5.2, and the atomicity test in P1.4).
///
/// The writer owns no connection. The transaction handed to [append] supplies
/// the connection, which is what keeps `device_meta` increments and `op_log`
/// inserts inside the caller's unit of work rather than in their own nested
/// transactions — sqflite forbids nesting, and separate transactions would
/// break atomicity.
class OpLogWriter {
  /// Builds a writer bound to the metadata table through [_meta].
  new({required this._meta});

  final DeviceMetaDao _meta;

  /// Records one mutation against [txn].
  ///
  /// [entityType] is the business table name, which is also the JSON:API
  /// `type` each entity emits (e.g. `categories`); [entityId] is always the
  /// **local** UUIDv7 of the row, because before the first successful push no
  /// Firefly id exists yet. [payload] is the JSON:API snapshot for
  /// create/update and null for delete. [seq] must already have been allocated
  /// on [txn] by the caller, so the op and the row it describes carry the same
  /// value.
  Future<void> append(
    DatabaseExecutor txn, {
    required String entityType,
    required String entityId,
    required OpAction action,
    required int seq,
    String? payload,
    DateTime? at,
  }) async {
    final now = (at ?? DateTime.now().toUtc()).millisecondsSinceEpoch;
    final deviceId = await _meta.getOrCreateDeviceIdIn(txn);

    await OpLogDao(txn).append(
      OpLogEntry(
        opId: newOpId(),
        entityType: entityType,
        entityId: entityId,
        action: action,
        payload: payload,
        wallTs: now,
        deviceId: deviceId,
        seq: seq,
        createdAt: now,
      ),
    );
  }
}
