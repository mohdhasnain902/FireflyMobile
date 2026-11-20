import 'package:firefly_mobile/core/errors/failure.dart';
import 'package:firefly_mobile/core/settings/connection_probe.dart';
import 'package:firefly_mobile/core/utils/result.dart';
import 'package:firefly_mobile/data/sync/pull_engine.dart' show PullStats;
import 'package:firefly_mobile/data/sync/sync_engine.dart';

/// Why a sync trigger was skipped before any engine work ran (P3.6).
///
/// Every trigger — manual ("Sync now"), pull-to-refresh, lifecycle
/// auto-sync and restore — runs this gate first: a 4s probe against
/// `/api/v1/about` replaces letting the engine grind through ~30s × 5
/// timeout retries per entity when the host is offline.
enum SyncSkipReason {
  /// No base URL saved yet — nothing to probe.
  notConfigured('No server configured yet — add one in Settings.'),

  /// Probe got no HTTP response (DNS/TLS/route/timeout).
  unreachable('Firefly is unreachable — will retry when it is back.'),

  /// Host answered, but not like a Firefly API (proxy login page, 5xx, 404).
  wrongEndpoint(
    'That URL did not answer like a Firefly API — check it in Settings.',
  ),

  /// Host answered 401/403 — the saved PAT is bad.
  unauthorized('The server rejected the saved token — check it in Settings.'),

  /// A cycle or restore is already in flight (only used when joining is not
  /// possible, i.e. restore while a sync runs).
  busy('A sync is already running.');

  /// Creates a skip reason carrying its user-facing text.
  new(this.message);

  /// Snackbar-safe message for this skip.
  final String message;
}

/// Result of one [SyncController.runNow] attempt.
///
/// Exactly one of [outcome] / [skipped] is non-null: a *ran* attempt carries
/// the engine's aggregate result, a *skipped* attempt never touched the
/// engine at all.
class SyncAttempt {
  /// Builds an attempt that ran the cycle to completion.
  const new ran(this.outcome) : skipped = null;

  /// Builds an attempt stopped by the gate.
  const new skippedBy(this.skipped) : outcome = null;

  /// Engine result when the cycle ran, else null.
  final SyncOutcome? outcome;

  /// Gate reason when the cycle was skipped, else null.
  final SyncSkipReason? skipped;

  /// Whether the engine actually ran.
  bool get ran => outcome != null;

  /// Whether the whole cycle succeeded (false when skipped or failed).
  bool get ok => outcome?.ok ?? false;
}

/// UI-facing façade over [SyncEngine]: probe-gated triggers, in-flight
/// coalescing, and a shared busy lock for restore (P3.2/P3.6).
///
/// Pure Dart — no Riverpod, no Flutter. The provider layer wires the three
/// seams (`engine`, `isConfigured`, `probe`); widget tests substitute their
/// own closures so no network or database is needed at the UI level.
class SyncController {
  /// Creates a controller over the given seams.
  ///
  /// * [_engine] — resolves the (possibly already-built) sync engine lazily so
  ///   constructing the controller never opens a database.
  /// * [_isConfigured] — whether a base URL is saved (fast pre-probe check).
  /// * [_probe] — the 4s `about` probe against the saved URL/token.
  new({
    required this._engine,
    required this._isConfigured,
    required this._probe,
  });

  final Future<SyncEngine> Function() _engine;
  final Future<bool> Function() _isConfigured;
  final Future<ProbeResult> Function() _probe;

  /// The cycle started by [runNow], while it is in flight.
  Future<SyncAttempt>? _inFlight;

  /// Whether [restore] is running.
  bool _restoring = false;

  /// True while a sync cycle or a restore is running.
  ///
  /// UI disables restore and shows spinners off this single flag.
  bool get busy => _inFlight != null || _restoring;

  /// Runs one full probe-gated sync cycle (push then pull).
  Future<SyncAttempt> runNow() => _run((engine) => engine.sync());

  /// Syncs phone data to the website only (push queued local ops).
  Future<SyncAttempt> pushToWebsite() => _run((engine) => engine.pushOnly());

  /// Syncs website data to the phone only (pull server records).
  Future<SyncAttempt> pullFromWebsite() => _run((engine) => engine.pullOnly());

  Future<SyncAttempt> _run(Future<SyncOutcome> Function(SyncEngine) op) async {
    final existing = _inFlight;
    if (existing != null) return await existing;
    if (_restoring) {
      return const SyncAttempt.skippedBy(SyncSkipReason.busy);
    }
    final run = _runWithGate(op);
    _inFlight = run;
    try {
      return await run;
    } finally {
      _inFlight = null;
    }
  }

  Future<SyncAttempt> _runWithGate(
    Future<SyncOutcome> Function(SyncEngine) op,
  ) async {
    final gate = await _gate();
    if (gate != null) return SyncAttempt.skippedBy(gate);
    final engine = await _engine();
    return SyncAttempt.ran(await op(engine));
  }

  /// Probe-gated restore: same gate as [runNow], but exclusive (never joins).
  ///
  /// The error for a skipped restore carries `sync.skipped.<reason>` so the
  /// settings screen can show the reason's [SyncSkipReason.message] without
  /// string matching on prose.
  Future<Result<PullStats>> restore() async {
    if (busy) {
      return Err<PullStats>(
        ValidationFailure(
          SyncSkipReason.busy.message,
          code: 'sync.skipped.busy',
        ),
      );
    }
    _restoring = true;
    try {
      final gate = await _gate();
      if (gate != null) return Err<PullStats>(_skipFailure(gate));
      final engine = await _engine();
      return await engine.restoreFromServer();
    } finally {
      _restoring = false;
    }
  }

  /// Returns null when the cycle may proceed, else the skip reason.
  Future<SyncSkipReason?> _gate() async {
    if (!await _isConfigured()) return SyncSkipReason.notConfigured;
    final result = await _probe();
    return switch (result.status) {
      ProbeStatus.ok => null,
      ProbeStatus.unauthorized => SyncSkipReason.unauthorized,
      ProbeStatus.unexpectedStatus => SyncSkipReason.wrongEndpoint,
      ProbeStatus.unreachable => SyncSkipReason.unreachable,
    };
  }

  /// Maps a gate skip to the concrete [Failure] a [Result] caller needs.
  Failure _skipFailure(SyncSkipReason reason) => switch (reason) {
    SyncSkipReason.unauthorized =>
      AuthFailure(reason.message, code: 'sync.skipped.unauthorized'),
    SyncSkipReason.unreachable || SyncSkipReason.wrongEndpoint =>
      NetworkFailure(reason.message, code: 'sync.skipped.${reason.name}'),
    SyncSkipReason.notConfigured || SyncSkipReason.busy =>
      ValidationFailure(reason.message, code: 'sync.skipped.${reason.name}'),
  };
}
