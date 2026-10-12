import 'package:firefly_mobile/core/errors/failure.dart';

/// Explicit success-or-failure container.
///
/// Every repository method and sync step returns a [Result] so callers must
/// handle failure — there is no `throw` path to forget. Use [fold] for a
/// terminal decision, or pattern-match with `switch` for richer handling.
sealed class Result<T> {
  /// Creates a result. Concrete variants are [Ok] and [Err].
  const new();

  /// Reduces the result to a single value of type [R].
  ///
  /// Exactly one of [onOk] / [onErr] runs.
  R fold<R>(R Function(T value) onOk, R Function(Failure failure) onErr) =>
      switch (this) {
        Ok<T>(:final value) => onOk(value),
        Err<T>(:final failure) => onErr(failure),
      };

  /// The contained value, or `null` when this is an [Err].
  T? get valueOrNull => switch (this) {
    Ok<T>(:final value) => value,
    Err<T>() => null,
  };

  /// The failure, or `null` when this is an [Ok].
  Failure? get failureOrNull => switch (this) {
    Ok<T>() => null,
    Err<T>(:final failure) => failure,
  };

  /// Whether the operation succeeded.
  bool get isOk => this is Ok<T>;
}

/// Successful terminal carrying [value].
final class Ok<T> extends Result<T> {
  /// Creates a successful result holding [value].
  const new(this.value);

  /// The produced value.
  final T value;
}

/// Failed terminal carrying [failure].
final class Err<T> extends Result<T> {
  /// Creates a failed result holding [failure].
  const new(this.failure);

  /// Why the operation failed.
  final Failure failure;
}
