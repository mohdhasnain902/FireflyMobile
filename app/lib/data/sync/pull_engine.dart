/// Pull-diff engine — Firefly → phone (P3.3, DESIGN §7.2–7.5).
///
/// Firefly's list endpoints have no `updated-since` filter, so a pull is a
/// full pagination of each entity type followed by a local diff:
///
/// 1. GET `/api/v1/{entity}?page=N&limit=100`, page until
///    `meta.pagination.total_pages` (the client's default `limit` is 100,
///    which is the page size DESIGN §7.2 assumes).
/// 2. For each resource: look the local row up by `firefly_id`.
///    * absent → INSERT a brand-new synced row (a server-side create).
///    * present and `sync_status == 'pending'` → **skip** (leave the unsent
///      local op for the push phase; see the ordering note below).
///    * present and `server.updated_at > local.remote_updated_at` →
///      last-writer-wins: overwrite the local row with the server copy,
///      keeping the local primary key (DESIGN §7.3).
///    * present and not newer → no change.
/// 3. Only after **every** page of the entity succeeded, tombstone the local
///    rows whose `firefly_id` is absent from the response and whose
///    `sync_status` is `synced` (server-side deletion, DESIGN §7.4 row "Server
///    row deleted on PC"). Pending rows are never tombstoned here.
///
/// Ordering note (pending before newer): DESIGN §7.2's pseudocode checks
/// "server newer" (step e) before "local pending" (step f). This engine
/// deliberately checks pending **first**. The pseudocode's ordering is only
/// safe under the intended push-then-pull orchestration, where a pending row
/// has already been flushed before pull starts (§7.3). When a push has failed
/// mid-cycle — exactly the state §7.4's "local pending + server newer" row
/// describes — the matrix's prescribed outcome is *local wins*. Checking
/// pending first delivers that outcome unconditionally and can never clobber
/// an unsent local op. The two orderings agree whenever the orchestrator's
/// push-then-pull invariant holds, and the pending-first order is the safe
/// one when it does not.
///
/// Transaction granularity: one SQLite transaction per HTTP page. A network
/// round-trip never happens inside an open write transaction (that would
/// block every other writer for the duration of the request and risk a
/// mobile OS killing the socket mid-transaction). A failure mid-entity
/// therefore leaves earlier pages merged but skips the tombstone pass — which
/// is safe, because merge is idempotent (insert-if-absent / LWW-if-newer) and
/// the next pull simply re-fetches and re-merges.
///
/// `budget_limits` has no flat list endpoint; it is nested under each budget
/// (`GET /budgets/{id}/limits`, DESIGN §7.5). The engine iterates the local
/// budgets' `firefly_id`s and merges each budget's limits into one combined
/// seen-set, tombstoning once at the end.
///
/// The engine never throws for expected conditions; failures surface as a
/// typed [Failure] inside a [Result], mirroring `OpLogPusher`.
library;

import 'package:firefly_mobile/core/errors/failure.dart';
import 'package:firefly_mobile/core/utils/id_generator.dart';
import 'package:firefly_mobile/core/utils/result.dart';
import 'package:firefly_mobile/data/api/firefly_api_client.dart';
import 'package:firefly_mobile/data/dao/device_meta_dao.dart';
import 'package:firefly_mobile/domain/entities/account.dart';
import 'package:firefly_mobile/domain/entities/bill.dart';
import 'package:firefly_mobile/domain/entities/budget.dart';
import 'package:firefly_mobile/domain/entities/budget_limit.dart';
import 'package:firefly_mobile/domain/entities/category.dart';
import 'package:firefly_mobile/domain/entities/currency.dart';
import 'package:firefly_mobile/domain/entities/piggy_bank.dart';
import 'package:firefly_mobile/domain/entities/recurrence.dart';
import 'package:firefly_mobile/domain/entities/row_codec.dart';
import 'package:firefly_mobile/domain/entities/rule.dart';
import 'package:firefly_mobile/domain/entities/rule_group.dart';
import 'package:firefly_mobile/domain/entities/subscription.dart';
import 'package:firefly_mobile/domain/entities/sync_bookkeeping.dart';
import 'package:firefly_mobile/domain/entities/tag.dart';
import 'package:firefly_mobile/domain/entities/transaction.dart';
import 'package:sqflite_common/sqlite_api.dart' hide Transaction;

/// The thirteen entity types a full pull walks, in a dependency-friendly
/// order (parents before children so a child row that references a parent
/// arrives after the parent exists locally).
///
/// `attachments` is intentionally absent: Firefly exposes no list endpoint
/// for it (DESIGN §7.5 — only per-id `GET /attachments/{id}`), so it is
/// fetched on demand, not pulled.
const List<String> kPullEntityTypes = <String>[
  'currencies',
  'accounts',
  'categories',
  'tags',
  'budgets',
  'budget_limits',
  'bills',
  'subscriptions',
  'piggy_banks',
  'rules',
  'rule_groups',
  'recurrences',
  'transactions',
];

