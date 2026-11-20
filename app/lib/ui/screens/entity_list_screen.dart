import 'package:firefly_mobile/core/providers.dart';
import 'package:firefly_mobile/domain/entities/sync_bookkeeping.dart';
import 'package:firefly_mobile/ui/models/entity_config.dart';
import 'package:firefly_mobile/ui/screens/entity_form_screen.dart';
import 'package:firefly_mobile/ui/theme/app_theme.dart';
import 'package:firefly_mobile/ui/widgets/confirm_delete_dialog.dart';
import 'package:firefly_mobile/ui/widgets/sync_badge.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Generic list driven by an [EntityConfig] (P2.2.1, P2.2.5).
///
/// One widget serves all 14 entities: it watches the config's typed
/// `listProvider`, renders rows via `rowTitle`/`rowSubtitle` with a
/// [SyncBadge], and offers create/edit/delete only when `canWrite`. Refresh
/// re-queries SQLite (the P3 sync engine hooks onto the same invalidate).
///
/// Search filters the loaded rows client-side against title + subtitle —
/// offline-first, no query planning against SQLite needed for the ≤50-row
/// pages the list providers fetch (server pagination lands with P3 sync).
class EntityListScreen<T extends SyncBookkeeping>
    extends ConsumerStatefulWidget {
  /// Lists rows for [config].
  ///
  /// When [embedded] is true the screen skips its own [AppBar] so the
  /// bottom-nav shell can host it inside an [IndexedStack] under one
  /// shared app bar (Phase 1 redesign). The FAB and list body are
  /// unchanged.
  const new({
    required this.config,
    this.embedded = false,
    super.key,
  });

  /// The entity definition supplying provider, rows and write path.
  final EntityConfig<T> config;

  /// True when hosted inside the bottom-nav shell (no own app bar).
  final bool embedded;

  @override
  ConsumerState<EntityListScreen<T>> createState() =>
      _EntityListScreenState<T>();
}

