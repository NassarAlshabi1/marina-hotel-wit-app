// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sync_state.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_SyncSettings _$SyncSettingsFromJson(Map<String, dynamic> json) =>
    _SyncSettings(
      autoSyncEnabled: json['autoSyncEnabled'] as bool? ?? true,
      syncIntervalMinutes: (json['syncIntervalMinutes'] as num?)?.toInt() ?? 5,
      syncOnWifiOnly: json['syncOnWifiOnly'] as bool? ?? true,
      compressData: json['compressData'] as bool? ?? true,
      defaultPriority:
          $enumDecodeNullable(_$SyncPriorityEnumMap, json['defaultPriority']) ??
          SyncPriority.normal,
    );

Map<String, dynamic> _$SyncSettingsToJson(_SyncSettings instance) =>
    <String, dynamic>{
      'autoSyncEnabled': instance.autoSyncEnabled,
      'syncIntervalMinutes': instance.syncIntervalMinutes,
      'syncOnWifiOnly': instance.syncOnWifiOnly,
      'compressData': instance.compressData,
      'defaultPriority': _$SyncPriorityEnumMap[instance.defaultPriority]!,
    };

const _$SyncPriorityEnumMap = {
  SyncPriority.low: 'low',
  SyncPriority.normal: 'normal',
  SyncPriority.high: 'high',
  SyncPriority.critical: 'critical',
};