/// Decodes one JSON:API member into the SQLite row for its table.
///
/// Every entity's `fromJsonApi` takes the same local-only bookkeeping
/// arguments (`id`, `updatedAt`, `seq`), so a single typedef covers all
/// thirteen. [id] is the *local* primary key the caller chooses (a fresh
/// UUIDv7 for an insert, the existing row's id for an LWW overwrite).
typedef PullDecoder =
    Map<String, Object?> Function(
      Map<String, dynamic> member, {
      required String id,
      required DateTime updatedAt,
      required int seq,
    });

/// Per-entity counters from one [PullEngine.pullEntity] call.
class PullEntityStats {
  /// Builds the counters, all defaulting to zero.
  const new({
    this.inserted = 0,
    this.updated = 0,
    this.skippedPending = 0,
    this.skippedUnchanged = 0,
    this.tombstoned = 0,
  });

  /// Server-side rows the phone had never seen (new local rows).
  final int inserted;

  /// Local rows overwritten by a newer server copy (LWW).
  final int updated;

  /// Local rows skipped because they still carry unsent ops.
  final int skippedPending;

  /// Local rows left alone because the server copy was not newer.
  final int skippedUnchanged;

  /// Local synced rows tombstoned because the server no longer lists them.
  final int tombstoned;

  /// Adds [other]'s counters into a new snapshot.
  PullEntityStats operator +(PullEntityStats other) => PullEntityStats(
    inserted: inserted + other.inserted,
    updated: updated + other.updated,
    skippedPending: skippedPending + other.skippedPending,
    skippedUnchanged: skippedUnchanged + other.skippedUnchanged,
    tombstoned: tombstoned + other.tombstoned,
  );

  @override
  String toString() =>
      'PullEntityStats(inserted: $inserted, updated: $updated, '
      'skippedPending: $skippedPending, skippedUnchanged: $skippedUnchanged, '
      'tombstoned: $tombstoned)';
}

/// Aggregated counters for one [PullEngine.pullAll] run.
class PullStats {
  /// Builds the aggregate from its per-entity parts.
  const new(this.entities, {this.failures = const <String, Failure>{}});

  /// Counters keyed by entity type.
  final Map<String, PullEntityStats> entities;

  /// Entity types that failed, keyed by entity type (R39).
  ///
  /// A pull no longer aborts on the first failing entity: every other entity
  /// still merges (and still tombstones what the server dropped), so one
  /// broken endpoint — a 404 from a deleted budget's limits, a 500 on a single
  /// list — cannot freeze the rest of the book. The cycle is still reported as
  /// failed through [firstFailure].
  final Map<String, Failure> failures;

  /// Whether any entity failed to pull.
  bool get hasFailures => failures.isNotEmpty;

  /// The first entity failure in pull order, or null when all pulled clean.
  Failure? get firstFailure =>
      failures.isEmpty ? null : failures.values.first;

  /// Sum of every entity's [PullEntityStats.inserted].
  int get inserted =>
      entities.values.fold(0, (sum, stats) => sum + stats.inserted);

  /// Sum of every entity's [PullEntityStats.updated].
  int get updated =>
      entities.values.fold(0, (sum, stats) => sum + stats.updated);

  /// Sum of every entity's [PullEntityStats.skippedPending].
  int get skippedPending =>
      entities.values.fold(0, (sum, stats) => sum + stats.skippedPending);

  /// Sum of every entity's [PullEntityStats.skippedUnchanged].
  int get skippedUnchanged =>
      entities.values.fold(0, (sum, stats) => sum + stats.skippedUnchanged);

  /// Sum of every entity's [PullEntityStats.tombstoned].
  int get tombstoned =>
      entities.values.fold(0, (sum, stats) => sum + stats.tombstoned);

  @override
  String toString() =>
      'PullStats(entities: ${entities.length}, inserted: $inserted, '
      'updated: $updated, tombstoned: $tombstoned)';
}

/// Diffs the server's collections against local tables (DESIGN §7.2).
class PullEngine {
  /// Builds a pull engine bound to an open SQLite connection and an API
  /// client.
  ///
  /// [db] is the same connection the repositories write through, so a merged
  /// row commits against the schema the rest of the app reads.
  new({required Database db, required this._client})
    : _db = db,
      _meta = DeviceMetaDao(db);

  final Database _db;
  final FireflyApiClient _client;
  final DeviceMetaDao _meta;

