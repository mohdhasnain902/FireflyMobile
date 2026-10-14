import 'package:firefly_mobile/domain/entities/json_api.dart';
import 'package:firefly_mobile/domain/entities/row_codec.dart';
import 'package:firefly_mobile/domain/entities/sync_bookkeeping.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'budget.freezed.dart';

/// A Firefly III budget (DESIGN §3.1).
///
/// [currencyCode] is stored denormalised alongside [currencyId] because the
/// budget screens render the code without a join (DESIGN §5.1). [orderIndex]
/// maps the wire attribute `order`.
@freezed
abstract class Budget with _$Budget, SyncBookkeeping {
  /// Builds a budget from its local and remote fields.
  const factory({
    required String id,
    required String name,
    required DateTime updatedAt,
    required int seq,
    String? notes,
    String? currencyCode,
    String? currencyId,
    String? autoBudgetType,
    String? fireflyId,
    @Default(true) bool active,
    int? orderIndex,
    DateTime? remoteUpdatedAt,
    @Default(SyncStatus.pending) SyncStatus syncStatus,
    DateTime? deletedAt,
  }) = _Budget;

  const new _();

  /// Rebuilds a budget from one JSON:API member object.
  factory fromJsonApi(
    Map<String, dynamic> member, {
    required String id,
    required DateTime updatedAt,
    required int seq,
    SyncStatus syncStatus = SyncStatus.synced,
    DateTime? deletedAt,
  }) {
    final attributes = jsonApiAttributes(member);
    return Budget(
      id: id,
      name: jsonString(attributes, 'name') ?? '',
      notes: jsonString(attributes, 'notes'),
      currencyCode: jsonString(attributes, 'currency_code'),
      currencyId: jsonString(attributes, 'currency_id'),
      autoBudgetType: jsonString(attributes, 'auto_budget_type'),
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

  /// Rebuilds a budget from a row of the `budgets` table.
  factory fromRow(Map<String, Object?> row) => Budget(
    id: row['id']! as String,
    name: row['name']! as String,
    notes: row['notes'] as String?,
    currencyCode: row['currency_code'] as String?,
    currencyId: row['currency_id'] as String?,
    autoBudgetType: row['auto_budget_type'] as String?,
    active: sqliteBool(row['active'] as int?),
    orderIndex: row['order_index'] as int?,
    fireflyId: row['firefly_id'] as String?,
    updatedAt: millisToDateTime(row['updated_at']! as int)!,
    remoteUpdatedAt: millisToDateTime(row['remote_updated_at'] as int?),
    syncStatus: syncStatusFromRow(row['sync_status'] as String?),
    deletedAt: millisToDateTime(row['deleted_at'] as int?),
    seq: row['seq']! as int,
  );

  /// The JSON:API member object for this budget.
  Map<String, dynamic> toJsonApi() => jsonApiMember(
    type: 'budgets',
    id: fireflyId,
    attributes: <String, dynamic>{
      'name': name,
      if (notes != null) 'notes': notes,
      if (currencyCode != null) 'currency_code': currencyCode,
      if (currencyId != null) 'currency_id': currencyId,
      if (autoBudgetType != null) 'auto_budget_type': autoBudgetType,
      'active': active,
      if (orderIndex != null) 'order': orderIndex,
      if (remoteUpdatedAt != null)
        'updated_at': dateTimeToJson(remoteUpdatedAt),
    },
  );

  /// The `budgets` row for this budget, columns keyed by column name.
  Map<String, Object?> toRow() => <String, Object?>{
    'id': id,
    'name': name,
    'notes': notes,
    'currency_code': currencyCode,
    'currency_id': currencyId,
    'auto_budget_type': autoBudgetType,
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
