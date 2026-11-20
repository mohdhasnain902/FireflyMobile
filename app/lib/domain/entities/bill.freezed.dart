// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'bill.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Bill {

 String get id; String get name; String get amount; DateTime get updatedAt; int get seq; String? get currencyCode; String? get currencyId; String? get billDirection; String get repeatFreq; String? get payDates; String? get remainingAmount; DateTime? get nextExpectedMatch; String? get notes; String? get autoBudgetType; DateTime? get date; String? get fireflyId; int get skip; bool get active; DateTime? get remoteUpdatedAt; SyncStatus get syncStatus; DateTime? get deletedAt;
/// Create a copy of Bill
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BillCopyWith<Bill> get copyWith => _$BillCopyWithImpl<Bill>(this as Bill, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as Bill;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Bill&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.amount, _this.amount) || other.amount == _this.amount)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&(identical(other.seq, _this.seq) || other.seq == _this.seq)&&(identical(other.currencyCode, _this.currencyCode) || other.currencyCode == _this.currencyCode)&&(identical(other.currencyId, _this.currencyId) || other.currencyId == _this.currencyId)&&(identical(other.billDirection, _this.billDirection) || other.billDirection == _this.billDirection)&&(identical(other.repeatFreq, _this.repeatFreq) || other.repeatFreq == _this.repeatFreq)&&(identical(other.payDates, _this.payDates) || other.payDates == _this.payDates)&&(identical(other.remainingAmount, _this.remainingAmount) || other.remainingAmount == _this.remainingAmount)&&(identical(other.nextExpectedMatch, _this.nextExpectedMatch) || other.nextExpectedMatch == _this.nextExpectedMatch)&&(identical(other.notes, _this.notes) || other.notes == _this.notes)&&(identical(other.autoBudgetType, _this.autoBudgetType) || other.autoBudgetType == _this.autoBudgetType)&&(identical(other.date, _this.date) || other.date == _this.date)&&(identical(other.fireflyId, _this.fireflyId) || other.fireflyId == _this.fireflyId)&&(identical(other.skip, _this.skip) || other.skip == _this.skip)&&(identical(other.active, _this.active) || other.active == _this.active)&&(identical(other.remoteUpdatedAt, _this.remoteUpdatedAt) || other.remoteUpdatedAt == _this.remoteUpdatedAt)&&(identical(other.syncStatus, _this.syncStatus) || other.syncStatus == _this.syncStatus)&&(identical(other.deletedAt, _this.deletedAt) || other.deletedAt == _this.deletedAt));
}


@override
int get hashCode {
  final _this = this as Bill;
  return Object.hashAll([runtimeType,_this.id,_this.name,_this.amount,_this.updatedAt,_this.seq,_this.currencyCode,_this.currencyId,_this.billDirection,_this.repeatFreq,_this.payDates,_this.remainingAmount,_this.nextExpectedMatch,_this.notes,_this.autoBudgetType,_this.date,_this.fireflyId,_this.skip,_this.active,_this.remoteUpdatedAt,_this.syncStatus,_this.deletedAt]);
}

@override
String toString() {
  final _this = this as Bill;
  return 'Bill(id: ${_this.id}, name: ${_this.name}, amount: ${_this.amount}, updatedAt: ${_this.updatedAt}, seq: ${_this.seq}, currencyCode: ${_this.currencyCode}, currencyId: ${_this.currencyId}, billDirection: ${_this.billDirection}, repeatFreq: ${_this.repeatFreq}, payDates: ${_this.payDates}, remainingAmount: ${_this.remainingAmount}, nextExpectedMatch: ${_this.nextExpectedMatch}, notes: ${_this.notes}, autoBudgetType: ${_this.autoBudgetType}, date: ${_this.date}, fireflyId: ${_this.fireflyId}, skip: ${_this.skip}, active: ${_this.active}, remoteUpdatedAt: ${_this.remoteUpdatedAt}, syncStatus: ${_this.syncStatus}, deletedAt: ${_this.deletedAt})';
}


}

