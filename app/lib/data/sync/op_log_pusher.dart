/// Op-log replay engine — phone → Firefly push (P3.2, DESIGN §6.3).
///
/// One sync cycle runs [OpLogPusher.pushBatch] in a loop until the queue is
/// empty or a failure stops the batch. The algorithm matches DESIGN §6.3
/// verbatim:
///
/// 1. Fetch the oldest [kSyncBatchSize] pending ops (already ordered by
///    `wall_ts, device_id, seq` by the DAO).
/// 2. For each op, replay its action against the server.
/// 3. On 2xx (or delete-404): acknowledge the op, patch the local row's
///    `firefly_id` / `sync_status` / `remote_updated_at`, hard-delete the row
///    for deletes.
/// 4. On failure: increment `attempts`, store `last_error`, **break** —
///    remaining ops in the batch stay queued.
///
/// The engine never throws for expected conditions; it returns a typed
/// [Result] so the caller (a future sync orchestrator) can decide whether to
/// retry, surface the error, or fall through to pull.
///
/// URL path mapping (DESIGN §6.3 "entity → path"):
/// * default: `entity_type` underscores → hyphens (`piggy_banks` →
///   `piggy-banks`, `rule_groups` → `rule-groups`).
/// * `budget_limits` is nested: `budgets/{budget_id}/limits`.
///
/// `firefly_api_client.dart`'s `update` uses `PUT` (Firefly's actual verb);
/// DESIGN's "PATCH" is conceptual, not the wire method.
library;

import 'dart:convert';

import 'package:firefly_mobile/core/errors/failure.dart';
import 'package:firefly_mobile/core/utils/result.dart';
import 'package:firefly_mobile/data/api/firefly_api_client.dart';
import 'package:firefly_mobile/data/dao/op_log_dao.dart';
import 'package:firefly_mobile/domain/entities/op_log_entry.dart';
import 'package:firefly_mobile/domain/entities/row_codec.dart';
import 'package:firefly_mobile/domain/entities/sync_bookkeeping.dart';
import 'package:sqflite_common/sqlite_api.dart';

/// Batch size for one replay pass (DESIGN §7.1).
const int kSyncBatchSize = 50;

/// Outcome of a single [OpLogPusher.pushBatch] call.
enum PushOutcome {
  /// Every op in the batch was acknowledged.
  allOk,

  /// The queue was already empty.
  empty,

  /// At least one op failed; the batch stopped at the first failure.
  stopped,
}

/// Replays the op log against Firefly (DESIGN §6.3).
class OpLogPusher {
  /// Builds a pusher bound to an open SQLite connection and an API client.
  ///
  /// [db] is the same connection the repositories write through, so the
  /// firefly-id patch and the op ack commit together (DESIGN §5.2).
  new({required Database db, required this._client})
    : _db = db,
      _opLog = OpLogDao(db);

  final Database _db;
  final FireflyApiClient _client;
  final OpLogDao _opLog;

  /// Pushes one batch of pending ops.
  ///
  /// Returns [PushOutcome.allOk] when every op in the batch was acknowledged,
  /// [PushOutcome.empty] when there was nothing to push, and
  /// [PushOutcome.stopped] when a failure stopped the loop early. In the
  /// stopped case the caller should not try another batch this cycle — the
  /// client already retried transient errors internally.
  Future<Result<PushOutcome>> pushBatch({int limit = kSyncBatchSize}) async {
    final ops = await _opLog.getPendingBatch(limit);
    if (ops.isEmpty) return const Ok(PushOutcome.empty);

    for (final op in ops) {
      final failure = await _replay(op);
      if (failure != null) {
        await _opLog.recordFailure(
          op.opId,
          '${failure.code}: ${failure.message}',
        );
        return const Ok(PushOutcome.stopped);
      }
    }
    return const Ok(PushOutcome.allOk);
  }

  /// Replays one op; returns null on success, a [Failure] on first error.
  Future<Failure?> _replay(OpLogEntry op) => switch (op.action) {
    OpAction.create => _replayCreate(op),
    OpAction.update => _replayUpdate(op),
    OpAction.delete => _replayDelete(op),
  };

  // -------------------------------------------------------------------------
  // create
  // -------------------------------------------------------------------------

  Future<Failure?> _replayCreate(OpLogEntry op) async {
    final row = await _fetchRow(op.entityType, op.entityId);
    if (row == null) {
      // The row is gone locally — the op is stale; acknowledge it.
      await _opLog.acknowledge(op.opId);
      return null;
    }
    // Already has a firefly_id — the server has seen it; drop the op.
    if (row['firefly_id'] != null) {
      await _opLog.acknowledge(op.opId);
      return null;
    }

    final member = _decodePayload(op.payload);
    if (member == null) {
      return const ValidationFailure('op payload is not a JSON object');
    }
    final references = await _resolveReferences(op, member);

    final path = _collectionPath(op.entityType, row);
    final result = await _client.create(path, member);
    final failure = result.failureOrNull;
    if (failure != null) return failure;

    final resource = result.valueOrNull!;
    await _markSynced(
      op.entityType,
      op.entityId,
      fireflyId: resource.id,
      remoteUpdatedAt: resource.updatedAt,
    );
    await _applyResolvedReferences(op.entityType, op.entityId, references);
    await _opLog.acknowledge(op.opId);
    return null;
  }

