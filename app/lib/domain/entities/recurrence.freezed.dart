// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'recurrence.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Recurrence {

 String get id; String get title; DateTime get updatedAt; int get seq; String? get type; String? get description; DateTime? get repeatUntil; int? get nrOfRepetitions; String? get transactionsJson; String? get fireflyId; bool get active; DateTime? get remoteUpdatedAt; SyncStatus get syncStatus; DateTime? get deletedAt; DateTime? get firstDate; DateTime? get latestDate; bool get applyRules; List<RecurrenceRepetition> get repetitions;
/// Create a copy of Recurrence
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RecurrenceCopyWith<Recurrence> get copyWith => _$RecurrenceCopyWithImpl<Recurrence>(this as Recurrence, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as Recurrence;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Recurrence&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.title, _this.title) || other.title == _this.title)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&(identical(other.seq, _this.seq) || other.seq == _this.seq)&&(identical(other.type, _this.type) || other.type == _this.type)&&(identical(other.description, _this.description) || other.description == _this.description)&&(identical(other.repeatUntil, _this.repeatUntil) || other.repeatUntil == _this.repeatUntil)&&(identical(other.nrOfRepetitions, _this.nrOfRepetitions) || other.nrOfRepetitions == _this.nrOfRepetitions)&&(identical(other.transactionsJson, _this.transactionsJson) || other.transactionsJson == _this.transactionsJson)&&(identical(other.fireflyId, _this.fireflyId) || other.fireflyId == _this.fireflyId)&&(identical(other.active, _this.active) || other.active == _this.active)&&(identical(other.remoteUpdatedAt, _this.remoteUpdatedAt) || other.remoteUpdatedAt == _this.remoteUpdatedAt)&&(identical(other.syncStatus, _this.syncStatus) || other.syncStatus == _this.syncStatus)&&(identical(other.deletedAt, _this.deletedAt) || other.deletedAt == _this.deletedAt)&&(identical(other.firstDate, _this.firstDate) || other.firstDate == _this.firstDate)&&(identical(other.latestDate, _this.latestDate) || other.latestDate == _this.latestDate)&&(identical(other.applyRules, _this.applyRules) || other.applyRules == _this.applyRules)&&const DeepCollectionEquality().equals(other.repetitions, _this.repetitions));
}


@override
int get hashCode {
  final _this = this as Recurrence;
  return Object.hash(runtimeType,_this.id,_this.title,_this.updatedAt,_this.seq,_this.type,_this.description,_this.repeatUntil,_this.nrOfRepetitions,_this.transactionsJson,_this.fireflyId,_this.active,_this.remoteUpdatedAt,_this.syncStatus,_this.deletedAt,_this.firstDate,_this.latestDate,_this.applyRules,const DeepCollectionEquality().hash(_this.repetitions));
}

@override
String toString() {
  final _this = this as Recurrence;
  return 'Recurrence(id: ${_this.id}, title: ${_this.title}, updatedAt: ${_this.updatedAt}, seq: ${_this.seq}, type: ${_this.type}, description: ${_this.description}, repeatUntil: ${_this.repeatUntil}, nrOfRepetitions: ${_this.nrOfRepetitions}, transactionsJson: ${_this.transactionsJson}, fireflyId: ${_this.fireflyId}, active: ${_this.active}, remoteUpdatedAt: ${_this.remoteUpdatedAt}, syncStatus: ${_this.syncStatus}, deletedAt: ${_this.deletedAt}, firstDate: ${_this.firstDate}, latestDate: ${_this.latestDate}, applyRules: ${_this.applyRules}, repetitions: ${_this.repetitions})';
}


}

