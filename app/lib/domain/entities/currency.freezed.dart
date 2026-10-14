// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'currency.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Currency {

 String get id; String get code; String get name; DateTime get updatedAt; int get seq; String? get symbol; String? get rate; String? get fireflyId; bool get symbolFirst; int get decimalPlaces; bool get enabled; bool get isDefault; DateTime? get remoteUpdatedAt; SyncStatus get syncStatus; DateTime? get deletedAt;
/// Create a copy of Currency
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CurrencyCopyWith<Currency> get copyWith => _$CurrencyCopyWithImpl<Currency>(this as Currency, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as Currency;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Currency&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.code, _this.code) || other.code == _this.code)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&(identical(other.seq, _this.seq) || other.seq == _this.seq)&&(identical(other.symbol, _this.symbol) || other.symbol == _this.symbol)&&(identical(other.rate, _this.rate) || other.rate == _this.rate)&&(identical(other.fireflyId, _this.fireflyId) || other.fireflyId == _this.fireflyId)&&(identical(other.symbolFirst, _this.symbolFirst) || other.symbolFirst == _this.symbolFirst)&&(identical(other.decimalPlaces, _this.decimalPlaces) || other.decimalPlaces == _this.decimalPlaces)&&(identical(other.enabled, _this.enabled) || other.enabled == _this.enabled)&&(identical(other.isDefault, _this.isDefault) || other.isDefault == _this.isDefault)&&(identical(other.remoteUpdatedAt, _this.remoteUpdatedAt) || other.remoteUpdatedAt == _this.remoteUpdatedAt)&&(identical(other.syncStatus, _this.syncStatus) || other.syncStatus == _this.syncStatus)&&(identical(other.deletedAt, _this.deletedAt) || other.deletedAt == _this.deletedAt));
}


@override
int get hashCode {
  final _this = this as Currency;
  return Object.hash(runtimeType,_this.id,_this.code,_this.name,_this.updatedAt,_this.seq,_this.symbol,_this.rate,_this.fireflyId,_this.symbolFirst,_this.decimalPlaces,_this.enabled,_this.isDefault,_this.remoteUpdatedAt,_this.syncStatus,_this.deletedAt);
}

@override
String toString() {
  final _this = this as Currency;
  return 'Currency(id: ${_this.id}, code: ${_this.code}, name: ${_this.name}, updatedAt: ${_this.updatedAt}, seq: ${_this.seq}, symbol: ${_this.symbol}, rate: ${_this.rate}, fireflyId: ${_this.fireflyId}, symbolFirst: ${_this.symbolFirst}, decimalPlaces: ${_this.decimalPlaces}, enabled: ${_this.enabled}, isDefault: ${_this.isDefault}, remoteUpdatedAt: ${_this.remoteUpdatedAt}, syncStatus: ${_this.syncStatus}, deletedAt: ${_this.deletedAt})';
}


}