  // -------------------------------------------------------------------------
  // update
  // -------------------------------------------------------------------------

  Future<Failure?> _replayUpdate(OpLogEntry op) async {
    final row = await _fetchRow(op.entityType, op.entityId);
    if (row == null) {
      await _opLog.acknowledge(op.opId);
      return null;
    }

    final member = _decodePayload(op.payload);
    if (member == null) {
      return const ValidationFailure('op payload is not a JSON object');
    }
    final references = await _resolveReferences(op, member);

    final fireflyId = row['firefly_id'] as String?;
    // No firefly_id yet — the server has never seen this row. Fall back to a
    // create (DESIGN §6.3 step 3b warning).
    if (fireflyId == null) {
      final createResult = await _client.create(
        _collectionPath(op.entityType, row),
        member,
      );
      final createFailure = createResult.failureOrNull;
      if (createFailure != null) return createFailure;
      final resource = createResult.valueOrNull!;
      await _markSynced(
        op.entityType,
        op.entityId,
        fireflyId: resource.id,
        remoteUpdatedAt: resource.updatedAt,
      );
      await _applyResolvedReferences(op.entityType, op.entityId, references);
      await _opLog.acknowledge(op.opId);
      return null;
    }

    final path = _itemPath(op.entityType, row, fireflyId);
    final result = await _client.update(path, member);
    final failure = result.failureOrNull;
    if (failure is NotFoundFailure) {
      // The server no longer has this row: it was deleted on the website (R41).
      // Re-sending the edit would resurrect deleted data, and leaving the op
      // queued made every later push fail with the same 404, which in turn
      // stopped the pull from ever learning about the deletion. The server is
      // the authority on existence (DESIGN §7.4), so the local row and its
      // queued ops go — the pull would have tombstoned the row anyway.
      await _discardRowAndOps(op.entityType, op.entityId);
      await _opLog.acknowledge(op.opId);
      return null;
    }
    if (failure != null) return failure;

    final resource = result.valueOrNull!;
    await _markSynced(
      op.entityType,
      op.entityId,
      remoteUpdatedAt: resource.updatedAt,
    );
    await _applyResolvedReferences(op.entityType, op.entityId, references);
    await _opLog.acknowledge(op.opId);
    return null;
  }

  // -------------------------------------------------------------------------
  // delete
  // -------------------------------------------------------------------------

  Future<Failure?> _replayDelete(OpLogEntry op) async {
    final row = await _fetchRow(op.entityType, op.entityId);
    // Local-only row — no server counterpart; just hard-delete + ack.
    if (row == null || row['firefly_id'] == null) {
      await _hardDelete(op.entityType, op.entityId);
      await _opLog.acknowledge(op.opId);
      return null;
    }

    final fireflyId = row['firefly_id']! as String;
    final path = _itemPath(op.entityType, row, fireflyId);
    final result = await _client.delete(path);
    final failure = result.failureOrNull;
    // 404 counts as success for a delete (DESIGN §6.3 step 3c).
    if (failure != null && failure is! NotFoundFailure) return failure;

    await _hardDelete(op.entityType, op.entityId);
    await _opLog.acknowledge(op.opId);
    return null;
  }

  /// Removes a local row the server no longer has, together with every queued
  /// op that targets it.
  ///
  /// A single `transactions` row and its op, or a whole account: the children
  /// (a deleted account's transactions, a deleted budget's limits) are never
  /// re-added here — the server deleted them too and the pull tombstones what
  /// the phone still holds.
  Future<void> _discardRowAndOps(String entityType, String entityId) async {
    await _db.transaction((txn) async {
      await txn.delete(
        entityType,
        where: 'id = ?',
        whereArgs: [entityId],
      );
      await txn.delete(
        'op_log',
        where: 'entity_type = ? AND entity_id = ?',
        whereArgs: [entityType, entityId],
      );
    });
  }

  // -------------------------------------------------------------------------
  // Reference resolution
  // -------------------------------------------------------------------------

  /// Firefly reference keys on a transaction leg, plus the local table they
  /// point at and the `transactions` column that mirrors them.
  static const List<({String key, String table, String column})>
  _transactionReferences = <({String key, String table, String column})>[
    (key: 'source_id', table: 'accounts', column: 'source_account_id'),
    (key: 'destination_id', table: 'accounts', column: 'dest_account_id'),
    (key: 'category_id', table: 'categories', column: 'category_id'),
    (key: 'budget_id', table: 'budgets', column: 'budget_id'),
    (key: 'bill_id', table: 'bills', column: 'bill_id'),
  ];