/// @nodoc
abstract mixin class $RecurrenceCopyWith<$Res>  {
  factory $RecurrenceCopyWith(Recurrence value, $Res Function(Recurrence) _then) = _$RecurrenceCopyWithImpl;
@useResult
$Res call({
 String id, String title, DateTime updatedAt, int seq, String? type, String? description, DateTime? repeatUntil, int? nrOfRepetitions, String? transactionsJson, String? fireflyId, bool active, DateTime? remoteUpdatedAt, SyncStatus syncStatus, DateTime? deletedAt, DateTime? firstDate, DateTime? latestDate, bool applyRules, List<RecurrenceRepetition> repetitions
});




}
/// @nodoc
class _$RecurrenceCopyWithImpl<$Res>
    implements $RecurrenceCopyWith<$Res> {
  _$RecurrenceCopyWithImpl(this._self, this._then);

  final Recurrence _self;
  final $Res Function(Recurrence) _then;

/// Create a copy of Recurrence
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? title = null,Object? updatedAt = null,Object? seq = null,Object? type = freezed,Object? description = freezed,Object? repeatUntil = freezed,Object? nrOfRepetitions = freezed,Object? transactionsJson = freezed,Object? fireflyId = freezed,Object? active = null,Object? remoteUpdatedAt = freezed,Object? syncStatus = null,Object? deletedAt = freezed,Object? firstDate = freezed,Object? latestDate = freezed,Object? applyRules = null,Object? repetitions = null,}) {
  return _then(Recurrence(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,seq: null == seq ? _self.seq : seq // ignore: cast_nullable_to_non_nullable
as int,type: freezed == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String?,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,repeatUntil: freezed == repeatUntil ? _self.repeatUntil : repeatUntil // ignore: cast_nullable_to_non_nullable
as DateTime?,nrOfRepetitions: freezed == nrOfRepetitions ? _self.nrOfRepetitions : nrOfRepetitions // ignore: cast_nullable_to_non_nullable
as int?,transactionsJson: freezed == transactionsJson ? _self.transactionsJson : transactionsJson // ignore: cast_nullable_to_non_nullable
as String?,fireflyId: freezed == fireflyId ? _self.fireflyId : fireflyId // ignore: cast_nullable_to_non_nullable
as String?,active: null == active ? _self.active : active // ignore: cast_nullable_to_non_nullable
as bool,remoteUpdatedAt: freezed == remoteUpdatedAt ? _self.remoteUpdatedAt : remoteUpdatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,syncStatus: null == syncStatus ? _self.syncStatus : syncStatus // ignore: cast_nullable_to_non_nullable
as SyncStatus,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,firstDate: freezed == firstDate ? _self.firstDate : firstDate // ignore: cast_nullable_to_non_nullable
as DateTime?,latestDate: freezed == latestDate ? _self.latestDate : latestDate // ignore: cast_nullable_to_non_nullable
as DateTime?,applyRules: null == applyRules ? _self.applyRules : applyRules // ignore: cast_nullable_to_non_nullable
as bool,repetitions: null == repetitions ? _self.repetitions : repetitions // ignore: cast_nullable_to_non_nullable
as List<RecurrenceRepetition>,
  ));
}

}


/// Adds pattern-matching-related methods to [Recurrence].
extension RecurrencePatterns on Recurrence {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Recurrence value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Recurrence() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Recurrence value)  $default,){
final _that = this;
switch (_that) {
case _Recurrence():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Recurrence value)?  $default,){
final _that = this;
switch (_that) {
case _Recurrence() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String title,  DateTime updatedAt,  int seq,  String? type,  String? description,  DateTime? repeatUntil,  int? nrOfRepetitions,  String? transactionsJson,  String? fireflyId,  bool active,  DateTime? remoteUpdatedAt,  SyncStatus syncStatus,  DateTime? deletedAt,  DateTime? firstDate,  DateTime? latestDate,  bool applyRules,  List<RecurrenceRepetition> repetitions)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Recurrence() when $default != null:
return $default(_that.id,_that.title,_that.updatedAt,_that.seq,_that.type,_that.description,_that.repeatUntil,_that.nrOfRepetitions,_that.transactionsJson,_that.fireflyId,_that.active,_that.remoteUpdatedAt,_that.syncStatus,_that.deletedAt,_that.firstDate,_that.latestDate,_that.applyRules,_that.repetitions);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String title,  DateTime updatedAt,  int seq,  String? type,  String? description,  DateTime? repeatUntil,  int? nrOfRepetitions,  String? transactionsJson,  String? fireflyId,  bool active,  DateTime? remoteUpdatedAt,  SyncStatus syncStatus,  DateTime? deletedAt,  DateTime? firstDate,  DateTime? latestDate,  bool applyRules,  List<RecurrenceRepetition> repetitions)  $default,) {final _that = this;
switch (_that) {
case _Recurrence():
return $default(_that.id,_that.title,_that.updatedAt,_that.seq,_that.type,_that.description,_that.repeatUntil,_that.nrOfRepetitions,_that.transactionsJson,_that.fireflyId,_that.active,_that.remoteUpdatedAt,_that.syncStatus,_that.deletedAt,_that.firstDate,_that.latestDate,_that.applyRules,_that.repetitions);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String title,  DateTime updatedAt,  int seq,  String? type,  String? description,  DateTime? repeatUntil,  int? nrOfRepetitions,  String? transactionsJson,  String? fireflyId,  bool active,  DateTime? remoteUpdatedAt,  SyncStatus syncStatus,  DateTime? deletedAt,  DateTime? firstDate,  DateTime? latestDate,  bool applyRules,  List<RecurrenceRepetition> repetitions)?  $default,) {final _that = this;
switch (_that) {
case _Recurrence() when $default != null:
return $default(_that.id,_that.title,_that.updatedAt,_that.seq,_that.type,_that.description,_that.repeatUntil,_that.nrOfRepetitions,_that.transactionsJson,_that.fireflyId,_that.active,_that.remoteUpdatedAt,_that.syncStatus,_that.deletedAt,_that.firstDate,_that.latestDate,_that.applyRules,_that.repetitions);case _:
  return null;

}
}

}

