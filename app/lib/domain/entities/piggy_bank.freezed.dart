// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'piggy_bank.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$PiggyBank {

 String get id; String get name; DateTime get updatedAt; int get seq; String? get accountId; String? get targetAmount; String? get currentAmount; DateTime? get startDate; DateTime? get targetDate; String? get currencyCode; String? get currencyId; String? get notes; String? get fireflyId; int? get orderIndex; DateTime? get remoteUpdatedAt; SyncStatus get syncStatus; DateTime? get deletedAt;
/// Create a copy of PiggyBank
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PiggyBankCopyWith<PiggyBank> get copyWith => _$PiggyBankCopyWithImpl<PiggyBank>(this as PiggyBank, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PiggyBank;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PiggyBank&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&(identical(other.seq, _this.seq) || other.seq == _this.seq)&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId)&&(identical(other.targetAmount, _this.targetAmount) || other.targetAmount == _this.targetAmount)&&(identical(other.currentAmount, _this.currentAmount) || other.currentAmount == _this.currentAmount)&&(identical(other.startDate, _this.startDate) || other.startDate == _this.startDate)&&(identical(other.targetDate, _this.targetDate) || other.targetDate == _this.targetDate)&&(identical(other.currencyCode, _this.currencyCode) || other.currencyCode == _this.currencyCode)&&(identical(other.currencyId, _this.currencyId) || other.currencyId == _this.currencyId)&&(identical(other.notes, _this.notes) || other.notes == _this.notes)&&(identical(other.fireflyId, _this.fireflyId) || other.fireflyId == _this.fireflyId)&&(identical(other.orderIndex, _this.orderIndex) || other.orderIndex == _this.orderIndex)&&(identical(other.remoteUpdatedAt, _this.remoteUpdatedAt) || other.remoteUpdatedAt == _this.remoteUpdatedAt)&&(identical(other.syncStatus, _this.syncStatus) || other.syncStatus == _this.syncStatus)&&(identical(other.deletedAt, _this.deletedAt) || other.deletedAt == _this.deletedAt));
}


@override
int get hashCode {
  final _this = this as PiggyBank;
  return Object.hash(runtimeType,_this.id,_this.name,_this.updatedAt,_this.seq,_this.accountId,_this.targetAmount,_this.currentAmount,_this.startDate,_this.targetDate,_this.currencyCode,_this.currencyId,_this.notes,_this.fireflyId,_this.orderIndex,_this.remoteUpdatedAt,_this.syncStatus,_this.deletedAt);
}

@override
String toString() {
  final _this = this as PiggyBank;
  return 'PiggyBank(id: ${_this.id}, name: ${_this.name}, updatedAt: ${_this.updatedAt}, seq: ${_this.seq}, accountId: ${_this.accountId}, targetAmount: ${_this.targetAmount}, currentAmount: ${_this.currentAmount}, startDate: ${_this.startDate}, targetDate: ${_this.targetDate}, currencyCode: ${_this.currencyCode}, currencyId: ${_this.currencyId}, notes: ${_this.notes}, fireflyId: ${_this.fireflyId}, orderIndex: ${_this.orderIndex}, remoteUpdatedAt: ${_this.remoteUpdatedAt}, syncStatus: ${_this.syncStatus}, deletedAt: ${_this.deletedAt})';
}


}

