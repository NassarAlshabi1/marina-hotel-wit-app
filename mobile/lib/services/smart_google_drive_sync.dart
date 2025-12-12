import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'google_drive_backup_service.dart';
import 'google_drive_delta_sync.dart';
import 'local_db.dart';
import '../utils/debug_logs.dart';
import 'sync_performance_optimizer.dart';
import 'data_usage_manager.dart';
import 'sync_locks.dart';

/// مدير مزامنة Google Drive الذكي المبسط
/// 
/// الاستراتيجية:
/// 1. Delta Sync للتحديثات الصغيرة (كل 1-2 دقيقة)
/// 2. Full Backup مرة واحدة يومياً
/// 3. Pull عند فتح التطبيق
/// 4. Debouncing للتغييرات المتتالية
class SmartGoogleDriveSync {
  SmartGoogleDriveSync._();
  static final instance = SmartGoogleDriveSync._();

  GoogleDriveBackupService? _driveService;
  GoogleDriveDeltaSync? _deltaSync;
  
  Timer? _debounceTimer;
  Timer? _periodicSyncTimer;
  Timer? _dailyFullBackupTimer;
  
  bool _isSyncing = false;
  bool _isEnabled = false;
  bool _hasPendingChanges = false;
  int _pendingChangesCount = 0;
  
  static const String _prefsEnabledKey = 'smart_gd_sync_enabled';
  static const String _prefsLastFullBackupKey = 'smart_gd_last_full_backup';
  static const String _prefsLastDeltaSyncKey = 'smart_gd_last_delta_sync';
  
  // الإعدادات
  static const Duration _debounceDuration = Duration(seconds: 5); // تجميع التغييرات لمدة 5 ثواني
  static const Duration _periodicSyncInterval = Duration(minutes: 2); // فحص دوري كل دقيقتين
  static const Duration _dailyFullBackupInterval = Duration(hours: 24); // نسخة كاملة يومياً
  
  void _log(String message) {
    DebugLogs.add('SmartGDSync', message);
    debugPrint('[SmartGDSync] $message');
  }

  /// تهيئة الخدمة
  Future<void> initialize({
    required GoogleDriveBackupService driveService,
    required AppDatabase database,
  }) async {
    _driveService = driveService;
    _deltaSync = GoogleDriveDeltaSync.instance;
    await _deltaSync!.initialize(driveService, database);
    
    await _loadSettings();
    
    if (_isEnabled && driveService.isSignedIn) {
      await start();
    }
    
    _log('✅ تم تهيئة المزامنة الذكية');
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _isEnabled = prefs.getBool(_prefsEnabledKey) ?? false;
  }

  /// بدء المزامنة التلقائية
  Future<void> start() async {
    if (!_isEnabled || _driveService?.isSignedIn != true) {
      _log('⚠️ المزامنة غير مُفعلة أو غير مسجل الدخول');
      return;
    }
    
    // 1. سحب التحديثات فوراً عند البدء
    await pullRemoteChanges();
    
    // 2. جدولة الفحص الدوري
    _startPeriodicSync();
    
    // 3. جدولة النسخ الاحتياطي اليومي
    _scheduleDailyFullBackup();
    
    _log('🚀 بدء المزامنة التلقائية');
  }

  /// إيقاف المزامنة
  void stop() {
    _debounceTimer?.cancel();
    _periodicSyncTimer?.cancel();
    _dailyFullBackupTimer?.cancel();
    _hasPendingChanges = false;
    _pendingChangesCount = 0;
    _log('⏸️ تم إيقاف المزامنة التلقائية');
  }

  /// تفعيل/تعطيل المزامنة
  Future<void> setEnabled(bool enabled) async {
    _isEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsEnabledKey, enabled);
    
