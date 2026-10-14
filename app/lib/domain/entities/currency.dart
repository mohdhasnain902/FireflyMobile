import 'package:firefly_mobile/domain/entities/json_api.dart';
import 'package:firefly_mobile/domain/entities/row_codec.dart';
import 'package:firefly_mobile/domain/entities/sync_bookkeeping.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'currency.freezed.dart';

/// A Firefly III currency (DESIGN §3.1).
///
/// Pull-only: the phone never creates or edits a currency, so [syncStatus] is
/// [SyncStatus.synced] in practice and no create payload is ever built for it.
///
/// `default` on the wire maps to [isDefault] because `default` is a Dart
/// reserved word, and `symbol_first` / `rate` are parsed defensively because
/// the captured list payload omits them — they must never fail a pull.
@freezed
abstract class Currency with _$Currency, SyncBookkeeping {
  /// Builds a currency from its local and remote fields.
  const factory({
    required String id,
    required String code,
    required String name,
    required DateTime updatedAt,
    required int seq,
    String? symbol,
    String? rate,
    String? fireflyId,
    @Default(false) bool symbolFirst,
    @Default(2) int decimalPlaces,
    @Default(true) bool enabled,
    @Default(false) bool isDefault,
    DateTime? remoteUpdatedAt,
    @Default(SyncStatus.pending) SyncStatus syncStatus,
    DateTime? deletedAt,
  }) = _Currency;

  const new _();

  /// Rebuilds a currency from one JSON:API member object.
  ///
  /// [member] is the unwrapped `{type, id, attributes}` object; [id],
  /// [updatedAt] and [seq] are the local-only fields JSON:API never carries.
  factory fromJsonApi(
    Map<String, dynamic> member, {
    required String id,
    required DateTime updatedAt,
    required int seq,
    SyncStatus syncStatus = SyncStatus.synced,
    DateTime? deletedAt,
  }) {
    final attributes = jsonApiAttributes(member);
    return Currency(
      id: id,
      code: jsonString(attributes, 'code') ?? '',
      name: jsonString(attributes, 'name') ?? '',
      symbol: jsonString(attributes, 'symbol'),
      symbolFirst: jsonBool(attributes, 'symbol_first'),
      decimalPlaces: jsonInt(attributes, 'decimal_places') ?? 2,
      enabled: jsonBool(attributes, 'enabled', orElse: true),
      isDefault: jsonBool(attributes, 'default'),
      rate: jsonString(attributes, 'rate'),
      fireflyId: jsonApiId(member),
      updatedAt: updatedAt,
      remoteUpdatedAt: jsonApiUpdatedAt(attributes),
      syncStatus: syncStatus,
      deletedAt: deletedAt,
      seq: seq,
    );
  }

  /// Rebuilds a currency from a row of the `currencies` table.
  factory fromRow(Map<String, Object?> row) => Currency(
    id: row['id']! as String,
    code: row['code']! as String,
    name: row['name']! as String,
    symbol: row['symbol'] as String?,
    symbolFirst: sqliteBool(row['symbol_first'] as int?),
    decimalPlaces: (row['decimal_places'] as int?) ?? 2,
    enabled: sqliteBool(row['enabled'] as int?),
    isDefault: sqliteBool(row['is_default'] as int?),
    rate: row['rate'] as String?,
    fireflyId: row['firefly_id'] as String?,
    updatedAt: millisToDateTime(row['updated_at']! as int)!,
    remoteUpdatedAt: millisToDateTime(row['remote_updated_at'] as int?),
    syncStatus: syncStatusFromRow(row['sync_status'] as String?),
    deletedAt: millisToDateTime(row['deleted_at'] as int?),
    seq: row['seq']! as int,
  );

  /// The JSON:API member object for this currency, as a server would return it.
  Map<String, dynamic> toJsonApi() => jsonApiMember(
    type: 'currencies',
    id: fireflyId,
    attributes: <String, dynamic>{
      'code': code,
      'name': name,
      if (symbol != null) 'symbol': symbol,
      'symbol_first': symbolFirst,
      'decimal_places': decimalPlaces,
      'enabled': enabled,
      'default': isDefault,
      if (rate != null) 'rate': rate,
      if (remoteUpdatedAt != null)
        'updated_at': dateTimeToJson(remoteUpdatedAt),
    },
  );

  /// The `currencies` row for this currency, columns keyed by column name.
  Map<String, Object?> toRow() => <String, Object?>{
    'id': id,
    'code': code,
    'name': name,
    'symbol': symbol,
    'symbol_first': sqliteInt(value: symbolFirst),
    'decimal_places': decimalPlaces,
    'enabled': sqliteInt(value: enabled),
    'is_default': sqliteInt(value: isDefault),
    'rate': rate,
    'firefly_id': fireflyId,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'remote_updated_at': dateTimeToMillis(remoteUpdatedAt),
    'sync_status': syncStatusToRow(syncStatus),
    'deleted_at': dateTimeToMillis(deletedAt),
    'seq': seq,
  };
}
