import 'dart:async';

import 'package:firefly_mobile/core/providers.dart';
import 'package:firefly_mobile/data/sync/sync_controller.dart';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Debounced lifecycle auto-trigger for sync (P3.4.2).
///
/// Fires one [SyncController.runNow] per transition into
/// [AppLifecycleState.resumed], debounced by [debounce] (5s in the app) so a
/// user flipping between apps rapidly only produces a single cycle. A
/// transition *out* of resumed (paused/inactive/detached/hidden) cancels any
/// pending trigger — a backgrounded app must never kick off a network cycle.
///
/// Design decisions, pinned by `test/ui/sync_lifecycle_test.dart`:
///
/// * **Resume transitions only, never cold start.** The watcher reacts to
///   lifecycle *changes*; mounting while already resumed does nothing. First
///   launch already has the list pull-to-refresh and Settings "Sync now"
///   (P3.4.1/.3) as manual entry points, and an automatic cold-start sync
///   would double-fire with the pull-to-refresh the user often performs
///   right after opening.
/// * **Silent fire-and-forget.** The result is deliberately ignored: the
///   controller's probe gate already skips cleanly when the app is
///   unconfigured or the server is unreachable, and a background trigger
///   must never surface a SnackBar the user did not ask for. Manual
///   triggers keep their existing SnackBar reporting.
/// * **No connectivity dependency.** "Network available" is enforced by the
///   existing probe gate inside [SyncController.runNow], not by a separate
///   connectivity_plus subscription — one less plugin, one less source of
///   truth, same outcome (offline resume = silent skip).
///
/// Must live inside a [ProviderScope] (it reads [syncControllerProvider]).
class SyncLifecycleWatcher extends ConsumerStatefulWidget {
  /// Creates a watcher wrapping [child] for the lifetime of the app.
  const new({
    required this.child,
    this.debounce = const Duration(seconds: 5),
    super.key,
  });

  /// The subtree to run (in the app: the whole MaterialApp).
  final Widget child;

  /// How long after a resume event the sync fires; injectable for tests.
  final Duration debounce;

  @override
  ConsumerState<SyncLifecycleWatcher> createState() =>
      _SyncLifecycleWatcherState();
}

class _SyncLifecycleWatcherState extends ConsumerState<SyncLifecycleWatcher>
    with WidgetsBindingObserver {
  /// Pending debounced trigger, cancelled on every new event or pause.
  Timer? _pending;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pending?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Any transition out of resumed kills the pending trigger — the window
    // for a "just came back to the app" sync has closed.
    if (state != AppLifecycleState.resumed) {
      _pending?.cancel();
      return;
    }
    // (Re)schedule: a fresh resume within the debounce window restarts the
    // timer rather than stacking a second one.
    _pending?.cancel();
    _pending = Timer(widget.debounce, () {
      // Fire-and-forget by design (see class doc); unawaited documents that
      // the floating future is intentional for the discarded_futures lint.
      unawaited(ref.read(syncControllerProvider).runNow());
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
