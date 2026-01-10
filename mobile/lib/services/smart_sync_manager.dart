import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/debug_logs.dart';
import 'google_drive_backup_service.dart';
import 'google_drive_unified_sync_coordinator.dart';
import 'sync_notification_manager.dart';

// REFACTORED: This class now delegates all sync logic to GoogleDriveUnifiedSyncCoordinator
// and acts as a high-level configuration wrapper for device-specific settings.

/// استراتيجيات حل التضارب
enum ConflictResolution {
  newerWins, // الأحدث يفوز (افتراضي)
  manualResolve, // طلب تدخل المستخدم
  devicePriority, // أولوية لجهاز معين
}


/// مدير المزامنة التلقائية الذكي بين الأجهزة المتعددة
class SmartSyncManager {
  static SmartSyncManager? _instance;
  static SmartSyncManager get instance => _instance ??= SmartSyncManager._();
  
  SmartSyncManager._();

  GoogleDriveBackupService? _backupService;
  bool _isLoggedIn = false;
  String? _deviceId;
  
  String? get deviceId => _deviceId;
  bool get isDriveSignedIn => _backupService?.isSignedIn ?? false;
  
  void _log(String message) {
    DebugLogs.add('SmartSync', message);
    debugPrint(message);
  }
  
  static const String _prefsEnabledKey = 'smart_sync_enabled';
  static const String _prefsIntervalKey = 'smart_sync_interval';
  static const String _prefsDeviceIdKey = 'smart_sync_device_id';
  static const String _prefsLastRemoteTimestampKey = 'smart_sync_last_remote_timestamp';
  static const String _prefsConflictResolutionKey = 'smart_sync_conflict_resolution';
  
  static const int _defaultSyncIntervalMinutes = 2; // تغيير من 1 إلى 2 لتقليل الحمل
  
  /// تهيئة مدير المزامنة
  Future<void> initialize(GoogleDriveBackupService backupService) async {
    _backupService = backupService;
    await _initializeDeviceId();
    await _loadSettings();
    _isLoggedIn = backupService.isSignedIn;

    _log('🔄 مدير المزامنة الذكي: تم تهيئة الغلاف بنجاح (Logic moved to Coordinator)');
  }

  /// توليد معرف فريد للجهاز تلقائياً
  Future<void> _initializeDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString(_prefsDeviceIdKey);
    
