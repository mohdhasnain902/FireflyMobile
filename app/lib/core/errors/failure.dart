/// Typed error surface for every fallible operation in the app.
///
/// A `Failure` is *expected* — it carries a user-presentable message and a
/// stable machine-readable `code` so the UI and the sync log can branch on
/// it without string matching. Programmer errors keep throwing (assertions,
/// `StateError`); anything a user could reasonably hit is a `Failure`.
///
/// Pattern: repositories and the sync engine return `Result<T>` (see
/// `core/utils/result.dart`) instead of throwing, so failures propagate
/// explicitly and cannot be silently swallowed.
library;

/// Base class for all expected failures.
sealed class Failure {
  /// Creates a failure with a human-readable [message].
  const new(this.message, {this.code, this.cause});

  /// Message safe to show to the user (English, localisation-ready).
  final String message;

  /// Stable machine-readable identifier, e.g. `network.timeout`.
  ///
  /// Never null for concrete subclasses — it is the contract the UI and the
  /// sync log branch on.
  final String? code;

  /// Underlying exception, kept for logs only — never shown to the user.
  final Object? cause;

  @override
  String toString() => '${code ?? 'failure'}: $message';
}

/// Device could not reach Firefly (offline, DNS, Tailscale down).
final class NetworkFailure extends Failure {
  /// Creates a network-layer failure.
  const new(super.message, {super.code = 'network.unreachable', super.cause});
}

/// Firefly rejected our credentials — PAT revoked, expired or malformed.
final class AuthFailure extends Failure {
  /// Creates an authentication failure.
  const new(super.message, {super.code = 'auth.rejected', super.cause});
}

/// Local SQLite read/write failed (corruption, lock, disk full).
final class StorageFailure extends Failure {
  /// Creates a local-storage failure.
  const new(super.message, {super.code = 'storage.local', super.cause});
}

/// Payload failed validation before it reached the network or the DB.
final class ValidationFailure extends Failure {
  /// Creates a validation failure.
  const new(super.message, {super.code = 'validation.invalid', super.cause});
}

/// Server refused the write because of a conflicting state (409).
///
/// Sync-specific: the op-log entry stays `pending` and is retried after the
/// pull side of the cycle re-reads the server state.
final class ConflictFailure extends Failure {
  /// Creates a write-conflict failure.
  const new(super.message, {super.code = 'sync.conflict', super.cause});
}

/// Bucket for anything unexpected that still has to surface to the UI.
final class UnknownFailure extends Failure {
  /// Creates a catch-all failure.
  const new(super.message, {super.code = 'unknown', super.cause});
}
