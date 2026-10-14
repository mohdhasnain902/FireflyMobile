// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'account.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Account {

 String get id; String get name; String get type; DateTime get updatedAt; int get seq; String? get currencyCode; String? get currencyId; String? get accountRole; String? get openingBalance; DateTime? get openingBalanceDate; String? get iban; String? get bic; String? get accountNumber; String? get virtualBalance; String? get notes; String? get fireflyId; bool get active; bool get includeNetWorth; int? get orderIndex; DateTime? get remoteUpdatedAt; SyncStatus get syncStatus; DateTime? get deletedAt;
/// Create a copy of Account
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountCopyWith<Account> get copyWith => _$AccountCopyWithImpl<Account>(this as Account, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as Account;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Account&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.type, _this.type) || other.type == _this.type)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&(identical(other.seq, _this.seq) || other.seq == _this.seq)&&(identical(other.currencyCode, _this.currencyCode) || other.currencyCode == _this.currencyCode)&&(identical(other.currencyId, _this.currencyId) || other.currencyId == _this.currencyId)&&(identical(other.accountRole, _this.accountRole) || other.accountRole == _this.accountRole)&&(identical(other.openingBalance, _this.openingBalance) || other.openingBalance == _this.openingBalance)&&(identical(other.openingBalanceDate, _this.openingBalanceDate) || other.openingBalanceDate == _this.openingBalanceDate)&&(identical(other.iban, _this.iban) || other.iban == _this.iban)&&(identical(other.bic, _this.bic) || other.bic == _this.bic)&&(identical(other.accountNumber, _this.accountNumber) || other.accountNumber == _this.accountNumber)&&(identical(other.virtualBalance, _this.virtualBalance) || other.virtualBalance == _this.virtualBalance)&&(identical(other.notes, _this.notes) || other.notes == _this.notes)&&(identical(other.fireflyId, _this.fireflyId) || other.fireflyId == _this.fireflyId)&&(identical(other.active, _this.active) || other.active == _this.active)&&(identical(other.includeNetWorth, _this.includeNetWorth) || other.includeNetWorth == _this.includeNetWorth)&&(identical(other.orderIndex, _this.orderIndex) || other.orderIndex == _this.orderIndex)&&(identical(other.remoteUpdatedAt, _this.remoteUpdatedAt) || other.remoteUpdatedAt == _this.remoteUpdatedAt)&&(identical(other.syncStatus, _this.syncStatus) || other.syncStatus == _this.syncStatus)&&(identical(other.deletedAt, _this.deletedAt) || other.deletedAt == _this.deletedAt));
}


@override
int get hashCode {
  final _this = this as Account;
  return Object.hashAll([runtimeType,_this.id,_this.name,_this.type,_this.updatedAt,_this.seq,_this.currencyCode,_this.currencyId,_this.accountRole,_this.openingBalance,_this.openingBalanceDate,_this.iban,_this.bic,_this.accountNumber,_this.virtualBalance,_this.notes,_this.fireflyId,_this.active,_this.includeNetWorth,_this.orderIndex,_this.remoteUpdatedAt,_this.syncStatus,_this.deletedAt]);
}

@override
String toString() {
  final _this = this as Account;
  return 'Account(id: ${_this.id}, name: ${_this.name}, type: ${_this.type}, updatedAt: ${_this.updatedAt}, seq: ${_this.seq}, currencyCode: ${_this.currencyCode}, currencyId: ${_this.currencyId}, accountRole: ${_this.accountRole}, openingBalance: ${_this.openingBalance}, openingBalanceDate: ${_this.openingBalanceDate}, iban: ${_this.iban}, bic: ${_this.bic}, accountNumber: ${_this.accountNumber}, virtualBalance: ${_this.virtualBalance}, notes: ${_this.notes}, fireflyId: ${_this.fireflyId}, active: ${_this.active}, includeNetWorth: ${_this.includeNetWorth}, orderIndex: ${_this.orderIndex}, remoteUpdatedAt: ${_this.remoteUpdatedAt}, syncStatus: ${_this.syncStatus}, deletedAt: ${_this.deletedAt})';
}


}

