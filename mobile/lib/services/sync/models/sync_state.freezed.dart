// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'sync_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

/// @nodoc
mixin _$SyncState {
  SyncStatus get status => throw _privateConstructorUsedError;
  int get progress => throw _privateConstructorUsedError;
  String? get message => throw _privateConstructorUsedError;
  DateTime? get lastSyncTime => throw _privateConstructorUsedError;
  int get pendingChanges => throw _privateConstructorUsedError;
  String? get error => throw _privateConstructorUsedError;

  /// Create a copy of SyncState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SyncStateCopyWith<SyncState> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SyncStateCopyWith<$Res> {
  factory $SyncStateCopyWith(SyncState value, $Res Function(SyncState) then) =
      _$SyncStateCopyWithImpl<$Res, SyncState>;
  @useResult
  $Res call(
      {SyncStatus status,
      int progress,
      String? message,
      DateTime? lastSyncTime,
      int pendingChanges,
      String? error});
}

/// @nodoc
class _$SyncStateCopyWithImpl<$Res, $Val extends SyncState>
    implements $SyncStateCopyWith<$Res> {
  _$SyncStateCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of SyncState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? status = null,
    Object? progress = null,
    Object? message = freezed,
    Object? lastSyncTime = freezed,
    Object? pendingChanges = null,
    Object? error = freezed,
  }) {
    return _then(_value.copyWith(
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as SyncStatus,
      progress: null == progress
          ? _value.progress
          : progress // ignore: cast_nullable_to_non_nullable
              as int,
      message: freezed == message
          ? _value.message
          : message // ignore: cast_nullable_to_non_nullable
              as String?,
      lastSyncTime: freezed == lastSyncTime
          ? _value.lastSyncTime
          : lastSyncTime // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      pendingChanges: null == pendingChanges
          ? _value.pendingChanges
          : pendingChanges // ignore: cast_nullable_to_non_nullable
              as int,
      error: freezed == error
          ? _value.error
          : error // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$SyncStateImplCopyWith<$Res>
    implements $SyncStateCopyWith<$Res> {
  factory _$$SyncStateImplCopyWith(
          _$SyncStateImpl value, $Res Function(_$SyncStateImpl) then) =
      __$$SyncStateImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {SyncStatus status,
      int progress,
      String? message,
      DateTime? lastSyncTime,
      int pendingChanges,
      String? error});
}

/// @nodoc
class __$$SyncStateImplCopyWithImpl<$Res>
    extends _$SyncStateCopyWithImpl<$Res, _$SyncStateImpl>
    implements _$$SyncStateImplCopyWith<$Res> {
  __$$SyncStateImplCopyWithImpl(
      _$SyncStateImpl _value, $Res Function(_$SyncStateImpl) _then)
      : super(_value, _then);

  /// Create a copy of SyncState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? status = null,
    Object? progress = null,
    Object? message = freezed,
    Object? lastSyncTime = freezed,
    Object? pendingChanges = null,
    Object? error = freezed,
  }) {
    return _then(_$SyncStateImpl(
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as SyncStatus,
      progress: null == progress
          ? _value.progress
          : progress // ignore: cast_nullable_to_non_nullable
              as int,
      message: freezed == message
          ? _value.message
          : message // ignore: cast_nullable_to_non_nullable
              as String?,
      lastSyncTime: freezed == lastSyncTime
          ? _value.lastSyncTime
          : lastSyncTime // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      pendingChanges: null == pendingChanges
          ? _value.pendingChanges
          : pendingChanges // ignore: cast_nullable_to_non_nullable
              as int,
      error: freezed == error
          ? _value.error
          : error // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc

class _$SyncStateImpl extends _SyncState with DiagnosticableTreeMixin {
  const _$SyncStateImpl(
      {required this.status,
      this.progress = 0,
      this.message,
      this.lastSyncTime,
      this.pendingChanges = 0,
      this.error})
      : super._();

  @override
  final SyncStatus status;
  @override
  @JsonKey()
  final int progress;
  @override
  final String? message;
  @override
  final DateTime? lastSyncTime;
  @override
  @JsonKey()
  final int pendingChanges;
  @override
  final String? error;

  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) {
    return 'SyncState(status: $status, progress: $progress, message: $message, lastSyncTime: $lastSyncTime, pendingChanges: $pendingChanges, error: $error)';
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty('type', 'SyncState'))
      ..add(DiagnosticsProperty('status', status))
      ..add(DiagnosticsProperty('progress', progress))
      ..add(DiagnosticsProperty('message', message))
      ..add(DiagnosticsProperty('lastSyncTime', lastSyncTime))
      ..add(DiagnosticsProperty('pendingChanges', pendingChanges))
      ..add(DiagnosticsProperty('error', error));
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SyncStateImpl &&
            (identical(other.status, status) || other.status == status) &&
            (identical(other.progress, progress) ||
                other.progress == progress) &&
            (identical(other.message, message) || other.message == message) &&
            (identical(other.lastSyncTime, lastSyncTime) ||
                other.lastSyncTime == lastSyncTime) &&
            (identical(other.pendingChanges, pendingChanges) ||
                other.pendingChanges == pendingChanges) &&
            (identical(other.error, error) || other.error == error));
  }

  @override
  int get hashCode => Object.hash(runtimeType, status, progress, message,
      lastSyncTime, pendingChanges, error);

  /// Create a copy of SyncState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SyncStateImplCopyWith<_$SyncStateImpl> get copyWith =>
      __$$SyncStateImplCopyWithImpl<_$SyncStateImpl>(this, _$identity);
}

abstract class _SyncState extends SyncState {
  const factory _SyncState(
      {required final SyncStatus status,
      final int progress,
      final String? message,
      final DateTime? lastSyncTime,
      final int pendingChanges,
      final String? error}) = _$SyncStateImpl;
  const _SyncState._() : super._();

  @override
  SyncStatus get status;
  @override
  int get progress;
  @override
  String? get message;
  @override
  DateTime? get lastSyncTime;
  @override
  int get pendingChanges;
  @override
  String? get error;

  /// Create a copy of SyncState
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SyncStateImplCopyWith<_$SyncStateImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

SyncSettings _$SyncSettingsFromJson(Map<String, dynamic> json) {
  return _SyncSettings.fromJson(json);
}

/// @nodoc
mixin _$SyncSettings {
  bool get autoSyncEnabled => throw _privateConstructorUsedError;
  int get syncIntervalMinutes => throw _privateConstructorUsedError;
  bool get syncOnWifiOnly => throw _privateConstructorUsedError;
  bool get compressData => throw _privateConstructorUsedError;
  SyncPriority get defaultPriority => throw _privateConstructorUsedError;

  /// Serializes this SyncSettings to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of SyncSettings
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SyncSettingsCopyWith<SyncSettings> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SyncSettingsCopyWith<$Res> {
  factory $SyncSettingsCopyWith(
          SyncSettings value, $Res Function(SyncSettings) then) =
      _$SyncSettingsCopyWithImpl<$Res, SyncSettings>;
  @useResult
  $Res call(
      {bool autoSyncEnabled,
      int syncIntervalMinutes,
      bool syncOnWifiOnly,
      bool compressData,
      SyncPriority defaultPriority});
}

/// @nodoc
class _$SyncSettingsCopyWithImpl<$Res, $Val extends SyncSettings>
    implements $SyncSettingsCopyWith<$Res> {
  _$SyncSettingsCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of SyncSettings
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? autoSyncEnabled = null,
    Object? syncIntervalMinutes = null,
    Object? syncOnWifiOnly = null,
    Object? compressData = null,
    Object? defaultPriority = null,
  }) {
    return _then(_value.copyWith(
      autoSyncEnabled: null == autoSyncEnabled
          ? _value.autoSyncEnabled
          : autoSyncEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      syncIntervalMinutes: null == syncIntervalMinutes
          ? _value.syncIntervalMinutes
          : syncIntervalMinutes // ignore: cast_nullable_to_non_nullable
              as int,
      syncOnWifiOnly: null == syncOnWifiOnly
          ? _value.syncOnWifiOnly
          : syncOnWifiOnly // ignore: cast_nullable_to_non_nullable
              as bool,
      compressData: null == compressData
          ? _value.compressData
          : compressData // ignore: cast_nullable_to_non_nullable
              as bool,
      defaultPriority: null == defaultPriority
          ? _value.defaultPriority
          : defaultPriority // ignore: cast_nullable_to_non_nullable
              as SyncPriority,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$SyncSettingsImplCopyWith<$Res>
    implements $SyncSettingsCopyWith<$Res> {
  factory _$$SyncSettingsImplCopyWith(
          _$SyncSettingsImpl value, $Res Function(_$SyncSettingsImpl) then) =
      __$$SyncSettingsImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {bool autoSyncEnabled,
      int syncIntervalMinutes,
      bool syncOnWifiOnly,
      bool compressData,
      SyncPriority defaultPriority});
}

/// @nodoc
class __$$SyncSettingsImplCopyWithImpl<$Res>
    extends _$SyncSettingsCopyWithImpl<$Res, _$SyncSettingsImpl>
    implements _$$SyncSettingsImplCopyWith<$Res> {
  __$$SyncSettingsImplCopyWithImpl(
      _$SyncSettingsImpl _value, $Res Function(_$SyncSettingsImpl) _then)
      : super(_value, _then);

  /// Create a copy of SyncSettings
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? autoSyncEnabled = null,
    Object? syncIntervalMinutes = null,
    Object? syncOnWifiOnly = null,
    Object? compressData = null,
    Object? defaultPriority = null,
  }) {
    return _then(_$SyncSettingsImpl(
      autoSyncEnabled: null == autoSyncEnabled
          ? _value.autoSyncEnabled
          : autoSyncEnabled // ignore: cast_nullable_to_non_nullable
              as bool,
      syncIntervalMinutes: null == syncIntervalMinutes
          ? _value.syncIntervalMinutes
          : syncIntervalMinutes // ignore: cast_nullable_to_non_nullable
              as int,
      syncOnWifiOnly: null == syncOnWifiOnly
          ? _value.syncOnWifiOnly
          : syncOnWifiOnly // ignore: cast_nullable_to_non_nullable
              as bool,
      compressData: null == compressData
          ? _value.compressData
          : compressData // ignore: cast_nullable_to_non_nullable
              as bool,
      defaultPriority: null == defaultPriority
          ? _value.defaultPriority
          : defaultPriority // ignore: cast_nullable_to_non_nullable
              as SyncPriority,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$SyncSettingsImpl with DiagnosticableTreeMixin implements _SyncSettings {
  const _$SyncSettingsImpl(
      {this.autoSyncEnabled = true,
      this.syncIntervalMinutes = 5,
      this.syncOnWifiOnly = true,
      this.compressData = true,
      this.defaultPriority = SyncPriority.normal});

  factory _$SyncSettingsImpl.fromJson(Map<String, dynamic> json) =>
      _$$SyncSettingsImplFromJson(json);

  @override
  @JsonKey()
  final bool autoSyncEnabled;
  @override
  @JsonKey()
  final int syncIntervalMinutes;
  @override
  @JsonKey()
  final bool syncOnWifiOnly;
  @override
  @JsonKey()
  final bool compressData;
  @override
  @JsonKey()
  final SyncPriority defaultPriority;

  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) {
    return 'SyncSettings(autoSyncEnabled: $autoSyncEnabled, syncIntervalMinutes: $syncIntervalMinutes, syncOnWifiOnly: $syncOnWifiOnly, compressData: $compressData, defaultPriority: $defaultPriority)';
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty('type', 'SyncSettings'))
      ..add(DiagnosticsProperty('autoSyncEnabled', autoSyncEnabled))
      ..add(DiagnosticsProperty('syncIntervalMinutes', syncIntervalMinutes))
      ..add(DiagnosticsProperty('syncOnWifiOnly', syncOnWifiOnly))
      ..add(DiagnosticsProperty('compressData', compressData))
      ..add(DiagnosticsProperty('defaultPriority', defaultPriority));
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SyncSettingsImpl &&
            (identical(other.autoSyncEnabled, autoSyncEnabled) ||
                other.autoSyncEnabled == autoSyncEnabled) &&
            (identical(other.syncIntervalMinutes, syncIntervalMinutes) ||
                other.syncIntervalMinutes == syncIntervalMinutes) &&
            (identical(other.syncOnWifiOnly, syncOnWifiOnly) ||
                other.syncOnWifiOnly == syncOnWifiOnly) &&
            (identical(other.compressData, compressData) ||
                other.compressData == compressData) &&
            (identical(other.defaultPriority, defaultPriority) ||
                other.defaultPriority == defaultPriority));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, autoSyncEnabled,
      syncIntervalMinutes, syncOnWifiOnly, compressData, defaultPriority);

  /// Create a copy of SyncSettings
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SyncSettingsImplCopyWith<_$SyncSettingsImpl> get copyWith =>
      __$$SyncSettingsImplCopyWithImpl<_$SyncSettingsImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$SyncSettingsImplToJson(
      this,
    );
  }
}

abstract class _SyncSettings implements SyncSettings {
  const factory _SyncSettings(
      {final bool autoSyncEnabled,
      final int syncIntervalMinutes,
      final bool syncOnWifiOnly,
      final bool compressData,
      final SyncPriority defaultPriority}) = _$SyncSettingsImpl;

  factory _SyncSettings.fromJson(Map<String, dynamic> json) =
      _$SyncSettingsImpl.fromJson;

  @override
  bool get autoSyncEnabled;
  @override
  int get syncIntervalMinutes;
  @override
  bool get syncOnWifiOnly;
  @override
  bool get compressData;
  @override
  SyncPriority get defaultPriority;

  /// Create a copy of SyncSettings
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SyncSettingsImplCopyWith<_$SyncSettingsImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
