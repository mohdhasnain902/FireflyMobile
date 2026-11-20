import 'package:firefly_mobile/core/providers.dart';
import 'package:firefly_mobile/core/sync_status.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// App-bar sync status chip (P2.3, DESIGN §3.2).
///
/// Watches syncStatusProvider and renders connection state + last-sync age
/// + pending op count. The manual "Sync now" action lives in Settings;
/// this indicator stays visible in the app bar so sync state (including
/// in-progress syncing) is always apparent.
///
/// The only Riverpod touchpoint in the home shell: HomeScreen itself stays
/// free of providers (the P0 smoke test still pumps FireflyApp bare; the
/// scope now lives inside FireflyApp so this widget always finds one).
class SyncStatusIndicator extends ConsumerWidget {
  /// Creates the app-bar indicator.
  const new({super.key});

  /// Compact relative age: "just now", "5m ago", "2h ago", else "Nd ago".
  static String formatAge(int tsMs, {DateTime? now}) {
    final diff = (now ?? DateTime.now()).difference(
      DateTime.fromMillisecondsSinceEpoch(tsMs),
    );
    if (diff.isNegative) return 'just now';
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  /// Icon per state — mirrors DESIGN §3.2: grey off, amber backlog, green ok,
  /// red error.
  static IconData iconFor(SyncState state) => switch (state) {
    SyncState.never => Icons.cloud_off,
    SyncState.pending => Icons.cloud_upload,
    SyncState.synced => Icons.cloud_done,
    SyncState.error => Icons.sync_problem,
  };

  /// Colour per state (grey/amber/green/red).
  static Color colorFor(SyncState state) => switch (state) {
    SyncState.never => Colors.grey,
    SyncState.pending => Colors.amber,
    SyncState.synced => Colors.green,
    SyncState.error => Colors.red,
  };

  /// Tooltip / semantics text: state summary plus ages and backlog.
  static String labelFor(AppSyncStatus s) {
    final age = s.lastSyncTsMs == null ? 'never' : formatAge(s.lastSyncTsMs!);
    return switch (s.state) {
      SyncState.never => 'Never synced',
      SyncState.pending =>
        '${s.pendingOps} pending · last sync $age',
      SyncState.synced => 'Synced · last sync $age',
      SyncState.error => 'Sync error · last sync $age',
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(syncStatusProvider);
    // Loading and provider errors must never break the app bar: render a
    // neutral placeholder instead (offline-first rule — no spinner hostage).
    return async.when(
      loading: () => const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      error: (_, _) => const Tooltip(
        message: 'Sync status unavailable',
        child: Icon(
          Icons.cloud_off,
          size: 20,
          color: Colors.grey,
          semanticLabel: 'Sync status unavailable',
        ),
      ),
      data: (status) => _StatusBar(status: status),
    );
  }
}

/// Renders one resolved [AppSyncStatus] — split out so the data path is a plain
/// widget easy to reason about.
class _StatusBar extends StatelessWidget {
  /// Creates the resolved-status bar.
  // ignore: unnecessary_type_name_in_constructor — generative ctor, not redirecting.
  const _StatusBar({required this.status});

  final AppSyncStatus status;

  @override
  Widget build(BuildContext context) {
    final state = status.state;
    final label = SyncStatusIndicator.labelFor(status);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: label,
          child: Icon(
            SyncStatusIndicator.iconFor(state),
            size: 20,
            color: SyncStatusIndicator.colorFor(state),
            semanticLabel: label,
          ),
        ),
        if (status.pendingOps > 0) ...[
          const SizedBox(width: 4),
          // Backlog count visible at a glance (tests find it by key).
          Text(
            '${status.pendingOps}',
            key: const Key('sync-pending-count'),
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ],
    );
  }
}