/// @nodoc
abstract mixin class $CurrencyCopyWith<$Res>  {
  factory $CurrencyCopyWith(Currency value, $Res Function(Currency) _then) = _$CurrencyCopyWithImpl;
@useResult
$Res call({
 String id, String code, String name, DateTime updatedAt, int seq, String? symbol, String? rate, String? fireflyId, bool symbolFirst, int decimalPlaces, bool enabled, bool isDefault, DateTime? remoteUpdatedAt, SyncStatus syncStatus, DateTime? deletedAt
});




}
/// @nodoc
class _$CurrencyCopyWithImpl<$Res>
    implements $CurrencyCopyWith<$Res> {
  _$CurrencyCopyWithImpl(this._self, this._then);

  final Currency _self;
  final $Res Function(Currency) _then;

/// Create a copy of Currency
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? code = null,Object? name = null,Object? updatedAt = null,Object? seq = null,Object? symbol = freezed,Object? rate = freezed,Object? fireflyId = freezed,Object? symbolFirst = null,Object? decimalPlaces = null,Object? enabled = null,Object? isDefault = null,Object? remoteUpdatedAt = freezed,Object? syncStatus = null,Object? deletedAt = freezed,}) {
  return _then(Currency(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,seq: null == seq ? _self.seq : seq // ignore: cast_nullable_to_non_nullable
as int,symbol: freezed == symbol ? _self.symbol : symbol // ignore: cast_nullable_to_non_nullable
as String?,rate: freezed == rate ? _self.rate : rate // ignore: cast_nullable_to_non_nullable
as String?,fireflyId: freezed == fireflyId ? _self.fireflyId : fireflyId // ignore: cast_nullable_to_non_nullable
as String?,symbolFirst: null == symbolFirst ? _self.symbolFirst : symbolFirst // ignore: cast_nullable_to_non_nullable
as bool,decimalPlaces: null == decimalPlaces ? _self.decimalPlaces : decimalPlaces // ignore: cast_nullable_to_non_nullable
as int,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,isDefault: null == isDefault ? _self.isDefault : isDefault // ignore: cast_nullable_to_non_nullable
as bool,remoteUpdatedAt: freezed == remoteUpdatedAt ? _self.remoteUpdatedAt : remoteUpdatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,syncStatus: null == syncStatus ? _self.syncStatus : syncStatus // ignore: cast_nullable_to_non_nullable
as SyncStatus,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [Currency].
extension CurrencyPatterns on Currency {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Currency value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Currency() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Currency value)  $default,){
final _that = this;
switch (_that) {
case _Currency():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Currency value)?  $default,){
final _that = this;
switch (_that) {
case _Currency() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String code,  String name,  DateTime updatedAt,  int seq,  String? symbol,  String? rate,  String? fireflyId,  bool symbolFirst,  int decimalPlaces,  bool enabled,  bool isDefault,  DateTime? remoteUpdatedAt,  SyncStatus syncStatus,  DateTime? deletedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Currency() when $default != null:
return $default(_that.id,_that.code,_that.name,_that.updatedAt,_that.seq,_that.symbol,_that.rate,_that.fireflyId,_that.symbolFirst,_that.decimalPlaces,_that.enabled,_that.isDefault,_that.remoteUpdatedAt,_that.syncStatus,_that.deletedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String code,  String name,  DateTime updatedAt,  int seq,  String? symbol,  String? rate,  String? fireflyId,  bool symbolFirst,  int decimalPlaces,  bool enabled,  bool isDefault,  DateTime? remoteUpdatedAt,  SyncStatus syncStatus,  DateTime? deletedAt)  $default,) {final _that = this;
switch (_that) {
case _Currency():
return $default(_that.id,_that.code,_that.name,_that.updatedAt,_that.seq,_that.symbol,_that.rate,_that.fireflyId,_that.symbolFirst,_that.decimalPlaces,_that.enabled,_that.isDefault,_that.remoteUpdatedAt,_that.syncStatus,_that.deletedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String code,  String name,  DateTime updatedAt,  int seq,  String? symbol,  String? rate,  String? fireflyId,  bool symbolFirst,  int decimalPlaces,  bool enabled,  bool isDefault,  DateTime? remoteUpdatedAt,  SyncStatus syncStatus,  DateTime? deletedAt)?  $default,) {final _that = this;
switch (_that) {
case _Currency() when $default != null:
return $default(_that.id,_that.code,_that.name,_that.updatedAt,_that.seq,_that.symbol,_that.rate,_that.fireflyId,_that.symbolFirst,_that.decimalPlaces,_that.enabled,_that.isDefault,_that.remoteUpdatedAt,_that.syncStatus,_that.deletedAt);case _:
  return null;

}
}

}

/// @nodoc


class _Currency extends Currency {
  const _Currency({required this.id, required this.code, required this.name, required this.updatedAt, required this.seq, this.symbol, this.rate, this.fireflyId, this.symbolFirst = false, this.decimalPlaces = 2, this.enabled = true, this.isDefault = false, this.remoteUpdatedAt, this.syncStatus = SyncStatus.pending, this.deletedAt}): super._();
  

@override final  String id;
@override final  String code;
@override final  String name;
@override final  DateTime updatedAt;
@override final  int seq;
@override final  String? symbol;
@override final  String? rate;
@override final  String? fireflyId;
@override@JsonKey() final  bool symbolFirst;
@override@JsonKey() final  int decimalPlaces;
@override@JsonKey() final  bool enabled;
@override@JsonKey() final  bool isDefault;
@override final  DateTime? remoteUpdatedAt;
@override@JsonKey() final  SyncStatus syncStatus;
@override final  DateTime? deletedAt;

/// Create a copy of Currency
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CurrencyCopyWith<_Currency> get copyWith => __$CurrencyCopyWithImpl<_Currency>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _Currency&&(identical(other.id, id) || other.id == id)&&(identical(other.code, code) || other.code == code)&&(identical(other.name, name) || other.name == name)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.seq, seq) || other.seq == seq)&&(identical(other.symbol, symbol) || other.symbol == symbol)&&(identical(other.rate, rate) || other.rate == rate)&&(identical(other.fireflyId, fireflyId) || other.fireflyId == fireflyId)&&(identical(other.symbolFirst, symbolFirst) || other.symbolFirst == symbolFirst)&&(identical(other.decimalPlaces, decimalPlaces) || other.decimalPlaces == decimalPlaces)&&(identical(other.enabled, enabled) || other.enabled == enabled)&&(identical(other.isDefault, isDefault) || other.isDefault == isDefault)&&(identical(other.remoteUpdatedAt, remoteUpdatedAt) || other.remoteUpdatedAt == remoteUpdatedAt)&&(identical(other.syncStatus, syncStatus) || other.syncStatus == syncStatus)&&(identical(other.deletedAt, deletedAt) || other.deletedAt == deletedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,code,name,updatedAt,seq,symbol,rate,fireflyId,symbolFirst,decimalPlaces,enabled,isDefault,remoteUpdatedAt,syncStatus,deletedAt);
}

@override
String toString() {
    return 'Currency(id: $id, code: $code, name: $name, updatedAt: $updatedAt, seq: $seq, symbol: $symbol, rate: $rate, fireflyId: $fireflyId, symbolFirst: $symbolFirst, decimalPlaces: $decimalPlaces, enabled: $enabled, isDefault: $isDefault, remoteUpdatedAt: $remoteUpdatedAt, syncStatus: $syncStatus, deletedAt: $deletedAt)';
}


}

