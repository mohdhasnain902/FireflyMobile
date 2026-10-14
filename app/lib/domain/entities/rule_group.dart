import 'package:firefly_mobile/domain/entities/json_api.dart';
import 'package:firefly_mobile/domain/entities/row_codec.dart';
import 'package:firefly_mobile/domain/entities/sync_bookkeeping.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'rule_group.freezed.dart';

/// A Firefly III rule group (DESIGN §3.1).
///
/// Rule groups are stored and synced but never executed on the phone, so the
/// only fields the app needs are the ones the list and detail screens render.
/// The wire attribute is `order`, which the schema calls `order_index` to keep
/// the sort key distinct from a position inside a split transaction.
@freezed
abstract class RuleGroup with _$RuleGroup, SyncBookkeeping {
  /// Builds a rule group from its local and remote fields.
  const factory({
    required String id,
    required String title,
    required DateTime updatedAt,
    required int seq,
    String? description,
    String? fireflyId,
    @Default(true) bool active,
    int? orderIndex,
    DateTime? remoteUpdatedAt,
    @Default(SyncStatus.pending) SyncStatus syncStatus,
    DateTime? deletedAt,
  }) = _RuleGroup;

  const new _();

  /// Rebuilds a rule group from one JSON:API member object.
  factory fromJsonApi(
    Map<String, dynamic> member, {
    required String id,
    required DateTime updatedAt,
    required int seq,
    SyncStatus syncStatus = SyncStatus.synced,
    DateTime? deletedAt,
  }) {
    final attributes = jsonApiAttributes(member);
    return RuleGroup(
      id: id,
      title: jsonString(attributes, 'title') ?? '',
      description: jsonString(attributes, 'description'),
      active: jsonBool(attributes, 'active', orElse: true),
      orderIndex: jsonInt(attributes, 'order'),
      fireflyId: jsonApiId(member),
      updatedAt: updatedAt,
      remoteUpdatedAt: jsonApiUpdatedAt(attributes),
      syncStatus: syncStatus,
      deletedAt: deletedAt,
      seq: seq,
    );
  }

  /// Rebuilds a rule group from a row of the `rule_groups` table.
  factory fromRow(Map<String, Object?> row) => RuleGroup(
    id: row['id']! as String,
    title: row['title']! as String,
    description: row['description'] as String?,
    active: sqliteBool(row['active'] as int?),
    orderIndex: row['order_index'] as int?,
    fireflyId: row['firefly_id'] as String?,
    updatedAt: millisToDateTime(row['updated_at']! as int)!,
    remoteUpdatedAt: millisToDateTime(row['remote_updated_at'] as int?),
    syncStatus: syncStatusFromRow(row['sync_status'] as String?),
    deletedAt: millisToDateTime(row['deleted_at'] as int?),
    seq: row['seq']! as int,
  );

  /// The JSON:API member object for this rule group.
  Map<String, dynamic> toJsonApi() => jsonApiMember(
    type: 'rule_groups',
    id: fireflyId,
    attributes: <String, dynamic>{
      'title': title,
      if (description != null) 'description': description,
      'active': active,
      if (orderIndex != null) 'order': orderIndex,
      if (remoteUpdatedAt != null)
        'updated_at': dateTimeToJson(remoteUpdatedAt),
    },
  );

  /// The `rule_groups` row for this rule group, columns keyed by column name.
  Map<String, Object?> toRow() => <String, Object?>{
    'id': id,
    'title': title,
    'description': description,
    'active': sqliteInt(value: active),
    'order_index': orderIndex,
    'firefly_id': fireflyId,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'remote_updated_at': dateTimeToMillis(remoteUpdatedAt),
    'sync_status': syncStatusToRow(syncStatus),
    'deleted_at': dateTimeToMillis(deletedAt),
    'seq': seq,
  };
}
