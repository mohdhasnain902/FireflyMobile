import 'package:firefly_mobile/domain/entities/json_api.dart';
import 'package:firefly_mobile/domain/entities/row_codec.dart';
import 'package:firefly_mobile/domain/entities/sync_bookkeeping.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'tag.freezed.dart';

/// A Firefly III tag (DESIGN §3.1).
///
/// The wire attribute is `tag`, not `name`; the schema mirrors that spelling so
/// a create payload needs no field renaming. [date] is the tag's first-applied
/// date and is optional.
@freezed
abstract class Tag with _$Tag, SyncBookkeeping {
  /// Builds a tag from its local and remote fields.
  const factory({
    required String id,
    required String tag,
    required DateTime updatedAt,
    required int seq,
    DateTime? date,
    String? fireflyId,
    DateTime? remoteUpdatedAt,
    @Default(SyncStatus.pending) SyncStatus syncStatus,
    DateTime? deletedAt,
  }) = _Tag;

  const new _();

  /// Rebuilds a tag from one JSON:API member object.
  factory fromJsonApi(
    Map<String, dynamic> member, {
    required String id,
    required DateTime updatedAt,
    required int seq,
    SyncStatus syncStatus = SyncStatus.synced,
    DateTime? deletedAt,
  }) {
    final attributes = jsonApiAttributes(member);
    return Tag(
      id: id,
      tag: jsonString(attributes, 'tag') ?? '',
      date: isoJsonToDateTime(attributes['date']),
      fireflyId: jsonApiId(member),
      updatedAt: updatedAt,
      remoteUpdatedAt: jsonApiUpdatedAt(attributes),
      syncStatus: syncStatus,
      deletedAt: deletedAt,
      seq: seq,
    );
  }

  /// Rebuilds a tag from a row of the `tags` table.
  factory fromRow(Map<String, Object?> row) => Tag(
    id: row['id']! as String,
    tag: row['tag']! as String,
    date: isoToDateTime(row['date'] as String?),
    fireflyId: row['firefly_id'] as String?,
    updatedAt: millisToDateTime(row['updated_at']! as int)!,
    remoteUpdatedAt: millisToDateTime(row['remote_updated_at'] as int?),
    syncStatus: syncStatusFromRow(row['sync_status'] as String?),
    deletedAt: millisToDateTime(row['deleted_at'] as int?),
    seq: row['seq']! as int,
  );

  /// The JSON:API member object for this tag, as a server would return it.
  Map<String, dynamic> toJsonApi() => jsonApiMember(
    type: 'tags',
    id: fireflyId,
    attributes: <String, dynamic>{
      'tag': tag,
      if (date != null) 'date': dateTimeToJson(date),
      if (remoteUpdatedAt != null)
        'updated_at': dateTimeToJson(remoteUpdatedAt),
    },
  );

  /// The `tags` row for this tag, columns keyed by column name.
  Map<String, Object?> toRow() => <String, Object?>{
    'id': id,
    'tag': tag,
    'date': dateTimeToIso(date),
    'firefly_id': fireflyId,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'remote_updated_at': dateTimeToMillis(remoteUpdatedAt),
    'sync_status': syncStatusToRow(syncStatus),
    'deleted_at': dateTimeToMillis(deletedAt),
    'seq': seq,
  };
}