/// @nodoc
abstract mixin class _$CurrencyCopyWith<$Res> implements $CurrencyCopyWith<$Res> {
  factory _$CurrencyCopyWith(_Currency value, $Res Function(_Currency) _then) = __$CurrencyCopyWithImpl;
@override @useResult
$Res call({
 String id, String code, String name, DateTime updatedAt, int seq, String? symbol, String? rate, String? fireflyId, bool symbolFirst, int decimalPlaces, bool enabled, bool isDefault, DateTime? remoteUpdatedAt, SyncStatus syncStatus, DateTime? deletedAt
});




}
/// @nodoc
class __$CurrencyCopyWithImpl<$Res>
    implements _$CurrencyCopyWith<$Res> {
  __$CurrencyCopyWithImpl(this._self, this._then);

  final _Currency _self;
  final $Res Function(_Currency) _then;

/// Create a copy of Currency
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? code = null,Object? name = null,Object? updatedAt = null,Object? seq = null,Object? symbol = freezed,Object? rate = freezed,Object? fireflyId = freezed,Object? symbolFirst = null,Object? decimalPlaces = null,Object? enabled = null,Object? isDefault = null,Object? remoteUpdatedAt = freezed,Object? syncStatus = null,Object? deletedAt = freezed,}) {
  return _then(_Currency(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,seq: null == seq ? _self.seq : seq // ignore: cast_nullable_to_non_nullable
as int,symbol: freezed == symbol ? _self.symbol : symbol // ignore: cast_nullable_to_non_nullable
as String?,rate: freezed == rate ? _self.rate : rate // ignore: cast_nullable_to_non_nullable
as String?,fireflyId: freezed == fireflyId ? _self.fireflyId : fireflyId // ignore: cast_nullable_to_non_nullable
as String?,symbolFirst: null == symbolFirst ? _self.symbolFirst : symbolFirst // ignore: cast_nullable_to_non_nullable
as bool,decimalPlaces: null == decimalPlaces ? _self.decimalPlaces : decimalPlaces // ignore: cast_nullable_to_non_nullable
as int,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,isDefault: null == isDefault ? _self.isDefault : isDefault // ignore: cast_nullable_to_non_nullable
as bool,remoteUpdatedAt: freezed == remoteUpdatedAt ? _self.remoteUpdatedAt : remoteUpdatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,syncStatus: null == syncStatus ? _self.syncStatus : syncStatus // ignore: cast_nullable_to_non_nullable
as SyncStatus,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

// dart format on