    if (enabled) {
      await start();
    } else {
      stop();
    }
  }

  /// تسجيل تغيير محلي (يُستدعى من DAOs)
  void notifyLocalChange({String? entity, int count = 1}) {
    if (!_isEnabled) return;
    
    _hasPendingChanges = true;
    _pendingChangesCount += count;
    
    // إلغاء المؤقت السابق وبدء واحد جديد (Debouncing)
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, () {
      if (_hasPendingChanges) {
        _log('📤 رفع $_pendingChangesCount تغيير بعد debounce...');
        pushLocalChanges();
      }
    });
  }

  /// رفع التغييرات المحلية (Delta Sync)
  Future<bool> pushLocalChanges() async {
    final canStart = await SyncLocks.smartSyncLock.synchronized(() async {
      if (_isSyncing || !_isEnabled || _driveService?.isSignedIn != true) {
        return false;
      }
      _isSyncing = true;
      return true;
    });
    
    if (!canStart) return false;
    
    try {
      _log('📤 بدء رفع التغييرات...');
      
      // استخدام Delta Sync للتحديثات الصغيرة
      final result = await _deltaSync!.pushDeltaChanges();
      
      if (result.success) {
        _hasPendingChanges = false;
        _pendingChangesCount = 0;
        
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_prefsLastDeltaSyncKey, DateTime.now().millisecondsSinceEpoch);
        
        _log('✅ تم رفع التغييرات: ${result.changesCount} تغيير');
        
        // تحديث استهلاك البيانات
        if (result.changesCount > 0) {
          await DataUsageManager.instance.recordDataUsage(
            (result.changesCount * 500) / 1024 / 1024,
          );
        }
        
        return true;
      } else {
        _log('⚠️ فشل رفع التغييرات: ${result.message}');
        return false;
      }
    } catch (e) {
      _log('❌ خطأ في رفع التغييرات: $e');
      return false;
    } finally {
      await SyncLocks.smartSyncLock.synchronized(() async {
        _isSyncing = false;
      });
    }
  }

  /// سحب التغييرات من الأجهزة الأخرى
  Future<bool> pullRemoteChanges() async {
    final canStart = await SyncLocks.smartSyncLock.synchronized(() async {
      if (_isSyncing || !_isEnabled || _driveService?.isSignedIn != true) {
        return false;
      }
      _isSyncing = true;
      return true;
    });
    
    if (!canStart) return false;
    
    try {
      _log('📥 بدء سحب التحديثات...');
      
      // سحب Delta changes من الأجهزة الأخرى
      final result = await _deltaSync!.pullDeltaChanges();
      
      if (result.success) {
        _log('✅ تم سحب التحديثات: ${result.changesCount} تغيير');
        
        if (result.changesCount > 0) {
          await DataUsageManager.instance.recordDataUsage(
            (result.changesCount * 500) / 1024 / 1024,
          );
        }
        
        return true;
      } else {
        _log('⚠️ لا توجد تحديثات جديدة');
        return false;
      }
    } catch (e) {
      _log('❌ خطأ في سحب التحديثات: $e');
      return false;
    } finally {
      await SyncLocks.smartSyncLock.synchronized(() async {
        _isSyncing = false;
      });
    }
  }

  /// عمل نسخة احتياطية كاملة
  Future<bool> createFullBackup() async {
    final canStart = await SyncLocks.smartSyncLock.synchronized(() async {
      if (_isSyncing || _driveService?.isSignedIn != true) {
        return false;
      }
      _isSyncing = true;
      return true;
    });
    
    if (!canStart) return false;
    
    try {
      _log('💾 بدء النسخ الاحتياطي الكامل...');
      
      final backupData = await _driveService!.exportDatabaseToJson();
      
      // إضافة metadata للتمييز
      backupData['metadata'] = {
        ...backupData['metadata'],
        'backup_type': 'full',
        'sync_type': 'scheduled',
      };
      
      final fileId = await _driveService!.uploadBackup(backupData, isSync: false);
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefsLastFullBackupKey, DateTime.now().millisecondsSinceEpoch);
      
      _log('✅ تم إنشاء النسخة الاحتياطية الكاملة: $fileId');
      return true;
    } catch (e) {
      _log('❌ خطأ في النسخ الاحتياطي: $e');
      return false;
    } finally {
      await SyncLocks.smartSyncLock.synchronized(() async {
        _isSyncing = false;
      });
    }
  }

  /// بدء الفحص الدوري
  void _startPeriodicSync() {
    _periodicSyncTimer?.cancel();
    
    _periodicSyncTimer = Timer.periodic(_periodicSyncInterval, (timer) async {
      if (!_isSyncing) {
        _log('🔄 فحص دوري للتحديثات...');
        
        // سحب التحديثات
        await pullRemoteChanges();
        
        // رفع التغييرات المعلقة (إن وجدت)
        if (_hasPendingChanges) {
          await pushLocalChanges();
        }
      }
    });
  }

  /// جدولة النسخ الاحتياطي اليومي
  void _scheduleDailyFullBackup() async {
    final prefs = await SharedPreferences.getInstance();
    final lastBackup = prefs.getInt(_prefsLastFullBackupKey);
    
    Duration initialDelay;
    
    if (lastBackup == null) {
      // لم يتم عمل نسخة من قبل - انتظر ساعة
      initialDelay = const Duration(hours: 1);
    } else {
      final lastBackupDate = DateTime.fromMillisecondsSinceEpoch(lastBackup);
      final now = DateTime.now();
      final timeSinceLastBackup = now.difference(lastBackupDate);
      
      if (timeSinceLastBackup >= _dailyFullBackupInterval) {
        // حان وقت النسخة - افعلها الآن
        initialDelay = const Duration(seconds: 30);
      } else {
        // احسب المدة المتبقية
        initialDelay = _dailyFullBackupInterval - timeSinceLastBackup;
      }
    }
    
    _log('⏰ جدولة النسخ الاحتياطي الكامل بعد: ${initialDelay.inHours} ساعة');
    
    _dailyFullBackupTimer?.cancel();
    _dailyFullBackupTimer = Timer(initialDelay, () async {
      await createFullBackup();
      
      // جدولة التكرار اليومي
      _dailyFullBackupTimer = Timer.periodic(_dailyFullBackupInterval, (timer) async {
        await createFullBackup();
      });
    });
  }

  /// معلومات الحالة
  Map<String, dynamic> getStatus() {
    return {
      'enabled': _isEnabled,
      'syncing': _isSyncing,
      'signed_in': _driveService?.isSignedIn ?? false,
      'pending_changes': _hasPendingChanges,
      'pending_count': _pendingChangesCount,
      'device_id': _deltaSync?.deviceId,
    };
  }

  /// تنظيف الموارد
  void dispose() {
    stop();
  }
}