    if (_deviceId == null) {
      final deviceInfo = DeviceInfoPlugin();
      String deviceIdentifier = 'unknown';
      
      try {
        if (Platform.isAndroid) {
          final androidInfo = await deviceInfo.androidInfo;
          deviceIdentifier = androidInfo.id;
        } else if (Platform.isIOS) {
          final iosInfo = await deviceInfo.iosInfo;
          deviceIdentifier = iosInfo.identifierForVendor ?? 'ios-${DateTime.now().millisecondsSinceEpoch}';
        }
      } catch (e) {
        deviceIdentifier = 'device-${DateTime.now().millisecondsSinceEpoch}';
      }
      
      _deviceId = deviceIdentifier;
      await prefs.setString(_prefsDeviceIdKey, _deviceId!);
      _log('🆔 تم إنشاء معرف الجهاز الفريد تلقائياً: $_deviceId');
    } else {
      _log('🆔 معرف الجهاز: $_deviceId');
    }
  }

  /// تحميل إعدادات المزامنة
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_prefsEnabledKey)) {
      await prefs.setBool(_prefsEnabledKey, true);
    }
    
    // Sync settings with Coordinator
    final enabled = prefs.getBool(_prefsEnabledKey) ?? true;
    final interval = prefs.getInt(_prefsIntervalKey) ?? _defaultSyncIntervalMinutes;
    
    // Configure coordinator
    final coordinator = GoogleDriveUnifiedSyncCoordinator.instance;
    await coordinator.setPullEnabled(enabled);
    await coordinator.setPushEnabled(enabled);
    await coordinator.setPullInterval(interval);
  }

  /// استدعاء هذه الدالة عند تغير حالة تسجيل الدخول في Google Drive
  Future<void> onGoogleDriveSignInChanged(bool isSignedIn) async {
    _log('🔔 تغيرت حالة تسجيل الدخول Google Drive: $isSignedIn');
    _isLoggedIn = isSignedIn;
    
    // تفويض الحدث إلى المنسق الموحد
    await GoogleDriveUnifiedSyncCoordinator.instance.onSignInChanged(isSignedIn);
  }

  /// الإعدادات والتحكم

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsEnabledKey, enabled);
    
    // تفويض التحكم للمنسق الموحد
    await GoogleDriveUnifiedSyncCoordinator.instance.setPullEnabled(enabled);
    await GoogleDriveUnifiedSyncCoordinator.instance.setPushEnabled(enabled);
    
    _log('🔧 المزامنة التلقائية: ${enabled ? "مُفعلة" : "معطلة"}');
  }

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsEnabledKey) ?? true;
  }

  Future<void> setSyncInterval(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsIntervalKey, minutes);
    
    // تفويض التحكم للمنسق الموحد
    await GoogleDriveUnifiedSyncCoordinator.instance.setPullInterval(minutes);
    
    _log('⏰ فترة المزامنة: $minutes دقائق');
  }

  Future<int> getSyncInterval() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_prefsIntervalKey) ?? _defaultSyncIntervalMinutes;
  }

  Future<void> setConflictResolution(ConflictResolution resolution) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsConflictResolutionKey, resolution.name);
    _log('🤝 استراتيجية حل التضارب: ${resolution.name}');
  }

  Future<ConflictResolution> getConflictResolution() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_prefsConflictResolutionKey) ?? 'newerWins';
    return ConflictResolution.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ConflictResolution.newerWins,
    );
  }

  /// مزامنة يدوية فورية
  Future<void> forceSyncNow() async {
     _log('🚀 طلب مزامنة يدوية فورية...');
    // تفويض للمنسق الموحد
    await GoogleDriveUnifiedSyncCoordinator.instance.performSync(
      trigger: SyncTrigger.manual,
      mode: SyncMode.smart,
    );
  }

  /// تفويض PUSH للمنسق الموحد
  Future<bool> pushLocalChanges() async {
    if (GoogleDriveUnifiedSyncCoordinator.instance.isSyncing) {
       _log('⏸️ المزامنة جارية بالفعل - تخطي الرفع المباشر');
       return false; 
    }
    
    // استخدام trigger: localChange ليعمل بنفس المنطق القديم
    final result = await GoogleDriveUnifiedSyncCoordinator.instance.performSync(
      trigger: SyncTrigger.localChange,
      mode: SyncMode.smart,
    );
    
    return result.success;
  }

  /// تفويض PULL للمنسق الموحد
  Future<bool> pullRemoteChanges() async {
    if (GoogleDriveUnifiedSyncCoordinator.instance.isSyncing) {
       _log('⏸️ المزامنة جارية بالفعل - تخطي السحب المباشر');
       return false; 
    }

    final result = await GoogleDriveUnifiedSyncCoordinator.instance.performSync(
      trigger: SyncTrigger.manual,
      mode: SyncMode.smart, // Smart mode handles pull logic internally
    );
    
    // Check if actull pulled something
    return result.success && (result.pulledChanges ?? 0) > 0;
  }
  
  /// تنظيف الموارد
  void dispose() {
    // No resources to dispose here, coordinator handles it
    _log('🛑 مدير المزامنة الذكي: تم التنظيف');
  }

  /// إشعار نجاح المزامنة (يستخدمه Coordinator أحياناً)
  Future<void> _notifySuccessfulSync(DriveBackupFile backup) async { // Kept private if needed or expose if Coordinator calls it
     // Logic optionally moved to Coordinator or delegated
  }

  /// معلومات الحالة
  Future<Map<String, dynamic>> getStatus() async {
    final isEnabled = await this.isEnabled();
    final syncInterval = await getSyncInterval();
    final conflictResolution = await getConflictResolution();
    
    // Get real status from coordinator
    final coordStatus = await GoogleDriveUnifiedSyncCoordinator.instance.getStatus();

    return {
      'enabled': isEnabled,
      'is_syncing': coordStatus['is_syncing'],
      'sync_interval_minutes': syncInterval,
      'last_sync_check': coordStatus['last_pull'], // Map coordinator metrics
      'device_id': _deviceId,
      'conflict_resolution': conflictResolution.name,
      'signed_in': _isLoggedIn,
    };
  }
}
