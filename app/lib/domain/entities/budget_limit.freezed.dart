// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'budget_limit.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BudgetLimit {

 String get id; String get budgetId; DateTime get start; DateTime get end; String get amount; DateTime get updatedAt; int get seq; String? get currencyCode; String? get currencyId; String? get notes; String? get fireflyId; DateTime? get remoteUpdatedAt; SyncStatus get syncStatus; DateTime? get deletedAt;
/// Create a copy of BudgetLimit
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BudgetLimitCopyWith<BudgetLimit> get copyWith => _$BudgetLimitCopyWithImpl<BudgetLimit>(this as BudgetLimit, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BudgetLimit;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BudgetLimit&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.budgetId, _this.budgetId) || other.budgetId == _this.budgetId)&&(identical(other.start, _this.start) || other.start == _this.start)&&(identical(other.end, _this.end) || other.end == _this.end)&&(identical(other.amount, _this.amount) || other.amount == _this.amount)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&(identical(other.seq, _this.seq) || other.seq == _this.seq)&&(identical(other.currencyCode, _this.currencyCode) || other.currencyCode == _this.currencyCode)&&(identical(other.currencyId, _this.currencyId) || other.currencyId == _this.currencyId)&&(identical(other.notes, _this.notes) || other.notes == _this.notes)&&(identical(other.fireflyId, _this.fireflyId) || other.fireflyId == _this.fireflyId)&&(identical(other.remoteUpdatedAt, _this.remoteUpdatedAt) || other.remoteUpdatedAt == _this.remoteUpdatedAt)&&(identical(other.syncStatus, _this.syncStatus) || other.syncStatus == _this.syncStatus)&&(identical(other.deletedAt, _this.deletedAt) || other.deletedAt == _this.deletedAt));
}


@override
int get hashCode {
  final _this = this as BudgetLimit;
  return Object.hash(runtimeType,_this.id,_this.budgetId,_this.start,_this.end,_this.amount,_this.updatedAt,_this.seq,_this.currencyCode,_this.currencyId,_this.notes,_this.fireflyId,_this.remoteUpdatedAt,_this.syncStatus,_this.deletedAt);
}

@override
String toString() {
  final _this = this as BudgetLimit;
  return 'BudgetLimit(id: ${_this.id}, budgetId: ${_this.budgetId}, start: ${_this.start}, end: ${_this.end}, amount: ${_this.amount}, updatedAt: ${_this.updatedAt}, seq: ${_this.seq}, currencyCode: ${_this.currencyCode}, currencyId: ${_this.currencyId}, notes: ${_this.notes}, fireflyId: ${_this.fireflyId}, remoteUpdatedAt: ${_this.remoteUpdatedAt}, syncStatus: ${_this.syncStatus}, deletedAt: ${_this.deletedAt})';
}


}

