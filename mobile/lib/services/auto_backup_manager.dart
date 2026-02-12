import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'google_drive_backup_service.dart';
import 'google_drive_delta_sync.dart';
import 'appwrite_delta_sync.dart';
import 'appwrite_service.dart';
import 'smart_sync_manager.dart';
import 'local_db.dart';

/// مدير النسخ الاحتياطي التلقائي الذكي
/// يراقب التغييرات في قاعدة البيانات ويقوم بعمل نسخ احتياطية تلقائية
enum BackupMode { fullBackup, deltaSync, both }

class AutoBackupManager {
  static const String _lastAutoBackupKey = 'last_auto_backup_timestamp';
  static const String _autoBackupEnabledKey = 'auto_backup_enabled';
  static const String _maxBackupCountKey = 'max_backup_count';
  static const String _backupRetentionDaysKey = 'backup_retention_days';
  static const String _instantSyncEnabledKey = 'instant_sync_enabled';
  static const String _deltaSyncEnabledKey = 'delta_sync_enabled';
  static const String _backupModeKey = 'backup_mode';
  static const String _appwriteDeltaSyncEnabledKey =
      'appwrite_delta_sync_enabled';
  static const String _googleDriveDeltaSyncEnabledKey =
      'google_drive_delta_sync_enabled';

  static AutoBackupManager? _instance;
  static AutoBackupManager get instance => _instance ??= AutoBackupManager._();

  AutoBackupManager._();

  GoogleDriveBackupService? _backupService;
  GoogleDriveDeltaSync? _googleDriveDeltaSync;
  AppwriteDeltaSync? _appwriteDeltaSync;
  // ignore: unused_field
  AppwriteService? _appwriteService;
  // ignore: unused_field
  AppDatabase? _database;
  Timer? _debounceTimer;
  Timer? _deltaSyncDebounceTimer;
  Timer? _deltaSyncTimer;
  Timer? _cleanupTimer;
  bool _isBackingUp = false;
  bool _isDeltaSyncing = false;
  int _pendingChanges = 0;
  String? _deviceId;
  BackupMode _currentMode = BackupMode.both;

  /// مدة انتظار قبل النسخ التلقائي (بالثواني) - قللناها للاستجابة السريعة
  static const int _debounceSeconds = 5;

  /// مدة انتظار قبل المزامنة الفورية (بالثواني)
  static const int _instantSyncDebounceSeconds = 2;

  /// عدد النسخ الاحتياطية الافتراضي المراد الاحتفاظ به
  static const int _defaultMaxBackups = 10;

  /// عدد أيام الاحتفاظ بالنسخ الاحتياطية
  static const int _defaultRetentionDays = 14;

  /// تهيئة المدير مع خدمة النسخ الاحتياطي
  Future<void> initialize(
    GoogleDriveBackupService backupService, {
    AppwriteService? appwriteService,
    AppDatabase? database,
  }) async {
    _backupService = backupService;
    _appwriteService = appwriteService;
    _database = database;
    await _initializeDeviceId();
    await _loadBackupMode();
    await _schedulePeriodicCleanup();

    if (database != null) {
      _googleDriveDeltaSync = GoogleDriveDeltaSync.instance;
      await _googleDriveDeltaSync!.initialize(backupService, database);

      if (appwriteService != null) {
        _appwriteDeltaSync = AppwriteDeltaSync.instance;
        await _appwriteDeltaSync!.initialize(appwriteService, database);
      }

      await _startDeltaSyncTimer();
    }

    debugPrint(
      '🤖 مدير النسخ التلقائي: تم التهيئة بنجاح (الوضع: ${_currentMode.name})',
    );
  }

  Future<void> _loadBackupMode() async {
    final prefs = await SharedPreferences.getInstance();
    final modeIndex = prefs.getInt(_backupModeKey) ?? BackupMode.both.index;
    _currentMode = BackupMode.values[modeIndex];
  }

