import 'package:firefly_mobile/domain/entities/json_api.dart';
import 'package:firefly_mobile/domain/entities/row_codec.dart';
import 'package:firefly_mobile/domain/entities/sync_bookkeeping.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'rule.freezed.dart';

/// A Firefly III rule (DESIGN §3.1).
///
/// Rules are stored and synced but never executed on the phone. Their trigger
/// and action bodies are kept verbatim as JSON text ([triggersJson] and
/// [actionsJson]) rather than being re-typed into models: the wire shape is a
/// heterogeneous list of rule actions, and a lossless string keeps a round trip
/// to the server exact while the schema's TEXT columns stay simple.
@freezed
abstract class Rule with _$Rule, SyncBookkeeping {
  /// Builds a rule from its local and remote fields.
  const factory({
    required String id,
    required String title,
    required DateTime updatedAt,
    required int seq,
    String? description,
    String? ruleGroupId,
    String? trigger,
    String? scope,
    String? triggersJson,
    String? actionsJson,
    String? fireflyId,
    @Default(true) bool active,
    @Default(false) bool strict,
    @Default(false) bool stop,
    int? orderIndex,
    DateTime? remoteUpdatedAt,
    @Default(SyncStatus.pending) SyncStatus syncStatus,
    DateTime? deletedAt,
  }) = _Rule;

  const new _();

  /// Rebuilds a rule from one JSON:API member object.
  factory fromJsonApi(
    Map<String, dynamic> member, {
    required String id,
    required DateTime updatedAt,
    required int seq,
    SyncStatus syncStatus = SyncStatus.synced,
    DateTime? deletedAt,
  }) {
    final attributes = jsonApiAttributes(member);
    return Rule(
      id: id,
      title: jsonString(attributes, 'title') ?? '',
      description: jsonString(attributes, 'description'),
      ruleGroupId: jsonString(attributes, 'rule_group_id'),
      trigger: jsonString(attributes, 'trigger'),
      scope: jsonString(attributes, 'scope'),
      triggersJson: jsonListToColumn(attributes['triggers']),
      actionsJson: jsonListToColumn(attributes['actions']),
      active: jsonBool(attributes, 'active', orElse: true),
      strict: jsonBool(attributes, 'strict'),
      stop: jsonBool(attributes, 'stop'),
      orderIndex: jsonInt(attributes, 'order'),
      fireflyId: jsonApiId(member),
      updatedAt: updatedAt,
      remoteUpdatedAt: jsonApiUpdatedAt(attributes),
      syncStatus: syncStatus,
      deletedAt: deletedAt,
      seq: seq,
    );
  }

  /// Rebuilds a rule from a row of the `rules` table.
  factory fromRow(Map<String, Object?> row) => Rule(
    id: row['id']! as String,
    title: row['title']! as String,
    description: row['description'] as String?,
    ruleGroupId: row['rule_group_id'] as String?,
    trigger: row['trigger'] as String?,
    active: sqliteBool(row['active'] as int?),
    strict: sqliteBool(row['strict'] as int?),
    stop: sqliteBool(row['stop'] as int?),
    orderIndex: row['order_index'] as int?,
    scope: row['scope'] as String?,
    triggersJson: row['triggers_json'] as String?,
    actionsJson: row['actions_json'] as String?,
    fireflyId: row['firefly_id'] as String?,
    updatedAt: millisToDateTime(row['updated_at']! as int)!,
    remoteUpdatedAt: millisToDateTime(row['remote_updated_at'] as int?),
    syncStatus: syncStatusFromRow(row['sync_status'] as String?),
    deletedAt: millisToDateTime(row['deleted_at'] as int?),
    seq: row['seq']! as int,
  );

  /// The JSON:API member object for this rule.
  Map<String, dynamic> toJsonApi() => jsonApiMember(
    type: 'rules',
    id: fireflyId,
    attributes: <String, dynamic>{
      'title': title,
      if (description != null) 'description': description,
      if (ruleGroupId != null) 'rule_group_id': ruleGroupId,
      if (trigger != null) 'trigger': trigger,
      if (scope != null) 'scope': scope,
      'active': active,
      'strict': strict,
      'stop': stop,
      if (orderIndex != null) 'order': orderIndex,
      if (triggersJson != null)
        'triggers': jsonListFromColumn(triggersJson),
      if (actionsJson != null) 'actions': jsonListFromColumn(actionsJson),
      if (remoteUpdatedAt != null)
        'updated_at': dateTimeToJson(remoteUpdatedAt),
    },
  );

  /// The `rules` row for this rule, columns keyed by column name.
  Map<String, Object?> toRow() => <String, Object?>{
    'id': id,
    'title': title,
    'description': description,
    'rule_group_id': ruleGroupId,
    'trigger': trigger,
    'active': sqliteInt(value: active),
    'strict': sqliteInt(value: strict),
    'stop': sqliteInt(value: stop),
    'order_index': orderIndex,
    'scope': scope,
    'triggers_json': triggersJson,
    'actions_json': actionsJson,
    'firefly_id': fireflyId,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'remote_updated_at': dateTimeToMillis(remoteUpdatedAt),
    'sync_status': syncStatusToRow(syncStatus),
    'deleted_at': dateTimeToMillis(deletedAt),
    'seq': seq,
  };
}
