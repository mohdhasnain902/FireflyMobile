// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'rule_group.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$RuleGroup {

 String get id; String get title; DateTime get updatedAt; int get seq; String? get description; String? get fireflyId; bool get active; int? get orderIndex; DateTime? get remoteUpdatedAt; SyncStatus get syncStatus; DateTime? get deletedAt;
/// Create a copy of RuleGroup
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RuleGroupCopyWith<RuleGroup> get copyWith => _$RuleGroupCopyWithImpl<RuleGroup>(this as RuleGroup, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as RuleGroup;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RuleGroup&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.title, _this.title) || other.title == _this.title)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&(identical(other.seq, _this.seq) || other.seq == _this.seq)&&(identical(other.description, _this.description) || other.description == _this.description)&&(identical(other.fireflyId, _this.fireflyId) || other.fireflyId == _this.fireflyId)&&(identical(other.active, _this.active) || other.active == _this.active)&&(identical(other.orderIndex, _this.orderIndex) || other.orderIndex == _this.orderIndex)&&(identical(other.remoteUpdatedAt, _this.remoteUpdatedAt) || other.remoteUpdatedAt == _this.remoteUpdatedAt)&&(identical(other.syncStatus, _this.syncStatus) || other.syncStatus == _this.syncStatus)&&(identical(other.deletedAt, _this.deletedAt) || other.deletedAt == _this.deletedAt));
}


@override
int get hashCode {
  final _this = this as RuleGroup;
  return Object.hash(runtimeType,_this.id,_this.title,_this.updatedAt,_this.seq,_this.description,_this.fireflyId,_this.active,_this.orderIndex,_this.remoteUpdatedAt,_this.syncStatus,_this.deletedAt);
}

@override
String toString() {
  final _this = this as RuleGroup;
  return 'RuleGroup(id: ${_this.id}, title: ${_this.title}, updatedAt: ${_this.updatedAt}, seq: ${_this.seq}, description: ${_this.description}, fireflyId: ${_this.fireflyId}, active: ${_this.active}, orderIndex: ${_this.orderIndex}, remoteUpdatedAt: ${_this.remoteUpdatedAt}, syncStatus: ${_this.syncStatus}, deletedAt: ${_this.deletedAt})';
}


}

