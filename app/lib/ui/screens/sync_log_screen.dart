import 'package:firefly_mobile/core/providers.dart';
import 'package:firefly_mobile/data/sync/sync_engine.dart'
    show SyncLogEntry, kMaxSyncLogEntries;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// In-app sync audit trail: the last [kMaxSyncLogEntries] cycle lines,
/// newest first (P3.4 exit criterion "Sync log readable in-app").
///
/// Data comes from [syncLogProvider] (autoDispose), which reads
/// `SyncEngine.recentLog` — one `push` and one `pull` line per completed
/// cycle, pruned to 500 rows by the engine. Pull-to-refresh re-runs the
/// query so a cycle started from another screen shows up without
/// reopening this one.
class SyncLogScreen extends ConsumerStatefulWidget {
  /// Creates the sync log screen.
  // ignore: unnecessary_type_name_in_constructor — generative ctor, not redirecting.
  const SyncLogScreen({super.key});

  @override
  ConsumerState<SyncLogScreen> createState() => _SyncLogScreenState();
}

class _SyncLogScreenState extends ConsumerState<SyncLogScreen> {
  /// Re-runs the log query for pull-to-refresh.
  ///
  /// `invalidate` drops the cached rows, then we await the re-read so the
  /// refresh indicator spins until the fresh list is actually rendered.
  Future<void> _refresh() async {
    ref.invalidate(syncLogProvider);
    await ref.read(syncLogProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final logAsync = ref.watch(syncLogProvider);
    return Scaffold(
      appBar: AppBar(title: const Text(kSyncLogTitle)),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: logAsync.when(
          // Indeterminate spinner inside a scrollable so the refresh
          // gesture stays available even on the first load.
          loading: () => ListView(
            children: const [
              SizedBox(height: 160),
              Center(
                child: CircularProgressIndicator(
                  semanticsLabel: 'Loading sync log',
                ),
              ),
            ],
          ),
          error: (e, _) => ListView(
            children: [
              const SizedBox(height: 160),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 40,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Sync log unavailable: $e',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Pull down to retry.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          data: (entries) {
            if (entries.isEmpty) {
              return ListView(
                children: [
                  const SizedBox(height: 160),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.receipt_long_outlined, size: 40),
                        const SizedBox(height: 12),
                        const Text('No syncs yet'),
                        const SizedBox(height: 4),
                        Text(
                          'Run one from Settings → Sync now.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }
            return ListView.separated(
              itemCount: entries.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) =>
                  _SyncLogTile(entry: entries[index]),
            );
          },
        ),
      ),
    );
  }
}

/// One log line: icon by status, phase as the title, time + counters and
/// (when present) the failure message in the subtitle.
class _SyncLogTile extends StatelessWidget {
  /// Creates one log row.
  // ignore: unnecessary_type_name_in_constructor — generative ctor, not redirecting.
  const _SyncLogTile({required this.entry});

  /// The log row to render.
  final SyncLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final isError = entry.status == 'error';
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(
        isError ? Icons.error_outline : Icons.check_circle_outline,
        color: isError ? theme.colorScheme.error : Colors.green,
      ),
      title: Text(_phaseLabel(entry.phase)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _fmtTime(entry.startedAtMs),
            style: theme.textTheme.bodySmall,
          ),
          if (_countsLine() case final String counts)
            Text(counts, style: theme.textTheme.bodySmall),
          if (entry.error != null)
            Text(
              entry.error!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
        ],
      ),
    );
  }

  /// Human phase name; defensive capitalisation for unknown phase strings.
  static String _phaseLabel(String phase) => switch (phase) {
    'push' => 'Push',
    'pull' => 'Pull',
    _ => phase.isEmpty ? phase : phase[0].toUpperCase() + phase.substring(1),
  };

  /// Counters line for this phase, or null when the row carries none
  /// (e.g. a push line whose `pushed_ops` never got written).
  String? _countsLine() {
    if (entry.phase == 'push') {
      final ops = entry.pushedOps;
      return ops == null ? null : '$ops ops pushed';
    }
    // Backup line (P4): has no counters — the error text (when present)
    // carries all the detail; showing pull numbers here would be a lie.
    if (entry.phase == 'backup') return null;
    // Pull line: only non-zero counters, falling back to "No changes".
    final parts = <String>[
      if (entry.pullInserted case final n? when n > 0) '+$n new',
      if (entry.pullUpdated case final n? when n > 0) '~$n changed',
      if (entry.pullTombstoned case final n? when n > 0) '−$n removed',
    ];
    if (parts.isEmpty) return 'No changes';
    return parts.join(', ');
  }

  /// `yyyy-MM-dd HH:mm:ss` in local time — no intl dependency for one
  /// format string.
  static String _fmtTime(int epochMs) {
    final t = DateTime.fromMillisecondsSinceEpoch(epochMs);
    String p(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${p(t.month)}-${p(t.day)} '
        '${p(t.hour)}:${p(t.minute)}:${p(t.second)}';
  }
}

/// Route title shown in the app bar (reused by the Settings tile test).
const kSyncLogTitle = 'Sync log';
