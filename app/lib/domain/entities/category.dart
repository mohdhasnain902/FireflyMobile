import 'package:firefly_mobile/domain/entities/json_api.dart';
import 'package:firefly_mobile/domain/entities/row_codec.dart';
import 'package:firefly_mobile/domain/entities/sync_bookkeeping.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'category.freezed.dart';

/// A Firefly III category (DESIGN §3.1, §5.1).
///
/// Purely a local value type: the SQLite row mapping (`fromRow`/`toRow`) and
/// the Firefly JSON:API mapping (`fromJsonApi`/`toJsonApi`) are hand-written
/// because neither shape is a flat JSON object — the wire format is enveloped
/// in `data`/`attributes` and SQLite stores booleans as 0/1 and timestamps as
/// epoch milliseconds. freezed is used for the parts it is good at: value
/// equality (round-trip tests assert deep equality), `copyWith` (the
/// field-level LWW merge in DESIGN §7.4 rewrites one field at a time) and
/// `toString` (sync log readability).
@freezed
abstract class Category with _$Category, SyncBookkeeping {
  /// Builds a category from its local and remote fields.
  const factory({
    required String id,
    required String name,
    required DateTime updatedAt,
    required int seq,
    String? notes,
    String? fireflyId,
    DateTime? remoteUpdatedAt,
    @Default(SyncStatus.pending) SyncStatus syncStatus,
    DateTime? deletedAt,
  }) = _Category;

  const new _();

  /// Rebuilds a category from one JSON:API member object.
  ///
  /// [member] is the `{type, id, attributes}` object — the unwrapped `data`
  /// entry, not the whole document (see [jsonApiData]). The local-only fields
  /// are passed explicitly because JSON:API never carries them: [id] is the
  /// client UUIDv7, [updatedAt] is the wall clock of the local write and
  /// [seq] is the op-seq that produced this content (DESIGN §5.1).
  ///
  /// [syncStatus] defaults to [SyncStatus.synced] because a row that just
  /// arrived from the server has been acknowledged; callers performing a
  /// field-level merge pass [SyncStatus.conflict] instead (DESIGN §7.4).
  factory fromJsonApi(
    Map<String, dynamic> member, {
    required String id,
    required DateTime updatedAt,
    required int seq,
    SyncStatus syncStatus = SyncStatus.synced,
    DateTime? deletedAt,
  }) {
    final attributes = jsonApiAttributes(member);
    return Category(
      id: id,
      name: attributes['name'] as String? ?? '',
      notes: attributes['notes'] as String?,
      fireflyId: jsonApiId(member),
      updatedAt: updatedAt,
      remoteUpdatedAt: jsonApiUpdatedAt(attributes),
      syncStatus: syncStatus,
      deletedAt: deletedAt,
      seq: seq,
    );
  }

  /// Rebuilds a category from a row of the `categories` table.
  ///
  /// Uses `??`/null-tolerant parsing throughout so a row written by a future
  /// schema version reads as defaults instead of crashing the sync loop.
  factory fromRow(Map<String, Object?> row) => Category(
    id: row['id']! as String,
    name: row['name']! as String,
    notes: row['notes'] as String?,
    fireflyId: row['firefly_id'] as String?,
    updatedAt: millisToDateTime(row['updated_at']! as int)!,
    remoteUpdatedAt: millisToDateTime(row['remote_updated_at'] as int?),
    syncStatus: syncStatusFromRow(row['sync_status'] as String?),
    deletedAt: millisToDateTime(row['deleted_at'] as int?),
    seq: row['seq']! as int,
  );

  /// The JSON:API member object for this category, as a server would return it.
  ///
  /// Emits only the attributes this model owns; Firefly-only fields such as
  /// `created_at` and `user_id` are intentionally absent because the schema
  /// does not store them (DESIGN §5.1).
  Map<String, dynamic> toJsonApi() => jsonApiMember(
    type: 'categories',
    id: fireflyId,
    attributes: <String, dynamic>{
      'name': name,
      if (notes != null) 'notes': notes,
      if (remoteUpdatedAt != null)
        'updated_at': dateTimeToJson(remoteUpdatedAt),
    },
  );

  /// The `categories` row for this category, columns keyed by column name.
  Map<String, Object?> toRow() => <String, Object?>{
    'id': id,
    'name': name,
    'notes': notes,
    'firefly_id': fireflyId,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'remote_updated_at': dateTimeToMillis(remoteUpdatedAt),
    'sync_status': syncStatusToRow(syncStatus),
    'deleted_at': dateTimeToMillis(deletedAt),
    'seq': seq,
  };
}
