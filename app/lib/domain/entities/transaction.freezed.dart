// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'transaction.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Transaction {

 String get id; String get type; String get description; DateTime get date; String get amount; DateTime get updatedAt; int get seq; String? get fireflyId; String? get journalId; String? get currencyCode; String? get currencyId; String? get sourceAccountId; String? get destAccountId; String? get sourceName; String? get destName; String? get categoryId; String? get categoryName; String? get budgetId; String? get budgetName; String? get billId; String? get billName; String? get tagsJson; String? get notes; String? get foreignAmount; String? get foreignCurrencyCode; bool get reconciled; DateTime? get remoteUpdatedAt; SyncStatus get syncStatus; DateTime? get deletedAt;
/// Create a copy of Transaction
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TransactionCopyWith<Transaction> get copyWith => _$TransactionCopyWithImpl<Transaction>(this as Transaction, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as Transaction;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Transaction&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.type, _this.type) || other.type == _this.type)&&(identical(other.description, _this.description) || other.description == _this.description)&&(identical(other.date, _this.date) || other.date == _this.date)&&(identical(other.amount, _this.amount) || other.amount == _this.amount)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&(identical(other.seq, _this.seq) || other.seq == _this.seq)&&(identical(other.fireflyId, _this.fireflyId) || other.fireflyId == _this.fireflyId)&&(identical(other.journalId, _this.journalId) || other.journalId == _this.journalId)&&(identical(other.currencyCode, _this.currencyCode) || other.currencyCode == _this.currencyCode)&&(identical(other.currencyId, _this.currencyId) || other.currencyId == _this.currencyId)&&(identical(other.sourceAccountId, _this.sourceAccountId) || other.sourceAccountId == _this.sourceAccountId)&&(identical(other.destAccountId, _this.destAccountId) || other.destAccountId == _this.destAccountId)&&(identical(other.sourceName, _this.sourceName) || other.sourceName == _this.sourceName)&&(identical(other.destName, _this.destName) || other.destName == _this.destName)&&(identical(other.categoryId, _this.categoryId) || other.categoryId == _this.categoryId)&&(identical(other.categoryName, _this.categoryName) || other.categoryName == _this.categoryName)&&(identical(other.budgetId, _this.budgetId) || other.budgetId == _this.budgetId)&&(identical(other.budgetName, _this.budgetName) || other.budgetName == _this.budgetName)&&(identical(other.billId, _this.billId) || other.billId == _this.billId)&&(identical(other.billName, _this.billName) || other.billName == _this.billName)&&(identical(other.tagsJson, _this.tagsJson) || other.tagsJson == _this.tagsJson)&&(identical(other.notes, _this.notes) || other.notes == _this.notes)&&(identical(other.foreignAmount, _this.foreignAmount) || other.foreignAmount == _this.foreignAmount)&&(identical(other.foreignCurrencyCode, _this.foreignCurrencyCode) || other.foreignCurrencyCode == _this.foreignCurrencyCode)&&(identical(other.reconciled, _this.reconciled) || other.reconciled == _this.reconciled)&&(identical(other.remoteUpdatedAt, _this.remoteUpdatedAt) || other.remoteUpdatedAt == _this.remoteUpdatedAt)&&(identical(other.syncStatus, _this.syncStatus) || other.syncStatus == _this.syncStatus)&&(identical(other.deletedAt, _this.deletedAt) || other.deletedAt == _this.deletedAt));
}


@override
int get hashCode {
  final _this = this as Transaction;
  return Object.hashAll([runtimeType,_this.id,_this.type,_this.description,_this.date,_this.amount,_this.updatedAt,_this.seq,_this.fireflyId,_this.journalId,_this.currencyCode,_this.currencyId,_this.sourceAccountId,_this.destAccountId,_this.sourceName,_this.destName,_this.categoryId,_this.categoryName,_this.budgetId,_this.budgetName,_this.billId,_this.billName,_this.tagsJson,_this.notes,_this.foreignAmount,_this.foreignCurrencyCode,_this.reconciled,_this.remoteUpdatedAt,_this.syncStatus,_this.deletedAt]);
}

