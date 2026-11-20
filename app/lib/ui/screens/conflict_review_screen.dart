/// Conflict review screen (P5.4 — conflict resolution UI).
///
/// Lists every local row whose `sync_status='conflict'` across all entity
/// tables, so the user can review server-won LWW overwrites and dismiss
/// conflicts they accept. Conflict rows are informational by design
/// (DESIGN §7.4, P3.5.2): the server's copy is already stored locally and the
/// badge says "Resolved by server". This screen makes conflicts visible and
/// gives the user a one-tap dismiss per row.
///
/// Data access is via raw SQL on the shared connection — each business table
/// carries `sync_status`, so a single query per table collects all conflicts.
/// Tapping a row navigates to [ConflictDetailScreen], which shows the row's
/// current (server-won) fields read-only; a "Dismiss conflict" button flips
/// `sync_status` back to `'synced'` and re-queues nothing (the server already
/// won — there is nothing to push).
///
/// Pure Dart + Flutter/Riverpod. The database is injected through
/// [databaseProvider] so widget tests can override it with an in-memory DB.
library;

import 'dart:async';

import 'package:firefly_mobile/core/providers.dart';
import 'package:firefly_mobile/domain/entities/sync_bookkeeping.dart';
import 'package:firefly_mobile/ui/widgets/sync_badge.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common/sqlite_api.dart';

/// One conflict row's identity across all entity tables.
class ConflictEntry {
  /// Creates a conflict row identity for one table row.
  const new({
    required this.entityType,
    required this.localId,
    required this.fireflyId,
    required this.rowTitle,
    required this.updatedAtMs,
  });

  /// The table name, also the `entity_type` used in op_log and pull decoders.
  final String entityType;

  /// Local primary key (UUIDv7).
  final String localId;

  /// Server-assigned id (null if never pushed — conflicts can't be local-only,
  /// but the column exists for completeness).
  final String? fireflyId;

  /// Human-readable row title.
  final String rowTitle;

  /// Epoch-ms of `updated_at` (local last-write time).
  final int updatedAtMs;
}

/// All business tables that carry `sync_status`, in dependency-friendly order
/// (parents before children).
///
/// `currencies` is pull-only and always `synced`; it is omitted because it
/// can never conflict. `attachments` is included.
const List<String> kConflictTables = <String>[
  'accounts',
  'categories',
  'tags',
  'budgets',
  'bills',
  'subscriptions',
  'piggy_banks',
  'rules',
  'rule_groups',
  'recurrences',
  'transactions',
  'attachments',
  'budget_limits',
];

/// Reviews every conflict row across all entity tables.
class ConflictReviewScreen extends ConsumerWidget {
  /// Creates the conflict review screen.
  const new({super.key});

  /// Queries every conflict table for rows where `sync_status='conflict'`,
  /// returning them newest-first by `updated_at`.
  ///
  /// Each table's title column differs (`name`, `title`, `tag`, `filename`,
  /// …), so we only read `id`/`firefly_id`/`updated_at` and use the entity
  /// type + id as the display label. The detail screen reads the full row.
  static Future<List<ConflictEntry>> loadAll(Database db) async {
    final entries = <ConflictEntry>[];
    for (final table in kConflictTables) {
      final rows = await db.query(
        table,
        columns: ['id', 'firefly_id', 'updated_at'],
        where: "sync_status = 'conflict' AND deleted_at IS NULL",
        orderBy: 'updated_at DESC',
      );
      for (final row in rows) {
        entries.add(ConflictEntry(
          entityType: table,
          localId: row['id']! as String,
          fireflyId: row['firefly_id'] as String?,
          rowTitle:
              '${table[0].toUpperCase()}${table.substring(1)} '
              '#${row['id']! as String}',
          updatedAtMs: row['updated_at']! as int,
        ));
      }
    }
    entries.sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
    return entries;
  }

  /// Dismisses one conflict: flips `sync_status` back to `'synced'` so the
  /// badge clears. No op is queued — the server already won.
  static Future<void> dismiss(
    Database db,
    String entityType,
    String localId,
  ) async {
    await db.update(
      entityType,
      {'sync_status': 'synced'},
      where: 'id = ?',
      whereArgs: [localId],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dbAsync = ref.watch(databaseProvider.future);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Conflicts'),
        actions: [
          // Refresh: re-query all tables.
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(databaseProvider),
          ),
        ],
      ),
      body: _ConflictListView(
        databaseProvider: dbAsync,
        ref: ref,
        onRefresh: () => ref.invalidate(databaseProvider),
      ),
      floatingActionButton: const _ConflictDoneButton(),
    );
  }
}

/// The list view of conflict rows, rebuilt when the database changes.
class _ConflictListView extends ConsumerWidget {
  const new({
    required this.databaseProvider,
    required this.ref,
    required this.onRefresh,
  });

