/// The op log (DESIGN §5.2).
///
/// Every local mutation is recorded here before it is applied, which is what
/// makes the app work offline: the UI writes to SQLite immediately and the
/// op log is the durable queue that later replays those writes to the server.
library;

import 'package:meta/meta.dart';

/// What an op did to a row.
enum OpAction {
  /// A new row that the server has not seen yet.
  create,

  /// An edit to a row that already exists locally.
  update,

  /// A tombstone awaiting replay (DESIGN §6.4).
  delete,
}

/// One queued mutation, in the exact shape stored in `op_log`.
///
/// [opId] is a client-generated UUIDv4 and doubles as the idempotency key: it
/// is the primary key of the table, so re-appending the same op is a no-op.
/// [seq] is allocated from the per-device monotonic counter and is what breaks
/// ties when two ops share a wall-clock millisecond (DESIGN §6.6).
@immutable
class OpLogEntry {
  /// Builds an entry from its fields.
  const new({
    required this.opId,
    required this.entityType,
    required this.entityId,
    required this.action,
    required this.wallTs,
    required this.deviceId,
    required this.seq,
    required this.createdAt,
    this.payload,
    this.attempts = 0,
    this.lastError,
  });

  /// Rebuilds an entry from a row read out of the `op_log` table.
  ///
  /// The keys here are the schema's column names; the inverse of `toRow`.
  factory fromRow(Map<String, Object?> row) {
    return OpLogEntry(
      opId: row['op_id']! as String,
      entityType: row['entity_type']! as String,
      entityId: row['entity_id']! as String,
      action: OpAction.values.byName(row['action']! as String),
      payload: row['payload'] as String?,
      wallTs: row['wall_ts']! as int,
      deviceId: row['device_id']! as String,
      seq: row['seq']! as int,
      createdAt: row['created_at']! as int,
      attempts: (row['attempts'] as int?) ?? 0,
      lastError: row['last_error'] as String?,
    );
  }

  /// Idempotency key; also the `op_log` primary key.
  final String opId;

  /// Firefly resource name, e.g. `transaction`, `account`.
  final String entityType;

  /// The **local** UUIDv7 of the affected row.
  final String entityId;

  /// Which kind of mutation this op represents.
  final OpAction action;

  /// JSON snapshot of the changed fields for create/update; null for delete.
  final String? payload;

  /// Device wall-clock ms at append time. Ordering information only —
  /// cross-device order comes from the server's `updated_at` (DESIGN §6.5).
  final int wallTs;

  /// Stable per-install UUID.
  final String deviceId;

  /// Per-device monotonically increasing counter.
  final int seq;

  /// When the op was appended, in epoch ms.
  final int createdAt;

  /// How many replay attempts have failed.
  final int attempts;

  /// Most recent failure message, kept for the sync log shown in settings.
  final String? lastError;

  /// Rebuilds a copy with the given fields replaced.
  OpLogEntry copyWith({
    int? attempts,
    String? lastError,
  }) {
    return OpLogEntry(
      opId: opId,
      entityType: entityType,
      entityId: entityId,
      action: action,
      payload: payload,
      wallTs: wallTs,
      deviceId: deviceId,
      seq: seq,
      createdAt: createdAt,
      attempts: attempts ?? this.attempts,
      lastError: lastError ?? this.lastError,
    );
  }

  /// Serialises to the `op_log` column map.
  ///
  /// Keys are the schema's column names; the inverse of `fromRow`.
  Map<String, Object?> toRow() => <String, Object?>{
        'op_id': opId,
        'entity_type': entityType,
        'entity_id': entityId,
        'action': action.name,
        'payload': payload,
        'wall_ts': wallTs,
        'device_id': deviceId,
        'seq': seq,
        'created_at': createdAt,
        'attempts': attempts,
        'last_error': lastError,
      };

  /// Identity is [opId] alone: it is unique and immutable by construction.
  @override
  bool operator ==(Object other) =>
      other is OpLogEntry && other.opId == opId;

  @override
  int get hashCode => opId.hashCode;

  @override
  String toString() =>
      'OpLogEntry($opId, $entityType/$entityId, ${action.name}, '
      'seq=$seq, attempts=$attempts)';
}
