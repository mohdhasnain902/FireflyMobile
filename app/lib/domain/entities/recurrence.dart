import 'package:firefly_mobile/domain/entities/json_api.dart';
import 'package:firefly_mobile/domain/entities/row_codec.dart';
import 'package:firefly_mobile/domain/entities/sync_bookkeeping.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'recurrence.freezed.dart';

/// A Firefly III recurring transaction definition (DESIGN §3.1).
///
/// Recurrences are stored and synced but never fired by the phone — Firefly's
/// own cron materialises them server-side. The generated transaction templates
/// are kept verbatim in [transactionsJson] so a definition can be displayed and
/// re-uploaded without the app re-deriving Firefly's template format.
@freezed
abstract class Recurrence with _$Recurrence, SyncBookkeeping {
  /// Builds a recurrence from its local and remote fields.
  const factory({
    required String id,
    required String title,
    required DateTime updatedAt,
    required int seq,
    String? description,
    @Default('monthly') String repeatFreq,
    DateTime? recurUntil,
    int? nrOfRepetitions,
    String? transactionsJson,
    String? fireflyId,
    @Default(true) bool active,
    DateTime? remoteUpdatedAt,
    @Default(SyncStatus.pending) SyncStatus syncStatus,
    DateTime? deletedAt,
  }) = _Recurrence;

  const new _();

  /// Rebuilds a recurrence from one JSON:API member object.
  factory fromJsonApi(
    Map<String, dynamic> member, {
    required String id,
    required DateTime updatedAt,
    required int seq,
    SyncStatus syncStatus = SyncStatus.synced,
    DateTime? deletedAt,
  }) {
    final attributes = jsonApiAttributes(member);
    return Recurrence(
      id: id,
      title: jsonString(attributes, 'title') ?? '',
      description: jsonString(attributes, 'description'),
      repeatFreq: jsonString(attributes, 'repeat_freq') ?? 'monthly',
      recurUntil: isoJsonToDateTime(attributes['recur_until']),
      nrOfRepetitions: jsonInt(attributes, 'nr_of_repetitions'),
      transactionsJson: jsonListToColumn(attributes['transactions']),
      active: jsonBool(attributes, 'active', orElse: true),
      fireflyId: jsonApiId(member),
      updatedAt: updatedAt,
      remoteUpdatedAt: jsonApiUpdatedAt(attributes),
      syncStatus: syncStatus,
      deletedAt: deletedAt,
      seq: seq,
    );
  }

  /// Rebuilds a recurrence from a row of the `recurrences` table.
  factory fromRow(Map<String, Object?> row) => Recurrence(
    id: row['id']! as String,
    title: row['title']! as String,
    description: row['description'] as String?,
    repeatFreq: (row['repeat_freq'] as String?) ?? 'monthly',
    recurUntil: isoToDateTime(row['recur_until'] as String?),
    nrOfRepetitions: row['nr_of_repetitions'] as int?,
    transactionsJson: row['transactions_json'] as String?,
    active: sqliteBool(row['active'] as int?),
    fireflyId: row['firefly_id'] as String?,
    updatedAt: millisToDateTime(row['updated_at']! as int)!,
    remoteUpdatedAt: millisToDateTime(row['remote_updated_at'] as int?),
    syncStatus: syncStatusFromRow(row['sync_status'] as String?),
    deletedAt: millisToDateTime(row['deleted_at'] as int?),
    seq: row['seq']! as int,
  );

  /// The JSON:API member object for this recurrence.
  Map<String, dynamic> toJsonApi() => jsonApiMember(
    type: 'recurrences',
    id: fireflyId,
    attributes: <String, dynamic>{
      'title': title,
      if (description != null) 'description': description,
      'repeat_freq': repeatFreq,
      if (recurUntil != null) 'recur_until': dateTimeToJson(recurUntil),
      if (nrOfRepetitions != null) 'nr_of_repetitions': nrOfRepetitions,
      'active': active,
      if (transactionsJson != null)
        'transactions': jsonListFromColumn(transactionsJson),
      if (remoteUpdatedAt != null)
        'updated_at': dateTimeToJson(remoteUpdatedAt),
    },
  );

  /// The `recurrences` row for this recurrence.
  Map<String, Object?> toRow() => <String, Object?>{
    'id': id,
    'title': title,
    'description': description,
    'repeat_freq': repeatFreq,
    'recur_until': dateTimeToIso(recurUntil),
    'nr_of_repetitions': nrOfRepetitions,
    'active': sqliteInt(value: active),
    'transactions_json': transactionsJson,
    'firefly_id': fireflyId,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'remote_updated_at': dateTimeToMillis(remoteUpdatedAt),
    'sync_status': syncStatusToRow(syncStatus),
    'deleted_at': dateTimeToMillis(deletedAt),
    'seq': seq,
  };
}