/// @nodoc
abstract mixin class $BudgetLimitCopyWith<$Res>  {
  factory $BudgetLimitCopyWith(BudgetLimit value, $Res Function(BudgetLimit) _then) = _$BudgetLimitCopyWithImpl;
@useResult
$Res call({
 String id, String budgetId, DateTime start, DateTime end, String amount, DateTime updatedAt, int seq, String? currencyCode, String? currencyId, String? notes, String? fireflyId, DateTime? remoteUpdatedAt, SyncStatus syncStatus, DateTime? deletedAt
});




}
/// @nodoc
class _$BudgetLimitCopyWithImpl<$Res>
    implements $BudgetLimitCopyWith<$Res> {
  _$BudgetLimitCopyWithImpl(this._self, this._then);

  final BudgetLimit _self;
  final $Res Function(BudgetLimit) _then;

/// Create a copy of BudgetLimit
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? budgetId = null,Object? start = null,Object? end = null,Object? amount = null,Object? updatedAt = null,Object? seq = null,Object? currencyCode = freezed,Object? currencyId = freezed,Object? notes = freezed,Object? fireflyId = freezed,Object? remoteUpdatedAt = freezed,Object? syncStatus = null,Object? deletedAt = freezed,}) {
  return _then(BudgetLimit(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,budgetId: null == budgetId ? _self.budgetId : budgetId // ignore: cast_nullable_to_non_nullable
as String,start: null == start ? _self.start : start // ignore: cast_nullable_to_non_nullable
as DateTime,end: null == end ? _self.end : end // ignore: cast_nullable_to_non_nullable
as DateTime,amount: null == amount ? _self.amount : amount // ignore: cast_nullable_to_non_nullable
as String,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,seq: null == seq ? _self.seq : seq // ignore: cast_nullable_to_non_nullable
as int,currencyCode: freezed == currencyCode ? _self.currencyCode : currencyCode // ignore: cast_nullable_to_non_nullable
as String?,currencyId: freezed == currencyId ? _self.currencyId : currencyId // ignore: cast_nullable_to_non_nullable
as String?,notes: freezed == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String?,fireflyId: freezed == fireflyId ? _self.fireflyId : fireflyId // ignore: cast_nullable_to_non_nullable
as String?,remoteUpdatedAt: freezed == remoteUpdatedAt ? _self.remoteUpdatedAt : remoteUpdatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,syncStatus: null == syncStatus ? _self.syncStatus : syncStatus // ignore: cast_nullable_to_non_nullable
as SyncStatus,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [BudgetLimit].
extension BudgetLimitPatterns on BudgetLimit {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BudgetLimit value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BudgetLimit() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BudgetLimit value)  $default,){
final _that = this;
switch (_that) {
case _BudgetLimit():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BudgetLimit value)?  $default,){
final _that = this;
switch (_that) {
case _BudgetLimit() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String budgetId,  DateTime start,  DateTime end,  String amount,  DateTime updatedAt,  int seq,  String? currencyCode,  String? currencyId,  String? notes,  String? fireflyId,  DateTime? remoteUpdatedAt,  SyncStatus syncStatus,  DateTime? deletedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BudgetLimit() when $default != null:
return $default(_that.id,_that.budgetId,_that.start,_that.end,_that.amount,_that.updatedAt,_that.seq,_that.currencyCode,_that.currencyId,_that.notes,_that.fireflyId,_that.remoteUpdatedAt,_that.syncStatus,_that.deletedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String budgetId,  DateTime start,  DateTime end,  String amount,  DateTime updatedAt,  int seq,  String? currencyCode,  String? currencyId,  String? notes,  String? fireflyId,  DateTime? remoteUpdatedAt,  SyncStatus syncStatus,  DateTime? deletedAt)  $default,) {final _that = this;
switch (_that) {
case _BudgetLimit():
return $default(_that.id,_that.budgetId,_that.start,_that.end,_that.amount,_that.updatedAt,_that.seq,_that.currencyCode,_that.currencyId,_that.notes,_that.fireflyId,_that.remoteUpdatedAt,_that.syncStatus,_that.deletedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String budgetId,  DateTime start,  DateTime end,  String amount,  DateTime updatedAt,  int seq,  String? currencyCode,  String? currencyId,  String? notes,  String? fireflyId,  DateTime? remoteUpdatedAt,  SyncStatus syncStatus,  DateTime? deletedAt)?  $default,) {final _that = this;
switch (_that) {
case _BudgetLimit() when $default != null:
return $default(_that.id,_that.budgetId,_that.start,_that.end,_that.amount,_that.updatedAt,_that.seq,_that.currencyCode,_that.currencyId,_that.notes,_that.fireflyId,_that.remoteUpdatedAt,_that.syncStatus,_that.deletedAt);case _:
  return null;

}
}

}

/// @nodoc


class _BudgetLimit extends BudgetLimit {
  const _BudgetLimit({required this.id, required this.budgetId, required this.start, required this.end, required this.amount, required this.updatedAt, required this.seq, this.currencyCode, this.currencyId, this.notes, this.fireflyId, this.remoteUpdatedAt, this.syncStatus = SyncStatus.pending, this.deletedAt}): super._();
  

@override final  String id;
@override final  String budgetId;
@override final  DateTime start;
@override final  DateTime end;
@override final  String amount;
@override final  DateTime updatedAt;
@override final  int seq;
@override final  String? currencyCode;
@override final  String? currencyId;
@override final  String? notes;
@override final  String? fireflyId;
@override final  DateTime? remoteUpdatedAt;
@override@JsonKey() final  SyncStatus syncStatus;
@override final  DateTime? deletedAt;

/// Create a copy of BudgetLimit
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BudgetLimitCopyWith<_BudgetLimit> get copyWith => __$BudgetLimitCopyWithImpl<_BudgetLimit>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _BudgetLimit&&(identical(other.id, id) || other.id == id)&&(identical(other.budgetId, budgetId) || other.budgetId == budgetId)&&(identical(other.start, start) || other.start == start)&&(identical(other.end, end) || other.end == end)&&(identical(other.amount, amount) || other.amount == amount)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.seq, seq) || other.seq == seq)&&(identical(other.currencyCode, currencyCode) || other.currencyCode == currencyCode)&&(identical(other.currencyId, currencyId) || other.currencyId == currencyId)&&(identical(other.notes, notes) || other.notes == notes)&&(identical(other.fireflyId, fireflyId) || other.fireflyId == fireflyId)&&(identical(other.remoteUpdatedAt, remoteUpdatedAt) || other.remoteUpdatedAt == remoteUpdatedAt)&&(identical(other.syncStatus, syncStatus) || other.syncStatus == syncStatus)&&(identical(other.deletedAt, deletedAt) || other.deletedAt == deletedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,budgetId,start,end,amount,updatedAt,seq,currencyCode,currencyId,notes,fireflyId,remoteUpdatedAt,syncStatus,deletedAt);
}

@override
String toString() {
    return 'BudgetLimit(id: $id, budgetId: $budgetId, start: $start, end: $end, amount: $amount, updatedAt: $updatedAt, seq: $seq, currencyCode: $currencyCode, currencyId: $currencyId, notes: $notes, fireflyId: $fireflyId, remoteUpdatedAt: $remoteUpdatedAt, syncStatus: $syncStatus, deletedAt: $deletedAt)';
}


}

