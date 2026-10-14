// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'subscription.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Subscription {

 String get id; String get title; String get amount; DateTime get updatedAt; int get seq; String? get currencyCode; String? get currencyId; String? get transactionJournalId; String get repeatFreq; DateTime? get nextDate; DateTime? get endDate; String? get periods; String? get method; String? get notes; String? get fireflyId; bool get active; DateTime? get remoteUpdatedAt; SyncStatus get syncStatus; DateTime? get deletedAt;
/// Create a copy of Subscription
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SubscriptionCopyWith<Subscription> get copyWith => _$SubscriptionCopyWithImpl<Subscription>(this as Subscription, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as Subscription;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Subscription&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.title, _this.title) || other.title == _this.title)&&(identical(other.amount, _this.amount) || other.amount == _this.amount)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&(identical(other.seq, _this.seq) || other.seq == _this.seq)&&(identical(other.currencyCode, _this.currencyCode) || other.currencyCode == _this.currencyCode)&&(identical(other.currencyId, _this.currencyId) || other.currencyId == _this.currencyId)&&(identical(other.transactionJournalId, _this.transactionJournalId) || other.transactionJournalId == _this.transactionJournalId)&&(identical(other.repeatFreq, _this.repeatFreq) || other.repeatFreq == _this.repeatFreq)&&(identical(other.nextDate, _this.nextDate) || other.nextDate == _this.nextDate)&&(identical(other.endDate, _this.endDate) || other.endDate == _this.endDate)&&(identical(other.periods, _this.periods) || other.periods == _this.periods)&&(identical(other.method, _this.method) || other.method == _this.method)&&(identical(other.notes, _this.notes) || other.notes == _this.notes)&&(identical(other.fireflyId, _this.fireflyId) || other.fireflyId == _this.fireflyId)&&(identical(other.active, _this.active) || other.active == _this.active)&&(identical(other.remoteUpdatedAt, _this.remoteUpdatedAt) || other.remoteUpdatedAt == _this.remoteUpdatedAt)&&(identical(other.syncStatus, _this.syncStatus) || other.syncStatus == _this.syncStatus)&&(identical(other.deletedAt, _this.deletedAt) || other.deletedAt == _this.deletedAt));
}


@override
int get hashCode {
  final _this = this as Subscription;
  return Object.hashAll([runtimeType,_this.id,_this.title,_this.amount,_this.updatedAt,_this.seq,_this.currencyCode,_this.currencyId,_this.transactionJournalId,_this.repeatFreq,_this.nextDate,_this.endDate,_this.periods,_this.method,_this.notes,_this.fireflyId,_this.active,_this.remoteUpdatedAt,_this.syncStatus,_this.deletedAt]);
}

@override
String toString() {
  final _this = this as Subscription;
  return 'Subscription(id: ${_this.id}, title: ${_this.title}, amount: ${_this.amount}, updatedAt: ${_this.updatedAt}, seq: ${_this.seq}, currencyCode: ${_this.currencyCode}, currencyId: ${_this.currencyId}, transactionJournalId: ${_this.transactionJournalId}, repeatFreq: ${_this.repeatFreq}, nextDate: ${_this.nextDate}, endDate: ${_this.endDate}, periods: ${_this.periods}, method: ${_this.method}, notes: ${_this.notes}, fireflyId: ${_this.fireflyId}, active: ${_this.active}, remoteUpdatedAt: ${_this.remoteUpdatedAt}, syncStatus: ${_this.syncStatus}, deletedAt: ${_this.deletedAt})';
}


}

