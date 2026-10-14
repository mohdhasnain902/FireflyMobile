/// SQLite row codecs shared by every business table (DESIGN §5.1).
///
/// SQLite has no boolean or timestamp column type, so every entity model
/// converts on the way in and out of a row. Keeping those conversions here
/// (rather than inline in fourteen models) means a format change is a one-line
/// edit and the round-trip tests exercise a single implementation.
library;

import 'package:firefly_mobile/domain/entities/sync_bookkeeping.dart';

/// Converts the 0/1 integers SQLite stores for booleans to a [bool].
///
/// NULL is treated as `false`, which matches the `NOT NULL DEFAULT 0` columns
/// that can still be read back as null through a left join.
bool sqliteBool(int? raw) => raw == 1;

/// Converts [value] to the 0/1 integer SQLite stores for booleans.
///
/// The parameter is named because `avoid_positional_boolean_parameters` makes
/// a positional bool unreadable at the call site — `sqliteInt(value: active)`
/// says what is being converted where it is converted.
int sqliteInt({required bool value}) => value ? 1 : 0;

/// Parses an ISO-8601 text column (all business dates) back to a [DateTime].
///
/// Returns null for null or unparseable input rather than throwing, because a
/// pull must not abort on one bad row. The result is normalised to UTC to
/// uphold the app-wide invariant documented on [millisToDateTime].
DateTime? isoToDateTime(String? raw) =>
    raw == null ? null : DateTime.tryParse(raw)?.toUtc();

/// Formats a [DateTime] as the ISO-8601 text SQLite stores for business dates.
String? dateTimeToIso(DateTime? value) => value?.toUtc().toIso8601String();

/// Reads the `sync_status` text column, defaulting to [SyncStatus.pending].
///
/// An unknown value means the row predates the enum's current members, and
/// pending is the safe answer: it makes the row replay rather than drop.
SyncStatus syncStatusFromRow(String? raw) => SyncStatus.values.firstWhere(
  (status) => status.name == raw,
  orElse: () => SyncStatus.pending,
);

/// Writes [status] back to the `sync_status` text column.
String syncStatusToRow(SyncStatus status) => status.name;