/// @nodoc
abstract mixin class _$BudgetLimitCopyWith<$Res> implements $BudgetLimitCopyWith<$Res> {
  factory _$BudgetLimitCopyWith(_BudgetLimit value, $Res Function(_BudgetLimit) _then) = __$BudgetLimitCopyWithImpl;
@override @useResult
$Res call({
 String id, String budgetId, DateTime start, DateTime end, String amount, DateTime updatedAt, int seq, String? currencyCode, String? currencyId, String? notes, String? fireflyId, DateTime? remoteUpdatedAt, SyncStatus syncStatus, DateTime? deletedAt
});




}
/// @nodoc
class __$BudgetLimitCopyWithImpl<$Res>
    implements _$BudgetLimitCopyWith<$Res> {
  __$BudgetLimitCopyWithImpl(this._self, this._then);

  final _BudgetLimit _self;
  final $Res Function(_BudgetLimit) _then;

/// Create a copy of BudgetLimit
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? budgetId = null,Object? start = null,Object? end = null,Object? amount = null,Object? updatedAt = null,Object? seq = null,Object? currencyCode = freezed,Object? currencyId = freezed,Object? notes = freezed,Object? fireflyId = freezed,Object? remoteUpdatedAt = freezed,Object? syncStatus = null,Object? deletedAt = freezed,}) {
  return _then(_BudgetLimit(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,budgetId: null == budgetId ? _self.budgetId : budgetId // ignore: cast_nullable_to_non_nullable
as String,start: null == start ? _self.start : start // ignore: cast_nullable_to_non_nullable
as DateTime,end: null == end ? _self.end : end // ignore: cast_nullable_to_non_nullable
as DateTime,amount: null == amount ? _self.amount : amount // ignore: cast_nullable_to_non_nullable
as String,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,seq: null == seq ? _self.seq : seq // ignore: cast_nullable_to_non_nullable
as int,currencyCode: freezed == currencyCode ? _self.currencyCode : currencyCode // ignore: cast_nullable_to_non_nullable
as String?,currencyId: freezed == currencyId ? _self.currencyId : currencyId // ignore: cast_nullable_to_non_nullable
as String?,notes: freezed == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String?,fireflyId: freezed == fireflyId ? _self.fireflyId : fireflyId // ignore: cast_nullable_to_non_nullable
as String?,remoteUpdatedAt: freezed == remoteUpdatedAt ? _self.remoteUpdatedAt : remoteUpdatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,syncStatus: null == syncStatus ? _self.syncStatus : syncStatus // ignore: cast_nullable_to_non_nullable
as SyncStatus,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

// dart format on
