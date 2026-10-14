import 'package:firefly_mobile/domain/entities/json_api.dart';
import 'package:firefly_mobile/domain/entities/row_codec.dart';
import 'package:firefly_mobile/domain/entities/sync_bookkeeping.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'piggy_bank.freezed.dart';

/// A Firefly III piggy bank (DESIGN §3.1).
///
/// A piggy bank is a saved-up amount held by an account: [accountId] is the
/// account that carries the money, [currentAmount] is what has been accrued so
/// far and [targetAmount] is the goal. [orderIndex] maps the wire attribute
/// `order`.
@freezed
abstract class PiggyBank with _$PiggyBank, SyncBookkeeping {
  /// Builds a piggy bank from its local and remote fields.
  const factory({
    required String id,
    required String name,
    required DateTime updatedAt,
    required int seq,
    String? accountId,
    String? targetAmount,
    String? currentAmount,
    DateTime? startDate,
    DateTime? targetDate,
    String? currencyCode,
    String? currencyId,
    String? notes,
    String? fireflyId,
    int? orderIndex,
    DateTime? remoteUpdatedAt,
    @Default(SyncStatus.pending) SyncStatus syncStatus,
    DateTime? deletedAt,
  }) = _PiggyBank;

  const new _();

  /// Rebuilds a piggy bank from one JSON:API member object.
  factory fromJsonApi(
    Map<String, dynamic> member, {
    required String id,
    required DateTime updatedAt,
    required int seq,
    SyncStatus syncStatus = SyncStatus.synced,
    DateTime? deletedAt,
  }) {
    final attributes = jsonApiAttributes(member);
    return PiggyBank(
      id: id,
      name: jsonString(attributes, 'name') ?? '',
      accountId: jsonString(attributes, 'account_id'),
      targetAmount: jsonDecimal(attributes, 'target_amount'),
      currentAmount: jsonDecimal(attributes, 'current_amount'),
      startDate: isoJsonToDateTime(attributes['start_date']),
      targetDate: isoJsonToDateTime(attributes['target_date']),
      currencyCode: jsonString(attributes, 'currency_code'),
      currencyId: jsonString(attributes, 'currency_id'),
      notes: jsonString(attributes, 'notes'),
      orderIndex: jsonInt(attributes, 'order'),
      fireflyId: jsonApiId(member),
      updatedAt: updatedAt,
      remoteUpdatedAt: jsonApiUpdatedAt(attributes),
      syncStatus: syncStatus,
      deletedAt: deletedAt,
      seq: seq,
    );
  }

  /// Rebuilds a piggy bank from a row of the `piggy_banks` table.
  factory fromRow(Map<String, Object?> row) => PiggyBank(
    id: row['id']! as String,
    name: row['name']! as String,
    accountId: row['account_id'] as String?,
    targetAmount: row['target_amount'] as String?,
    currentAmount: row['current_amount'] as String?,
    startDate: isoToDateTime(row['start_date'] as String?),
    targetDate: isoToDateTime(row['target_date'] as String?),
    currencyCode: row['currency_code'] as String?,
    currencyId: row['currency_id'] as String?,
    notes: row['notes'] as String?,
    orderIndex: row['order_index'] as int?,
    fireflyId: row['firefly_id'] as String?,
    updatedAt: millisToDateTime(row['updated_at']! as int)!,
    remoteUpdatedAt: millisToDateTime(row['remote_updated_at'] as int?),
    syncStatus: syncStatusFromRow(row['sync_status'] as String?),
    deletedAt: millisToDateTime(row['deleted_at'] as int?),
    seq: row['seq']! as int,
  );

  /// The JSON:API member object for this piggy bank.
  Map<String, dynamic> toJsonApi() => jsonApiMember(
    type: 'piggy_banks',
    id: fireflyId,
    attributes: <String, dynamic>{
      'name': name,
      if (accountId != null) 'account_id': accountId,
      if (targetAmount != null) 'target_amount': targetAmount,
      if (currentAmount != null) 'current_amount': currentAmount,
      if (startDate != null) 'start_date': dateTimeToJson(startDate),
      if (targetDate != null) 'target_date': dateTimeToJson(targetDate),
      if (currencyCode != null) 'currency_code': currencyCode,
      if (currencyId != null) 'currency_id': currencyId,
      if (notes != null) 'notes': notes,
      if (orderIndex != null) 'order': orderIndex,
      if (remoteUpdatedAt != null)
        'updated_at': dateTimeToJson(remoteUpdatedAt),
    },
  );

  /// The `piggy_banks` row for this piggy bank.
  Map<String, Object?> toRow() => <String, Object?>{
    'id': id,
    'name': name,
    'account_id': accountId,
    'target_amount': targetAmount,
    'current_amount': currentAmount,
    'start_date': dateTimeToIso(startDate),
    'target_date': dateTimeToIso(targetDate),
    'currency_code': currencyCode,
    'currency_id': currencyId,
    'notes': notes,
    'order_index': orderIndex,
    'firefly_id': fireflyId,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'remote_updated_at': dateTimeToMillis(remoteUpdatedAt),
    'sync_status': syncStatusToRow(syncStatus),
    'deleted_at': dateTimeToMillis(deletedAt),
    'seq': seq,
  };
}
