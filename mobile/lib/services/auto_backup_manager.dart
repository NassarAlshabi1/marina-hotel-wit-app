import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'google_drive_backup_service.dart';
import 'smart_sync_manager.dart';

/// مدير النسخ الاحتياطي التلقائي الذكي
/// يراقب التغييرات في قاعدة البيانات ويقوم بعمل نسخ احتياطية تلقائية
class AutoBackupManager {
  static const String _lastAutoBackupKey = 'last_auto_backup_timestamp';
  static const String _autoBackupEnabledKey = 'auto_backup_enabled';
  static const String _maxBackupCountKey = 'max_backup_count';
  static const String _backupRetentionDaysKey = 'backup_retention_days';
  static const String _instantSyncEnabledKey = 'instant_sync_enabled';
  
  static AutoBackupManager? _instance;
  static AutoBackupManager get instance => _instance ??= AutoBackupManager._();
  
  AutoBackupManager._();

  GoogleDriveBackupService? _backupService;
  Timer? _debounceTimer;
  Timer? _cleanupTimer;
  bool _isBackingUp = false;
  int _pendingChanges = 0;
  String? _deviceId;
  
  /// مدة انتظار قبل النسخ التلقائي (بالثواني) لتجميع التغييرات
  static const int _debounceSeconds = 15;
  
  /// مدة انتظار قبل المزامنة الفورية (بالثواني)
  static const int _instantSyncDebounceSeconds = 5;
  
  /// عدد النسخ الاحتياطية الافتراضي المراد الاحتفاظ به
  static const int _defaultMaxBackups = 10;
  
  /// عدد أيام الاحتفاظ بالنسخ الاحتياطية
  static const int _defaultRetentionDays = 14;

  /// تهيئة المدير مع خدمة النسخ الاحتياطي
  Future<void> initialize(GoogleDriveBackupService backupService) async {
    _backupService = backupService;
    await _initializeDeviceId();
    await _schedulePeriodicCleanup();
    debugPrint('🤖 مدير النسخ التلقائي: تم التهيئة بنجاح');
  }

  /// تهيئة معرف الجهاز للتمييز بين الأجهزة
  Future<void> _initializeDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString('device_id');
    
    if (_deviceId == null) {
      final deviceInfo = DeviceInfoPlugin();
      String deviceName = 'Unknown';
      String deviceModel = 'Unknown';
      
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        deviceName = androidInfo.device;
        deviceModel = androidInfo.model;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        deviceName = iosInfo.name;
        deviceModel = iosInfo.model;
      }
      