  /// Decoders for every pullable entity type, keyed by `entity_type`.
  ///
  /// `entity_type` doubles as the physical table name (DESIGN §5.1), so the
  /// same key addresses both the wire decoder and the SQLite table.
  static final Map<String, PullDecoder> _decoders = <String, PullDecoder>{
    'accounts':
        (m, {required id, required updatedAt, required seq}) =>
            Account.fromJsonApi(
              m,
              id: id,
              updatedAt: updatedAt,
              seq: seq,
            ).toRow(),
    'bills':
        (m, {required id, required updatedAt, required seq}) =>
            Bill.fromJsonApi(m, id: id, updatedAt: updatedAt, seq: seq).toRow(),
    'budgets':
        (m, {required id, required updatedAt, required seq}) =>
            Budget.fromJsonApi(
              m,
              id: id,
              updatedAt: updatedAt,
              seq: seq,
            ).toRow(),
    'budget_limits':
        (m, {required id, required updatedAt, required seq}) =>
            BudgetLimit.fromJsonApi(
              m,
              id: id,
              updatedAt: updatedAt,
              seq: seq,
            ).toRow(),
    'categories':
        (m, {required id, required updatedAt, required seq}) =>
            Category.fromJsonApi(
              m,
              id: id,
              updatedAt: updatedAt,
              seq: seq,
            ).toRow(),
    'currencies':
        (m, {required id, required updatedAt, required seq}) =>
            Currency.fromJsonApi(
              m,
              id: id,
              updatedAt: updatedAt,
              seq: seq,
            ).toRow(),
    'piggy_banks':
        (m, {required id, required updatedAt, required seq}) =>
            PiggyBank.fromJsonApi(
              m,
              id: id,
              updatedAt: updatedAt,
              seq: seq,
            ).toRow(),
    'recurrences':
        (m, {required id, required updatedAt, required seq}) =>
            Recurrence.fromJsonApi(
              m,
              id: id,
              updatedAt: updatedAt,
              seq: seq,
            ).toRow(),
    'rules':
        (m, {required id, required updatedAt, required seq}) =>
            Rule.fromJsonApi(m, id: id, updatedAt: updatedAt, seq: seq).toRow(),
    'rule_groups':
        (m, {required id, required updatedAt, required seq}) =>
            RuleGroup.fromJsonApi(
              m,
              id: id,
              updatedAt: updatedAt,
              seq: seq,
            ).toRow(),
    'subscriptions':
        (m, {required id, required updatedAt, required seq}) =>
            Subscription.fromJsonApi(
              m,
              id: id,
              updatedAt: updatedAt,
              seq: seq,
            ).toRow(),
    'tags':
        (m, {required id, required updatedAt, required seq}) =>
            Tag.fromJsonApi(m, id: id, updatedAt: updatedAt, seq: seq).toRow(),
    // Transactions are decoded per journal leg in the merge loop so split
    // groups (multiple journals) are stored correctly; this entry remains for
    // generic callers and decodes the first leg.
    'transactions':
        (m, {required id, required updatedAt, required seq}) =>
            Transaction.fromJsonApi(
              m,
              id: id,
              updatedAt: updatedAt,
              seq: seq,
            ).toRow(),
  };

  /// Pulls every entity type in [kPullEntityTypes] and aggregates the stats.
  ///
  /// An entity that fails is recorded in [PullStats.failures] and the walk
  /// continues with the next entity (R39) — merges are idempotent, so the next
  /// pull re-fetches whatever failed. This matters most for deletions: with an
  /// abort-on-first-failure walk a single broken endpoint (say the limits of a
  /// budget that was just deleted on the website) also froze every later
  /// entity, so a server-deleted account or transaction never disappeared.
  Future<Result<PullStats>> pullAll() async {
    final perEntity = <String, PullEntityStats>{};
    final failures = <String, Failure>{};
    for (final entityType in kPullEntityTypes) {
      final result = await pullEntity(entityType);
      final failure = result.failureOrNull;
      if (failure != null &&
          (failure is NetworkFailure || failure is AuthFailure)) {
        // Not an entity-specific problem: the socket is down or the token is
        // rejected, so every remaining request would fail the same way after
        // its own retry budget. Stop instead of grinding through 13 entities.
        return Err<PullStats>(failure);
      }
      if (failure != null) {
        failures[entityType] = failure;
        continue;
      }
      perEntity[entityType] = result.valueOrNull!;
    }
    return Ok<PullStats>(PullStats(perEntity, failures: failures));
  }

  /// Pulls one entity type (all pages) and returns its counters.
  ///
  /// [entityType] must be one of [kPullEntityTypes]. `budget_limits` is
  /// special-cased to walk its nested per-budget endpoint.
  Future<Result<PullEntityStats>> pullEntity(String entityType) {
    final decoder = _decoders[entityType];
    if (decoder == null) {
      return Future.value(
        Err<PullEntityStats>(
          ValidationFailure('unknown pull entity type: $entityType'),
        ),
      );
    }
    if (entityType == 'budget_limits') {
      return _pullBudgetLimits();
    }
    return _pullCollection(entityType, _hyphenate(entityType), decoder);
  }

  // -------------------------------------------------------------------------
  // Flat collection pull
  // -------------------------------------------------------------------------