/// @nodoc
abstract mixin class $RuleGroupCopyWith<$Res>  {
  factory $RuleGroupCopyWith(RuleGroup value, $Res Function(RuleGroup) _then) = _$RuleGroupCopyWithImpl;
@useResult
$Res call({
 String id, String title, DateTime updatedAt, int seq, String? description, String? fireflyId, bool active, int? orderIndex, DateTime? remoteUpdatedAt, SyncStatus syncStatus, DateTime? deletedAt
});




}
/// @nodoc
class _$RuleGroupCopyWithImpl<$Res>
    implements $RuleGroupCopyWith<$Res> {
  _$RuleGroupCopyWithImpl(this._self, this._then);

  final RuleGroup _self;
  final $Res Function(RuleGroup) _then;

/// Create a copy of RuleGroup
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? title = null,Object? updatedAt = null,Object? seq = null,Object? description = freezed,Object? fireflyId = freezed,Object? active = null,Object? orderIndex = freezed,Object? remoteUpdatedAt = freezed,Object? syncStatus = null,Object? deletedAt = freezed,}) {
  return _then(RuleGroup(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,seq: null == seq ? _self.seq : seq // ignore: cast_nullable_to_non_nullable
as int,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,fireflyId: freezed == fireflyId ? _self.fireflyId : fireflyId // ignore: cast_nullable_to_non_nullable
as String?,active: null == active ? _self.active : active // ignore: cast_nullable_to_non_nullable
as bool,orderIndex: freezed == orderIndex ? _self.orderIndex : orderIndex // ignore: cast_nullable_to_non_nullable
as int?,remoteUpdatedAt: freezed == remoteUpdatedAt ? _self.remoteUpdatedAt : remoteUpdatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,syncStatus: null == syncStatus ? _self.syncStatus : syncStatus // ignore: cast_nullable_to_non_nullable
as SyncStatus,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [RuleGroup].
extension RuleGroupPatterns on RuleGroup {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RuleGroup value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RuleGroup() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RuleGroup value)  $default,){
final _that = this;
switch (_that) {
case _RuleGroup():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RuleGroup value)?  $default,){
final _that = this;
switch (_that) {
case _RuleGroup() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String title,  DateTime updatedAt,  int seq,  String? description,  String? fireflyId,  bool active,  int? orderIndex,  DateTime? remoteUpdatedAt,  SyncStatus syncStatus,  DateTime? deletedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RuleGroup() when $default != null:
return $default(_that.id,_that.title,_that.updatedAt,_that.seq,_that.description,_that.fireflyId,_that.active,_that.orderIndex,_that.remoteUpdatedAt,_that.syncStatus,_that.deletedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String title,  DateTime updatedAt,  int seq,  String? description,  String? fireflyId,  bool active,  int? orderIndex,  DateTime? remoteUpdatedAt,  SyncStatus syncStatus,  DateTime? deletedAt)  $default,) {final _that = this;
switch (_that) {
case _RuleGroup():
return $default(_that.id,_that.title,_that.updatedAt,_that.seq,_that.description,_that.fireflyId,_that.active,_that.orderIndex,_that.remoteUpdatedAt,_that.syncStatus,_that.deletedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String title,  DateTime updatedAt,  int seq,  String? description,  String? fireflyId,  bool active,  int? orderIndex,  DateTime? remoteUpdatedAt,  SyncStatus syncStatus,  DateTime? deletedAt)?  $default,) {final _that = this;
switch (_that) {
case _RuleGroup() when $default != null:
return $default(_that.id,_that.title,_that.updatedAt,_that.seq,_that.description,_that.fireflyId,_that.active,_that.orderIndex,_that.remoteUpdatedAt,_that.syncStatus,_that.deletedAt);case _:
  return null;

}
}

}

/// @nodoc


class _RuleGroup extends RuleGroup {
  const _RuleGroup({required this.id, required this.title, required this.updatedAt, required this.seq, this.description, this.fireflyId, this.active = true, this.orderIndex, this.remoteUpdatedAt, this.syncStatus = SyncStatus.pending, this.deletedAt}): super._();
  

@override final  String id;
@override final  String title;
@override final  DateTime updatedAt;
@override final  int seq;
@override final  String? description;
@override final  String? fireflyId;
@override@JsonKey() final  bool active;
@override final  int? orderIndex;
@override final  DateTime? remoteUpdatedAt;
@override@JsonKey() final  SyncStatus syncStatus;
@override final  DateTime? deletedAt;

/// Create a copy of RuleGroup
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RuleGroupCopyWith<_RuleGroup> get copyWith => __$RuleGroupCopyWithImpl<_RuleGroup>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _RuleGroup&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.seq, seq) || other.seq == seq)&&(identical(other.description, description) || other.description == description)&&(identical(other.fireflyId, fireflyId) || other.fireflyId == fireflyId)&&(identical(other.active, active) || other.active == active)&&(identical(other.orderIndex, orderIndex) || other.orderIndex == orderIndex)&&(identical(other.remoteUpdatedAt, remoteUpdatedAt) || other.remoteUpdatedAt == remoteUpdatedAt)&&(identical(other.syncStatus, syncStatus) || other.syncStatus == syncStatus)&&(identical(other.deletedAt, deletedAt) || other.deletedAt == deletedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,title,updatedAt,seq,description,fireflyId,active,orderIndex,remoteUpdatedAt,syncStatus,deletedAt);
}

@override
String toString() {
    return 'RuleGroup(id: $id, title: $title, updatedAt: $updatedAt, seq: $seq, description: $description, fireflyId: $fireflyId, active: $active, orderIndex: $orderIndex, remoteUpdatedAt: $remoteUpdatedAt, syncStatus: $syncStatus, deletedAt: $deletedAt)';
}


}

/// @nodoc
abstract mixin class _$RuleGroupCopyWith<$Res> implements $RuleGroupCopyWith<$Res> {
  factory _$RuleGroupCopyWith(_RuleGroup value, $Res Function(_RuleGroup) _then) = __$RuleGroupCopyWithImpl;
@override @useResult
$Res call({
 String id, String title, DateTime updatedAt, int seq, String? description, String? fireflyId, bool active, int? orderIndex, DateTime? remoteUpdatedAt, SyncStatus syncStatus, DateTime? deletedAt
});




}
/// @nodoc
class __$RuleGroupCopyWithImpl<$Res>
    implements _$RuleGroupCopyWith<$Res> {
  __$RuleGroupCopyWithImpl(this._self, this._then);

  final _RuleGroup _self;
  final $Res Function(_RuleGroup) _then;

/// Create a copy of RuleGroup
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? title = null,Object? updatedAt = null,Object? seq = null,Object? description = freezed,Object? fireflyId = freezed,Object? active = null,Object? orderIndex = freezed,Object? remoteUpdatedAt = freezed,Object? syncStatus = null,Object? deletedAt = freezed,}) {
  return _then(_RuleGroup(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,seq: null == seq ? _self.seq : seq // ignore: cast_nullable_to_non_nullable
as int,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,fireflyId: freezed == fireflyId ? _self.fireflyId : fireflyId // ignore: cast_nullable_to_non_nullable
as String?,active: null == active ? _self.active : active // ignore: cast_nullable_to_non_nullable
as bool,orderIndex: freezed == orderIndex ? _self.orderIndex : orderIndex // ignore: cast_nullable_to_non_nullable
as int?,remoteUpdatedAt: freezed == remoteUpdatedAt ? _self.remoteUpdatedAt : remoteUpdatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,syncStatus: null == syncStatus ? _self.syncStatus : syncStatus // ignore: cast_nullable_to_non_nullable
as SyncStatus,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

// dart format on