@override
String toString() {
  final _this = this as Transaction;
  return 'Transaction(id: ${_this.id}, type: ${_this.type}, description: ${_this.description}, date: ${_this.date}, amount: ${_this.amount}, updatedAt: ${_this.updatedAt}, seq: ${_this.seq}, fireflyId: ${_this.fireflyId}, journalId: ${_this.journalId}, currencyCode: ${_this.currencyCode}, currencyId: ${_this.currencyId}, sourceAccountId: ${_this.sourceAccountId}, destAccountId: ${_this.destAccountId}, sourceName: ${_this.sourceName}, destName: ${_this.destName}, categoryId: ${_this.categoryId}, categoryName: ${_this.categoryName}, budgetId: ${_this.budgetId}, budgetName: ${_this.budgetName}, billId: ${_this.billId}, billName: ${_this.billName}, tagsJson: ${_this.tagsJson}, notes: ${_this.notes}, foreignAmount: ${_this.foreignAmount}, foreignCurrencyCode: ${_this.foreignCurrencyCode}, reconciled: ${_this.reconciled}, remoteUpdatedAt: ${_this.remoteUpdatedAt}, syncStatus: ${_this.syncStatus}, deletedAt: ${_this.deletedAt})';
}


}

/// @nodoc
abstract mixin class $TransactionCopyWith<$Res>  {
  factory $TransactionCopyWith(Transaction value, $Res Function(Transaction) _then) = _$TransactionCopyWithImpl;
@useResult
$Res call({
 String id, String type, String description, DateTime date, String amount, DateTime updatedAt, int seq, String? fireflyId, String? journalId, String? currencyCode, String? currencyId, String? sourceAccountId, String? destAccountId, String? sourceName, String? destName, String? categoryId, String? categoryName, String? budgetId, String? budgetName, String? billId, String? billName, String? tagsJson, String? notes, String? foreignAmount, String? foreignCurrencyCode, bool reconciled, DateTime? remoteUpdatedAt, SyncStatus syncStatus, DateTime? deletedAt
});




}
/// @nodoc
class _$TransactionCopyWithImpl<$Res>
    implements $TransactionCopyWith<$Res> {
  _$TransactionCopyWithImpl(this._self, this._then);

  final Transaction _self;
  final $Res Function(Transaction) _then;

/// Create a copy of Transaction
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? type = null,Object? description = null,Object? date = null,Object? amount = null,Object? updatedAt = null,Object? seq = null,Object? fireflyId = freezed,Object? journalId = freezed,Object? currencyCode = freezed,Object? currencyId = freezed,Object? sourceAccountId = freezed,Object? destAccountId = freezed,Object? sourceName = freezed,Object? destName = freezed,Object? categoryId = freezed,Object? categoryName = freezed,Object? budgetId = freezed,Object? budgetName = freezed,Object? billId = freezed,Object? billName = freezed,Object? tagsJson = freezed,Object? notes = freezed,Object? foreignAmount = freezed,Object? foreignCurrencyCode = freezed,Object? reconciled = null,Object? remoteUpdatedAt = freezed,Object? syncStatus = null,Object? deletedAt = freezed,}) {
  return _then(Transaction(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,date: null == date ? _self.date : date // ignore: cast_nullable_to_non_nullable
as DateTime,amount: null == amount ? _self.amount : amount // ignore: cast_nullable_to_non_nullable
as String,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,seq: null == seq ? _self.seq : seq // ignore: cast_nullable_to_non_nullable
as int,fireflyId: freezed == fireflyId ? _self.fireflyId : fireflyId // ignore: cast_nullable_to_non_nullable
as String?,journalId: freezed == journalId ? _self.journalId : journalId // ignore: cast_nullable_to_non_nullable
as String?,currencyCode: freezed == currencyCode ? _self.currencyCode : currencyCode // ignore: cast_nullable_to_non_nullable
as String?,currencyId: freezed == currencyId ? _self.currencyId : currencyId // ignore: cast_nullable_to_non_nullable
as String?,sourceAccountId: freezed == sourceAccountId ? _self.sourceAccountId : sourceAccountId // ignore: cast_nullable_to_non_nullable
as String?,destAccountId: freezed == destAccountId ? _self.destAccountId : destAccountId // ignore: cast_nullable_to_non_nullable
as String?,sourceName: freezed == sourceName ? _self.sourceName : sourceName // ignore: cast_nullable_to_non_nullable
as String?,destName: freezed == destName ? _self.destName : destName // ignore: cast_nullable_to_non_nullable
as String?,categoryId: freezed == categoryId ? _self.categoryId : categoryId // ignore: cast_nullable_to_non_nullable
as String?,categoryName: freezed == categoryName ? _self.categoryName : categoryName // ignore: cast_nullable_to_non_nullable
as String?,budgetId: freezed == budgetId ? _self.budgetId : budgetId // ignore: cast_nullable_to_non_nullable
as String?,budgetName: freezed == budgetName ? _self.budgetName : budgetName // ignore: cast_nullable_to_non_nullable
as String?,billId: freezed == billId ? _self.billId : billId // ignore: cast_nullable_to_non_nullable
as String?,billName: freezed == billName ? _self.billName : billName // ignore: cast_nullable_to_non_nullable
as String?,tagsJson: freezed == tagsJson ? _self.tagsJson : tagsJson // ignore: cast_nullable_to_non_nullable
as String?,notes: freezed == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String?,foreignAmount: freezed == foreignAmount ? _self.foreignAmount : foreignAmount // ignore: cast_nullable_to_non_nullable
as String?,foreignCurrencyCode: freezed == foreignCurrencyCode ? _self.foreignCurrencyCode : foreignCurrencyCode // ignore: cast_nullable_to_non_nullable
as String?,reconciled: null == reconciled ? _self.reconciled : reconciled // ignore: cast_nullable_to_non_nullable
as bool,remoteUpdatedAt: freezed == remoteUpdatedAt ? _self.remoteUpdatedAt : remoteUpdatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,syncStatus: null == syncStatus ? _self.syncStatus : syncStatus // ignore: cast_nullable_to_non_nullable
as SyncStatus,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [Transaction].
extension TransactionPatterns on Transaction {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Transaction value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Transaction() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Transaction value)  $default,){
final _that = this;
switch (_that) {
case _Transaction():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Transaction value)?  $default,){
final _that = this;
switch (_that) {
case _Transaction() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String type,  String description,  DateTime date,  String amount,  DateTime updatedAt,  int seq,  String? fireflyId,  String? journalId,  String? currencyCode,  String? currencyId,  String? sourceAccountId,  String? destAccountId,  String? sourceName,  String? destName,  String? categoryId,  String? categoryName,  String? budgetId,  String? budgetName,  String? billId,  String? billName,  String? tagsJson,  String? notes,  String? foreignAmount,  String? foreignCurrencyCode,  bool reconciled,  DateTime? remoteUpdatedAt,  SyncStatus syncStatus,  DateTime? deletedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Transaction() when $default != null:
return $default(_that.id,_that.type,_that.description,_that.date,_that.amount,_that.updatedAt,_that.seq,_that.fireflyId,_that.journalId,_that.currencyCode,_that.currencyId,_that.sourceAccountId,_that.destAccountId,_that.sourceName,_that.destName,_that.categoryId,_that.categoryName,_that.budgetId,_that.budgetName,_that.billId,_that.billName,_that.tagsJson,_that.notes,_that.foreignAmount,_that.foreignCurrencyCode,_that.reconciled,_that.remoteUpdatedAt,_that.syncStatus,_that.deletedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String type,  String description,  DateTime date,  String amount,  DateTime updatedAt,  int seq,  String? fireflyId,  String? journalId,  String? currencyCode,  String? currencyId,  String? sourceAccountId,  String? destAccountId,  String? sourceName,  String? destName,  String? categoryId,  String? categoryName,  String? budgetId,  String? budgetName,  String? billId,  String? billName,  String? tagsJson,  String? notes,  String? foreignAmount,  String? foreignCurrencyCode,  bool reconciled,  DateTime? remoteUpdatedAt,  SyncStatus syncStatus,  DateTime? deletedAt)  $default,) {final _that = this;
switch (_that) {
case _Transaction():
return $default(_that.id,_that.type,_that.description,_that.date,_that.amount,_that.updatedAt,_that.seq,_that.fireflyId,_that.journalId,_that.currencyCode,_that.currencyId,_that.sourceAccountId,_that.destAccountId,_that.sourceName,_that.destName,_that.categoryId,_that.categoryName,_that.budgetId,_that.budgetName,_that.billId,_that.billName,_that.tagsJson,_that.notes,_that.foreignAmount,_that.foreignCurrencyCode,_that.reconciled,_that.remoteUpdatedAt,_that.syncStatus,_that.deletedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String type,  String description,  DateTime date,  String amount,  DateTime updatedAt,  int seq,  String? fireflyId,  String? journalId,  String? currencyCode,  String? currencyId,  String? sourceAccountId,  String? destAccountId,  String? sourceName,  String? destName,  String? categoryId,  String? categoryName,  String? budgetId,  String? budgetName,  String? billId,  String? billName,  String? tagsJson,  String? notes,  String? foreignAmount,  String? foreignCurrencyCode,  bool reconciled,  DateTime? remoteUpdatedAt,  SyncStatus syncStatus,  DateTime? deletedAt)?  $default,) {final _that = this;
switch (_that) {
case _Transaction() when $default != null:
return $default(_that.id,_that.type,_that.description,_that.date,_that.amount,_that.updatedAt,_that.seq,_that.fireflyId,_that.journalId,_that.currencyCode,_that.currencyId,_that.sourceAccountId,_that.destAccountId,_that.sourceName,_that.destName,_that.categoryId,_that.categoryName,_that.budgetId,_that.budgetName,_that.billId,_that.billName,_that.tagsJson,_that.notes,_that.foreignAmount,_that.foreignCurrencyCode,_that.reconciled,_that.remoteUpdatedAt,_that.syncStatus,_that.deletedAt);case _:
  return null;

}
}

}

/// @nodoc


class _Transaction extends Transaction {
  const _Transaction({required this.id, required this.type, required this.description, required this.date, required this.amount, required this.updatedAt, required this.seq, this.fireflyId, this.journalId, this.currencyCode, this.currencyId, this.sourceAccountId, this.destAccountId, this.sourceName, this.destName, this.categoryId, this.categoryName, this.budgetId, this.budgetName, this.billId, this.billName, this.tagsJson, this.notes, this.foreignAmount, this.foreignCurrencyCode, this.reconciled = false, this.remoteUpdatedAt, this.syncStatus = SyncStatus.pending, this.deletedAt}): super._();
  

@override final  String id;
@override final  String type;
@override final  String description;
@override final  DateTime date;
@override final  String amount;
@override final  DateTime updatedAt;
@override final  int seq;
@override final  String? fireflyId;
@override final  String? journalId;
@override final  String? currencyCode;
@override final  String? currencyId;
@override final  String? sourceAccountId;
@override final  String? destAccountId;
@override final  String? sourceName;
@override final  String? destName;
@override final  String? categoryId;
@override final  String? categoryName;
@override final  String? budgetId;
@override final  String? budgetName;
@override final  String? billId;
@override final  String? billName;
@override final  String? tagsJson;
@override final  String? notes;
@override final  String? foreignAmount;
@override final  String? foreignCurrencyCode;
@override@JsonKey() final  bool reconciled;
@override final  DateTime? remoteUpdatedAt;
@override@JsonKey() final  SyncStatus syncStatus;
@override final  DateTime? deletedAt;

/// Create a copy of Transaction
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TransactionCopyWith<_Transaction> get copyWith => __$TransactionCopyWithImpl<_Transaction>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _Transaction&&(identical(other.id, id) || other.id == id)&&(identical(other.type, type) || other.type == type)&&(identical(other.description, description) || other.description == description)&&(identical(other.date, date) || other.date == date)&&(identical(other.amount, amount) || other.amount == amount)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.seq, seq) || other.seq == seq)&&(identical(other.fireflyId, fireflyId) || other.fireflyId == fireflyId)&&(identical(other.journalId, journalId) || other.journalId == journalId)&&(identical(other.currencyCode, currencyCode) || other.currencyCode == currencyCode)&&(identical(other.currencyId, currencyId) || other.currencyId == currencyId)&&(identical(other.sourceAccountId, sourceAccountId) || other.sourceAccountId == sourceAccountId)&&(identical(other.destAccountId, destAccountId) || other.destAccountId == destAccountId)&&(identical(other.sourceName, sourceName) || other.sourceName == sourceName)&&(identical(other.destName, destName) || other.destName == destName)&&(identical(other.categoryId, categoryId) || other.categoryId == categoryId)&&(identical(other.categoryName, categoryName) || other.categoryName == categoryName)&&(identical(other.budgetId, budgetId) || other.budgetId == budgetId)&&(identical(other.budgetName, budgetName) || other.budgetName == budgetName)&&(identical(other.billId, billId) || other.billId == billId)&&(identical(other.billName, billName) || other.billName == billName)&&(identical(other.tagsJson, tagsJson) || other.tagsJson == tagsJson)&&(identical(other.notes, notes) || other.notes == notes)&&(identical(other.foreignAmount, foreignAmount) || other.foreignAmount == foreignAmount)&&(identical(other.foreignCurrencyCode, foreignCurrencyCode) || other.foreignCurrencyCode == foreignCurrencyCode)&&(identical(other.reconciled, reconciled) || other.reconciled == reconciled)&&(identical(other.remoteUpdatedAt, remoteUpdatedAt) || other.remoteUpdatedAt == remoteUpdatedAt)&&(identical(other.syncStatus, syncStatus) || other.syncStatus == syncStatus)&&(identical(other.deletedAt, deletedAt) || other.deletedAt == deletedAt));
}