      _deviceId = 'marina_${deviceName}_${deviceModel}_${DateTime.now().millisecondsSinceEpoch}';
      await prefs.setString('device_id', _deviceId!);
      debugPrint('🆔 تم إنشاء معرف الجهاز: $_deviceId');
    }
  }

  /// تسجيل تغيير في قاعدة البيانات لبدء عد تنازلي للنسخ التلقائي
  Future<void> onDataChange(String tableName, String operation, {Map<String, dynamic>? recordData}) async {
    if (!await _isEnabled) return;
    
    _pendingChanges++;
    debugPrint('🔄 تغيير في $tableName ($operation) - تغييرات معلقة: $_pendingChanges');
    
    // إلغاء المؤقت السابق وبدء عد تنازلي جديد
    _debounceTimer?.cancel();
    _debounceTimer = Timer(Duration(seconds: _debounceSeconds), () {
      _performAutoBackup(
        reason: 'تغييرات تلقائية ($tableName: $operation)',
        changesCount: _pendingChanges,
      );
      _pendingChanges = 0;
    });
  }

  /// إجراء نسخة احتياطية تلقائية
  Future<void> _performAutoBackup({
    required String reason,
    int changesCount = 1,
  }) async {
    if (_isBackingUp || _backupService == null || !_backupService!.isSignedIn) {
      debugPrint('⏸️ نسخ تلقائي مؤجل: نسخ جارية $_isBackingUp، مسجل دخول ${_backupService?.isSignedIn}');
      return;
    }

    try {
      _isBackingUp = true;
      debugPrint('🚀 بدء النسخ التلقائي: $reason ($changesCount تغييرات)');

      // التحقق من آخر نسخة احتياطية لتجنب النسخ المتكررة
      final lastBackupTime = await _getLastAutoBackupTime();
      final now = DateTime.now();
      
      if (lastBackupTime != null && 
          now.difference(lastBackupTime).inMinutes < 5) {
        debugPrint('⏭️ تم تخطي النسخ التلقائي: نسخة حديثة موجودة (${now.difference(lastBackupTime).inMinutes} دقائق)');
        return;
      }

      // إنشاء وتصدير البيانات
      final backupData = await _backupService!.exportDatabaseToJson();
      
      // تحديث البيانات الوصفية لتمييز النسخة التلقائية
      final metadata = backupData['metadata'] as Map<String, dynamic>;
      metadata['backup_type'] = 'auto';
      metadata['trigger_reason'] = reason;
      metadata['changes_count'] = changesCount;
      metadata['device_info'] = '${Platform.operatingSystem} (تلقائي)';
      metadata['device_id'] = _deviceId; // معرف الجهاز للمزامنة الذكية
      metadata['created_by_device'] = _deviceId;
      
      // رفع النسخة الاحتياطية
      final fileId = await _backupService!.uploadBackup(backupData);
      
      // حفظ وقت آخر نسخة تلقائية
      await _setLastAutoBackupTime(now);
      
      debugPrint('✅ نسخ تلقائي مكتمل: $fileId ($changesCount تغييرات)');
      
      // تنظيف النسخ القديمة في الخلفية
      _cleanupOldBackups();
      
      // إشعار مدير المزامنة الذكية لمزامنة الأجهزة الأخرى
      await _notifySmartSync();
      
    } catch (e) {
      debugPrint('❌ فشل النسخ التلقائي: $e');
    } finally {
      _isBackingUp = false;
    }
  }

  /// حذف النسخ الاحتياطية القديمة حسب التاريخ والعدد
  Future<void> _cleanupOldBackups() async {
    if (_backupService == null || !_backupService!.isSignedIn) return;

    try {
      debugPrint('🧹 بدء تنظيف النسخ القديمة...');
      
      final backupFiles = await _backupService!.listBackupFiles();
      if (backupFiles.isEmpty) return;

      // ترتيب النسخ حسب التاريخ (الأحدث أولاً)
      backupFiles.sort((a, b) => b.createdTime.compareTo(a.createdTime));
      
      final maxBackups = await _getMaxBackupCount();
      final retentionDays = await _getRetentionDays();
      final cutoffDate = DateTime.now().subtract(Duration(days: retentionDays));
      
      List<DriveBackupFile> filesToDelete = [];
      
      // حذف النسخ الزائدة عن العدد المحدد
      if (backupFiles.length > maxBackups) {
        final excessFiles = backupFiles.sublist(maxBackups);
        filesToDelete.addAll(excessFiles);
        debugPrint('📊 نسخ زائدة عن العدد المحدد: ${excessFiles.length}');
      }
      
      // حذف النسخ الأقدم من فترة الاحتفاظ
      for (final file in backupFiles) {
        if (file.createdTime.isBefore(cutoffDate) && !filesToDelete.contains(file)) {
          filesToDelete.add(file);
        }
      }
      
      if (filesToDelete.isNotEmpty) {
        debugPrint('🗑️ حذف ${filesToDelete.length} نسخة احتياطية قديمة...');
        
        for (final file in filesToDelete) {
          try {
            await _backupService!.deleteBackupFile(file.fileId);
            debugPrint('✅ تم حذف: ${file.fileName} (${_formatDateTime(file.createdTime)})');
          } catch (e) {
            debugPrint('❌ فشل حذف ${file.fileName}: $e');
          }
        }
        
        debugPrint('🧹 اكتمل التنظيف: تم حذف ${filesToDelete.length} نسخة');
      } else {
        debugPrint('✨ لا توجد نسخ قديمة للحذف');
      }
      
    } catch (e) {
      debugPrint('❌ خطأ في تنظيف النسخ القديمة: $e');
    }
  }

  /// جدولة تنظيف دوري للنسخ القديمة
  Future<void> _schedulePeriodicCleanup() async {
    _cleanupTimer?.cancel();
    
    // تنظيف دوري كل 6 ساعات
    _cleanupTimer = Timer.periodic(Duration(hours: 6), (timer) {
      _cleanupOldBackups();
    });
    
    debugPrint('⏰ تم جدولة التنظيف الدوري كل 6 ساعات');
  }

  /// تنظيف فوري للنسخ القديمة (يمكن استدعاؤه يدوياً)
  Future<void> cleanupNow() async {
    debugPrint('🧹 تنظيف فوري مطلوب...');
    await _cleanupOldBackups();
  }

  /// إعدادات النسخ التلقائي
  
  Future<bool> get _isEnabled async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoBackupEnabledKey) ?? true; // مفعل افتراضياً
  }
  
  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoBackupEnabledKey, enabled);
    debugPrint('🔧 النسخ التلقائي: ${enabled ? 'مفعل' : 'معطل'}');
  }
  
  Future<int> _getMaxBackupCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_maxBackupCountKey) ?? _defaultMaxBackups;
  }
  
  Future<void> setMaxBackupCount(int count) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_maxBackupCountKey, count);
    debugPrint('🔧 عدد النسخ القصوى: $count');
  }
  
  Future<int> getMaxBackupCount() async {
    return await _getMaxBackupCount();
  }
  
  Future<int> _getRetentionDays() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_backupRetentionDaysKey) ?? _defaultRetentionDays;
  }
  
  Future<void> setRetentionDays(int days) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_backupRetentionDaysKey, days);
    debugPrint('🔧 فترة الاحتفاظ: $days يوماً');
  }

  Future<int> getRetentionDays() async {
    return await _getRetentionDays();
  }

  Future<DateTime?> _getLastAutoBackupTime() async {
    final prefs = await SharedPreferences.getInstance();
    final timeString = prefs.getString(_lastAutoBackupKey);
    return timeString != null ? DateTime.parse(timeString) : null;
  }
  
  Future<void> _setLastAutoBackupTime(DateTime time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastAutoBackupKey, time.toIso8601String());
  }

  /// معلومات النسخ التلقائي
  Future<Map<String, dynamic>> getStatus() async {
    final isEnabled = await _isEnabled;
    final lastBackup = await _getLastAutoBackupTime();
    final maxBackups = await _getMaxBackupCount();
    final retentionDays = await _getRetentionDays();
    
    return {
      'enabled': isEnabled,
      'is_backing_up': _isBackingUp,
      'pending_changes': _pendingChanges,
      'last_auto_backup': lastBackup?.toIso8601String(),
      'max_backups': maxBackups,
      'retention_days': retentionDays,
      'signed_in': _backupService?.isSignedIn ?? false,
    };
  }

  /// إيقاف المدير وتنظيف الموارد
  void dispose() {
    _debounceTimer?.cancel();
    _cleanupTimer?.cancel();
    debugPrint('🛑 مدير النسخ التلقائي: تم التنظيف');
  }

  /// تنسيق التاريخ والوقت للعرض
  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  /// إشعار مدير المزامنة الذكية بوجود نسخة جديدة
  Future<void> _notifySmartSync() async {
    try {
      final smartSync = SmartSyncManager.instance;
      if (await smartSync.isEnabled()) {
        debugPrint('🔔 إشعار مدير المزامنة الذكية بالنسخة الجديدة...');
      }
    } catch (e) {
      debugPrint('⚠️ خطأ في إشعار مدير المزامنة: $e');
    }
  }

  /// تفعيل/تعطيل المزامنة الفورية
  Future<void> setInstantSyncEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_instantSyncEnabledKey, enabled);
    debugPrint('🔧 المزامنة الفورية: ${enabled ? 'مفعلة' : 'معطلة'}');
  }

  /// التحقق من تفعيل المزامنة الفورية
  Future<bool> isInstantSyncEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_instantSyncEnabledKey) ?? true;
  }

  /// مزامنة فورية عند الطلب
  Future<void> syncNow() async {
    if (_backupService == null || !_backupService!.isSignedIn) {
      debugPrint('⚠️ لا يمكن المزامنة: غير مسجل الدخول في Google Drive');
      return;
    }
    
    debugPrint('🚀 بدء المزامنة الفورية...');
    await _performAutoBackup(
      reason: 'مزامنة فورية يدوية',
      changesCount: _pendingChanges > 0 ? _pendingChanges : 1,
    );
    _pendingChanges = 0;
  }

  /// الحصول على عدد التغييرات المعلقة
  int get pendingChangesCount => _pendingChanges;

  /// التحقق من حالة النسخ الجارية
  bool get isBackingUp => _isBackingUp;

  /// الحصول على معرف الجهاز
  String? get deviceId => _deviceId;
}