/// @nodoc
abstract mixin class $BillCopyWith<$Res>  {
  factory $BillCopyWith(Bill value, $Res Function(Bill) _then) = _$BillCopyWithImpl;
@useResult
$Res call({
 String id, String name, String amount, DateTime updatedAt, int seq, String? currencyCode, String? currencyId, String? billDirection, String repeatFreq, String? payDates, String? remainingAmount, DateTime? nextExpectedMatch, String? notes, String? autoBudgetType, DateTime? date, String? fireflyId, int skip, bool active, DateTime? remoteUpdatedAt, SyncStatus syncStatus, DateTime? deletedAt
});




}
/// @nodoc
class _$BillCopyWithImpl<$Res>
    implements $BillCopyWith<$Res> {
  _$BillCopyWithImpl(this._self, this._then);

  final Bill _self;
  final $Res Function(Bill) _then;

/// Create a copy of Bill
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? amount = null,Object? updatedAt = null,Object? seq = null,Object? currencyCode = freezed,Object? currencyId = freezed,Object? billDirection = freezed,Object? repeatFreq = null,Object? payDates = freezed,Object? remainingAmount = freezed,Object? nextExpectedMatch = freezed,Object? notes = freezed,Object? autoBudgetType = freezed,Object? date = freezed,Object? fireflyId = freezed,Object? skip = null,Object? active = null,Object? remoteUpdatedAt = freezed,Object? syncStatus = null,Object? deletedAt = freezed,}) {
  return _then(Bill(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,amount: null == amount ? _self.amount : amount // ignore: cast_nullable_to_non_nullable
as String,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,seq: null == seq ? _self.seq : seq // ignore: cast_nullable_to_non_nullable
as int,currencyCode: freezed == currencyCode ? _self.currencyCode : currencyCode // ignore: cast_nullable_to_non_nullable
as String?,currencyId: freezed == currencyId ? _self.currencyId : currencyId // ignore: cast_nullable_to_non_nullable
as String?,billDirection: freezed == billDirection ? _self.billDirection : billDirection // ignore: cast_nullable_to_non_nullable
as String?,repeatFreq: null == repeatFreq ? _self.repeatFreq : repeatFreq // ignore: cast_nullable_to_non_nullable
as String,payDates: freezed == payDates ? _self.payDates : payDates // ignore: cast_nullable_to_non_nullable
as String?,remainingAmount: freezed == remainingAmount ? _self.remainingAmount : remainingAmount // ignore: cast_nullable_to_non_nullable
as String?,nextExpectedMatch: freezed == nextExpectedMatch ? _self.nextExpectedMatch : nextExpectedMatch // ignore: cast_nullable_to_non_nullable
as DateTime?,notes: freezed == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String?,autoBudgetType: freezed == autoBudgetType ? _self.autoBudgetType : autoBudgetType // ignore: cast_nullable_to_non_nullable
as String?,date: freezed == date ? _self.date : date // ignore: cast_nullable_to_non_nullable
as DateTime?,fireflyId: freezed == fireflyId ? _self.fireflyId : fireflyId // ignore: cast_nullable_to_non_nullable
as String?,skip: null == skip ? _self.skip : skip // ignore: cast_nullable_to_non_nullable
as int,active: null == active ? _self.active : active // ignore: cast_nullable_to_non_nullable
as bool,remoteUpdatedAt: freezed == remoteUpdatedAt ? _self.remoteUpdatedAt : remoteUpdatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,syncStatus: null == syncStatus ? _self.syncStatus : syncStatus // ignore: cast_nullable_to_non_nullable
as SyncStatus,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [Bill].
extension BillPatterns on Bill {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Bill value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Bill() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Bill value)  $default,){
final _that = this;
switch (_that) {
case _Bill():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Bill value)?  $default,){
final _that = this;
switch (_that) {
case _Bill() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String amount,  DateTime updatedAt,  int seq,  String? currencyCode,  String? currencyId,  String? billDirection,  String repeatFreq,  String? payDates,  String? remainingAmount,  DateTime? nextExpectedMatch,  String? notes,  String? autoBudgetType,  DateTime? date,  String? fireflyId,  int skip,  bool active,  DateTime? remoteUpdatedAt,  SyncStatus syncStatus,  DateTime? deletedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Bill() when $default != null:
return $default(_that.id,_that.name,_that.amount,_that.updatedAt,_that.seq,_that.currencyCode,_that.currencyId,_that.billDirection,_that.repeatFreq,_that.payDates,_that.remainingAmount,_that.nextExpectedMatch,_that.notes,_that.autoBudgetType,_that.date,_that.fireflyId,_that.skip,_that.active,_that.remoteUpdatedAt,_that.syncStatus,_that.deletedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String amount,  DateTime updatedAt,  int seq,  String? currencyCode,  String? currencyId,  String? billDirection,  String repeatFreq,  String? payDates,  String? remainingAmount,  DateTime? nextExpectedMatch,  String? notes,  String? autoBudgetType,  DateTime? date,  String? fireflyId,  int skip,  bool active,  DateTime? remoteUpdatedAt,  SyncStatus syncStatus,  DateTime? deletedAt)  $default,) {final _that = this;
switch (_that) {
case _Bill():
return $default(_that.id,_that.name,_that.amount,_that.updatedAt,_that.seq,_that.currencyCode,_that.currencyId,_that.billDirection,_that.repeatFreq,_that.payDates,_that.remainingAmount,_that.nextExpectedMatch,_that.notes,_that.autoBudgetType,_that.date,_that.fireflyId,_that.skip,_that.active,_that.remoteUpdatedAt,_that.syncStatus,_that.deletedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String amount,  DateTime updatedAt,  int seq,  String? currencyCode,  String? currencyId,  String? billDirection,  String repeatFreq,  String? payDates,  String? remainingAmount,  DateTime? nextExpectedMatch,  String? notes,  String? autoBudgetType,  DateTime? date,  String? fireflyId,  int skip,  bool active,  DateTime? remoteUpdatedAt,  SyncStatus syncStatus,  DateTime? deletedAt)?  $default,) {final _that = this;
switch (_that) {
case _Bill() when $default != null:
return $default(_that.id,_that.name,_that.amount,_that.updatedAt,_that.seq,_that.currencyCode,_that.currencyId,_that.billDirection,_that.repeatFreq,_that.payDates,_that.remainingAmount,_that.nextExpectedMatch,_that.notes,_that.autoBudgetType,_that.date,_that.fireflyId,_that.skip,_that.active,_that.remoteUpdatedAt,_that.syncStatus,_that.deletedAt);case _:
  return null;

}
}

}

/// @nodoc


class _Bill extends Bill {
  const _Bill({required this.id, required this.name, required this.amount, required this.updatedAt, required this.seq, this.currencyCode, this.currencyId, this.billDirection, this.repeatFreq = 'monthly', this.payDates, this.remainingAmount, this.nextExpectedMatch, this.notes, this.autoBudgetType, this.date, this.fireflyId, this.skip = 0, this.active = true, this.remoteUpdatedAt, this.syncStatus = SyncStatus.pending, this.deletedAt}): super._();
  

@override final  String id;
@override final  String name;
@override final  String amount;
@override final  DateTime updatedAt;
@override final  int seq;
@override final  String? currencyCode;
@override final  String? currencyId;
@override final  String? billDirection;
@override@JsonKey() final  String repeatFreq;
@override final  String? payDates;
@override final  String? remainingAmount;
@override final  DateTime? nextExpectedMatch;
@override final  String? notes;
@override final  String? autoBudgetType;
@override final  DateTime? date;
@override final  String? fireflyId;
@override@JsonKey() final  int skip;
@override@JsonKey() final  bool active;
@override final  DateTime? remoteUpdatedAt;
@override@JsonKey() final  SyncStatus syncStatus;
@override final  DateTime? deletedAt;

/// Create a copy of Bill
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BillCopyWith<_Bill> get copyWith => __$BillCopyWithImpl<_Bill>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _Bill&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.amount, amount) || other.amount == amount)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.seq, seq) || other.seq == seq)&&(identical(other.currencyCode, currencyCode) || other.currencyCode == currencyCode)&&(identical(other.currencyId, currencyId) || other.currencyId == currencyId)&&(identical(other.billDirection, billDirection) || other.billDirection == billDirection)&&(identical(other.repeatFreq, repeatFreq) || other.repeatFreq == repeatFreq)&&(identical(other.payDates, payDates) || other.payDates == payDates)&&(identical(other.remainingAmount, remainingAmount) || other.remainingAmount == remainingAmount)&&(identical(other.nextExpectedMatch, nextExpectedMatch) || other.nextExpectedMatch == nextExpectedMatch)&&(identical(other.notes, notes) || other.notes == notes)&&(identical(other.autoBudgetType, autoBudgetType) || other.autoBudgetType == autoBudgetType)&&(identical(other.date, date) || other.date == date)&&(identical(other.fireflyId, fireflyId) || other.fireflyId == fireflyId)&&(identical(other.skip, skip) || other.skip == skip)&&(identical(other.active, active) || other.active == active)&&(identical(other.remoteUpdatedAt, remoteUpdatedAt) || other.remoteUpdatedAt == remoteUpdatedAt)&&(identical(other.syncStatus, syncStatus) || other.syncStatus == syncStatus)&&(identical(other.deletedAt, deletedAt) || other.deletedAt == deletedAt));
}


