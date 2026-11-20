import 'package:firefly_mobile/core/providers.dart';
import 'package:firefly_mobile/core/sync_lifecycle.dart';
import 'package:firefly_mobile/data/sync/sync_controller.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Widget tests for the P3.4.2 lifecycle auto-trigger ([SyncLifecycleWatcher]).
///
/// The watcher is deliberately silent and engine-agnostic — its whole job is
/// *when* it calls [SyncController.runNow], never what the cycle does. Every
/// test therefore injects a real [SyncController] whose gate short-circuits
/// (`isConfigured` returns false) and counts gate entries, so a "call" in the
/// assertions below means "one full runNow reached the gate" — the exact
/// observable that a debounced resume should produce exactly once, a pause
/// should cancel, and a cold start should never fire at all.
void main() {
  /// A controller plus a live counter of gate entries ([SyncController.runNow]
  /// invocations). The gate stops at `isConfigured` so the engine and probe
  /// closures are never reached — no DB, no network, no flakiness.
  ({SyncController controller, int Function() calls}) buildRecording() {
    var calls = 0;
    final controller = SyncController(
      engine: () async => throw UnimplementedError('engine not needed'),
      isConfigured: () async {
        calls++;
        return false; // skip before probe/engine — the count alone is enough
      },
      probe: () async => throw UnimplementedError('probe not reached'),
    );
    return (controller: controller, calls: () => calls);
  }

  /// Pumps [SyncLifecycleWatcher] around a bare [SizedBox] with the recording
  /// controller wired into the shared [syncControllerProvider].
  Future<void> pumpWatcher(
    WidgetTester tester, {
    required SyncController controller,
    Duration debounce = const Duration(milliseconds: 100),
  }) async {
    final overrides = [
      syncControllerProvider.overrideWithValue(controller),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: SyncLifecycleWatcher(
          debounce: debounce,
          child: const SizedBox(),
        ),
      ),
    );
    await tester.pump(); // settle initState (observer registration)
  }

  testWidgets('resume fires exactly one sync after the debounce window', (
    tester,
  ) async {
    final rec = buildRecording();
    await pumpWatcher(tester, controller: rec.controller);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    // Still inside the 100ms window — nothing may have fired yet.
    await tester.pump(const Duration(milliseconds: 99));
    expect(rec.calls(), 0, reason: 'sync must wait out the debounce window');

    // Cross the window boundary: exactly one runNow, no double-fire.
    await tester.pump(const Duration(milliseconds: 2));
    expect(rec.calls(), 1, reason: 'one (and only one) cycle after debounce');
  });

  testWidgets('rapid resume events coalesce into a single sync', (
    tester,
  ) async {
    final rec = buildRecording();
    await pumpWatcher(tester, controller: rec.controller);

    // First resume starts the 100ms timer…
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 50));

    // …a second resume 50ms later must *restart* it, not stack a second one.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 99));
    expect(rec.calls(), 0, reason: 'second resume reset the window');

    await tester.pump(const Duration(milliseconds: 2));
    expect(rec.calls(), 1, reason: 'both resumes collapsed into one cycle');
  });

  testWidgets('leaving resumed cancels a pending sync', (tester) async {
    final rec = buildRecording();
    await pumpWatcher(tester, controller: rec.controller);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 50)); // halfway pending

    // Backgrounded before the window elapsed — the pending trigger is killed.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(milliseconds: 200));
    expect(rec.calls(), 0, reason: 'a paused app must never start a cycle');

    // Coming back later schedules a fresh, clean cycle.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 101));
    expect(rec.calls(), 1, reason: 'next resume triggers normally');
  });

  testWidgets('cold start (no resume transition) never fires a sync', (
    tester,
  ) async {
    final rec = buildRecording();
    await pumpWatcher(tester, controller: rec.controller);

    // The watcher mounted while the binding was already resumed; no lifecycle
    // event is ever sent. It must stay silent — first-open sync remains the
    // user's call via pull-to-refresh or Settings "Sync now" (P3.4.1/.3).
    await tester.pump(const Duration(milliseconds: 300));
    expect(rec.calls(), 0, reason: 'mounting while resumed is not a trigger');
  });
}