/// @nodoc
abstract mixin class $SubscriptionCopyWith<$Res>  {
  factory $SubscriptionCopyWith(Subscription value, $Res Function(Subscription) _then) = _$SubscriptionCopyWithImpl;
@useResult
$Res call({
 String id, String title, String amount, DateTime updatedAt, int seq, String? currencyCode, String? currencyId, String? transactionJournalId, String repeatFreq, DateTime? nextDate, DateTime? endDate, String? periods, String? method, String? notes, String? fireflyId, bool active, DateTime? remoteUpdatedAt, SyncStatus syncStatus, DateTime? deletedAt
});




}
/// @nodoc
class _$SubscriptionCopyWithImpl<$Res>
    implements $SubscriptionCopyWith<$Res> {
  _$SubscriptionCopyWithImpl(this._self, this._then);

  final Subscription _self;
  final $Res Function(Subscription) _then;

/// Create a copy of Subscription
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? title = null,Object? amount = null,Object? updatedAt = null,Object? seq = null,Object? currencyCode = freezed,Object? currencyId = freezed,Object? transactionJournalId = freezed,Object? repeatFreq = null,Object? nextDate = freezed,Object? endDate = freezed,Object? periods = freezed,Object? method = freezed,Object? notes = freezed,Object? fireflyId = freezed,Object? active = null,Object? remoteUpdatedAt = freezed,Object? syncStatus = null,Object? deletedAt = freezed,}) {
  return _then(Subscription(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,amount: null == amount ? _self.amount : amount // ignore: cast_nullable_to_non_nullable
as String,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,seq: null == seq ? _self.seq : seq // ignore: cast_nullable_to_non_nullable
as int,currencyCode: freezed == currencyCode ? _self.currencyCode : currencyCode // ignore: cast_nullable_to_non_nullable
as String?,currencyId: freezed == currencyId ? _self.currencyId : currencyId // ignore: cast_nullable_to_non_nullable
as String?,transactionJournalId: freezed == transactionJournalId ? _self.transactionJournalId : transactionJournalId // ignore: cast_nullable_to_non_nullable
as String?,repeatFreq: null == repeatFreq ? _self.repeatFreq : repeatFreq // ignore: cast_nullable_to_non_nullable
as String,nextDate: freezed == nextDate ? _self.nextDate : nextDate // ignore: cast_nullable_to_non_nullable
as DateTime?,endDate: freezed == endDate ? _self.endDate : endDate // ignore: cast_nullable_to_non_nullable
as DateTime?,periods: freezed == periods ? _self.periods : periods // ignore: cast_nullable_to_non_nullable
as String?,method: freezed == method ? _self.method : method // ignore: cast_nullable_to_non_nullable
as String?,notes: freezed == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String?,fireflyId: freezed == fireflyId ? _self.fireflyId : fireflyId // ignore: cast_nullable_to_non_nullable
as String?,active: null == active ? _self.active : active // ignore: cast_nullable_to_non_nullable
as bool,remoteUpdatedAt: freezed == remoteUpdatedAt ? _self.remoteUpdatedAt : remoteUpdatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,syncStatus: null == syncStatus ? _self.syncStatus : syncStatus // ignore: cast_nullable_to_non_nullable
as SyncStatus,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [Subscription].
extension SubscriptionPatterns on Subscription {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Subscription value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Subscription() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Subscription value)  $default,){
final _that = this;
switch (_that) {
case _Subscription():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Subscription value)?  $default,){
final _that = this;
switch (_that) {
case _Subscription() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String title,  String amount,  DateTime updatedAt,  int seq,  String? currencyCode,  String? currencyId,  String? transactionJournalId,  String repeatFreq,  DateTime? nextDate,  DateTime? endDate,  String? periods,  String? method,  String? notes,  String? fireflyId,  bool active,  DateTime? remoteUpdatedAt,  SyncStatus syncStatus,  DateTime? deletedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Subscription() when $default != null:
return $default(_that.id,_that.title,_that.amount,_that.updatedAt,_that.seq,_that.currencyCode,_that.currencyId,_that.transactionJournalId,_that.repeatFreq,_that.nextDate,_that.endDate,_that.periods,_that.method,_that.notes,_that.fireflyId,_that.active,_that.remoteUpdatedAt,_that.syncStatus,_that.deletedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String title,  String amount,  DateTime updatedAt,  int seq,  String? currencyCode,  String? currencyId,  String? transactionJournalId,  String repeatFreq,  DateTime? nextDate,  DateTime? endDate,  String? periods,  String? method,  String? notes,  String? fireflyId,  bool active,  DateTime? remoteUpdatedAt,  SyncStatus syncStatus,  DateTime? deletedAt)  $default,) {final _that = this;
switch (_that) {
case _Subscription():
return $default(_that.id,_that.title,_that.amount,_that.updatedAt,_that.seq,_that.currencyCode,_that.currencyId,_that.transactionJournalId,_that.repeatFreq,_that.nextDate,_that.endDate,_that.periods,_that.method,_that.notes,_that.fireflyId,_that.active,_that.remoteUpdatedAt,_that.syncStatus,_that.deletedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String title,  String amount,  DateTime updatedAt,  int seq,  String? currencyCode,  String? currencyId,  String? transactionJournalId,  String repeatFreq,  DateTime? nextDate,  DateTime? endDate,  String? periods,  String? method,  String? notes,  String? fireflyId,  bool active,  DateTime? remoteUpdatedAt,  SyncStatus syncStatus,  DateTime? deletedAt)?  $default,) {final _that = this;
switch (_that) {
case _Subscription() when $default != null:
return $default(_that.id,_that.title,_that.amount,_that.updatedAt,_that.seq,_that.currencyCode,_that.currencyId,_that.transactionJournalId,_that.repeatFreq,_that.nextDate,_that.endDate,_that.periods,_that.method,_that.notes,_that.fireflyId,_that.active,_that.remoteUpdatedAt,_that.syncStatus,_that.deletedAt);case _:
  return null;

}
}

}

/// @nodoc


class _Subscription extends Subscription {
  const _Subscription({required this.id, required this.title, required this.amount, required this.updatedAt, required this.seq, this.currencyCode, this.currencyId, this.transactionJournalId, this.repeatFreq = 'monthly', this.nextDate, this.endDate, this.periods, this.method, this.notes, this.fireflyId, this.active = true, this.remoteUpdatedAt, this.syncStatus = SyncStatus.pending, this.deletedAt}): super._();
  

@override final  String id;
@override final  String title;
@override final  String amount;
@override final  DateTime updatedAt;
@override final  int seq;
@override final  String? currencyCode;
@override final  String? currencyId;
@override final  String? transactionJournalId;
@override@JsonKey() final  String repeatFreq;
@override final  DateTime? nextDate;
@override final  DateTime? endDate;
@override final  String? periods;
@override final  String? method;
@override final  String? notes;
@override final  String? fireflyId;
@override@JsonKey() final  bool active;
@override final  DateTime? remoteUpdatedAt;
@override@JsonKey() final  SyncStatus syncStatus;
@override final  DateTime? deletedAt;

/// Create a copy of Subscription
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SubscriptionCopyWith<_Subscription> get copyWith => __$SubscriptionCopyWithImpl<_Subscription>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _Subscription&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.amount, amount) || other.amount == amount)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.seq, seq) || other.seq == seq)&&(identical(other.currencyCode, currencyCode) || other.currencyCode == currencyCode)&&(identical(other.currencyId, currencyId) || other.currencyId == currencyId)&&(identical(other.transactionJournalId, transactionJournalId) || other.transactionJournalId == transactionJournalId)&&(identical(other.repeatFreq, repeatFreq) || other.repeatFreq == repeatFreq)&&(identical(other.nextDate, nextDate) || other.nextDate == nextDate)&&(identical(other.endDate, endDate) || other.endDate == endDate)&&(identical(other.periods, periods) || other.periods == periods)&&(identical(other.method, method) || other.method == method)&&(identical(other.notes, notes) || other.notes == notes)&&(identical(other.fireflyId, fireflyId) || other.fireflyId == fireflyId)&&(identical(other.active, active) || other.active == active)&&(identical(other.remoteUpdatedAt, remoteUpdatedAt) || other.remoteUpdatedAt == remoteUpdatedAt)&&(identical(other.syncStatus, syncStatus) || other.syncStatus == syncStatus)&&(identical(other.deletedAt, deletedAt) || other.deletedAt == deletedAt));
}


