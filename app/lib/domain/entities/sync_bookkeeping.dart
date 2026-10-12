/// Shared sync bookkeeping present on every business table (DESIGN §5.1).
library;

/// Lifecycle of a row with respect to the Firefly III server.
///
/// - [pending]: written locally, not yet acknowledged by the server.
/// - [synced]: the server has confirmed the latest local write.
/// - [conflict]: a field-level merge was required during pull (DESIGN §7.4).
enum SyncStatus {
  /// Written locally, not yet acknowledged by the server.
  pending,

  /// The server has confirmed the latest local write.
  synced,

  /// A field-level merge was required during pull (DESIGN §7.4).
  conflict,
}

/// The seven bookkeeping columns carried by every business table.
///
/// [id] is a client-generated UUIDv7 that is stable for the row's whole
/// lifetime, even before the server has seen it. [fireflyId] is only set once
/// a create has been acknowledged (DESIGN §6.3, step 3a), which is what makes
/// the replay loop idempotent on our side.
///
/// [seq] stores the op-seq that produced the row's current content. It is
/// allocated from the per-device monotonic counter in `device_meta`, so a
/// value always refers to a specific op in `op_log`.
mixin SyncBookkeeping {
  /// Client-generated UUIDv7; stable for the row's whole lifetime.
  String get id;

  /// Server-side Firefly ID, null until a create is acknowledged.
  String? get fireflyId;

  /// Wall-clock ms of the local write that produced this content.
  DateTime get updatedAt;

  /// Server `updated_at` at the last successful pull, if seen.
  DateTime? get remoteUpdatedAt;

  /// Current position in the local-to-remote lifecycle.
  SyncStatus get syncStatus;

  /// Set when the row is a tombstone awaiting replay (DESIGN §6.4).
  DateTime? get deletedAt;

  /// The op-seq that produced this row's current content.
  int get seq;
}

/// Converts the integer millisecond epochs stored in SQLite to [DateTime].
DateTime? millisToDateTime(int? millis) =>
    millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);

/// Converts a [DateTime] (or null) to the integer epoch SQLite stores.
int? dateTimeToMillis(DateTime? time) => time?.millisecondsSinceEpoch;