@override
int get hashCode {
    return Object.hashAll([runtimeType,id,name,amount,updatedAt,seq,currencyCode,currencyId,billDirection,repeatFreq,payDates,remainingAmount,nextExpectedMatch,notes,autoBudgetType,date,fireflyId,skip,active,remoteUpdatedAt,syncStatus,deletedAt]);
}

@override
String toString() {
    return 'Bill(id: $id, name: $name, amount: $amount, updatedAt: $updatedAt, seq: $seq, currencyCode: $currencyCode, currencyId: $currencyId, billDirection: $billDirection, repeatFreq: $repeatFreq, payDates: $payDates, remainingAmount: $remainingAmount, nextExpectedMatch: $nextExpectedMatch, notes: $notes, autoBudgetType: $autoBudgetType, date: $date, fireflyId: $fireflyId, skip: $skip, active: $active, remoteUpdatedAt: $remoteUpdatedAt, syncStatus: $syncStatus, deletedAt: $deletedAt)';
}


}

/// @nodoc
abstract mixin class _$BillCopyWith<$Res> implements $BillCopyWith<$Res> {
  factory _$BillCopyWith(_Bill value, $Res Function(_Bill) _then) = __$BillCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String amount, DateTime updatedAt, int seq, String? currencyCode, String? currencyId, String? billDirection, String repeatFreq, String? payDates, String? remainingAmount, DateTime? nextExpectedMatch, String? notes, String? autoBudgetType, DateTime? date, String? fireflyId, int skip, bool active, DateTime? remoteUpdatedAt, SyncStatus syncStatus, DateTime? deletedAt
});




}
/// @nodoc
class __$BillCopyWithImpl<$Res>
    implements _$BillCopyWith<$Res> {
  __$BillCopyWithImpl(this._self, this._then);

  final _Bill _self;
  final $Res Function(_Bill) _then;

/// Create a copy of Bill
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? amount = null,Object? updatedAt = null,Object? seq = null,Object? currencyCode = freezed,Object? currencyId = freezed,Object? billDirection = freezed,Object? repeatFreq = null,Object? payDates = freezed,Object? remainingAmount = freezed,Object? nextExpectedMatch = freezed,Object? notes = freezed,Object? autoBudgetType = freezed,Object? date = freezed,Object? fireflyId = freezed,Object? skip = null,Object? active = null,Object? remoteUpdatedAt = freezed,Object? syncStatus = null,Object? deletedAt = freezed,}) {
  return _then(_Bill(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,amount: null == amount ? _self.amount : amount // ignore: cast_nullable_to_non_nullable
as String,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,seq: null == seq ? _self.seq : seq // ignore: cast_nullable_to_non_nullable
as int,currencyCode: freezed == currencyCode ? _self.currencyCode : currencyCode // ignore: cast_nullable_to_non_nullable
as String?,currencyId: freezed == currencyId ? _self.currencyId : currencyId // ignore: cast_nullable_to_non_nullable
as String?,billDirection: freezed == billDirection ? _self.billDirection : billDirection // ignore: cast_nullable_to_non_nullable
as String?,repeatFreq: null == repeatFreq ? _self.repeatFreq : repeatFreq // ignore: cast_nullable_to_non_nullable
as String,payDates: freezed == payDates ? _self.payDates : payDates // ignore: cast_nullable_to_non_nullable
as String?,remainingAmount: freezed == remainingAmount ? _self.remainingAmount : remainingAmount // ignore: cast_nullable_to_non_nullable
as String?,nextExpectedMatch: freezed == nextExpectedMatch ? _self.nextExpectedMatch : nextExpectedMatch // ignore: cast_nullable_to_non_nullable
as DateTime?,notes: freezed == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String?,autoBudgetType: freezed == autoBudgetType ? _self.autoBudgetType : autoBudgetType // ignore: cast_nullable_to_non_nullable
as String?,date: freezed == date ? _self.date : date // ignore: cast_nullable_to_non_nullable
as DateTime?,fireflyId: freezed == fireflyId ? _self.fireflyId : fireflyId // ignore: cast_nullable_to_non_nullable
as String?,skip: null == skip ? _self.skip : skip // ignore: cast_nullable_to_non_nullable
as int,active: null == active ? _self.active : active // ignore: cast_nullable_to_non_nullable
as bool,remoteUpdatedAt: freezed == remoteUpdatedAt ? _self.remoteUpdatedAt : remoteUpdatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,syncStatus: null == syncStatus ? _self.syncStatus : syncStatus // ignore: cast_nullable_to_non_nullable
as SyncStatus,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

// dart format on
