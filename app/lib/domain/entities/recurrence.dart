import 'package:firefly_mobile/domain/entities/json_api.dart';
import 'package:firefly_mobile/domain/entities/recurrence_repetition.dart';
import 'package:firefly_mobile/domain/entities/row_codec.dart';
import 'package:firefly_mobile/domain/entities/sync_bookkeeping.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'recurrence.freezed.dart';

/// A Firefly III recurring transaction definition.
///
/// Under Model B the phone owns recurrence generation (the server's cron is
/// disabled). [firstDate] anchors the schedule and comes straight from the
/// wire; [latestDate] records the last date the scheduler actually generated
/// for, so a re-run is idempotent and never re-fires history. [repeatUntil] and
/// [nrOfRepetitions] cap the schedule (a `null` repetition count is endless),
/// and [applyRules] mirrors Firefly's per-recurrence switch for running rules
/// on the generated transaction.
///
/// The frequency is [repetitions] — 1:N [RecurrenceRepetition] rows, not a
/// single flat frequency, because Firefly allows a recurrence to be defined by
/// several rules at once. The generated transaction templates stay verbatim in
/// [transactionsJson] so a definition can be displayed and re-uploaded without
/// the app re-deriving Firefly's template format.
///
/// [type] is the transaction direction the recurrence generates
/// (`withdrawal`/`transfer`/`deposit`), required by the server's StoreRequest.
/// [repetitions] is held in memory after a load: locally it round-trips through
/// the `recurrence_repetitions` child table (the `recurrences` row itself has
/// no repetition columns), and on push it rides inside the parent's payload as
/// `repetitions[]` (StoreRequest demands ≥1 on create; RecurrenceUpdateService
/// replaces or field-updates children when the key is present).
@freezed
abstract class Recurrence with _$Recurrence, SyncBookkeeping {
  /// Builds a recurrence from its local and remote fields.
  const factory({
    required String id,
    required String title,
    required DateTime updatedAt,
    required int seq,
    String? type,
    String? description,
    DateTime? repeatUntil,
    int? nrOfRepetitions,
    String? transactionsJson,
    String? fireflyId,
    @Default(true) bool active,
    DateTime? remoteUpdatedAt,
    @Default(SyncStatus.pending) SyncStatus syncStatus,
    DateTime? deletedAt,
    DateTime? firstDate,
    DateTime? latestDate,
    @Default(true) bool applyRules,
    @Default(<RecurrenceRepetition>[]) List<RecurrenceRepetition> repetitions,
  }) = _Recurrence;

  const new _();

  /// Rebuilds a recurrence from one JSON:API member object.
  ///
  /// [firstDate], [repeatUntil], [applyRules] and the schedule cap
  /// [nrOfRepetitions] are all read from the wire, exactly as Firefly's
  /// `RecurrenceTransformer` emits them. The frequency list is parsed out of
  /// the nested `repetitions[]` array (each child keeps its parent's local
  /// [id]); [latestDate] is the only truly phone-local schedule field and
  /// stays null on a pull until the scheduler first runs.
  factory fromJsonApi(
    Map<String, dynamic> member, {
    required String id,
    required DateTime updatedAt,
    required int seq,
    SyncStatus syncStatus = SyncStatus.synced,
    DateTime? deletedAt,
  }) {
    final attributes = jsonApiAttributes(member);
    final transactionsJson = jsonListToColumn(attributes['transactions']);
    return Recurrence(
      id: id,
      title: jsonString(attributes, 'title') ?? '',
      type: jsonString(attributes, 'type'),
      description: jsonString(attributes, 'description'),
      // Wire key is `repeat_until` (RecurrenceTransformer), not `recur_until`.
      repeatUntil: isoJsonToDateTime(attributes['repeat_until']),
      nrOfRepetitions: jsonInt(attributes, 'nr_of_repetitions'),
      transactionsJson: transactionsJson,
      active: jsonBool(attributes, 'active', orElse: true),
      applyRules: jsonBool(attributes, 'apply_rules', orElse: true),
      firstDate: isoJsonToDateTime(attributes['first_date']),
      repetitions: _repetitionsFromWire(attributes['repetitions'], id),
      fireflyId: jsonApiId(member),
      updatedAt: updatedAt,
      remoteUpdatedAt: jsonApiUpdatedAt(attributes),
      syncStatus: syncStatus,
      deletedAt: deletedAt,
      seq: seq,
    );
  }