  /// Paginates `GET {listPath}` and merges every page into [table].
  ///
  /// [table] doubles as the entity type (DESIGN §5.1: table name == wire
  /// type); [listPath] is the hyphenated wire path derived from it. The
  /// seen-set of server ids accumulates across pages and drives the
  /// tombstone pass.
  Future<Result<PullEntityStats>> _pullCollection(
    String table,
    String listPath,
    PullDecoder decode,
  ) async {
    final seen = <String>{};
    var inserted = 0;
    var updated = 0;
    var skippedPending = 0;
    var skippedUnchanged = 0;
    // Completeness guard for the tombstone pass: a tombstone says "the server
    // does not have this row", which is only true when the whole collection
    // was read. The signal is a **full last page** together with fewer members
    // than the server's `total`: that is what a lying `total_pages` looks like.
    //
    // A plain `received < total` must NOT count, because Firefly's own
    // `/transactions` reports `total` higher than the number of groups it
    // serialises (551 vs 549 on the reference book), which would skip the
    // deletion pass for exactly the entity where deletions matter.
    var received = 0;
    var serverTotal = 0;
    var lastPageCount = 0;
    var perPage = 100;

    var page = 1;
    var totalPages = 1;
    do {
      final listResult = await _client.list(listPath, page: page);
      final listFailure = listResult.failureOrNull;
      if (listFailure != null) {
        return Err<PullEntityStats>(listFailure);
      }
      final collection = listResult.valueOrNull!;
      received += collection.resources.length;
      lastPageCount = collection.resources.length;
      perPage = collection.pagination.perPage;
      if (collection.pagination.total > serverTotal) {
        serverTotal = collection.pagination.total;
      }

      // Merge one page atomically. The HTTP round-trip already happened
      // before this transaction opened — never hold a write lock across the
      // network (see the library doc).
      final pageResult = await _mergePage(
        table: table,
        resources: collection.resources,
        decode: decode,
        seen: seen,
      );
      final pageFailure = pageResult.failureOrNull;
      if (pageFailure != null) {
        return Err<PullEntityStats>(pageFailure);
      }
      final pageStats = pageResult.valueOrNull!;
      inserted += pageStats.inserted;
      updated += pageStats.updated;
      skippedPending += pageStats.skippedPending;
      skippedUnchanged += pageStats.skippedUnchanged;

      totalPages = collection.pagination.totalPages;
      page++;
    } while (page <= totalPages);

    // Tombstone only after every page merged successfully (DESIGN §7.2
    // step 3). A partial pull must never mark rows deleted just because a
    // later page failed.
    if (received < serverTotal && lastPageCount >= perPage) {
      return Err<PullEntityStats>(
        ServerFailure(
          'Incomplete $listPath list: received $received of $serverTotal; '
          'skipped the deletion pass so nothing is hidden by mistake.',
          code: 'pull.incomplete-list',
        ),
      );
    }
    final tombstoneResult = await _tombstoneUnseen(table, seen);
    final tombstoneFailure = tombstoneResult.failureOrNull;
    if (tombstoneFailure != null) {
      return Err<PullEntityStats>(tombstoneFailure);
    }

    return Ok<PullEntityStats>(
      PullEntityStats(
        inserted: inserted,
        updated: updated,
        skippedPending: skippedPending,
        skippedUnchanged: skippedUnchanged,
        tombstoned: tombstoneResult.valueOrNull!,
      ),
    );
  }

  /// Merges one page's resources into [table] inside a single transaction.
  ///
  /// Accumulates the server ids it processed into [seen] (which outlives the
  /// transaction — it is an in-memory set for the whole entity pull).
  Future<Result<PullEntityStats>> _mergePage({
    required String table,
    required List<ApiResource> resources,
    required PullDecoder decode,
    required Set<String> seen,
  }) async {
    var inserted = 0;
    var updated = 0;
    var skippedPending = 0;
    var skippedUnchanged = 0;

    try {
      await _db.transaction((txn) async {
        for (final resource in resources) {
          final fireflyId = resource.id;
          if (fireflyId.isEmpty) continue;

          // A Firefly transaction is a group that can contain multiple journal
          // legs (splits). Store one local row per leg so split data is not
          // dropped; other entities remain one row per resource.
          if (table == 'transactions') {
            final count = Transaction.journalCount(resource.member);
            final legs = count <= 0 ? 1 : count;
            for (var j = 0; j < legs; j++) {
              final probe = Transaction.fromJsonApi(
                resource.member,
                id: '',
                updatedAt: DateTime.now().toUtc(),
                seq: 0,
                journalIndex: j,
              );
              final journalId = probe.journalId;
              final remoteKey = (journalId != null && journalId.isNotEmpty)
                  ? journalId
                  : fireflyId;
              seen.add(remoteKey);

              final local = await _fetchTransactionRow(
                txn,
                fireflyId: fireflyId,
                journalId: journalId,
              );
              if (local == null) {
                await _insertTransactionLeg(txn, resource, j);
                inserted++;
                continue;
              }
              final localStatus = local['sync_status'] as String?;
              if (localStatus == syncStatusToRow(SyncStatus.pending)) {
                skippedPending++;
                continue;
              }
              // A legacy row (stored before legs were tracked individually)
              // carries no journal id and may hold a *different* leg's content
              // under this group's id. Adopt it for this leg and rewrite it
              // unconditionally — comparing timestamps would leave the wrong
              // leg in place and the remaining legs would keep matching it.
              // A tombstoned row that the server still lists is likewise
              // restored: the server is the authority on existence here.
              final localJournalId = local['journal_id'] as String?;
              final isLegacyRow =
                  localJournalId == null || localJournalId.isEmpty;
              final isTombstoned = local['deleted_at'] != null;
              if (isLegacyRow ||
                  isTombstoned ||
                  _isServerNewer(resource, local)) {
                await _overwriteTransactionLeg(txn, resource, j, local);
                updated++;
              } else {
                await _healStaleConflict(txn, 'transactions', local, resource);
                skippedUnchanged++;
              }
            }
            continue;
          }

          seen.add(fireflyId);

          final local = await _fetchByFireflyId(txn, table, fireflyId);
          if (local == null) {
            // Server-side row we have never seen (created on the PC or
            // another device). Insert it as already-synced (§7.2 step d).
            await _insertFromServer(txn, table, resource, decode);
            inserted++;
            continue;
          }

          // Pending check comes *before* the newer check — see the library
          // doc's "ordering note". An unsent local op is never overwritten.
          // Only `pending` blocks the merge: a `conflict` row is a row the
          // server already won on a previous pull (P3.5.2), and LWW stays
          // deterministic — a *newer* server copy must still be allowed to
          // overwrite it (and remain `conflict`), or the row would freeze
          // at its first conflict forever.
          final localStatus = local['sync_status'] as String?;
          if (localStatus == syncStatusToRow(SyncStatus.pending)) {
            skippedPending++;
            continue;
          }

          if (_isServerNewer(resource, local)) {
            await _overwriteFromServer(txn, table, resource, local, decode);
            updated++;
          } else {
            await _healStaleConflict(txn, table, local, resource);
            skippedUnchanged++;
          }
        }
      });
    } on DatabaseException catch (e) {
      return Err<PullEntityStats>(StorageFailure(e.toString()));
    }

    return Ok<PullEntityStats>(
      PullEntityStats(
        inserted: inserted,
        updated: updated,
        skippedPending: skippedPending,
        skippedUnchanged: skippedUnchanged,
      ),
    );
  }

