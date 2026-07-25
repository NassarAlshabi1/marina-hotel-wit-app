// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sync_state.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_SyncSettings _$SyncSettingsFromJson(
  Map<String, dynamic> json,
) => _SyncSettings(
  autoSyncEnabled: json['auto_sync_enabled'] as bool? ?? true,
  syncIntervalMinutes: (json['sync_interval_minutes'] as num?)?.toInt() ?? 5,
  syncOnWifiOnly: json['sync_on_wifi_only'] as bool? ?? true,
  compressData: json['compress_data'] as bool? ?? true,
  defaultPriority:
      $enumDecodeNullable(_$SyncPriorityEnumMap, json['default_priority']) ??
      SyncPriority.normal,
);

const _$SyncPriorityEnumMap = {
  SyncPriority.low: 'low',
  SyncPriority.normal: 'normal',
  SyncPriority.high: 'high',
  SyncPriority.critical: 'critical',
};
