import 'package:firefly_mobile/domain/entities/json_api.dart';
import 'package:meta/meta.dart';

/// How a recurrence's weekend date is adjusted, mirroring Firefly's
/// `RecurrenceRepetitionWeekend` enum exactly (same integer values).
///
/// - [doNothing]: leave a Saturday/Sunday occurrence on the weekend.
/// - [skipCreation]: drop the weekend occurrence entirely.
/// - [toFriday]: move a weekend occurrence back to the preceding Friday.
/// - [toMonday]: push a weekend occurrence forward to the following Monday.
enum RecurrenceWeekend {
  /// Leave a weekend occurrence on its Saturday/Sunday date.
  doNothing(1),

  /// Drop occurrences that land on a Saturday/Sunday.
  skipCreation(2),

  /// Move a weekend occurrence back to the preceding Friday.
  toFriday(3),

  /// Push a weekend occurrence forward to the following Monday.
  toMonday(4);

  new(this.value);

  /// The integer Firefly stores and sends on the wire.
  final int value;

  /// Reads a wire/row integer back into the enum, defaulting to [doNothing] for
  /// an unknown value so one bad row cannot fail a whole pull.
  static RecurrenceWeekend fromValue(int? raw) =>
      RecurrenceWeekend.values.firstWhere(
        (weekend) => weekend.value == raw,
        orElse: () => RecurrenceWeekend.doNothing,
      );
}

/// One frequency rule of a recurring transaction.
///
/// Firefly models a recurrence's frequency as 1:N of these rows (server table
/// `recurrences_repetitions`, wire key `repetitions[]` on the recurrence), not
/// as a single flat frequency. Each row says how to step the schedule
/// ([repetitionType] + [repetitionSkip]) and which day each period targets
/// ([repetitionMoment]).
///
/// This is a plain immutable value, not a freezed `SyncBookkeeping` entity: it
/// is never pushed as its own resource. It is owned entirely by its parent
/// recurrence, rides along inside the parent's pull, is rewritten wholesale
/// whenever the parent is upserted, and is sent inside the parent's payload as
/// `repetitions[]` (see [toJsonWire]). That is why it carries no
/// `id`/`fireflyId`/`seq` and is keyed locally by `(recurrenceId, ord)`.
@immutable
class RecurrenceRepetition {
  /// Creates a repetition row for the parent recurrence [recurrenceId].
  const new({
    required this.recurrenceId,
    required this.ord,
    required this.repetitionType,
    required this.repetitionMoment,
    this.repetitionSkip = 0,
    this.weekend = RecurrenceWeekend.doNothing,
  });

  /// Rebuilds a repetition from one element of the wire's `repetitions[]`
  /// array plus the parent's local [recurrenceId].
  ///
  /// Unknown or malformed values fall back to safe defaults rather than
  /// throwing, so one bad child cannot fail an entire parent pull.
  factory fromJson(
    Map<String, dynamic> json, {
    required String recurrenceId,
    required int ord,
  }) => .new(
    recurrenceId: recurrenceId,
    ord: ord,
    repetitionType: jsonString(json, 'type') ?? 'monthly',
    repetitionMoment: jsonString(json, 'moment') ?? '',
    repetitionSkip: jsonInt(json, 'skip') ?? 0,
    weekend: RecurrenceWeekend.fromValue(jsonInt(json, 'weekend')),
  );

  /// Rebuilds a repetition from a row of the `recurrence_repetitions` table.
  factory fromRow(Map<String, Object?> row) =>
      .new(
        recurrenceId: row['recurrence_id']! as String,
        ord: row['ord']! as int,
        repetitionType: row['repetition_type']! as String,
        repetitionMoment: row['repetition_moment']! as String,
        repetitionSkip: (row['repetition_skip'] as int?) ?? 0,
        weekend: RecurrenceWeekend.fromValue(row['weekend'] as int?),
      );

  /// The parent recurrence's local `id`.
  final String recurrenceId;

  /// Position of this repetition within the parent's schedule, matching the
  /// server's own ordering of `repetitions[]`. Stable for the row's lifetime
  /// and used as the local primary-key suffix.
  final int ord;

  /// How to step the schedule. One of Firefly's five values:
  /// `daily`, `weekly`, `monthly`, `ndom`, `yearly`.
  final String repetitionType;

  /// The day each period targets. Meaning depends on [repetitionType]:
  ///
  /// * `daily`   — unused.
  /// * `weekly`  — ISO day of week (1=Mon … 7=Sun).
  /// * `monthly` — day of month (1–31).
  /// * `ndom`    — `nth,dayOfWeek`, e.g. `2,3` for "the 2nd Wednesday".
  /// * `yearly`  — an ISO date (`Y-m-d`) whose month+day anchor the recurrence.
  final String repetitionMoment;

  /// Extra periods to skip between creations. Stored as Firefly does — 0 means
  /// every period, 1 means every other period. The scheduler must add 1 before
  /// using it as a modulo (`skipMod = repetitionSkip + 1`), matching the
  /// server's `getOccurrencesInRange`.
  final int repetitionSkip;

  /// Weekend adjustment applied to generated dates.
  final RecurrenceWeekend weekend;

  /// The row for the `recurrence_repetitions` table.
  Map<String, Object?> toRow() => <String, Object?>{
    'recurrence_id': recurrenceId,
    'ord': ord,
    'repetition_type': repetitionType,
    'repetition_moment': repetitionMoment,
    'repetition_skip': repetitionSkip,
    'weekend': weekend.value,
  };

  /// One element of the parent recurrence's wire `repetitions[]` array.
  ///
  /// Exactly the four keys RecurrenceUpdateService maps onto its columns
  /// (`type`, `moment`, `skip`, `weekend`); local keys (`recurrenceId`, `ord`)
  /// never leave the device.
  Map<String, dynamic> toJsonWire() => <String, dynamic>{
    'type': repetitionType,
    'moment': repetitionMoment,
    'skip': repetitionSkip,
    'weekend': weekend.value,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RecurrenceRepetition &&
          other.recurrenceId == recurrenceId &&
          other.ord == ord &&
          other.repetitionType == repetitionType &&
          other.repetitionMoment == repetitionMoment &&
          other.repetitionSkip == repetitionSkip &&
          other.weekend == weekend);

  @override
  int get hashCode => Object.hash(
    recurrenceId,
    ord,
    repetitionType,
    repetitionMoment,
    repetitionSkip,
    weekend,
  );

  @override
  String toString() =>
      'RecurrenceRepetition($repetitionType moment=$repetitionMoment '
      'skip=$repetitionSkip weekend=${weekend.name})';
}