  /// Finds the local row that represents one journal leg.
  ///
  /// A leg's identity is its server journal id, which is unique across every
  /// transaction group, so it is looked up on its own rather than paired with
  /// the group id (an older build stored the first leg's journal id on a row
  /// keyed by the group id).
  ///
  /// Only when no row carries this journal id does the lookup fall back to a
  /// *legacy* row for the group — one with no journal id at all. Rows that
  /// already belong to another leg are never reused: doing so collapsed every
  /// leg of a split group onto one row and silently dropped the rest.
  Future<Map<String, Object?>?> _fetchTransactionRow(
    DatabaseExecutor executor, {
    required String fireflyId,
    String? journalId,
  }) async {
    if (journalId != null && journalId.isNotEmpty) {
      final rows = await executor.query(
        'transactions',
        columns: [
          'id',
          'firefly_id',
          'journal_id',
          'remote_updated_at',
          'sync_status',
          'deleted_at',
        ],
        where: 'journal_id = ?',
        whereArgs: [journalId],
        limit: 1,
      );
      if (rows.isNotEmpty) return rows.first;
    }
    final rows = await executor.query(
      'transactions',
      columns: [
        'id',
        'firefly_id',
        'journal_id',
        'remote_updated_at',
        'sync_status',
        'deleted_at',
      ],
      where: "firefly_id = ? AND (journal_id IS NULL OR journal_id = '')",
      whereArgs: [fireflyId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<String> _insertTransactionLeg(
    DatabaseExecutor txn,
    ApiResource resource,
    int journalIndex,
  ) async {
    final seq = await _meta.nextSeqIn(txn);
    final localId = newEntityId();
    final row = Transaction.fromJsonApi(
      resource.member,
      id: localId,
      updatedAt: DateTime.now().toUtc(),
      seq: seq,
      journalIndex: journalIndex,
    ).toRow();
    row['firefly_id'] = resource.id;
    row['sync_status'] = syncStatusToRow(SyncStatus.synced);
    if (resource.updatedAt != null) {
      row['remote_updated_at'] = dateTimeToMillis(resource.updatedAt);
    }
    await txn.insert(
      'transactions',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return localId;
  }

  Future<void> _overwriteTransactionLeg(
    DatabaseExecutor txn,
    ApiResource resource,
    int journalIndex,
    Map<String, Object?> local,
  ) async {
    final seq = await _meta.nextSeqIn(txn);
    final row = Transaction.fromJsonApi(
      resource.member,
      id: local['id']! as String,
      updatedAt: DateTime.now().toUtc(),
      seq: seq,
      journalIndex: journalIndex,
    ).toRow();
    row['firefly_id'] = resource.id;
    // A server-won overwrite is only a "conflict" when it actually replaced
    // different local content (P3.5.2). Rewriting an identical row — e.g. the
    // first pull after a column was added, which forces one full re-merge —
    // must leave the leg looking like the ordinary synced row it is, or the
    // whole book ends up badged red for no reason.
    final stored = await _fetchRowById(txn, 'transactions', local['id']! as String);
    final contentChanged = stored == null ||
        stored['deleted_at'] != null ||
        !_sameContent(row, stored);
    row['sync_status'] = syncStatusToRow(
      contentChanged ? SyncStatus.conflict : SyncStatus.synced,
    );
    row['deleted_at'] = null;
    if (resource.updatedAt != null) {
      row['remote_updated_at'] = dateTimeToMillis(resource.updatedAt);
    }
    await txn.insert(
      'transactions',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Columns the sync engine owns on every row; everything else is content
  /// that arrives from the server.
  static const Set<String> _bookkeepingColumns = {
    'id',
    'firefly_id',
    'seq',
    'updated_at',
    'remote_updated_at',
    'sync_status',
    'deleted_at',
  };

  /// True when [incoming] carries the same content as the stored row — every
  /// column except the sync bookkeeping ones.
  static bool _sameContent(
    Map<String, Object?> incoming,
    Map<String, Object?> stored,
  ) {
    for (final entry in incoming.entries) {
      if (_bookkeepingColumns.contains(entry.key)) continue;
      if ((entry.value?.toString() ?? '') !=
          (stored[entry.key]?.toString() ?? '')) {
        return false;
      }
    }
    return true;
  }

  /// Reads the full stored row with primary key [id], or null.
  Future<Map<String, Object?>?> _fetchRowById(
    DatabaseExecutor executor,
    String table,
    String id,
  ) async {
    final rows = await executor.query(
      table,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// Clears a stale `conflict` badge.
  ///
  /// A row badged `conflict` whose stored `remote_updated_at` equals the
  /// timestamp the server still reports was written from exactly this server
  /// version, so the row and the server already agree and the "resolved by
  /// server" badge is meaningless: the pull leaves the content alone, and only
  /// the status needs repairing. Without this the badge survives forever (the
  /// pull never sees a strictly newer copy), which is how a forced full
  /// re-merge once badged an entire book red.
  Future<void> _healStaleConflict(
    DatabaseExecutor executor,
    String table,
    Map<String, Object?> local,
    ApiResource resource,
  ) async {
    if (local['sync_status'] != syncStatusToRow(SyncStatus.conflict)) return;
    final serverUpdatedAt = resource.updatedAt;
    if (serverUpdatedAt == null) return;
    if (local['remote_updated_at'] != dateTimeToMillis(serverUpdatedAt)) {
      return;
    }
    await executor.update(
      table,
      {'sync_status': syncStatusToRow(SyncStatus.synced)},
      where: 'id = ?',
      whereArgs: [local['id']! as String],
    );
  }

  /// Reads the local row whose `firefly_id` is [fireflyId], or null.
  Future<Map<String, Object?>?> _fetchByFireflyId(
    DatabaseExecutor executor,
    String table,
    String fireflyId,
  ) async {
    final rows = await executor.query(
      table,
      columns: ['id', 'firefly_id', 'remote_updated_at', 'sync_status'],
      where: 'firefly_id = ?',
      whereArgs: [fireflyId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// True when the server's `updated_at` is strictly newer than the local
  /// row's stored `remote_updated_at`.
  ///
  /// A local row with a null `remote_updated_at` (never pushed) counts as
  /// older than any server timestamp, because the server has a definite time
  /// and the phone has none. A server resource with no parseable
  /// `updated_at` is never treated as newer — we cannot order against it, so
  /// the local copy stands (DESIGN §7.2 step e requires a comparison).
  bool _isServerNewer(ApiResource resource, Map<String, Object?> local) {
    final serverUpdatedAt = resource.updatedAt;
    if (serverUpdatedAt == null) return false;
    final localRemote = millisToDateTime(local['remote_updated_at'] as int?);
    if (localRemote == null) return true;
    return serverUpdatedAt.isAfter(localRemote);
  }

  /// Inserts a brand-new synced row decoded from [resource] and returns the
  /// local primary key it was stored under.
  ///
  /// The local primary key is a fresh UUIDv7; `seq` is allocated from the
  /// device counter so the row's bookkeeping stays consistent with every
  /// other local write (DESIGN §6.6). A `recurrences` insert also rewrites
  /// its child schedule rows (see [_rewriteRepetitionsFromWire]).
  Future<String> _insertFromServer(
    DatabaseExecutor txn,
    String table,
    ApiResource resource,
    PullDecoder decode,
  ) async {
    final seq = await _meta.nextSeqIn(txn);
    final localId = newEntityId();
    final row = decode(
      resource.member,
      id: localId,
      updatedAt: DateTime.now().toUtc(),
      seq: seq,
    );
    // Guarantee the three bookkeeping columns the decoder does not own: the
    // local primary key (already set by `decode`, repeated here only as a
    // safety net), the server id and the synced status.
    row['firefly_id'] = resource.id;
    row['sync_status'] = syncStatusToRow(SyncStatus.synced);
    if (resource.updatedAt != null) {
      row['remote_updated_at'] = dateTimeToMillis(resource.updatedAt);
    }
    await txn.insert(
      table,
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _rewriteRepetitionsFromWire(txn, resource, localId);
    return localId;
  }

  /// Rewrites `recurrence_repetitions` children from the wire after a
  /// `recurrences` parent row was written — no-op for every other table.
  ///
  /// Repetitions are not an independent synced entity: they ride inside the
  /// parent's wire `repetitions[]` and are owned entirely by the parent
  /// (schema.dart). The DAO rewrites them on every content write, but pull
  /// merges through raw row inserts whose decoded map (`toRow()`) carries no
  /// child rows — without this rewrite an inserted recurrence would land with
  /// no schedule at all, an LWW overwrite would keep the *stale* children,
  /// and a restore (wipe + pull) would resurrect every recurrence with an
  /// empty schedule.
  ///
  /// [localId] keys the children; on an overwrite it is the preserved local
  /// primary key. Wholesale delete+reinsert mirrors RecurrenceDao: the wire
  /// array is the complete schedule, so any child absent from it is gone.
  Future<void> _rewriteRepetitionsFromWire(
    DatabaseExecutor txn,
    ApiResource resource,
    String localId,
  ) async {
    // fromJsonApi's updatedAt/seq are unused by repetition rows (no
    // bookkeeping columns on the child table) — they exist only to satisfy
    // the shared decoder signature.
    final parent = Recurrence.fromJsonApi(
      resource.member,
      id: localId,
      updatedAt: DateTime.now().toUtc(),
      seq: 0,
    );
    await txn.delete(
      'recurrence_repetitions',
      where: 'recurrence_id = ?',
      whereArgs: [localId],
    );
    if (parent.repetitions.isNotEmpty) {
      final rows = parent.repetitionRows();
      for (final child in rows) {
        await txn.insert('recurrence_repetitions', child);
      }
    }
  }

  /// Overwrites an existing row with the server copy (LWW, DESIGN §7.3),
  /// keeping the local primary key.
  ///
  /// A fresh `seq` is allocated so the row's content version moves forward
  /// even though no local op produced it — the counter must stay strictly
  /// increasing (DESIGN §6.6). `sync_status` becomes `conflict` (P3.5.2):
  /// the server won this row, and the UI surfaces that as the informational
  /// "resolved by server" badge until the row is next pushed (a local edit
  /// flips it back through pending → synced). `remote_updated_at` records
  /// the server time the copy came from, which is what the *next* pull
  /// compares against.
  Future<void> _overwriteFromServer(
    DatabaseExecutor txn,
    String table,
    ApiResource resource,
    Map<String, Object?> local,
    PullDecoder decode,
  ) async {
    final seq = await _meta.nextSeqIn(txn);
    final row = decode(
      resource.member,
      id: local['id']! as String,
      updatedAt: DateTime.now().toUtc(),
      seq: seq,
    );
    row['firefly_id'] = resource.id;
    // P3.5.2 badges a server-won overwrite `conflict`, but only when it really
    // replaced different content — see [_overwriteTransactionLeg].
    final stored = await _fetchRowById(txn, table, local['id']! as String);
    final contentChanged = stored == null ||
        stored['deleted_at'] != null ||
        !_sameContent(row, stored);
    row['sync_status'] = syncStatusToRow(
      contentChanged ? SyncStatus.conflict : SyncStatus.synced,
    );
    // An LWW overwrite from the server clears any tombstone: the server
    // still has the row and its copy is newer, so it outranks a local
    // soft-delete that was never pushed.
    row['deleted_at'] = null;
    if (resource.updatedAt != null) {
      row['remote_updated_at'] = dateTimeToMillis(resource.updatedAt);
    }
    await txn.insert(
      table,
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _rewriteRepetitionsFromWire(txn, resource, local['id']! as String);
  }

  // -------------------------------------------------------------------------
  // Tombstone pass
  // -------------------------------------------------------------------------

  /// Tombstones every local row of [table] whose server copy is gone.
  ///
  /// Returns the number of local rows that stopped being visible (tombstoned
  /// or removed). A row is a candidate when it carries a `firefly_id` (the
  /// server once had it) and the server no longer lists it:
  ///
  /// * `synced` → soft-deleted: the server dropped it, so the phone hides it
  ///   too (DESIGN §7.4 row "Server row deleted on PC"). No op is queued, the
  ///   server already performed the delete.
  /// * `conflict` → same treatment (R40). The badge only says "the server won a
  ///   previous overwrite"; it must not make a deleted row immortal.
  /// * `pending` → the queued op can never succeed, so it is resolved here
  ///   instead of wedging every future push: the row is removed (`DELETE`, so a
  ///   half-pushed tombstone cannot linger) together with its `op_log` entries
  ///   (R40). A pending row **without** a `firefly_id` is a local-only create
  ///   and is never touched — the server has never heard of it.
  ///
  /// For transactions, [seen] contains journal ids (one per leg) so missing
  /// split legs/groups can be tombstoned precisely.
  Future<Result<int>> _tombstoneUnseen(String table, Set<String> seen) async {
    try {
      return await _db.transaction((txn) async {
        final columns = table == 'transactions'
            ? ['id', 'firefly_id', 'journal_id', 'sync_status', 'deleted_at']
            : ['id', 'firefly_id', 'sync_status', 'deleted_at'];
        // Pending rows are candidates too — including one already tombstoned
        // locally whose delete has not been pushed (deleted_at != null): the
        // server row is gone, so the push is moot.
        final localRows = await txn.query(
          table,
          columns: columns,
          where:
              "firefly_id IS NOT NULL "
              "AND (deleted_at IS NULL OR sync_status = 'pending')",
        );
        var tombstoned = 0;
        final nowMillis = DateTime.now().toUtc().millisecondsSinceEpoch;
        for (final local in localRows) {
          final fireflyId = local['firefly_id']! as String;
          String remoteKey = fireflyId;
          if (table == 'transactions') {
            final journalId = local['journal_id'] as String?;
            if (journalId != null && journalId.isNotEmpty) {
              remoteKey = journalId;
            }
          }
          if (seen.contains(remoteKey)) continue;
          final localId = local['id']! as String;
          if (local['sync_status'] == syncStatusToRow(SyncStatus.pending)) {
            await txn.delete(table, where: 'id = ?', whereArgs: [localId]);
            await txn.delete(
              'op_log',
              where: 'entity_type = ? AND entity_id = ?',
              whereArgs: [table, localId],
            );
            tombstoned++;
            continue;
          }
          await txn.update(
            table,
            {'deleted_at': nowMillis},
            where: 'id = ?',
            whereArgs: [localId],
          );
          tombstoned++;
        }
        return Ok<int>(tombstoned);
      });
    } on DatabaseException catch (e) {
      return Err<int>(StorageFailure(e.toString()));
    }
  }

  // -------------------------------------------------------------------------
  // Nested budget_limits pull
  // -------------------------------------------------------------------------

  /// Pulls `budget_limits` by walking each local budget's nested endpoint.
  ///
  /// Firefly exposes no flat `/budget-limits` list (DESIGN §7.5): limits live
  /// under their budget. The engine reads every local budget's `firefly_id`,
  /// paginates `budgets/{budgetFireflyId}/limits` for each, and merges all of
  /// them into the `budget_limits` table against one combined seen-set so the
  /// tombstone pass at the end sees every limit the server still lists.
  ///
  /// A budget with no `firefly_id` (never pushed) has no server id to address
  /// and is skipped — its limits cannot exist server-side yet.
  Future<Result<PullEntityStats>> _pullBudgetLimits() async {
    final decode = _decoders['budget_limits']!;
    final budgetRows = await _db.query(
      'budgets',
      columns: ['firefly_id'],
      where: 'firefly_id IS NOT NULL',
    );
    final budgetFireflyIds = budgetRows
        .map((row) => row['firefly_id']! as String)
        .toList();

    final seen = <String>{};
    var inserted = 0;
    var updated = 0;
    var skippedPending = 0;
    var skippedUnchanged = 0;

    for (final budgetFireflyId in budgetFireflyIds) {
      final listPath = 'budgets/$budgetFireflyId/limits';
      var page = 1;
      var totalPages = 1;
      do {
        final listResult = await _client.list(listPath, page: page);
        final listFailure = listResult.failureOrNull;
        if (listFailure is NotFoundFailure) {
          // The budget itself is gone server-side: its limits went with it, and
          // the budgets pull already tombstoned the parent. Aborting the whole
          // pull over a deleted parent was how one website-side delete could
          // freeze every later entity (R39).
          break;
        }
        if (listFailure != null) {
          return Err<PullEntityStats>(listFailure);
        }
        final collection = listResult.valueOrNull!;

        final pageResult = await _mergePage(
          table: 'budget_limits',
          resources: collection.resources,
          decode: decode,
          seen: seen,
        );
        final pageFailure = pageResult.failureOrNull;
        if (pageFailure != null) {
          return Err<PullEntityStats>(pageFailure);
        }
        final pageStats = pageResult.valueOrNull!;
        inserted += pageStats.inserted;
        updated += pageStats.updated;
        skippedPending += pageStats.skippedPending;
        skippedUnchanged += pageStats.skippedUnchanged;

        totalPages = collection.pagination.totalPages;
        page++;
      } while (page <= totalPages);
    }

    final tombstoneResult = await _tombstoneUnseen('budget_limits', seen);
    final tombstoneFailure = tombstoneResult.failureOrNull;
    if (tombstoneFailure != null) {
      return Err<PullEntityStats>(tombstoneFailure);
    }

    return Ok<PullEntityStats>(
      PullEntityStats(
        inserted: inserted,
        updated: updated,
        skippedPending: skippedPending,
        skippedUnchanged: skippedUnchanged,
        tombstoned: tombstoneResult.valueOrNull!,
      ),
    );
  }

  /// Wire path: `snake_case` → `kebab-case` (`piggy_banks` → `piggy-banks`).
  ///
  /// Same rule the pusher uses (DESIGN §6.3), so list and item paths always
  /// agree.
  String _hyphenate(String entityType) => entityType.replaceAll('_', '-');
}