@override
int get hashCode {
    return Object.hashAll([runtimeType,id,type,description,date,amount,updatedAt,seq,fireflyId,journalId,currencyCode,currencyId,sourceAccountId,destAccountId,sourceName,destName,categoryId,categoryName,budgetId,budgetName,billId,billName,tagsJson,notes,foreignAmount,foreignCurrencyCode,reconciled,remoteUpdatedAt,syncStatus,deletedAt]);
}

@override
String toString() {
    return 'Transaction(id: $id, type: $type, description: $description, date: $date, amount: $amount, updatedAt: $updatedAt, seq: $seq, fireflyId: $fireflyId, journalId: $journalId, currencyCode: $currencyCode, currencyId: $currencyId, sourceAccountId: $sourceAccountId, destAccountId: $destAccountId, sourceName: $sourceName, destName: $destName, categoryId: $categoryId, categoryName: $categoryName, budgetId: $budgetId, budgetName: $budgetName, billId: $billId, billName: $billName, tagsJson: $tagsJson, notes: $notes, foreignAmount: $foreignAmount, foreignCurrencyCode: $foreignCurrencyCode, reconciled: $reconciled, remoteUpdatedAt: $remoteUpdatedAt, syncStatus: $syncStatus, deletedAt: $deletedAt)';
}


}