  final Future<Database> databaseProvider;
  final WidgetRef ref;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<Database>(
      future: databaseProvider,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final db = snapshot.data!;
        return FutureBuilder<List<ConflictEntry>>(
          future: ConflictReviewScreen.loadAll(db),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final conflicts = snapshot.data ?? <ConflictEntry>[];
            if (conflicts.isEmpty) {
              return const _NoConflictsView();
            }
            return ListView.builder(
              itemCount: conflicts.length,
              itemBuilder: (context, index) {
                final c = conflicts[index];
                return _ConflictRow(
                  entry: c,
                  db: db,
                  onDismiss: () async {
                    await ConflictReviewScreen.dismiss(
                      db,
                      c.entityType,
                      c.localId,
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content:
                              Text('Conflict dismissed: ${c.rowTitle}'),
                        ),
                      );
                    }
                  },
                  onTap: () async {
                    final result = await Navigator.of(context).push<bool>(
                      MaterialPageRoute<bool>(
                        builder: (_) => ConflictDetailScreen(
                          db: db,
                          entityType: c.entityType,
                          localId: c.localId,
                          fireflyId: c.fireflyId,
                          rowTitle: c.rowTitle,
                        ),
                      ),
                    );
                    if (result == true && context.mounted) {
                      // Detail screen dismissed the conflict; refresh.
                      onRefresh();
                    }
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

/// Done button shown in the floating action button slot.
class _ConflictDoneButton extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      heroTag: 'conflict-fab',
      onPressed: () => Navigator.of(context).pop(),
      icon: const Icon(Icons.close),
      label: const Text('Done'),
    );
  }
}

/// One conflict row in the list: entity icon, title, sync badge, dismiss.
class _ConflictRow extends StatelessWidget {
  const new({
    required this.entry,
    required this.db,
    required this.onDismiss,
    required this.onTap,
  });

  final ConflictEntry entry;
  final Database db;
  final VoidCallback onDismiss;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading:
          const Icon(Icons.warning_amber_rounded, color: Colors.amber),
      title: Text(
        entry.rowTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${entry.entityType} · ${entry.fireflyId ?? 'local-only'}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SyncBadge(status: SyncStatus.conflict),
          IconButton(
            tooltip: 'Dismiss conflict',
            icon: const Icon(Icons.check_circle_outline),
            onPressed: onDismiss,
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}

/// Empty state when no conflicts exist.
class _NoConflictsView extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, size: 72, color: Colors.green),
          const SizedBox(height: 16),
          Text(
            'No conflicts',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'All local rows match the server. '
            'Conflicts appear here when a server edit wins LWW.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

/// Read-only detail of one conflict row: current (server-won) fields.
///
/// The user can read what the server stored and tap "Dismiss conflict" to
/// clear the badge. Editing local-vs-server field overrides is deferred
/// (DESIGN §4.4: single-user app, LWW is almost always what the user wants).
class ConflictDetailScreen extends ConsumerStatefulWidget {
  /// Creates the read-only detail screen for one conflict row.
  const new({
    required this.db,
    required this.entityType,
    required this.localId,
    required this.fireflyId,
    required this.rowTitle,
    super.key,
  });

  /// Shared database handle used to re-read the row.
  final Database db;

  /// Table name carrying the row (also the `entity_type` in op_log).
  final String entityType;

  /// Local primary key (UUIDv7) of the row.
  final String localId;

  /// Server-assigned id, null if the row was never pushed.
  final String? fireflyId;

  /// Human-readable row title shown in the app bar.
  final String rowTitle;

  @override
  ConsumerState<ConflictDetailScreen> createState() =>
      _ConflictDetailScreenState();
}

class _ConflictDetailScreenState extends ConsumerState<ConflictDetailScreen> {
  Map<String, Object?>? _row;

  @override
  void initState() {
    super.initState();
    // Fire-and-forget initial load; errors surface via the spinner state.
    unawaited(_load());
  }

  Future<void> _load() async {
    final rows = await widget.db.query(
      widget.entityType,
      where: 'id = ?',
      whereArgs: [widget.localId],
      limit: 1,
    );
    if (!mounted) return;
    setState(() => _row = rows.isEmpty ? null : rows.first);
  }

  Future<void> _dismiss() async {
    await ConflictReviewScreen.dismiss(
      widget.db,
      widget.entityType,
      widget.localId,
    );
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    if (_row == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Conflict')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final row = _row!;

    return Scaffold(
      appBar: AppBar(
        title: Text('Conflict: ${widget.rowTitle}'),
        actions: [
          TextButton(
            onPressed: _dismiss,
            child: const Text('Dismiss conflict'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            title: const Text('Entity'),
            subtitle: Text(widget.entityType),
          ),
          ListTile(
            title: const Text('Local id'),
            subtitle: Text(widget.localId),
          ),
          if (widget.fireflyId != null)
            ListTile(
              title: const Text('Server id'),
              subtitle: Text(widget.fireflyId!),
            ),
          const Divider(),
          ...row.entries
              .where((e) => e.key != 'id')
              .map((e) => ListTile(
                    title: Text(e.key.replaceAll('_', ' ')),
                    subtitle: Text(
                      e.value == null ? '—' : e.value.toString(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )),
        ],
      ),
    );
  }
}