  /// Rebuilds a recurrence from a row of the `recurrences` table.
  ///
  /// [repetitions] is left empty here — this only decodes the parent row, which
  /// cannot know its children. [loadRepetitions] is the paired accessor that
  /// joins the child table; `RecurrenceDao` calls it after every read.
  factory fromRow(Map<String, Object?> row) => Recurrence(
    id: row['id']! as String,
    title: row['title']! as String,
    type: row['type'] as String?,
    description: row['description'] as String?,
    repeatUntil: isoToDateTime(row['repeat_until'] as String?),
    nrOfRepetitions: row['nr_of_repetitions'] as int?,
    transactionsJson: row['transactions_json'] as String?,
    active: sqliteBool(row['active'] as int?),
    fireflyId: row['firefly_id'] as String?,
    updatedAt: millisToDateTime(row['updated_at']! as int)!,
    remoteUpdatedAt: millisToDateTime(row['remote_updated_at'] as int?),
    syncStatus: syncStatusFromRow(row['sync_status'] as String?),
    deletedAt: millisToDateTime(row['deleted_at'] as int?),
    seq: row['seq']! as int,
    firstDate: isoToDateTime(row['first_date'] as String?),
    latestDate: isoToDateTime(row['latest_date'] as String?),
    applyRules: sqliteBool(row['apply_rules'] as int?),
  );

  /// Parses the wire's `repetitions[]` array into child entities.
  ///
  /// Ordinals follow array order so a child's local key is stable across pulls.
  /// A non-list or an element that is not a map is skipped rather than thrown,
  /// because one malformed child must not fail the whole recurrence.
  static List<RecurrenceRepetition> _repetitionsFromWire(
    dynamic raw,
    String recurrenceId,
  ) {
    if (raw is! List<dynamic>) return const <RecurrenceRepetition>[];
    final parsed = <RecurrenceRepetition>[];
    for (var ord = 0; ord < raw.length; ord++) {
      final element = raw[ord];
      if (element is! Map<String, dynamic>) continue;
      parsed.add(
        RecurrenceRepetition.fromJson(
          element,
          recurrenceId: recurrenceId,
          ord: ord,
        ),
      );
    }
    return parsed;
  }

  /// Attaches this recurrence's parsed child rows to a copy of itself.
  ///
  /// Returns `this` unchanged when [rows] is empty, so a recurrence with no
  /// frequency rows still decodes cleanly.
  Recurrence loadRepetitions(Iterable<Map<String, Object?>> rows) {
    final parsed = rows
        .map(RecurrenceRepetition.fromRow)
        .where((repetition) => repetition.recurrenceId == id)
        .toList()
      ..sort((a, b) => a.ord.compareTo(b.ord));
    if (parsed.isEmpty) return this;
    return copyWith(repetitions: parsed);
  }

  /// The JSON:API member object for this recurrence.
  ///
  /// Deliberately omits [latestDate] (phone-local scheduler cursor, never
  /// pushed). [repetitions] is included whenever non-empty: StoreRequest
  /// demands ≥1 on create, and RecurrenceUpdateService field-updates or
  /// recreates children on update when the key is present (an empty payload
  /// list is ignored server-side, so an empty local list is omitted entirely
  /// rather than sent as `[]`).
  Map<String, dynamic> toJsonApi() => jsonApiMember(
    type: 'recurrences',
    id: fireflyId,
    attributes: <String, dynamic>{
      'title': title,
      if (type != null) 'type': type,
      if (description != null) 'description': description,
      if (repeatUntil != null) 'repeat_until': dateTimeToJson(repeatUntil),
      if (nrOfRepetitions != null) 'nr_of_repetitions': nrOfRepetitions,
      'active': active,
      'apply_rules': applyRules,
      if (firstDate != null) 'first_date': dateTimeToJson(firstDate),
      if (transactionsJson != null)
        'transactions': jsonListFromColumn(transactionsJson),
      if (repetitions.isNotEmpty)
        'repetitions': repetitions
            .map((repetition) => repetition.toJsonWire())
            .toList(),
      if (remoteUpdatedAt != null)
        'updated_at': dateTimeToJson(remoteUpdatedAt),
    },
  );

  /// The `recurrences` row for this recurrence.
  ///
  /// [latestDate] is phone-local schedule state with no wire counterpart, so it
  /// round-trips through the row only — never through [toJsonApi]. Child
  /// [repetitions] live in the `recurrence_repetitions` table (see
  /// [repetitionRows]), not in this row.
  Map<String, Object?> toRow() => <String, Object?>{
    'id': id,
    'title': title,
    'type': type,
    'description': description,
    'repeat_until': dateTimeToIso(repeatUntil),
    'nr_of_repetitions': nrOfRepetitions,
    'active': sqliteInt(value: active),
    'transactions_json': transactionsJson,
    'firefly_id': fireflyId,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'remote_updated_at': dateTimeToMillis(remoteUpdatedAt),
    'sync_status': syncStatusToRow(syncStatus),
    'deleted_at': dateTimeToMillis(deletedAt),
    'seq': seq,
    'first_date': dateTimeToIso(firstDate),
    'latest_date': dateTimeToIso(latestDate),
    'apply_rules': sqliteInt(value: applyRules),
  };

  /// The rows to write into `recurrence_repetitions` for this recurrence,
  /// each keyed back to the parent's local [id].
  ///
  /// Returns an empty list when the schedule has no frequency rows, which keeps
  /// a child-table rewrite a no-op instead of an error for an empty schedule.
  List<Map<String, Object?>> repetitionRows() =>
      repetitions.map((repetition) => repetition.toRow()).toList();
}
