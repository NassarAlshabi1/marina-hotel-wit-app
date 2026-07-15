// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'sync_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SyncState implements DiagnosticableTreeMixin {

 SyncStatus get status; int get progress; String? get message; DateTime? get lastSyncTime; int get pendingChanges; String? get error;
/// Create a copy of SyncState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SyncStateCopyWith<SyncState> get copyWith => _$SyncStateCopyWithImpl<SyncState>(this as SyncState, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'SyncState'))
    ..add(DiagnosticsProperty('status', status))..add(DiagnosticsProperty('progress', progress))..add(DiagnosticsProperty('message', message))..add(DiagnosticsProperty('lastSyncTime', lastSyncTime))..add(DiagnosticsProperty('pendingChanges', pendingChanges))..add(DiagnosticsProperty('error', error));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SyncState&&(identical(other.status, status) || other.status == status)&&(identical(other.progress, progress) || other.progress == progress)&&(identical(other.message, message) || other.message == message)&&(identical(other.lastSyncTime, lastSyncTime) || other.lastSyncTime == lastSyncTime)&&(identical(other.pendingChanges, pendingChanges) || other.pendingChanges == pendingChanges)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode => Object.hash(runtimeType,status,progress,message,lastSyncTime,pendingChanges,error);

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'SyncState(status: $status, progress: $progress, message: $message, lastSyncTime: $lastSyncTime, pendingChanges: $pendingChanges, error: $error)';
}


}

