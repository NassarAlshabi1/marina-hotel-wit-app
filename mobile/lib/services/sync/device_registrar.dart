// ignore_for_file: sort_constructors_first

import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

import '../../utils/id.dart';
import '../../utils/time.dart';
import '../appwrite_config.dart';
import '../appwrite_logger.dart';
import '../appwrite_service.dart';
import '../sync_enums.dart';
import '../sync_locks.dart';

/// DeviceRegistrar — مسؤول عن تسجيل الجهاز في Appwrite Cloud
///
/// تم استخراجه من AppwriteSyncManager (God Class) لفصل منطق تسجيل
/// الأجهزة عن منطق المزامنة.
///
/// المسؤوليات:
/// - جمع معلومات الجهاز (اسم، موديل، إصدار OS)
/// - إنشاء أو تحديث سجل الجهاز في Appwrite
/// - إدارة معرف الجهاز (deviceId, localUuid, version)
class DeviceRegistrar {
  DeviceRegistrar({
    required this.appwriteService,
    required this.logger,
  });

  final AppwriteService appwriteService;
  final AppwriteLogger logger;

  // Device state
  String? _currentDeviceId;
  String? _deviceLocalUuid;
  int? _deviceVersion;
  int? _deviceCreatedAtEpoch;
  String? _fcmToken;

  // Getters
  String? get currentDeviceId => _currentDeviceId;
  String? get deviceLocalUuid => _deviceLocalUuid;
  int? get deviceVersion => _deviceVersion;
  int? get deviceCreatedAtEpoch => _deviceCreatedAtEpoch;

  /// تعيين FCM token لتسجيله مع الجهاز
  set fcmToken(String? token) => _fcmToken = token;

  /// تحديث معرف الجهاز
  void setDeviceId(String? id) {
    _currentDeviceId = id;
  }

  /// تحديث localUuid
  void setDeviceLocalUuid(String? uuid) {
    _deviceLocalUuid = uuid;
  }

  /// تحديث إصدار الجهاز
  void setDeviceVersion(int? version) {
    _deviceVersion = version;
  }

  /// تحديث تاريخ إنشاء الجهاز
  void setDeviceCreatedAtEpoch(int? epoch) {
    _deviceCreatedAtEpoch = epoch;
  }

  /// تسجيل الجهاز تلقائياً
  Future<String> registerDevice({
    String? deviceName,
    String? deviceModel,
    String? osVersion,
  }) async {
    try {
      String finalDeviceName = deviceName ?? 'Unknown Device';
      String finalDeviceModel = deviceModel ?? 'Unknown Model';
      String finalOsVersion = osVersion ?? 'Unknown OS';

      if (deviceName == null || deviceModel == null || osVersion == null) {
        final deviceInfo = DeviceInfoPlugin();

        if (Platform.isAndroid) {
          final androidInfo = await deviceInfo.androidInfo;
          finalDeviceName = androidInfo.model;
          finalDeviceModel = androidInfo.device;
          finalOsVersion = 'Android ${androidInfo.version.release}';
        } else if (Platform.isIOS) {
          final iosInfo = await deviceInfo.iosInfo;
          finalDeviceName = iosInfo.name;
          finalDeviceModel = iosInfo.model;
          finalOsVersion = '${iosInfo.systemName} ${iosInfo.systemVersion}';
        }
      }

      logger.info('Registering device: $finalDeviceName', tag: 'SYNC');
      final deviceType = _resolveDeviceType();
      final nowIso = Time.nowIso();
      final nowEpoch = Time.nowEpoch();

      _deviceLocalUuid ??=
          'marina_${finalDeviceModel.replaceAll(RegExp('[^a-zA-Z0-9_-]'), '_')}_${IdGen.shortId()}';
      _deviceCreatedAtEpoch ??= nowEpoch;

      if (_currentDeviceId != null) {
        await SyncLocks.appwriteSyncLock.synchronized(() async {
          final existingDoc = await appwriteService.getDocument(
            collectionId: AppwriteConfig.devicesCollectionId,
            documentId: _currentDeviceId!,
          );
          final currentRemoteVersion =
              _asInt(existingDoc.data['version']);
          if (_deviceVersion == null ||
              _deviceVersion! <= currentRemoteVersion) {
            _deviceVersion = currentRemoteVersion + 1;
          }

          await appwriteService.updateDocument(
            collectionId: AppwriteConfig.devicesCollectionId,
            documentId: _currentDeviceId!,
            data: {
              'deviceName': finalDeviceName,
              'deviceModel': finalDeviceModel,
              'osVersion': finalOsVersion,
              'deviceType': deviceType,
              'status': DeviceStatus.active.value,
              'localUuid': _deviceLocalUuid,
              'lastSeen': nowIso,
              'lastActive': nowEpoch,
              'createdAt': _deviceCreatedAtEpoch,
              'updatedAt': nowEpoch,
              'lastModified': nowEpoch,
              'version': _deviceVersion,
              'origin': 'mobile',
              'deviceId': _deviceLocalUuid,
              'isActive': true,
              if (_fcmToken != null) 'fcmToken': _fcmToken,
            },
          );
        });

        logger.info('Device updated: $_currentDeviceId', tag: 'SYNC');
        return _currentDeviceId!;
      } else {
        _deviceVersion = 1;
        _deviceCreatedAtEpoch = nowEpoch;

        final device = await appwriteService.createDevice({
          'deviceName': finalDeviceName,
          'deviceModel': finalDeviceModel,
          'osVersion': finalOsVersion,
          'deviceType': deviceType,
          'status': DeviceStatus.active.value,
          'localUuid': _deviceLocalUuid,
          'lastSeen': nowIso,
          'lastActive': nowEpoch,
          'createdAt': _deviceCreatedAtEpoch,
          'updatedAt': nowEpoch,
          'lastModified': nowEpoch,
          'version': _deviceVersion,
          'origin': 'mobile',
          'deviceId': _deviceLocalUuid,
          'isActive': true,
          if (_fcmToken != null) 'fcmToken': _fcmToken,
        });

        _currentDeviceId = device.$id;
        logger.info('Device registered: $_currentDeviceId', tag: 'SYNC');
        return _currentDeviceId!;
      }
    } catch (e, stackTrace) {
      logger.error(
        'Failed to register device',
        error: e,
        stackTrace: stackTrace,
        tag: 'SYNC',
      );
      rethrow;
    }
  }

  /// حل نوع الجهاز
  String _resolveDeviceType() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (kIsWeb) return 'web';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  /// تحميل إعدادات الجهاز من SharedPreferences
  Future<void> loadFromPrefs(Map<String, dynamic> prefs) async {
    _currentDeviceId = prefs['appwrite_device_id'] as String?;
    _deviceLocalUuid = prefs['appwrite_device_local_uuid'] as String?;
    _deviceVersion = prefs['appwrite_device_version'] as int?;
    _deviceCreatedAtEpoch = prefs['appwrite_device_created_at'] as int?;
  }

  /// حفظ إعدادات الجهاز لـ SharedPreferences
  Map<String, dynamic> toPrefsMap() {
    return {
      'appwrite_device_id': _currentDeviceId,
      'appwrite_device_local_uuid': _deviceLocalUuid,
      'appwrite_device_version': _deviceVersion,
      'appwrite_device_created_at': _deviceCreatedAtEpoch,
    };
  }
}
