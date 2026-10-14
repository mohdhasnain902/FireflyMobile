import 'package:firefly_mobile/domain/entities/json_api.dart';
import 'package:firefly_mobile/domain/entities/row_codec.dart';
import 'package:firefly_mobile/domain/entities/sync_bookkeeping.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'account.freezed.dart';

/// A Firefly III account (DESIGN §3.1).
///
/// The captured list payload carries roughly forty attributes, of which the
/// schema stores fifteen — the rest are computed values (`current_balance`,
/// `pc_*`) that the app recalculates locally from the ledger, so mapping them
/// would freeze a derived number into a source of truth.
///
/// `order` on the wire becomes [orderIndex], the schema's sort-key column.
@freezed
abstract class Account with _$Account, SyncBookkeeping {
  /// Builds an account from its local and remote fields.
  const factory({
    required String id,
    required String name,
    required String type,
    required DateTime updatedAt,
    required int seq,
    String? currencyCode,
    String? currencyId,
    String? accountRole,
    String? openingBalance,
    DateTime? openingBalanceDate,
    String? iban,
    String? bic,
    String? accountNumber,
    String? virtualBalance,
    String? notes,
    String? fireflyId,
    @Default(true) bool active,
    @Default(true) bool includeNetWorth,
    int? orderIndex,
    DateTime? remoteUpdatedAt,
    @Default(SyncStatus.pending) SyncStatus syncStatus,
    DateTime? deletedAt,
  }) = _Account;

  const new _();

  /// Rebuilds an account from one JSON:API member object.
  factory fromJsonApi(
    Map<String, dynamic> member, {
    required String id,
    required DateTime updatedAt,
    required int seq,
    SyncStatus syncStatus = SyncStatus.synced,
    DateTime? deletedAt,
  }) {
    final attributes = jsonApiAttributes(member);
    return Account(
      id: id,
      name: jsonString(attributes, 'name') ?? '',
      type: jsonString(attributes, 'type') ?? '',
      currencyCode: jsonString(attributes, 'currency_code'),
      currencyId: jsonString(attributes, 'currency_id'),
      accountRole: jsonString(attributes, 'account_role'),
      openingBalance: jsonDecimal(attributes, 'opening_balance'),
      openingBalanceDate: isoJsonToDateTime(
        attributes['opening_balance_date'],
      ),
      iban: jsonString(attributes, 'iban'),
      bic: jsonString(attributes, 'bic'),
      accountNumber: jsonString(attributes, 'account_number'),
      virtualBalance: jsonDecimal(attributes, 'virtual_balance'),
      notes: jsonString(attributes, 'notes'),
      active: jsonBool(attributes, 'active', orElse: true),
      includeNetWorth: jsonBool(attributes, 'include_net_worth', orElse: true),
      orderIndex: jsonInt(attributes, 'order'),
      fireflyId: jsonApiId(member),
      updatedAt: updatedAt,
      remoteUpdatedAt: jsonApiUpdatedAt(attributes),
      syncStatus: syncStatus,
      deletedAt: deletedAt,
      seq: seq,
    );
  }

  /// Rebuilds an account from a row of the `accounts` table.
  factory fromRow(Map<String, Object?> row) => Account(
    id: row['id']! as String,
    name: row['name']! as String,
    type: row['type']! as String,
    currencyCode: row['currency_code'] as String?,
    currencyId: row['currency_id'] as String?,
    accountRole: row['account_role'] as String?,
    openingBalance: row['opening_balance'] as String?,
    openingBalanceDate: isoToDateTime(row['opening_balance_date'] as String?),
    iban: row['iban'] as String?,
    bic: row['bic'] as String?,
    accountNumber: row['account_number'] as String?,
    orderIndex: row['order_index'] as int?,
    active: sqliteBool(row['active'] as int?),
    virtualBalance: row['virtual_balance'] as String?,
    notes: row['notes'] as String?,
    includeNetWorth: sqliteBool(row['include_net_worth'] as int?),
    fireflyId: row['firefly_id'] as String?,
    updatedAt: millisToDateTime(row['updated_at']! as int)!,
    remoteUpdatedAt: millisToDateTime(row['remote_updated_at'] as int?),
    syncStatus: syncStatusFromRow(row['sync_status'] as String?),
    deletedAt: millisToDateTime(row['deleted_at'] as int?),
    seq: row['seq']! as int,
  );

  /// The JSON:API member object for this account.
  Map<String, dynamic> toJsonApi() => jsonApiMember(
    type: 'accounts',
    id: fireflyId,
    attributes: <String, dynamic>{
      'name': name,
      'type': type,
      if (currencyCode != null) 'currency_code': currencyCode,
      if (currencyId != null) 'currency_id': currencyId,
      if (accountRole != null) 'account_role': accountRole,
      if (openingBalance != null) 'opening_balance': openingBalance,
      if (openingBalanceDate != null)
        'opening_balance_date': dateTimeToJson(openingBalanceDate),
      if (iban != null) 'iban': iban,
      if (bic != null) 'bic': bic,
      if (accountNumber != null) 'account_number': accountNumber,
      if (orderIndex != null) 'order': orderIndex,
      'active': active,
      if (virtualBalance != null) 'virtual_balance': virtualBalance,
      if (notes != null) 'notes': notes,
      'include_net_worth': includeNetWorth,
      if (remoteUpdatedAt != null)
        'updated_at': dateTimeToJson(remoteUpdatedAt),
    },
  );

  /// The `accounts` row for this account, columns keyed by column name.
  Map<String, Object?> toRow() => <String, Object?>{
    'id': id,
    'name': name,
    'type': type,
    'currency_code': currencyCode,
    'currency_id': currencyId,
    'account_role': accountRole,
    'opening_balance': openingBalance,
    'opening_balance_date': dateTimeToIso(openingBalanceDate),
    'iban': iban,
    'bic': bic,
    'account_number': accountNumber,
    'order_index': orderIndex,
    'active': sqliteInt(value: active),
    'virtual_balance': virtualBalance,
    'notes': notes,
    'include_net_worth': sqliteInt(value: includeNetWorth),
    'firefly_id': fireflyId,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'remote_updated_at': dateTimeToMillis(remoteUpdatedAt),
    'sync_status': syncStatusToRow(syncStatus),
    'deleted_at': dateTimeToMillis(deletedAt),
    'seq': seq,
  };
}