class _EntityListScreenState<T extends SyncBookkeeping>
    extends ConsumerState<EntityListScreen<T>> {
  /// Editable search text; also drives the visible rows through `_query`.
  final TextEditingController _searchController = TextEditingController();

  /// Current (untrimmed, lowercase-compared) search query.
  String _query = '';

  /// Selected quick-filter pill: 0 = `All`, i > 0 = `config.filters[i - 1]`.
  int _filterIndex = 0;

  EntityConfig<T> get config => widget.config;

  bool get _canWrite => config.canWrite && config.repoOf != null;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Case-insensitive match of [query] against a row's visible text.
  bool _matches(T row, String query) {
    return config.rowTitle(row).toLowerCase().contains(query) ||
        config.rowSubtitle(row).toLowerCase().contains(query);
  }

  /// Pushes the generic form for [row] (edit) or a blank row (create).
  ///
  /// Popping with `true` (save happened) just re-queries — the form already
  /// invalidated the provider, but doing it here too covers external edits.
  Future<void> _openForm(BuildContext context, {T? row}) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            EntityFormScreen<T>(config: config, existing: row),
      ),
    );
    ref.invalidate(config.listProvider);
  }

  /// Confirms, soft-deletes the row, then re-queries the list.
  Future<void> _delete(BuildContext context, T row) async {
    final confirmed = await showConfirmDeleteDialog(
      context,
      singular: config.singular,
      rowTitle: config.rowTitle(row),
    );
    if (!confirmed || !context.mounted) return;
    final repo = await config.repoOf!(ref);
    await repo.softDelete(row.id);
    // The list watches this provider — invalidate so it re-queries.
    // App-bar sync badge watches this too — a soft-delete queues an op.
    ref
      ..invalidate(config.listProvider)
      ..invalidate(pendingOpsCountProvider);
  }

  @override
  Widget build(BuildContext context) {
    final rowsAsync = ref.watch(config.listProvider);
    return Scaffold(
      // Embedded mode: the shell's app bar already names the tab.
      appBar: widget.embedded
          ? null
          : AppBar(title: Text(config.title)),
      body: rowsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorView(
          message: 'Could not load ${config.title.toLowerCase()}.',
          onRetry: () => ref.invalidate(config.listProvider),
        ),
        data: (rows) {
          // Search only appears once there is something to search; the query
          // survives refreshes because it lives in this State, not the data.
          final query = _query.trim().toLowerCase();
          final filters = config.filters;
          // Pill index guards against a stale selection (config swap).
          final filterActive = filters != null &&
              _filterIndex > 0 &&
              _filterIndex <= filters.length;
          var visible = rows;
          if (query.isNotEmpty) {
            visible = visible.where((row) => _matches(row, query)).toList();
          }
          if (filterActive) {
            final test = filters[_filterIndex - 1].test;
            visible = visible.where(test).toList();
          }
          return Column(
            children: [
              if (rows.isNotEmpty)
                _SearchField(
                  controller: _searchController,
                  hint: config.searchHint ?? 'Search',
                  onChanged: (value) => setState(() => _query = value),
                  onClear: () {
                    _searchController.clear();
                    setState(() => _query = '');
                  },
                ),
              // Quick-filter pills (index 0 is always `All`).
              if (rows.isNotEmpty && filters != null)
                _FilterRow(
                  labels: [
                    'All',
                    for (final filter in filters) filter.label,
                  ],
                  selected: filterActive ? _filterIndex : 0,
                  onSelected: (index) => setState(() => _filterIndex = index),
                ),
              Expanded(
                child: _buildResults(
                  visible,
                  query,
                  hasRows: rows.isNotEmpty,
                ),
              ),
            ],
          );
        },
      ),
      // Unique hero tag per config: the home shell keeps several
      // EntityListScreens alive in ONE route (IndexedStack), and two FABs
      // with the default tag in the same PageRoute subtree throw
      // "multiple heroes that share the same tag".
      floatingActionButton: _canWrite
          ? config.fabLabel == null
              ? FloatingActionButton(
                  heroTag: 'entity-list-fab-${config.title}',
                  onPressed: () => _openForm(context),
                  child: const Icon(Icons.add),
                )
              : FloatingActionButton.extended(
                  heroTag: 'entity-list-fab-${config.title}',
                  onPressed: () => _openForm(context),
                  icon: const Icon(Icons.add),
                  label: Text(config.fabLabel!),
                )
          : null,
    );
  }

  /// Refresh + empty / no-match / populated states for the visible rows.
  Widget _buildResults(List<T> visible, String query, {required bool hasRows}) {
    if (visible.isEmpty && query.isNotEmpty) {
      return _NoMatchView(query: query.trim());
    }
    // Active filter with no hits: same view, filter label as the "query".
    final filterActive =
        hasRows && config.filters != null && _filterIndex > 0 &&
            _filterIndex <= config.filters!.length;
    if (visible.isEmpty && filterActive) {
      return _NoMatchView(query: config.filters![_filterIndex - 1].label);
    }
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(config.listProvider),
      child: visible.isEmpty
          ? _EmptyView(title: config.title)
          : config.groupLabel == null
              ? ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: visible.length,
                  itemBuilder: (context, index) =>
                      _buildRow(context, visible[index]),
                )
              : _buildGrouped(visible),
    );
  }

  /// Day-grouped list: newest-first sort + section headers + Card rows.
  ///
  /// Dart's `List.sort` is unstable, so an index list is sorted and the rows
  /// rebuilt from it — rows sharing a group label keep provider order.
  Widget _buildGrouped(List<T> visible) {
    final indices = List<int>.generate(visible.length, (i) => i);
    final compare = config.groupCompare;
    if (compare != null) {
      indices.sort((a, b) => compare(visible[a], visible[b]));
    }
    final children = <Widget>[];
    String? lastLabel;
    for (final i in indices) {
      final row = visible[i];
      final label = config.groupLabel!(row);
      if (label != lastLabel) {
        lastLabel = label;
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: FireflyPalette.textMuted,
              ),
            ),
          ),
        );
      }
      children.add(_buildRow(context, row));
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: children,
    );
  }

  /// One row: optional leading/subtitle/trailing hooks (transactions card
  /// design) — configs without hooks render exactly the old ListTile.
  Widget _buildRow(BuildContext context, T row) {
    final tile = ListTile(
      leading: config.rowLeading?.call(context, ref, row),
      title: Text(
        config.rowTitle(row),
        maxLines: config.cardRows ? 1 : null,
        overflow: config.cardRows ? TextOverflow.ellipsis : null,
      ),
      subtitle: config.rowSubtitleWidget?.call(context, ref, row) ??
          Text(
            config.rowSubtitle(row),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (config.rowTrailingWidget != null) ...[
            config.rowTrailingWidget!(context, ref, row),
            const SizedBox(width: 8),
          ],
          SyncBadge(status: row.syncStatus),
          if (_canWrite)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (action) async {
                if (action == 'edit') {
                  await _openForm(context, row: row);
                } else if (action == 'delete') {
                  await _delete(context, row);
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
        ],
      ),
      // Read-only entities open the form in view mode; writable ones edit.
      onTap: () => _openForm(context, row: row),
    );
    if (!config.cardRows) return tile;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: tile,
    );
  }
}

/// Search input pinned above the results; clear button appears with text.
class _SearchField extends StatelessWidget {
  const new({
    required this.controller,
    required this.onChanged,
    required this.onClear,
    this.hint = 'Search',
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.search),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  key: const Key('clear-search'),
                  icon: const Icon(Icons.clear),
                  onPressed: onClear,
                ),
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

/// Horizontal quick-filter pills (`All` + config filter labels).
///
/// The theme's ChoiceChip already matches the mockup: stadium shape, lime
/// selected fill with dark label, `showCheckmark: false`.
class _FilterRow extends StatelessWidget {
  const new({
    required this.labels,
    required this.selected,
    required this.onSelected,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < labels.length; i++)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(labels[i]),
                  selected: selected == i,
                  onSelected: (_) => onSelected(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Centred "no matches" view; pull-to-refresh stays available.
class _NoMatchView extends StatelessWidget {
  const new({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: 320,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.search_off_outlined, size: 48),
                const SizedBox(height: 12),
                Text('No matches for "$query"'),
                const SizedBox(height: 4),
                const Text(
                  'Pull down to refresh',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Centred empty-state view with a hint to create the first row.
class _EmptyView extends StatelessWidget {
  const new({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: 320,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.inbox_outlined, size: 48),
                const SizedBox(height: 12),
                Text('No $title yet'),
                const SizedBox(height: 4),
                const Text(
                  'Pull down to refresh',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Centred error view with a retry action.
class _ErrorView extends StatelessWidget {
  const new({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48),
          const SizedBox(height: 12),
          Text(message),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