/// @nodoc
abstract mixin class $AccountCopyWith<$Res>  {
  factory $AccountCopyWith(Account value, $Res Function(Account) _then) = _$AccountCopyWithImpl;
@useResult
$Res call({
 String id, String name, String type, DateTime updatedAt, int seq, String? currencyCode, String? currencyId, String? accountRole, String? openingBalance, DateTime? openingBalanceDate, String? iban, String? bic, String? accountNumber, String? virtualBalance, String? notes, String? fireflyId, bool active, bool includeNetWorth, int? orderIndex, DateTime? remoteUpdatedAt, SyncStatus syncStatus, DateTime? deletedAt
});




}
/// @nodoc
class _$AccountCopyWithImpl<$Res>
    implements $AccountCopyWith<$Res> {
  _$AccountCopyWithImpl(this._self, this._then);

  final Account _self;
  final $Res Function(Account) _then;

/// Create a copy of Account
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? type = null,Object? updatedAt = null,Object? seq = null,Object? currencyCode = freezed,Object? currencyId = freezed,Object? accountRole = freezed,Object? openingBalance = freezed,Object? openingBalanceDate = freezed,Object? iban = freezed,Object? bic = freezed,Object? accountNumber = freezed,Object? virtualBalance = freezed,Object? notes = freezed,Object? fireflyId = freezed,Object? active = null,Object? includeNetWorth = null,Object? orderIndex = freezed,Object? remoteUpdatedAt = freezed,Object? syncStatus = null,Object? deletedAt = freezed,}) {
  return _then(Account(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,seq: null == seq ? _self.seq : seq // ignore: cast_nullable_to_non_nullable
as int,currencyCode: freezed == currencyCode ? _self.currencyCode : currencyCode // ignore: cast_nullable_to_non_nullable
as String?,currencyId: freezed == currencyId ? _self.currencyId : currencyId // ignore: cast_nullable_to_non_nullable
as String?,accountRole: freezed == accountRole ? _self.accountRole : accountRole // ignore: cast_nullable_to_non_nullable
as String?,openingBalance: freezed == openingBalance ? _self.openingBalance : openingBalance // ignore: cast_nullable_to_non_nullable
as String?,openingBalanceDate: freezed == openingBalanceDate ? _self.openingBalanceDate : openingBalanceDate // ignore: cast_nullable_to_non_nullable
as DateTime?,iban: freezed == iban ? _self.iban : iban // ignore: cast_nullable_to_non_nullable
as String?,bic: freezed == bic ? _self.bic : bic // ignore: cast_nullable_to_non_nullable
as String?,accountNumber: freezed == accountNumber ? _self.accountNumber : accountNumber // ignore: cast_nullable_to_non_nullable
as String?,virtualBalance: freezed == virtualBalance ? _self.virtualBalance : virtualBalance // ignore: cast_nullable_to_non_nullable
as String?,notes: freezed == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String?,fireflyId: freezed == fireflyId ? _self.fireflyId : fireflyId // ignore: cast_nullable_to_non_nullable
as String?,active: null == active ? _self.active : active // ignore: cast_nullable_to_non_nullable
as bool,includeNetWorth: null == includeNetWorth ? _self.includeNetWorth : includeNetWorth // ignore: cast_nullable_to_non_nullable
as bool,orderIndex: freezed == orderIndex ? _self.orderIndex : orderIndex // ignore: cast_nullable_to_non_nullable
as int?,remoteUpdatedAt: freezed == remoteUpdatedAt ? _self.remoteUpdatedAt : remoteUpdatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,syncStatus: null == syncStatus ? _self.syncStatus : syncStatus // ignore: cast_nullable_to_non_nullable
as SyncStatus,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [Account].
extension AccountPatterns on Account {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Account value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Account() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Account value)  $default,){
final _that = this;
switch (_that) {
case _Account():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Account value)?  $default,){
final _that = this;
switch (_that) {
case _Account() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String type,  DateTime updatedAt,  int seq,  String? currencyCode,  String? currencyId,  String? accountRole,  String? openingBalance,  DateTime? openingBalanceDate,  String? iban,  String? bic,  String? accountNumber,  String? virtualBalance,  String? notes,  String? fireflyId,  bool active,  bool includeNetWorth,  int? orderIndex,  DateTime? remoteUpdatedAt,  SyncStatus syncStatus,  DateTime? deletedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Account() when $default != null:
return $default(_that.id,_that.name,_that.type,_that.updatedAt,_that.seq,_that.currencyCode,_that.currencyId,_that.accountRole,_that.openingBalance,_that.openingBalanceDate,_that.iban,_that.bic,_that.accountNumber,_that.virtualBalance,_that.notes,_that.fireflyId,_that.active,_that.includeNetWorth,_that.orderIndex,_that.remoteUpdatedAt,_that.syncStatus,_that.deletedAt);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String type,  DateTime updatedAt,  int seq,  String? currencyCode,  String? currencyId,  String? accountRole,  String? openingBalance,  DateTime? openingBalanceDate,  String? iban,  String? bic,  String? accountNumber,  String? virtualBalance,  String? notes,  String? fireflyId,  bool active,  bool includeNetWorth,  int? orderIndex,  DateTime? remoteUpdatedAt,  SyncStatus syncStatus,  DateTime? deletedAt)  $default,) {final _that = this;
switch (_that) {
case _Account():
return $default(_that.id,_that.name,_that.type,_that.updatedAt,_that.seq,_that.currencyCode,_that.currencyId,_that.accountRole,_that.openingBalance,_that.openingBalanceDate,_that.iban,_that.bic,_that.accountNumber,_that.virtualBalance,_that.notes,_that.fireflyId,_that.active,_that.includeNetWorth,_that.orderIndex,_that.remoteUpdatedAt,_that.syncStatus,_that.deletedAt);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String type,  DateTime updatedAt,  int seq,  String? currencyCode,  String? currencyId,  String? accountRole,  String? openingBalance,  DateTime? openingBalanceDate,  String? iban,  String? bic,  String? accountNumber,  String? virtualBalance,  String? notes,  String? fireflyId,  bool active,  bool includeNetWorth,  int? orderIndex,  DateTime? remoteUpdatedAt,  SyncStatus syncStatus,  DateTime? deletedAt)?  $default,) {final _that = this;
switch (_that) {
case _Account() when $default != null:
return $default(_that.id,_that.name,_that.type,_that.updatedAt,_that.seq,_that.currencyCode,_that.currencyId,_that.accountRole,_that.openingBalance,_that.openingBalanceDate,_that.iban,_that.bic,_that.accountNumber,_that.virtualBalance,_that.notes,_that.fireflyId,_that.active,_that.includeNetWorth,_that.orderIndex,_that.remoteUpdatedAt,_that.syncStatus,_that.deletedAt);case _:
  return null;

}
}

}

/// @nodoc


class _Account extends Account {
  const _Account({required this.id, required this.name, required this.type, required this.updatedAt, required this.seq, this.currencyCode, this.currencyId, this.accountRole, this.openingBalance, this.openingBalanceDate, this.iban, this.bic, this.accountNumber, this.virtualBalance, this.notes, this.fireflyId, this.active = true, this.includeNetWorth = true, this.orderIndex, this.remoteUpdatedAt, this.syncStatus = SyncStatus.pending, this.deletedAt}): super._();
  

@override final  String id;
@override final  String name;
@override final  String type;
@override final  DateTime updatedAt;
@override final  int seq;
@override final  String? currencyCode;
@override final  String? currencyId;
@override final  String? accountRole;
@override final  String? openingBalance;
@override final  DateTime? openingBalanceDate;
@override final  String? iban;
@override final  String? bic;
@override final  String? accountNumber;
@override final  String? virtualBalance;
@override final  String? notes;
@override final  String? fireflyId;
@override@JsonKey() final  bool active;
@override@JsonKey() final  bool includeNetWorth;
@override final  int? orderIndex;
@override final  DateTime? remoteUpdatedAt;
@override@JsonKey() final  SyncStatus syncStatus;
@override final  DateTime? deletedAt;

/// Create a copy of Account
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountCopyWith<_Account> get copyWith => __$AccountCopyWithImpl<_Account>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _Account&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.type, type) || other.type == type)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.seq, seq) || other.seq == seq)&&(identical(other.currencyCode, currencyCode) || other.currencyCode == currencyCode)&&(identical(other.currencyId, currencyId) || other.currencyId == currencyId)&&(identical(other.accountRole, accountRole) || other.accountRole == accountRole)&&(identical(other.openingBalance, openingBalance) || other.openingBalance == openingBalance)&&(identical(other.openingBalanceDate, openingBalanceDate) || other.openingBalanceDate == openingBalanceDate)&&(identical(other.iban, iban) || other.iban == iban)&&(identical(other.bic, bic) || other.bic == bic)&&(identical(other.accountNumber, accountNumber) || other.accountNumber == accountNumber)&&(identical(other.virtualBalance, virtualBalance) || other.virtualBalance == virtualBalance)&&(identical(other.notes, notes) || other.notes == notes)&&(identical(other.fireflyId, fireflyId) || other.fireflyId == fireflyId)&&(identical(other.active, active) || other.active == active)&&(identical(other.includeNetWorth, includeNetWorth) || other.includeNetWorth == includeNetWorth)&&(identical(other.orderIndex, orderIndex) || other.orderIndex == orderIndex)&&(identical(other.remoteUpdatedAt, remoteUpdatedAt) || other.remoteUpdatedAt == remoteUpdatedAt)&&(identical(other.syncStatus, syncStatus) || other.syncStatus == syncStatus)&&(identical(other.deletedAt, deletedAt) || other.deletedAt == deletedAt));
}


