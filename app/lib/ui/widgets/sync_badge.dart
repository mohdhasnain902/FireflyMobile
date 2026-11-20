import 'package:firefly_mobile/domain/entities/sync_bookkeeping.dart';

import 'package:flutter/material.dart';

/// Per-row sync state chip shown on every entity list row (P2.2.5).
///
/// Purely informational: it maps [SyncStatus] onto an icon + colour and is
/// never interactive. The three states are the ones DESIGN §5.1 defines —
/// `pending` (local write not yet acknowledged), `synced` (server
/// confirmed), `conflict` (field-level merge happened during pull).
class SyncBadge extends StatelessWidget {
  /// Renders the badge for one row's [status].
  const new({required this.status, super.key});

  /// The row's lifecycle state.
  final SyncStatus status;

  /// Icon for the status — clock/check/warning as per the P2.2.5 spec.
  IconData get _icon => switch (status) {
    SyncStatus.pending => Icons.schedule,
    SyncStatus.synced => Icons.check_circle_outline,
    SyncStatus.conflict => Icons.warning_amber_outlined,
  };

  /// Colour for the status — amber/green/red so state reads at a glance.
  Color get _color => switch (status) {
    SyncStatus.pending => Colors.amber,
    SyncStatus.synced => Colors.green,
    SyncStatus.conflict => Colors.red,
  };

  /// Human-readable status for semantics (screen readers) and tests.
  ///
  /// `conflict` reads "Resolved by server" (P3.5.2 plan wording): the merge
  /// already happened during pull and is informational only — the user does
  /// not need to do anything, and a bare "Conflict" oversells the drama.
  String get _label => switch (status) {
    SyncStatus.pending => 'Pending sync',
    SyncStatus.synced => 'Synced',
    SyncStatus.conflict => 'Resolved by server',
  };

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: _label,
      child: Icon(_icon, size: 18, color: _color, semanticLabel: _label),
    );
  }
}