@override
int get hashCode {
    return Object.hashAll([runtimeType,id,title,amount,updatedAt,seq,currencyCode,currencyId,transactionJournalId,repeatFreq,nextDate,endDate,periods,method,notes,fireflyId,active,remoteUpdatedAt,syncStatus,deletedAt]);
}

@override
String toString() {
    return 'Subscription(id: $id, title: $title, amount: $amount, updatedAt: $updatedAt, seq: $seq, currencyCode: $currencyCode, currencyId: $currencyId, transactionJournalId: $transactionJournalId, repeatFreq: $repeatFreq, nextDate: $nextDate, endDate: $endDate, periods: $periods, method: $method, notes: $notes, fireflyId: $fireflyId, active: $active, remoteUpdatedAt: $remoteUpdatedAt, syncStatus: $syncStatus, deletedAt: $deletedAt)';
}


}

/// @nodoc
abstract mixin class _$SubscriptionCopyWith<$Res> implements $SubscriptionCopyWith<$Res> {
  factory _$SubscriptionCopyWith(_Subscription value, $Res Function(_Subscription) _then) = __$SubscriptionCopyWithImpl;
@override @useResult
$Res call({
 String id, String title, String amount, DateTime updatedAt, int seq, String? currencyCode, String? currencyId, String? transactionJournalId, String repeatFreq, DateTime? nextDate, DateTime? endDate, String? periods, String? method, String? notes, String? fireflyId, bool active, DateTime? remoteUpdatedAt, SyncStatus syncStatus, DateTime? deletedAt
});




}
/// @nodoc
class __$SubscriptionCopyWithImpl<$Res>
    implements _$SubscriptionCopyWith<$Res> {
  __$SubscriptionCopyWithImpl(this._self, this._then);

  final _Subscription _self;
  final $Res Function(_Subscription) _then;

/// Create a copy of Subscription
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? title = null,Object? amount = null,Object? updatedAt = null,Object? seq = null,Object? currencyCode = freezed,Object? currencyId = freezed,Object? transactionJournalId = freezed,Object? repeatFreq = null,Object? nextDate = freezed,Object? endDate = freezed,Object? periods = freezed,Object? method = freezed,Object? notes = freezed,Object? fireflyId = freezed,Object? active = null,Object? remoteUpdatedAt = freezed,Object? syncStatus = null,Object? deletedAt = freezed,}) {
  return _then(_Subscription(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,amount: null == amount ? _self.amount : amount // ignore: cast_nullable_to_non_nullable
as String,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,seq: null == seq ? _self.seq : seq // ignore: cast_nullable_to_non_nullable
as int,currencyCode: freezed == currencyCode ? _self.currencyCode : currencyCode // ignore: cast_nullable_to_non_nullable
as String?,currencyId: freezed == currencyId ? _self.currencyId : currencyId // ignore: cast_nullable_to_non_nullable
as String?,transactionJournalId: freezed == transactionJournalId ? _self.transactionJournalId : transactionJournalId // ignore: cast_nullable_to_non_nullable
as String?,repeatFreq: null == repeatFreq ? _self.repeatFreq : repeatFreq // ignore: cast_nullable_to_non_nullable
as String,nextDate: freezed == nextDate ? _self.nextDate : nextDate // ignore: cast_nullable_to_non_nullable
as DateTime?,endDate: freezed == endDate ? _self.endDate : endDate // ignore: cast_nullable_to_non_nullable
as DateTime?,periods: freezed == periods ? _self.periods : periods // ignore: cast_nullable_to_non_nullable
as String?,method: freezed == method ? _self.method : method // ignore: cast_nullable_to_non_nullable
as String?,notes: freezed == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String?,fireflyId: freezed == fireflyId ? _self.fireflyId : fireflyId // ignore: cast_nullable_to_non_nullable
as String?,active: null == active ? _self.active : active // ignore: cast_nullable_to_non_nullable
as bool,remoteUpdatedAt: freezed == remoteUpdatedAt ? _self.remoteUpdatedAt : remoteUpdatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,syncStatus: null == syncStatus ? _self.syncStatus : syncStatus // ignore: cast_nullable_to_non_nullable
as SyncStatus,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

// dart format on