/// @nodoc
abstract mixin class $SyncStateCopyWith<$Res>  {
  factory $SyncStateCopyWith(SyncState value, $Res Function(SyncState) _then) = _$SyncStateCopyWithImpl;
@useResult
$Res call({
 SyncStatus status, int progress, String? message, DateTime? lastSyncTime, int pendingChanges, String? error
});




}
/// @nodoc
class _$SyncStateCopyWithImpl<$Res>
    implements $SyncStateCopyWith<$Res> {
  _$SyncStateCopyWithImpl(this._self, this._then);

  final SyncState _self;
  final $Res Function(SyncState) _then;

/// Create a copy of SyncState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? status = null,Object? progress = null,Object? message = freezed,Object? lastSyncTime = freezed,Object? pendingChanges = null,Object? error = freezed,}) {
  return _then(_self.copyWith(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as SyncStatus,progress: null == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as int,message: freezed == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String?,lastSyncTime: freezed == lastSyncTime ? _self.lastSyncTime : lastSyncTime // ignore: cast_nullable_to_non_nullable
as DateTime?,pendingChanges: null == pendingChanges ? _self.pendingChanges : pendingChanges // ignore: cast_nullable_to_non_nullable
as int,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [SyncState].
extension SyncStatePatterns on SyncState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SyncState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SyncState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SyncState value)  $default,){
final _that = this;
switch (_that) {
case _SyncState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SyncState value)?  $default,){
final _that = this;
switch (_that) {
case _SyncState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( SyncStatus status,  int progress,  String? message,  DateTime? lastSyncTime,  int pendingChanges,  String? error)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SyncState() when $default != null:
return $default(_that.status,_that.progress,_that.message,_that.lastSyncTime,_that.pendingChanges,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( SyncStatus status,  int progress,  String? message,  DateTime? lastSyncTime,  int pendingChanges,  String? error)  $default,) {final _that = this;
switch (_that) {
case _SyncState():
return $default(_that.status,_that.progress,_that.message,_that.lastSyncTime,_that.pendingChanges,_that.error);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( SyncStatus status,  int progress,  String? message,  DateTime? lastSyncTime,  int pendingChanges,  String? error)?  $default,) {final _that = this;
switch (_that) {
case _SyncState() when $default != null:
return $default(_that.status,_that.progress,_that.message,_that.lastSyncTime,_that.pendingChanges,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class _SyncState extends SyncState with DiagnosticableTreeMixin {
  const _SyncState({required this.status, this.progress = 0, this.message, this.lastSyncTime, this.pendingChanges = 0, this.error}): super._();
  

@override final  SyncStatus status;
@override@JsonKey() final  int progress;
@override final  String? message;
@override final  DateTime? lastSyncTime;
@override@JsonKey() final  int pendingChanges;
@override final  String? error;

/// Create a copy of SyncState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SyncStateCopyWith<_SyncState> get copyWith => __$SyncStateCopyWithImpl<_SyncState>(this, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'SyncState'))
    ..add(DiagnosticsProperty('status', status))..add(DiagnosticsProperty('progress', progress))..add(DiagnosticsProperty('message', message))..add(DiagnosticsProperty('lastSyncTime', lastSyncTime))..add(DiagnosticsProperty('pendingChanges', pendingChanges))..add(DiagnosticsProperty('error', error));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SyncState&&(identical(other.status, status) || other.status == status)&&(identical(other.progress, progress) || other.progress == progress)&&(identical(other.message, message) || other.message == message)&&(identical(other.lastSyncTime, lastSyncTime) || other.lastSyncTime == lastSyncTime)&&(identical(other.pendingChanges, pendingChanges) || other.pendingChanges == pendingChanges)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode => Object.hash(runtimeType,status,progress,message,lastSyncTime,pendingChanges,error);

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'SyncState(status: $status, progress: $progress, message: $message, lastSyncTime: $lastSyncTime, pendingChanges: $pendingChanges, error: $error)';
}


}

/// @nodoc
abstract mixin class _$SyncStateCopyWith<$Res> implements $SyncStateCopyWith<$Res> {
  factory _$SyncStateCopyWith(_SyncState value, $Res Function(_SyncState) _then) = __$SyncStateCopyWithImpl;
@override @useResult
$Res call({
 SyncStatus status, int progress, String? message, DateTime? lastSyncTime, int pendingChanges, String? error
});




}
/// @nodoc
class __$SyncStateCopyWithImpl<$Res>
    implements _$SyncStateCopyWith<$Res> {
  __$SyncStateCopyWithImpl(this._self, this._then);

  final _SyncState _self;
  final $Res Function(_SyncState) _then;

/// Create a copy of SyncState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? status = null,Object? progress = null,Object? message = freezed,Object? lastSyncTime = freezed,Object? pendingChanges = null,Object? error = freezed,}) {
  return _then(_SyncState(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as SyncStatus,progress: null == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as int,message: freezed == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String?,lastSyncTime: freezed == lastSyncTime ? _self.lastSyncTime : lastSyncTime // ignore: cast_nullable_to_non_nullable
as DateTime?,pendingChanges: null == pendingChanges ? _self.pendingChanges : pendingChanges // ignore: cast_nullable_to_non_nullable
as int,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}


/// @nodoc
mixin _$SyncSettings implements DiagnosticableTreeMixin {

 bool get autoSyncEnabled; int get syncIntervalMinutes; bool get syncOnWifiOnly; bool get compressData; SyncPriority get defaultPriority;
/// Create a copy of SyncSettings
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SyncSettingsCopyWith<SyncSettings> get copyWith => _$SyncSettingsCopyWithImpl<SyncSettings>(this as SyncSettings, _$identity);

  /// Serializes this SyncSettings to a JSON map.
  Map<String, dynamic> toJson();

@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'SyncSettings'))
    ..add(DiagnosticsProperty('autoSyncEnabled', autoSyncEnabled))..add(DiagnosticsProperty('syncIntervalMinutes', syncIntervalMinutes))..add(DiagnosticsProperty('syncOnWifiOnly', syncOnWifiOnly))..add(DiagnosticsProperty('compressData', compressData))..add(DiagnosticsProperty('defaultPriority', defaultPriority));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SyncSettings&&(identical(other.autoSyncEnabled, autoSyncEnabled) || other.autoSyncEnabled == autoSyncEnabled)&&(identical(other.syncIntervalMinutes, syncIntervalMinutes) || other.syncIntervalMinutes == syncIntervalMinutes)&&(identical(other.syncOnWifiOnly, syncOnWifiOnly) || other.syncOnWifiOnly == syncOnWifiOnly)&&(identical(other.compressData, compressData) || other.compressData == compressData)&&(identical(other.defaultPriority, defaultPriority) || other.defaultPriority == defaultPriority));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,autoSyncEnabled,syncIntervalMinutes,syncOnWifiOnly,compressData,defaultPriority);

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'SyncSettings(autoSyncEnabled: $autoSyncEnabled, syncIntervalMinutes: $syncIntervalMinutes, syncOnWifiOnly: $syncOnWifiOnly, compressData: $compressData, defaultPriority: $defaultPriority)';
}


}

/// @nodoc
abstract mixin class $SyncSettingsCopyWith<$Res>  {
  factory $SyncSettingsCopyWith(SyncSettings value, $Res Function(SyncSettings) _then) = _$SyncSettingsCopyWithImpl;
@useResult
$Res call({
 bool autoSyncEnabled, int syncIntervalMinutes, bool syncOnWifiOnly, bool compressData, SyncPriority defaultPriority
});




}
/// @nodoc
class _$SyncSettingsCopyWithImpl<$Res>
    implements $SyncSettingsCopyWith<$Res> {
  _$SyncSettingsCopyWithImpl(this._self, this._then);

  final SyncSettings _self;
  final $Res Function(SyncSettings) _then;

/// Create a copy of SyncSettings
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? autoSyncEnabled = null,Object? syncIntervalMinutes = null,Object? syncOnWifiOnly = null,Object? compressData = null,Object? defaultPriority = null,}) {
  return _then(_self.copyWith(
autoSyncEnabled: null == autoSyncEnabled ? _self.autoSyncEnabled : autoSyncEnabled // ignore: cast_nullable_to_non_nullable
as bool,syncIntervalMinutes: null == syncIntervalMinutes ? _self.syncIntervalMinutes : syncIntervalMinutes // ignore: cast_nullable_to_non_nullable
as int,syncOnWifiOnly: null == syncOnWifiOnly ? _self.syncOnWifiOnly : syncOnWifiOnly // ignore: cast_nullable_to_non_nullable
as bool,compressData: null == compressData ? _self.compressData : compressData // ignore: cast_nullable_to_non_nullable
as bool,defaultPriority: null == defaultPriority ? _self.defaultPriority : defaultPriority // ignore: cast_nullable_to_non_nullable
as SyncPriority,
  ));
}

}


/// Adds pattern-matching-related methods to [SyncSettings].
extension SyncSettingsPatterns on SyncSettings {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SyncSettings value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SyncSettings() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SyncSettings value)  $default,){
final _that = this;
switch (_that) {
case _SyncSettings():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SyncSettings value)?  $default,){
final _that = this;
switch (_that) {
case _SyncSettings() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool autoSyncEnabled,  int syncIntervalMinutes,  bool syncOnWifiOnly,  bool compressData,  SyncPriority defaultPriority)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SyncSettings() when $default != null:
return $default(_that.autoSyncEnabled,_that.syncIntervalMinutes,_that.syncOnWifiOnly,_that.compressData,_that.defaultPriority);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool autoSyncEnabled,  int syncIntervalMinutes,  bool syncOnWifiOnly,  bool compressData,  SyncPriority defaultPriority)  $default,) {final _that = this;
switch (_that) {
case _SyncSettings():
return $default(_that.autoSyncEnabled,_that.syncIntervalMinutes,_that.syncOnWifiOnly,_that.compressData,_that.defaultPriority);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool autoSyncEnabled,  int syncIntervalMinutes,  bool syncOnWifiOnly,  bool compressData,  SyncPriority defaultPriority)?  $default,) {final _that = this;
switch (_that) {
case _SyncSettings() when $default != null:
return $default(_that.autoSyncEnabled,_that.syncIntervalMinutes,_that.syncOnWifiOnly,_that.compressData,_that.defaultPriority);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _SyncSettings with DiagnosticableTreeMixin implements SyncSettings {
  const _SyncSettings({this.autoSyncEnabled = true, this.syncIntervalMinutes = 5, this.syncOnWifiOnly = true, this.compressData = true, this.defaultPriority = SyncPriority.normal});
  factory _SyncSettings.fromJson(Map<String, dynamic> json) => _$SyncSettingsFromJson(json);

@override@JsonKey() final  bool autoSyncEnabled;
@override@JsonKey() final  int syncIntervalMinutes;
@override@JsonKey() final  bool syncOnWifiOnly;
@override@JsonKey() final  bool compressData;
@override@JsonKey() final  SyncPriority defaultPriority;

/// Create a copy of SyncSettings
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SyncSettingsCopyWith<_SyncSettings> get copyWith => __$SyncSettingsCopyWithImpl<_SyncSettings>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$SyncSettingsToJson(this, );
}
@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'SyncSettings'))
    ..add(DiagnosticsProperty('autoSyncEnabled', autoSyncEnabled))..add(DiagnosticsProperty('syncIntervalMinutes', syncIntervalMinutes))..add(DiagnosticsProperty('syncOnWifiOnly', syncOnWifiOnly))..add(DiagnosticsProperty('compressData', compressData))..add(DiagnosticsProperty('defaultPriority', defaultPriority));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SyncSettings&&(identical(other.autoSyncEnabled, autoSyncEnabled) || other.autoSyncEnabled == autoSyncEnabled)&&(identical(other.syncIntervalMinutes, syncIntervalMinutes) || other.syncIntervalMinutes == syncIntervalMinutes)&&(identical(other.syncOnWifiOnly, syncOnWifiOnly) || other.syncOnWifiOnly == syncOnWifiOnly)&&(identical(other.compressData, compressData) || other.compressData == compressData)&&(identical(other.defaultPriority, defaultPriority) || other.defaultPriority == defaultPriority));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,autoSyncEnabled,syncIntervalMinutes,syncOnWifiOnly,compressData,defaultPriority);

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'SyncSettings(autoSyncEnabled: $autoSyncEnabled, syncIntervalMinutes: $syncIntervalMinutes, syncOnWifiOnly: $syncOnWifiOnly, compressData: $compressData, defaultPriority: $defaultPriority)';
}


}