/// @nodoc
abstract mixin class $PiggyBankCopyWith<$Res>  {
  factory $PiggyBankCopyWith(PiggyBank value, $Res Function(PiggyBank) _then) = _$PiggyBankCopyWithImpl;
@useResult
$Res call({
 String id, String name, DateTime updatedAt, int seq, String? accountId, String? targetAmount, String? currentAmount, DateTime? startDate, DateTime? targetDate, String? currencyCode, String? currencyId, String? notes, String? fireflyId, int? orderIndex, DateTime? remoteUpdatedAt, SyncStatus syncStatus, DateTime? deletedAt
});




}
/// @nodoc
class _$PiggyBankCopyWithImpl<$Res>
    implements $PiggyBankCopyWith<$Res> {
  _$PiggyBankCopyWithImpl(this._self, this._then);

  final PiggyBank _self;
  final $Res Function(PiggyBank) _then;

/// Create a copy of PiggyBank
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? updatedAt = null,Object? seq = null,Object? accountId = freezed,Object? targetAmount = freezed,Object? currentAmount = freezed,Object? startDate = freezed,Object? targetDate = freezed,Object? currencyCode = freezed,Object? currencyId = freezed,Object? notes = freezed,Object? fireflyId = freezed,Object? orderIndex = freezed,Object? remoteUpdatedAt = freezed,Object? syncStatus = null,Object? deletedAt = freezed,}) {
  return _then(PiggyBank(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,seq: null == seq ? _self.seq : seq // ignore: cast_nullable_to_non_nullable
as int,accountId: freezed == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String?,targetAmount: freezed == targetAmount ? _self.targetAmount : targetAmount // ignore: cast_nullable_to_non_nullable
as String?,currentAmount: freezed == currentAmount ? _self.currentAmount : currentAmount // ignore: cast_nullable_to_non_nullable
as String?,startDate: freezed == startDate ? _self.startDate : startDate // ignore: cast_nullable_to_non_nullable
as DateTime?,targetDate: freezed == targetDate ? _self.targetDate : targetDate // ignore: cast_nullable_to_non_nullable
as DateTime?,currencyCode: freezed == currencyCode ? _self.currencyCode : currencyCode // ignore: cast_nullable_to_non_nullable
as String?,currencyId: freezed == currencyId ? _self.currencyId : currencyId // ignore: cast_nullable_to_non_nullable
as String?,notes: freezed == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String?,fireflyId: freezed == fireflyId ? _self.fireflyId : fireflyId // ignore: cast_nullable_to_non_nullable
as String?,orderIndex: freezed == orderIndex ? _self.orderIndex : orderIndex // ignore: cast_nullable_to_non_nullable
as int?,remoteUpdatedAt: freezed == remoteUpdatedAt ? _self.remoteUpdatedAt : remoteUpdatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,syncStatus: null == syncStatus ? _self.syncStatus : syncStatus // ignore: cast_nullable_to_non_nullable
as SyncStatus,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [PiggyBank].
extension PiggyBankPatterns on PiggyBank {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PiggyBank value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PiggyBank() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PiggyBank value)  $default,){
final _that = this;
switch (_that) {
case _PiggyBank():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PiggyBank value)?  $default,){
final _that = this;
switch (_that) {
case _PiggyBank() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  DateTime updatedAt,  int seq,  String? accountId,  String? targetAmount,  String? currentAmount,  DateTime? startDate,  DateTime? targetDate,  String? currencyCode,  String? currencyId,  String? notes,  String? fireflyId,  int? orderIndex,  DateTime? remoteUpdatedAt,  SyncStatus syncStatus,  DateTime? deletedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PiggyBank() when $default != null:
return $default(_that.id,_that.name,_that.updatedAt,_that.seq,_that.accountId,_that.targetAmount,_that.currentAmount,_that.startDate,_that.targetDate,_that.currencyCode,_that.currencyId,_that.notes,_that.fireflyId,_that.orderIndex,_that.remoteUpdatedAt,_that.syncStatus,_that.deletedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  DateTime updatedAt,  int seq,  String? accountId,  String? targetAmount,  String? currentAmount,  DateTime? startDate,  DateTime? targetDate,  String? currencyCode,  String? currencyId,  String? notes,  String? fireflyId,  int? orderIndex,  DateTime? remoteUpdatedAt,  SyncStatus syncStatus,  DateTime? deletedAt)  $default,) {final _that = this;
switch (_that) {
case _PiggyBank():
return $default(_that.id,_that.name,_that.updatedAt,_that.seq,_that.accountId,_that.targetAmount,_that.currentAmount,_that.startDate,_that.targetDate,_that.currencyCode,_that.currencyId,_that.notes,_that.fireflyId,_that.orderIndex,_that.remoteUpdatedAt,_that.syncStatus,_that.deletedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  DateTime updatedAt,  int seq,  String? accountId,  String? targetAmount,  String? currentAmount,  DateTime? startDate,  DateTime? targetDate,  String? currencyCode,  String? currencyId,  String? notes,  String? fireflyId,  int? orderIndex,  DateTime? remoteUpdatedAt,  SyncStatus syncStatus,  DateTime? deletedAt)?  $default,) {final _that = this;
switch (_that) {
case _PiggyBank() when $default != null:
return $default(_that.id,_that.name,_that.updatedAt,_that.seq,_that.accountId,_that.targetAmount,_that.currentAmount,_that.startDate,_that.targetDate,_that.currencyCode,_that.currencyId,_that.notes,_that.fireflyId,_that.orderIndex,_that.remoteUpdatedAt,_that.syncStatus,_that.deletedAt);case _:
  return null;

}
}

}

/// @nodoc


class _PiggyBank extends PiggyBank {
  const _PiggyBank({required this.id, required this.name, required this.updatedAt, required this.seq, this.accountId, this.targetAmount, this.currentAmount, this.startDate, this.targetDate, this.currencyCode, this.currencyId, this.notes, this.fireflyId, this.orderIndex, this.remoteUpdatedAt, this.syncStatus = SyncStatus.pending, this.deletedAt}): super._();
  

@override final  String id;
@override final  String name;
@override final  DateTime updatedAt;
@override final  int seq;
@override final  String? accountId;
@override final  String? targetAmount;
@override final  String? currentAmount;
@override final  DateTime? startDate;
@override final  DateTime? targetDate;
@override final  String? currencyCode;
@override final  String? currencyId;
@override final  String? notes;
@override final  String? fireflyId;
@override final  int? orderIndex;
@override final  DateTime? remoteUpdatedAt;
@override@JsonKey() final  SyncStatus syncStatus;
@override final  DateTime? deletedAt;

/// Create a copy of PiggyBank
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PiggyBankCopyWith<_PiggyBank> get copyWith => __$PiggyBankCopyWithImpl<_PiggyBank>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PiggyBank&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.seq, seq) || other.seq == seq)&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.targetAmount, targetAmount) || other.targetAmount == targetAmount)&&(identical(other.currentAmount, currentAmount) || other.currentAmount == currentAmount)&&(identical(other.startDate, startDate) || other.startDate == startDate)&&(identical(other.targetDate, targetDate) || other.targetDate == targetDate)&&(identical(other.currencyCode, currencyCode) || other.currencyCode == currencyCode)&&(identical(other.currencyId, currencyId) || other.currencyId == currencyId)&&(identical(other.notes, notes) || other.notes == notes)&&(identical(other.fireflyId, fireflyId) || other.fireflyId == fireflyId)&&(identical(other.orderIndex, orderIndex) || other.orderIndex == orderIndex)&&(identical(other.remoteUpdatedAt, remoteUpdatedAt) || other.remoteUpdatedAt == remoteUpdatedAt)&&(identical(other.syncStatus, syncStatus) || other.syncStatus == syncStatus)&&(identical(other.deletedAt, deletedAt) || other.deletedAt == deletedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,name,updatedAt,seq,accountId,targetAmount,currentAmount,startDate,targetDate,currencyCode,currencyId,notes,fireflyId,orderIndex,remoteUpdatedAt,syncStatus,deletedAt);
}