  /// Rewrites local reference ids in a transaction payload to Firefly ids.
  ///
  /// The form's reference dropdowns store the *local* row id, so a transfer
  /// created on the phone carried `"source_id": "01a1ec0d-…"` and every push
  /// was rejected with "The transactions.0.source_id must be a number."
  /// Resolving here rather than at save time also covers a row that references
  /// an account with no firefly_id yet: the account's create op is replayed
  /// first, so by the time this op is sent its firefly_id exists.
  ///
  /// Returns the `transactions` columns that were rewritten, ready to be
  /// written back so the device row matches the server's numeric ids.
  Future<Map<String, Object?>> _resolveReferences(
    OpLogEntry op,
    Map<String, dynamic> member,
  ) async {
    if (op.entityType != 'transactions') return const <String, Object?>{};
    final attributes = member['attributes'];
    if (attributes is! Map) return const <String, Object?>{};
    final legs = attributes['transactions'];
    if (legs is! List) return const <String, Object?>{};

    final written = <String, Object?>{};
    for (final leg in legs) {
      if (leg is! Map) continue;
      for (final reference in _transactionReferences) {
        final value = leg[reference.key];
        // Already numeric (a pulled row) — nothing to translate.
        if (value is! String || int.tryParse(value) != null) continue;
        final resolved = await _fireflyIdFor(reference.table, value);
        if (resolved == null) continue;
        leg[reference.key] = resolved;
        written[reference.column] = resolved;
      }
    }
    return written;
  }

  /// The `firefly_id` of local row [localId] in [table], or null when the row
  /// is unknown or has never been pushed.
  Future<String?> _fireflyIdFor(String table, String localId) async {
    final rows = await _db.query(
      table,
      columns: const ['firefly_id'],
      where: 'id = ?',
      whereArgs: [localId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['firefly_id'] as String?;
  }

  /// Stores resolved reference ids on the pushed row.
  Future<void> _applyResolvedReferences(
    String entityType,
    String entityId,
    Map<String, Object?> references,
  ) async {
    if (references.isEmpty) return;
    await _db.update(
      entityType,
      references,
      where: 'id = ?',
      whereArgs: [entityId],
    );
  }

  // -------------------------------------------------------------------------
  // Table helpers
  // -------------------------------------------------------------------------

  /// Reads the local row for [entityId] from table [entityType], or null.
  Future<Map<String, Object?>?> _fetchRow(
    String entityType,
    String entityId,
  ) async {
    final rows = await _db.query(
      entityType,
      where: 'id = ?',
      whereArgs: [entityId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// Marks a row synced after a successful push.
  ///
  /// When [fireflyId] is non-null it is also stored (the create case).
  /// [remoteUpdatedAt] is the server's `updated_at` from the response, used by
  /// the pull phase's LWW merge (DESIGN §7.3).
  Future<void> _markSynced(
    String entityType,
    String entityId, {
    String? fireflyId,
    DateTime? remoteUpdatedAt,
  }) async {
    await _db.update(
      entityType,
      {
        'firefly_id': ?fireflyId,
        'sync_status': syncStatusToRow(SyncStatus.synced),
        if (remoteUpdatedAt != null)
          'remote_updated_at': dateTimeToMillis(remoteUpdatedAt),
      },
      where: 'id = ?',
      whereArgs: [entityId],
    );
  }

  /// Hard-deletes a local row (the delete case after the server acked).
  Future<void> _hardDelete(String entityType, String entityId) async {
    await _db.delete(entityType, where: 'id = ?', whereArgs: [entityId]);
  }

  // -------------------------------------------------------------------------
  // Path mapping
  // -------------------------------------------------------------------------

  /// Collection path for a create (or an update-that-fell-back-to-create).
  ///
  /// Default rule: underscores → hyphens (`piggy_banks` → `piggy-banks`).
  /// `budget_limits` is nested under its budget: `budgets/{budget_id}/limits`.
  String _collectionPath(String entityType, Map<String, Object?> row) {
    if (entityType == 'budget_limits') {
      final budgetId = row['budget_id'] as String?;
      if (budgetId != null && budgetId.isNotEmpty) {
        return 'budgets/$budgetId/limits';
      }
    }
    return _hyphenate(entityType);
  }

  /// Item path for an update or delete (needs the server-assigned id).
  String _itemPath(
    String entityType,
    Map<String, Object?> row,
    String fireflyId,
  ) {
    if (entityType == 'budget_limits') {
      final budgetId = row['budget_id'] as String?;
      if (budgetId != null && budgetId.isNotEmpty) {
        return 'budgets/$budgetId/limits/$fireflyId';
      }
    }
    return '${_hyphenate(entityType)}/$fireflyId';
  }

  /// Default wire path: `snake_case` → `kebab-case`.
  String _hyphenate(String entityType) => entityType.replaceAll('_', '-');

  // -------------------------------------------------------------------------
  // Payload
  // -------------------------------------------------------------------------

  /// Decodes the op's stored JSON payload into the unwrapped member the API
  /// client expects (`{type, attributes}`), or null when malformed.
  Map<String, dynamic>? _decodePayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return null;
    } on FormatException {
      return null;
    }
  }
}