/// @nodoc
abstract mixin class _$SyncSettingsCopyWith<$Res> implements $SyncSettingsCopyWith<$Res> {
  factory _$SyncSettingsCopyWith(_SyncSettings value, $Res Function(_SyncSettings) _then) = __$SyncSettingsCopyWithImpl;
@override @useResult
$Res call({
 bool autoSyncEnabled, int syncIntervalMinutes, bool syncOnWifiOnly, bool compressData, SyncPriority defaultPriority
});




}
/// @nodoc
class __$SyncSettingsCopyWithImpl<$Res>
    implements _$SyncSettingsCopyWith<$Res> {
  __$SyncSettingsCopyWithImpl(this._self, this._then);

  final _SyncSettings _self;
  final $Res Function(_SyncSettings) _then;

/// Create a copy of SyncSettings
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? autoSyncEnabled = null,Object? syncIntervalMinutes = null,Object? syncOnWifiOnly = null,Object? compressData = null,Object? defaultPriority = null,}) {
  return _then(_SyncSettings(
autoSyncEnabled: null == autoSyncEnabled ? _self.autoSyncEnabled : autoSyncEnabled // ignore: cast_nullable_to_non_nullable
as bool,syncIntervalMinutes: null == syncIntervalMinutes ? _self.syncIntervalMinutes : syncIntervalMinutes // ignore: cast_nullable_to_non_nullable
as int,syncOnWifiOnly: null == syncOnWifiOnly ? _self.syncOnWifiOnly : syncOnWifiOnly // ignore: cast_nullable_to_non_nullable
as bool,compressData: null == compressData ? _self.compressData : compressData // ignore: cast_nullable_to_non_nullable
as bool,defaultPriority: null == defaultPriority ? _self.defaultPriority : defaultPriority // ignore: cast_nullable_to_non_nullable
as SyncPriority,
  ));
}


}

// dart format on
