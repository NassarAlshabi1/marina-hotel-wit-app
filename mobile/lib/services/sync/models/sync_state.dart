import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:flutter/foundation.dart';

part 'sync_state.freezed.dart';

/// حالات المزامنة الممكنة
enum SyncStatus {
  idle,
  syncing,
  error,
  disabled,
  offline,
}

/// أولوية المزامنة
enum SyncPriority {
  low,
  normal,
  high,
  critical,
}

/// نموذج حالة المزامنة باستخدام Freezed
@freezed
class SyncState with _$SyncState {
  const factory SyncState({
    required SyncStatus status,
    @Default(0) int progress,
    String? message,
    DateTime? lastSyncTime,
    @Default(0) int pendingChanges,
    String? error,
  }) = _SyncState;

  const SyncState._();

  factory SyncState.idle() => const SyncState(status: SyncStatus.idle);
  
  factory SyncState.syncing({
    int progress = 0,
    String? message,
  }) => SyncState(
    status: SyncStatus.syncing,
    progress: progress,
    message: message,
  );
  
  factory SyncState.error(String error) => SyncState(
    status: SyncStatus.error,
    error: error,
  );
  
  factory SyncState.offline() => const SyncState(status: SyncStatus.offline);
  
  factory SyncState.disabled() => const SyncState(status: SyncStatus.disabled);

  bool get isIdle => status == SyncStatus.idle;
  bool get isSyncing => status == SyncStatus.syncing;
  bool get hasError => status == SyncStatus.error;
  bool get isOffline => status == SyncStatus.offline;
  bool get isDisabled => status == SyncStatus.disabled;
}

/// إعدادات المزامنة
@freezed
class SyncSettings with _$SyncSettings {
  const factory SyncSettings({
    @Default(true) bool autoSyncEnabled,
    @Default(5) int syncIntervalMinutes,
    @Default(true) bool syncOnWifiOnly,
    @Default(true) bool compressData,
    @Default(SyncPriority.normal) SyncPriority defaultPriority,
  }) = _SyncSettings;

  factory SyncSettings.fromJson(Map<String, dynamic> json) =>
      _$SyncSettingsFromJson(json);
}