/// @nodoc
abstract mixin class _$TransactionCopyWith<$Res> implements $TransactionCopyWith<$Res> {
  factory _$TransactionCopyWith(_Transaction value, $Res Function(_Transaction) _then) = __$TransactionCopyWithImpl;
@override @useResult
$Res call({
 String id, String type, String description, DateTime date, String amount, DateTime updatedAt, int seq, String? fireflyId, String? journalId, String? currencyCode, String? currencyId, String? sourceAccountId, String? destAccountId, String? sourceName, String? destName, String? categoryId, String? categoryName, String? budgetId, String? budgetName, String? billId, String? billName, String? tagsJson, String? notes, String? foreignAmount, String? foreignCurrencyCode, bool reconciled, DateTime? remoteUpdatedAt, SyncStatus syncStatus, DateTime? deletedAt
});




}
/// @nodoc
class __$TransactionCopyWithImpl<$Res>
    implements _$TransactionCopyWith<$Res> {
  __$TransactionCopyWithImpl(this._self, this._then);

  final _Transaction _self;
  final $Res Function(_Transaction) _then;

/// Create a copy of Transaction
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? type = null,Object? description = null,Object? date = null,Object? amount = null,Object? updatedAt = null,Object? seq = null,Object? fireflyId = freezed,Object? journalId = freezed,Object? currencyCode = freezed,Object? currencyId = freezed,Object? sourceAccountId = freezed,Object? destAccountId = freezed,Object? sourceName = freezed,Object? destName = freezed,Object? categoryId = freezed,Object? categoryName = freezed,Object? budgetId = freezed,Object? budgetName = freezed,Object? billId = freezed,Object? billName = freezed,Object? tagsJson = freezed,Object? notes = freezed,Object? foreignAmount = freezed,Object? foreignCurrencyCode = freezed,Object? reconciled = null,Object? remoteUpdatedAt = freezed,Object? syncStatus = null,Object? deletedAt = freezed,}) {
  return _then(_Transaction(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,date: null == date ? _self.date : date // ignore: cast_nullable_to_non_nullable
as DateTime,amount: null == amount ? _self.amount : amount // ignore: cast_nullable_to_non_nullable
as String,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,seq: null == seq ? _self.seq : seq // ignore: cast_nullable_to_non_nullable
as int,fireflyId: freezed == fireflyId ? _self.fireflyId : fireflyId // ignore: cast_nullable_to_non_nullable
as String?,journalId: freezed == journalId ? _self.journalId : journalId // ignore: cast_nullable_to_non_nullable
as String?,currencyCode: freezed == currencyCode ? _self.currencyCode : currencyCode // ignore: cast_nullable_to_non_nullable
as String?,currencyId: freezed == currencyId ? _self.currencyId : currencyId // ignore: cast_nullable_to_non_nullable
as String?,sourceAccountId: freezed == sourceAccountId ? _self.sourceAccountId : sourceAccountId // ignore: cast_nullable_to_non_nullable
as String?,destAccountId: freezed == destAccountId ? _self.destAccountId : destAccountId // ignore: cast_nullable_to_non_nullable
as String?,sourceName: freezed == sourceName ? _self.sourceName : sourceName // ignore: cast_nullable_to_non_nullable
as String?,destName: freezed == destName ? _self.destName : destName // ignore: cast_nullable_to_non_nullable
as String?,categoryId: freezed == categoryId ? _self.categoryId : categoryId // ignore: cast_nullable_to_non_nullable
as String?,categoryName: freezed == categoryName ? _self.categoryName : categoryName // ignore: cast_nullable_to_non_nullable
as String?,budgetId: freezed == budgetId ? _self.budgetId : budgetId // ignore: cast_nullable_to_non_nullable
as String?,budgetName: freezed == budgetName ? _self.budgetName : budgetName // ignore: cast_nullable_to_non_nullable
as String?,billId: freezed == billId ? _self.billId : billId // ignore: cast_nullable_to_non_nullable
as String?,billName: freezed == billName ? _self.billName : billName // ignore: cast_nullable_to_non_nullable
as String?,tagsJson: freezed == tagsJson ? _self.tagsJson : tagsJson // ignore: cast_nullable_to_non_nullable
as String?,notes: freezed == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String?,foreignAmount: freezed == foreignAmount ? _self.foreignAmount : foreignAmount // ignore: cast_nullable_to_non_nullable
as String?,foreignCurrencyCode: freezed == foreignCurrencyCode ? _self.foreignCurrencyCode : foreignCurrencyCode // ignore: cast_nullable_to_non_nullable
as String?,reconciled: null == reconciled ? _self.reconciled : reconciled // ignore: cast_nullable_to_non_nullable
as bool,remoteUpdatedAt: freezed == remoteUpdatedAt ? _self.remoteUpdatedAt : remoteUpdatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,syncStatus: null == syncStatus ? _self.syncStatus : syncStatus // ignore: cast_nullable_to_non_nullable
as SyncStatus,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

// dart format on