/// @nodoc


class _Recurrence extends Recurrence {
  const _Recurrence({required this.id, required this.title, required this.updatedAt, required this.seq, this.type, this.description, this.repeatUntil, this.nrOfRepetitions, this.transactionsJson, this.fireflyId, this.active = true, this.remoteUpdatedAt, this.syncStatus = SyncStatus.pending, this.deletedAt, this.firstDate, this.latestDate, this.applyRules = true,  List<RecurrenceRepetition> repetitions = const <RecurrenceRepetition>[]}): _repetitions = repetitions,super._();
  

@override final  String id;
@override final  String title;
@override final  DateTime updatedAt;
@override final  int seq;
@override final  String? type;
@override final  String? description;
@override final  DateTime? repeatUntil;
@override final  int? nrOfRepetitions;
@override final  String? transactionsJson;
@override final  String? fireflyId;
@override@JsonKey() final  bool active;
@override final  DateTime? remoteUpdatedAt;
@override@JsonKey() final  SyncStatus syncStatus;
@override final  DateTime? deletedAt;
@override final  DateTime? firstDate;
@override final  DateTime? latestDate;
@override@JsonKey() final  bool applyRules;
 final  List<RecurrenceRepetition> _repetitions;
@override@JsonKey() List<RecurrenceRepetition> get repetitions {
  if (_repetitions is EqualUnmodifiableListView) return _repetitions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_repetitions);
}


/// Create a copy of Recurrence
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RecurrenceCopyWith<_Recurrence> get copyWith => __$RecurrenceCopyWithImpl<_Recurrence>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _Recurrence&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.seq, seq) || other.seq == seq)&&(identical(other.type, type) || other.type == type)&&(identical(other.description, description) || other.description == description)&&(identical(other.repeatUntil, repeatUntil) || other.repeatUntil == repeatUntil)&&(identical(other.nrOfRepetitions, nrOfRepetitions) || other.nrOfRepetitions == nrOfRepetitions)&&(identical(other.transactionsJson, transactionsJson) || other.transactionsJson == transactionsJson)&&(identical(other.fireflyId, fireflyId) || other.fireflyId == fireflyId)&&(identical(other.active, active) || other.active == active)&&(identical(other.remoteUpdatedAt, remoteUpdatedAt) || other.remoteUpdatedAt == remoteUpdatedAt)&&(identical(other.syncStatus, syncStatus) || other.syncStatus == syncStatus)&&(identical(other.deletedAt, deletedAt) || other.deletedAt == deletedAt)&&(identical(other.firstDate, firstDate) || other.firstDate == firstDate)&&(identical(other.latestDate, latestDate) || other.latestDate == latestDate)&&(identical(other.applyRules, applyRules) || other.applyRules == applyRules)&&const DeepCollectionEquality().equals(other.repetitions, _repetitions));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,title,updatedAt,seq,type,description,repeatUntil,nrOfRepetitions,transactionsJson,fireflyId,active,remoteUpdatedAt,syncStatus,deletedAt,firstDate,latestDate,applyRules,const DeepCollectionEquality().hash(_repetitions));
}