  Future<void> _startDeltaSyncTimer() async {
    _deltaSyncTimer?.cancel();
    final deltaSyncEnabled = await isDeltaSyncEnabled();
    if (!deltaSyncEnabled) return;

    _deltaSyncTimer = Timer.periodic(const Duration(minutes: 5), (timer) async {
      await performDeltaSync();
    });
    debugPrint('⏰ تم جدولة المزامنة التفاضلية كل 5 دقائق');
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

      _deviceId =
          'marina_${deviceName}_${deviceModel}_${DateTime.now().millisecondsSinceEpoch}';
      await prefs.setString('device_id', _deviceId!);
      debugPrint('🆔 تم إنشاء معرف الجهاز: $_deviceId');
    }
  }

  /// تسجيل تغيير في قاعدة البيانات لبدء عد تنازلي للنسخ التلقائي
  Future<void> onDataChange(
    String tableName,
    String operation, {
    Map<String, dynamic>? recordData,
  }) async {
    if (!await _isEnabled) return;

    _pendingChanges++;
    debugPrint(
      '🔄 تغيير في $tableName ($operation) - تغييرات معلقة: $_pendingChanges',
    );

    if (_currentMode == BackupMode.deltaSync ||
        _currentMode == BackupMode.both) {
      _deltaSyncDebounceTimer?.cancel();
      _deltaSyncDebounceTimer = Timer(
        const Duration(seconds: _instantSyncDebounceSeconds),
        () async {
          await performDeltaSync();
          if (_currentMode == BackupMode.deltaSync) {
            _pendingChanges = 0;
          }
        },
      );
    }

    if (_currentMode == BackupMode.fullBackup ||
        _currentMode == BackupMode.both) {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(Duration(seconds: _debounceSeconds), () {
        _performAutoBackup(
          reason: 'تغييرات تلقائية ($tableName: $operation)',
          changesCount: _pendingChanges,
        );
        _pendingChanges = 0;
      });
    }
  }

  /// إجراء نسخة احتياطية تلقائية
  Future<void> _performAutoBackup({
    required String reason,
    int changesCount = 1,
  }) async {
    if (_isBackingUp || _backupService == null || !_backupService!.isSignedIn) {
      debugPrint(
        '⏸️ نسخ تلقائي مؤجل: نسخ جارية $_isBackingUp، مسجل دخول ${_backupService?.isSignedIn}',
      );
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
        debugPrint(
          '⏭️ تم تخطي النسخ التلقائي: نسخة حديثة موجودة (${now.difference(lastBackupTime).inMinutes} دقائق)',
        );
        return;
      }

      // إنشاء وتصدير البيانات
      final backupData = await _backupService!.exportDatabaseToJson();

      // تحديث البيانات الوصفية لتمييز النسخة التلقائية
      final existingMetadata = backupData['metadata'];
      Map<String, dynamic> metadata;
      if (existingMetadata is Map<String, dynamic>) {
        metadata = existingMetadata;
      } else if (existingMetadata is Map) {
        metadata = Map<String, dynamic>.from(existingMetadata);
        backupData['metadata'] = metadata;
      } else {
        metadata = <String, dynamic>{};
        backupData['metadata'] = metadata;
      }
      metadata['backup_type'] = 'auto';
      metadata['trigger_reason'] = reason;
      metadata['changes_count'] = changesCount;
      metadata['device_info'] = '${Platform.operatingSystem} (تلقائي)';
      metadata['device_id'] = _deviceId;
      metadata['created_by_device'] = _deviceId;

      // رفع النسخة الاحتياطية كملف تلقائي
      final fileId = await _backupService!.uploadBackup(
        backupData,
        isSync: true,
      );

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

      final filesToDelete = <DriveBackupFile>[];

      // حذف النسخ الزائدة عن العدد المحدد
      if (backupFiles.length > maxBackups) {
        final excessFiles = backupFiles.sublist(maxBackups);
        filesToDelete.addAll(excessFiles);
        debugPrint('📊 نسخ زائدة عن العدد المحدد: ${excessFiles.length}');
      }

      // حذف النسخ الأقدم من فترة الاحتفاظ
      for (final file in backupFiles) {
        if (file.createdTime.isBefore(cutoffDate) &&
            !filesToDelete.contains(file)) {
          filesToDelete.add(file);
        }
      }

      if (filesToDelete.isNotEmpty) {
        debugPrint('🗑️ حذف ${filesToDelete.length} نسخة احتياطية قديمة...');

        for (final file in filesToDelete) {
          try {
            await _backupService!.deleteBackupFile(file.fileId);
            debugPrint(
              '✅ تم حذف: ${file.fileName} (${_formatDateTime(file.createdTime)})',
            );
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
    _deltaSyncDebounceTimer?.cancel();
    _deltaSyncTimer?.cancel();
    _cleanupTimer?.cancel();
    debugPrint('🛑 مدير النسخ التلقائي: تم التنظيف');
  }

  /// التحقق من حالة المزامنة التفاضلية
  bool get isDeltaSyncing => _isDeltaSyncing;

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
        await smartSync.onLocalBackupUploaded();
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
    debugPrint('🚀 بدء المزامنة الفورية...');

    if (_currentMode == BackupMode.deltaSync ||
        _currentMode == BackupMode.both) {
      await performDeltaSync();
    }

    if (_currentMode == BackupMode.fullBackup ||
        _currentMode == BackupMode.both) {
      if (_backupService != null && _backupService!.isSignedIn) {
        await _performAutoBackup(
          reason: 'مزامنة فورية يدوية',
          changesCount: _pendingChanges > 0 ? _pendingChanges : 1,
        );
      }
    }

    _pendingChanges = 0;
  }

  /// تنفيذ المزامنة التفاضلية
  Future<Map<String, dynamic>> performDeltaSync() async {
    if (_isDeltaSyncing) {
      return {'success': false, 'message': 'المزامنة التفاضلية جارية بالفعل'};
    }

    _isDeltaSyncing = true;
    final results = <String, dynamic>{
      'google_drive': null,
      'appwrite': null,
      'success': true,
    };

    try {
      debugPrint('🔄 بدء المزامنة التفاضلية...');

      if (await isGoogleDriveDeltaSyncEnabled() &&
          _googleDriveDeltaSync != null) {
        try {
          final pushResult = await _googleDriveDeltaSync!.pushDeltaChanges();
          final pullResult = await _googleDriveDeltaSync!.pullDeltaChanges();
          results['google_drive'] = {
            'push': {
              'success': pushResult.success,
              'count': pushResult.changesCount,
            },
            'pull': {
              'success': pullResult.success,
              'count': pullResult.changesCount,
            },
          };
          if (!pushResult.success || !pullResult.success) {
            results['success'] = false;
          }
          debugPrint(
            '✅ Google Drive Delta: رفع ${pushResult.changesCount}، سحب ${pullResult.changesCount}',
          );
        } catch (e) {
          results['google_drive'] = {'error': e.toString()};
          results['success'] = false;
          debugPrint('❌ خطأ في مزامنة Google Drive التفاضلية: $e');
        }
      }

      if (await isAppwriteDeltaSyncEnabled() && _appwriteDeltaSync != null) {
        try {
          final pushResult = await _appwriteDeltaSync!.pushDeltaChanges();
          final pullResult = await _appwriteDeltaSync!.pullDeltaChanges();
          results['appwrite'] = {
            'push': {
              'success': pushResult.success,
              'count': pushResult.pushedCount,
            },
            'pull': {
              'success': pullResult.success,
              'count': pullResult.pulledCount,
            },
          };
          if (!pushResult.success || !pullResult.success) {
            results['success'] = false;
          }
          debugPrint(
            '✅ Appwrite Delta: رفع ${pushResult.pushedCount}، سحب ${pullResult.pulledCount}',
          );
        } catch (e) {
          results['appwrite'] = {'error': e.toString()};
          results['success'] = false;
          debugPrint('❌ خطأ في مزامنة Appwrite التفاضلية: $e');
        }
      }

      debugPrint('✅ اكتملت المزامنة التفاضلية');
    } catch (e) {
      results['success'] = false;
      results['error'] = e.toString();
      debugPrint('❌ خطأ في المزامنة التفاضلية: $e');
    } finally {
      _isDeltaSyncing = false;
    }

    return results;
  }

  /// إعدادات المزامنة التفاضلية
  Future<bool> isDeltaSyncEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_deltaSyncEnabledKey) ?? false;
  }

  Future<void> setDeltaSyncEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_deltaSyncEnabledKey, enabled);
    if (enabled) {
      await _startDeltaSyncTimer();
    } else {
      _deltaSyncTimer?.cancel();
    }
    debugPrint('🔧 المزامنة التفاضلية: ${enabled ? 'مفعلة' : 'معطلة'}');
  }

  Future<bool> isGoogleDriveDeltaSyncEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_googleDriveDeltaSyncEnabledKey) ?? true;
  }

  Future<void> setGoogleDriveDeltaSyncEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_googleDriveDeltaSyncEnabledKey, enabled);
    debugPrint(
      '🔧 مزامنة Google Drive التفاضلية: ${enabled ? 'مفعلة' : 'معطلة'}',
    );
  }

  Future<bool> isAppwriteDeltaSyncEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_appwriteDeltaSyncEnabledKey) ?? true;
  }

  Future<void> setAppwriteDeltaSyncEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_appwriteDeltaSyncEnabledKey, enabled);
    debugPrint('🔧 مزامنة Appwrite التفاضلية: ${enabled ? 'مفعلة' : 'معطلة'}');
  }

  /// تعيين وضع النسخ الاحتياطي
  Future<void> setBackupMode(BackupMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_backupModeKey, mode.index);
    _currentMode = mode;
    debugPrint('🔧 وضع النسخ الاحتياطي: ${mode.name}');
  }

  BackupMode get currentBackupMode => _currentMode;

  /// الحصول على حالة المزامنة التفاضلية
  Future<Map<String, dynamic>> getDeltaSyncStatus() async {
    return {
      'delta_sync_enabled': await isDeltaSyncEnabled(),
      'google_drive_enabled': await isGoogleDriveDeltaSyncEnabled(),
      'appwrite_enabled': await isAppwriteDeltaSyncEnabled(),
      'is_syncing': _isDeltaSyncing,
      'backup_mode': _currentMode.name,
      'google_drive_status': _googleDriveDeltaSync != null
          ? await _googleDriveDeltaSync!.getStatus()
          : null,
      'appwrite_status': _appwriteDeltaSync != null
          ? await _appwriteDeltaSync!.getStatus()
          : null,
    };
  }

  /// الحصول على عدد التغييرات المعلقة
  int get pendingChangesCount => _pendingChanges;

  /// التحقق من حالة النسخ الجارية
  bool get isBackingUp => _isBackingUp;

  /// الحصول على معرف الجهاز
  String? get deviceId => _deviceId;
}