@override
String toString() {
    return 'PiggyBank(id: $id, name: $name, updatedAt: $updatedAt, seq: $seq, accountId: $accountId, targetAmount: $targetAmount, currentAmount: $currentAmount, startDate: $startDate, targetDate: $targetDate, currencyCode: $currencyCode, currencyId: $currencyId, notes: $notes, fireflyId: $fireflyId, orderIndex: $orderIndex, remoteUpdatedAt: $remoteUpdatedAt, syncStatus: $syncStatus, deletedAt: $deletedAt)';
}


}

/// @nodoc
abstract mixin class _$PiggyBankCopyWith<$Res> implements $PiggyBankCopyWith<$Res> {
  factory _$PiggyBankCopyWith(_PiggyBank value, $Res Function(_PiggyBank) _then) = __$PiggyBankCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, DateTime updatedAt, int seq, String? accountId, String? targetAmount, String? currentAmount, DateTime? startDate, DateTime? targetDate, String? currencyCode, String? currencyId, String? notes, String? fireflyId, int? orderIndex, DateTime? remoteUpdatedAt, SyncStatus syncStatus, DateTime? deletedAt
});




}
/// @nodoc
class __$PiggyBankCopyWithImpl<$Res>
    implements _$PiggyBankCopyWith<$Res> {
  __$PiggyBankCopyWithImpl(this._self, this._then);

  final _PiggyBank _self;
  final $Res Function(_PiggyBank) _then;

/// Create a copy of PiggyBank
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? updatedAt = null,Object? seq = null,Object? accountId = freezed,Object? targetAmount = freezed,Object? currentAmount = freezed,Object? startDate = freezed,Object? targetDate = freezed,Object? currencyCode = freezed,Object? currencyId = freezed,Object? notes = freezed,Object? fireflyId = freezed,Object? orderIndex = freezed,Object? remoteUpdatedAt = freezed,Object? syncStatus = null,Object? deletedAt = freezed,}) {
  return _then(_PiggyBank(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,seq: null == seq ? _self.seq : seq // ignore: cast_nullable_to_non_nullable
as int,accountId: freezed == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String?,targetAmount: freezed == targetAmount ? _self.targetAmount : targetAmount // ignore: cast_nullable_to_non_nullable
as String?,currentAmount: freezed == currentAmount ? _self.currentAmount : currentAmount // ignore: cast_nullable_to_non_nullable
as String?,startDate: freezed == startDate ? _self.startDate : startDate // ignore: cast_nullable_to_non_nullable
as DateTime?,targetDate: freezed == targetDate ? _self.targetDate : targetDate // ignore: cast_nullable_to_non_nullable
as DateTime?,currencyCode: freezed == currencyCode ? _self.currencyCode : currencyCode // ignore: cast_nullable_to_non_nullable
as String?,currencyId: freezed == currencyId ? _self.currencyId : currencyId // ignore: cast_nullable_to_non_nullable
as String?,notes: freezed == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String?,fireflyId: freezed == fireflyId ? _self.fireflyId : fireflyId // ignore: cast_nullable_to_non_nullable
as String?,orderIndex: freezed == orderIndex ? _self.orderIndex : orderIndex // ignore: cast_nullable_to_non_nullable
as int?,remoteUpdatedAt: freezed == remoteUpdatedAt ? _self.remoteUpdatedAt : remoteUpdatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,syncStatus: null == syncStatus ? _self.syncStatus : syncStatus // ignore: cast_nullable_to_non_nullable
as SyncStatus,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

// dart format on