@override
String toString() {
    return 'Recurrence(id: $id, title: $title, updatedAt: $updatedAt, seq: $seq, type: $type, description: $description, repeatUntil: $repeatUntil, nrOfRepetitions: $nrOfRepetitions, transactionsJson: $transactionsJson, fireflyId: $fireflyId, active: $active, remoteUpdatedAt: $remoteUpdatedAt, syncStatus: $syncStatus, deletedAt: $deletedAt, firstDate: $firstDate, latestDate: $latestDate, applyRules: $applyRules, repetitions: $repetitions)';
}


}

/// @nodoc
abstract mixin class _$RecurrenceCopyWith<$Res> implements $RecurrenceCopyWith<$Res> {
  factory _$RecurrenceCopyWith(_Recurrence value, $Res Function(_Recurrence) _then) = __$RecurrenceCopyWithImpl;
@override @useResult
$Res call({
 String id, String title, DateTime updatedAt, int seq, String? type, String? description, DateTime? repeatUntil, int? nrOfRepetitions, String? transactionsJson, String? fireflyId, bool active, DateTime? remoteUpdatedAt, SyncStatus syncStatus, DateTime? deletedAt, DateTime? firstDate, DateTime? latestDate, bool applyRules, List<RecurrenceRepetition> repetitions
});




}
/// @nodoc
class __$RecurrenceCopyWithImpl<$Res>
    implements _$RecurrenceCopyWith<$Res> {
  __$RecurrenceCopyWithImpl(this._self, this._then);

  final _Recurrence _self;
  final $Res Function(_Recurrence) _then;

/// Create a copy of Recurrence
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? title = null,Object? updatedAt = null,Object? seq = null,Object? type = freezed,Object? description = freezed,Object? repeatUntil = freezed,Object? nrOfRepetitions = freezed,Object? transactionsJson = freezed,Object? fireflyId = freezed,Object? active = null,Object? remoteUpdatedAt = freezed,Object? syncStatus = null,Object? deletedAt = freezed,Object? firstDate = freezed,Object? latestDate = freezed,Object? applyRules = null,Object? repetitions = null,}) {
  return _then(_Recurrence(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,seq: null == seq ? _self.seq : seq // ignore: cast_nullable_to_non_nullable
as int,type: freezed == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String?,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,repeatUntil: freezed == repeatUntil ? _self.repeatUntil : repeatUntil // ignore: cast_nullable_to_non_nullable
as DateTime?,nrOfRepetitions: freezed == nrOfRepetitions ? _self.nrOfRepetitions : nrOfRepetitions // ignore: cast_nullable_to_non_nullable
as int?,transactionsJson: freezed == transactionsJson ? _self.transactionsJson : transactionsJson // ignore: cast_nullable_to_non_nullable
as String?,fireflyId: freezed == fireflyId ? _self.fireflyId : fireflyId // ignore: cast_nullable_to_non_nullable
as String?,active: null == active ? _self.active : active // ignore: cast_nullable_to_non_nullable
as bool,remoteUpdatedAt: freezed == remoteUpdatedAt ? _self.remoteUpdatedAt : remoteUpdatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,syncStatus: null == syncStatus ? _self.syncStatus : syncStatus // ignore: cast_nullable_to_non_nullable
as SyncStatus,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,firstDate: freezed == firstDate ? _self.firstDate : firstDate // ignore: cast_nullable_to_non_nullable
as DateTime?,latestDate: freezed == latestDate ? _self.latestDate : latestDate // ignore: cast_nullable_to_non_nullable
as DateTime?,applyRules: null == applyRules ? _self.applyRules : applyRules // ignore: cast_nullable_to_non_nullable
as bool,repetitions: null == repetitions ? _self._repetitions : repetitions // ignore: cast_nullable_to_non_nullable
as List<RecurrenceRepetition>,
  ));
}


}

// dart format on