@override
int get hashCode {
    return Object.hashAll([runtimeType,id,name,type,updatedAt,seq,currencyCode,currencyId,accountRole,openingBalance,openingBalanceDate,iban,bic,accountNumber,virtualBalance,notes,fireflyId,active,includeNetWorth,orderIndex,remoteUpdatedAt,syncStatus,deletedAt]);
}

@override
String toString() {
    return 'Account(id: $id, name: $name, type: $type, updatedAt: $updatedAt, seq: $seq, currencyCode: $currencyCode, currencyId: $currencyId, accountRole: $accountRole, openingBalance: $openingBalance, openingBalanceDate: $openingBalanceDate, iban: $iban, bic: $bic, accountNumber: $accountNumber, virtualBalance: $virtualBalance, notes: $notes, fireflyId: $fireflyId, active: $active, includeNetWorth: $includeNetWorth, orderIndex: $orderIndex, remoteUpdatedAt: $remoteUpdatedAt, syncStatus: $syncStatus, deletedAt: $deletedAt)';
}


}

/// @nodoc
abstract mixin class _$AccountCopyWith<$Res> implements $AccountCopyWith<$Res> {
  factory _$AccountCopyWith(_Account value, $Res Function(_Account) _then) = __$AccountCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String type, DateTime updatedAt, int seq, String? currencyCode, String? currencyId, String? accountRole, String? openingBalance, DateTime? openingBalanceDate, String? iban, String? bic, String? accountNumber, String? virtualBalance, String? notes, String? fireflyId, bool active, bool includeNetWorth, int? orderIndex, DateTime? remoteUpdatedAt, SyncStatus syncStatus, DateTime? deletedAt
});




}
/// @nodoc
class __$AccountCopyWithImpl<$Res>
    implements _$AccountCopyWith<$Res> {
  __$AccountCopyWithImpl(this._self, this._then);

  final _Account _self;
  final $Res Function(_Account) _then;

/// Create a copy of Account
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? type = null,Object? updatedAt = null,Object? seq = null,Object? currencyCode = freezed,Object? currencyId = freezed,Object? accountRole = freezed,Object? openingBalance = freezed,Object? openingBalanceDate = freezed,Object? iban = freezed,Object? bic = freezed,Object? accountNumber = freezed,Object? virtualBalance = freezed,Object? notes = freezed,Object? fireflyId = freezed,Object? active = null,Object? includeNetWorth = null,Object? orderIndex = freezed,Object? remoteUpdatedAt = freezed,Object? syncStatus = null,Object? deletedAt = freezed,}) {
  return _then(_Account(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,seq: null == seq ? _self.seq : seq // ignore: cast_nullable_to_non_nullable
as int,currencyCode: freezed == currencyCode ? _self.currencyCode : currencyCode // ignore: cast_nullable_to_non_nullable
as String?,currencyId: freezed == currencyId ? _self.currencyId : currencyId // ignore: cast_nullable_to_non_nullable
as String?,accountRole: freezed == accountRole ? _self.accountRole : accountRole // ignore: cast_nullable_to_non_nullable
as String?,openingBalance: freezed == openingBalance ? _self.openingBalance : openingBalance // ignore: cast_nullable_to_non_nullable
as String?,openingBalanceDate: freezed == openingBalanceDate ? _self.openingBalanceDate : openingBalanceDate // ignore: cast_nullable_to_non_nullable
as DateTime?,iban: freezed == iban ? _self.iban : iban // ignore: cast_nullable_to_non_nullable
as String?,bic: freezed == bic ? _self.bic : bic // ignore: cast_nullable_to_non_nullable
as String?,accountNumber: freezed == accountNumber ? _self.accountNumber : accountNumber // ignore: cast_nullable_to_non_nullable
as String?,virtualBalance: freezed == virtualBalance ? _self.virtualBalance : virtualBalance // ignore: cast_nullable_to_non_nullable
as String?,notes: freezed == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String?,fireflyId: freezed == fireflyId ? _self.fireflyId : fireflyId // ignore: cast_nullable_to_non_nullable
as String?,active: null == active ? _self.active : active // ignore: cast_nullable_to_non_nullable
as bool,includeNetWorth: null == includeNetWorth ? _self.includeNetWorth : includeNetWorth // ignore: cast_nullable_to_non_nullable
as bool,orderIndex: freezed == orderIndex ? _self.orderIndex : orderIndex // ignore: cast_nullable_to_non_nullable
as int?,remoteUpdatedAt: freezed == remoteUpdatedAt ? _self.remoteUpdatedAt : remoteUpdatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,syncStatus: null == syncStatus ? _self.syncStatus : syncStatus // ignore: cast_nullable_to_non_nullable
as SyncStatus,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

// dart format on
