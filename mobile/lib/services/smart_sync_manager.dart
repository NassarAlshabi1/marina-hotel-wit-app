import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'google_drive_backup_service.dart';
import 'local_db.dart';
import 'providers.dart';
import 'sync_performance_optimizer.dart';
import 'data_usage_manager.dart';

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
  Timer? _syncCheckTimer;
  Timer? _periodicSyncTimer;
  bool _isSyncing = false;
  bool _isEnabled = false;
  String? _deviceId;
  
  static const String _prefsEnabledKey = 'smart_sync_enabled';
  static const String _prefsIntervalKey = 'smart_sync_interval';
  static const String _prefsLastSyncKey = 'smart_sync_last_check';
  static const String _prefsDeviceIdKey = 'smart_sync_device_id';
  static const String _prefsLastRemoteTimestampKey = 'smart_sync_last_remote_timestamp';
  static const String _prefsConflictResolutionKey = 'smart_sync_conflict_resolution';
  
  static const int _defaultSyncIntervalMinutes = 5;
  static const int _periodicFullSyncHours = 24;
  
  /// تهيئة مدير المزامنة
  Future<void> initialize(GoogleDriveBackupService backupService) async {
    _backupService = backupService;
    await _initializeDeviceId();
    await _loadSettings();
    
    // تهيئة مُحسِّن الأداء
    await SyncPerformanceOptimizer.instance.initialize();
    
    if (_isEnabled && _backupService?.isSignedIn == true) {
      await _startSyncMonitoring();
    }
    
    debugPrint('🔄 مدير المزامنة الذكي: تم التهيئة بنجاح');
  }

  /// توليد معرف فريد للجهاز
  Future<void> _initializeDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString(_prefsDeviceIdKey);
    
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
      await prefs.setString(_prefsDeviceIdKey, _deviceId!);
      debugPrint('🆔 تم إنشاء معرف الجهاز: $_deviceId');
    } else {
      debugPrint('🆔 معرف الجهاز: $_deviceId');
    }
  }

  /// تحميل إعدادات المزامنة
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _isEnabled = prefs.getBool(_prefsEnabledKey) ?? false;
  }

  /// بدء مراقبة المزامنة التلقائية مع تحسين الأداء
  Future<void> _startSyncMonitoring() async {
    if (_syncCheckTimer?.isActive == true) return;
    
    final baseInterval = await getSyncInterval();
    final optimizer = SyncPerformanceOptimizer.instance;
    
    // حساب الفترة المُحسَّنة
    final optimizedInterval = await optimizer.isAdaptiveIntervalEnabled()
      ? await optimizer.calculateOptimizedInterval(baseInterval)
      : baseInterval;
    
    // مراقبة دورية للتحقق من النسخ الجديدة مع تحسين الأداء
    _syncCheckTimer = Timer.periodic(
      Duration(minutes: optimizedInterval),
      (timer) => _performOptimizedSyncCheck(),
    );
    
    // مزامنة كاملة دورية
    _periodicSyncTimer = Timer.periodic(
      Duration(hours: _periodicFullSyncHours),
      (timer) => _performFullSync(),
    );
    
    // تحقق فوري عند البدء (إذا لم تكن هناك قيود)
    if (!await optimizer.shouldSkipSync()) {
      _performOptimizedSyncCheck();
    }
    
    debugPrint('⏰ بدء مراقبة المزامنة المُحسَّنة كل $optimizedInterval دقائق');
  }

  /// فحص مزامنة محسن للأداء
  Future<void> _performOptimizedSyncCheck() async {
    final optimizer = SyncPerformanceOptimizer.instance;
    final dataManager = DataUsageManager.instance;
    
    // تحقق من قيود الأداء
    if (await optimizer.shouldSkipSync()) {
      debugPrint('⏸️ تم تخطي المزامنة لتوفير الطاقة');
      return;
    }
    
    // تحقق من حد البيانات
    if (await dataManager.isLimitExceeded()) {
      debugPrint('📊 تم تجاوز حد البيانات اليومي - تخطي المزامنة');
      return;
    }
    
    try {
      await _performSyncCheck();
      
      // تسجيل نجاح المزامنة
      optimizer.recordSyncSuccess();
      
    } catch (e) {
      // تسجيل فشل المزامنة
      optimizer.recordSyncFailure();
      rethrow;
    }
  }

  /// إيقاف مراقبة المزامنة
  void _stopSyncMonitoring() {
    _syncCheckTimer?.cancel();
    _periodicSyncTimer?.cancel();
    _syncCheckTimer = null;
    _periodicSyncTimer = null;
    debugPrint('⏸️ تم إيقاف مراقبة المزامنة');
  }

  /// التحقق من وجود نسخ احتياطية جديدة
  Future<void> _performSyncCheck() async {
    if (_isSyncing || _backupService == null || !_backupService!.isSignedIn) {
      return;
    }

    try {
      _isSyncing = true;
      debugPrint('🔍 فحص وجود نسخ احتياطية جديدة...');

      // جلب قائمة النسخ الاحتياطية من Google Drive
      final backupFiles = await _backupService!.listBackupFiles();
      if (backupFiles.isEmpty) {
        debugPrint('📭 لا توجد نسخ احتياطية في Google Drive');
        return;
      }

      // ترتيب حسب التاريخ (الأحدث أولاً)
      backupFiles.sort((a, b) => b.createdTime.compareTo(a.createdTime));
      final latestBackup = backupFiles.first;

      // التحقق من آخر timestamp محفوظ محلياً
      final lastRemoteTimestamp = await _getLastRemoteTimestamp();
      
      if (lastRemoteTimestamp == null || 
          latestBackup.createdTime.isAfter(lastRemoteTimestamp)) {
        
        // التحقق من أن النسخة ليست من نفس الجهاز
        final backupDeviceId = latestBackup.appProperties['device_id'];
        if (backupDeviceId != _deviceId) {
          debugPrint('🆕 تم العثور على نسخة احتياطية جديدة من جهاز آخر');
          await _handleNewBackupFound(latestBackup);
        } else {
          debugPrint('📱 النسخة الأحدث من نفس هذا الجهاز، لا حاجة للمزامنة');
        }
      } else {
        debugPrint('✅ لا توجد نسخ احتياطية جديدة');
      }

      // تحديث timestamp آخر فحص
      await _updateLastSyncTime();
      
    } catch (e) {
      debugPrint('❌ خطأ في فحص المزامنة: $e');
    } finally {
      _isSyncing = false;
    }
  }

  /// معالجة اكتشاف نسخة احتياطية جديدة مع تحسين الأداء
  Future<void> _handleNewBackupFound(DriveBackupFile newBackup) async {
    try {
      debugPrint('🔄 بدء مزامنة النسخة الجديدة...');

      // تحميل بيانات النسخة الاحتياطية
      final backupData = await _backupService!.downloadBackup(newBackup.fileId);
      
      // تسجيل استهلاك البيانات
      final backupSize = newBackup.size ?? 0;
      if (backupSize > 0) {
        await DataUsageManager.instance.recordDataUsage(backupSize);
      }
      
      // تحديد استراتيجية حل التضارب
      final conflictResolution = await getConflictResolution();
      
      // تنفيذ المزامنة
      await _performDataSync(backupData, newBackup, conflictResolution);
      
      // حفظ timestamp النسخة الجديدة
      await _setLastRemoteTimestamp(newBackup.createdTime);
      
      // إشعار النجاح
      await _notifySuccessfulSync(newBackup);
      
      // تسجيل نجاح المزامنة لتحسين الأداء
      SyncPerformanceOptimizer.instance.recordSyncSuccess();
      
      debugPrint('✅ تمت المزامنة بنجاح');
      
    } catch (e) {
      debugPrint('❌ خطأ في مزامنة البيانات: $e');
      
      // تسجيل فشل المزامنة
      SyncPerformanceOptimizer.instance.recordSyncFailure();
      
      await _notifySyncError();
    }
  }

  /// تنفيذ مزامنة البيانات
  Future<void> _performDataSync(
    Map<String, dynamic> backupData,
    DriveBackupFile sourceBackup,
    ConflictResolution conflictResolution,
  ) async {
    final db = getDatabase();
    
    // إنشاء نسخة احتياطية محلية قبل المزامنة
    final localBackupData = await _backupService!.exportDatabaseToJson();
    
    try {
      debugPrint('📥 بدء استيراد البيانات الجديدة...');
      
      // مقارنة البيانات وتحديد التضارب
      final conflicts = await _detectDataConflicts(localBackupData, backupData);
      
      if (conflicts.isNotEmpty) {
        debugPrint('⚠️ تم العثور على ${conflicts.length} تضارب في البيانات');
        
        switch (conflictResolution) {
          case ConflictResolution.newerWins:
            await _resolveConflictsNewerWins(conflicts, backupData);
            break;
          case ConflictResolution.manualResolve:
            await _requestManualConflictResolution(conflicts);
            return; // لا نكمل المزامنة التلقائية
          case ConflictResolution.devicePriority:
            await _resolveConflictsDevicePriority(conflicts, backupData);
            break;
        }
      }
      
      // استيراد البيانات الجديدة
      await _mergeBackupData(backupData);
      
      debugPrint('✅ تم دمج البيانات بنجاح');
      
    } catch (e) {
      debugPrint('❌ خطأ في دمج البيانات، استعادة النسخة المحلية...');
      // استعادة البيانات المحلية في حالة الخطأ
      await _restoreLocalBackup(localBackupData);
      rethrow;
    }
  }

  /// اكتشاف تضارب البيانات
  Future<List<DataConflict>> _detectDataConflicts(
    Map<String, dynamic> localData,
    Map<String, dynamic> remoteData,
  ) async {
    final conflicts = <DataConflict>[];
    
    // مقارنة البيانات في الجداول المختلفة
    final tables = ['bookings', 'payments', 'expenses', 'rooms'];
    
    for (final tableName in tables) {
      final localRecords = (localData[tableName] as List<dynamic>?) ?? [];
      final remoteRecords = (remoteData[tableName] as List<dynamic>?) ?? [];
      
      // تحويل إلى Map للسهولة
      final localMap = <String, dynamic>{};
      final remoteMap = <String, dynamic>{};
      
      for (final record in localRecords) {
        if (record is Map<String, dynamic> && record['local_uuid'] != null) {
          localMap[record['local_uuid']] = record;
        }
      }
      
      for (final record in remoteRecords) {
        if (record is Map<String, dynamic> && record['local_uuid'] != null) {
          remoteMap[record['local_uuid']] = record;
        }
      }
      
      // البحث عن التضارب
      for (final uuid in localMap.keys) {
        if (remoteMap.containsKey(uuid)) {
          final localRecord = localMap[uuid];
          final remoteRecord = remoteMap[uuid];
          
          // مقارنة timestamps
          final localTimestamp = localRecord['last_modified'] as int?;
          final remoteTimestamp = remoteRecord['last_modified'] as int?;
          
          if (localTimestamp != null && remoteTimestamp != null) {
            final localTime = DateTime.fromMillisecondsSinceEpoch(localTimestamp);
            final remoteTime = DateTime.fromMillisecondsSinceEpoch(remoteTimestamp);
            
            // فرق أكثر من 30 ثانية يعتبر تضارب
            if ((localTime.difference(remoteTime).inSeconds).abs() > 30) {
              conflicts.add(DataConflict(
                tableName: tableName,
                recordId: uuid,
                localRecord: localRecord,
                remoteRecord: remoteRecord,
                localTimestamp: localTime,
                remoteTimestamp: remoteTime,
              ));
            }
          }
        }
      }
    }
    
    return conflicts;
  }

  /// حل التضارب: الأحدث يفوز
  Future<void> _resolveConflictsNewerWins(
    List<DataConflict> conflicts,
    Map<String, dynamic> backupData,
  ) async {
    debugPrint('🏆 حل التضارب: الأحدث يفوز');
    
    for (final conflict in conflicts) {
      if (conflict.remoteTimestamp.isAfter(conflict.localTimestamp)) {
        debugPrint('📥 استبدال ${conflict.tableName}/${conflict.recordId} بالنسخة الأحدث');
        // النسخة البعيدة أحدث، سيتم استيرادها
      } else {
        debugPrint('📱 الاحتفاظ بالنسخة المحلية لـ ${conflict.tableName}/${conflict.recordId}');
        // إزالة السجل من بيانات النسخ الاحتياطي ليتم تجاهله
        await _removeRecordFromBackupData(backupData, conflict.tableName, conflict.recordId);
      }
    }
  }

  /// دمج بيانات النسخ الاحتياطي
  Future<void> _mergeBackupData(Map<String, dynamic> backupData) async {
    // استخدام خدمة النسخ الاحتياطي الموجودة
    await _backupService!.restoreFromBackup(backupData);
  }

  /// إزالة سجل من بيانات النسخ الاحتياطي
  Future<void> _removeRecordFromBackupData(
    Map<String, dynamic> backupData,
    String tableName,
    String recordId,
  ) async {
    if (backupData.containsKey(tableName)) {
      final records = backupData[tableName] as List<dynamic>;
      records.removeWhere((record) => 
        record is Map<String, dynamic> && record['local_uuid'] == recordId);
    }
  }

  /// تنفيذ مزامنة كاملة
  Future<void> _performFullSync() async {
    debugPrint('🔄 بدء المزامنة الكاملة الدورية...');
    await _performSyncCheck();
  }

  /// إشعار نجاح المزامنة
  Future<void> _notifySuccessfulSync(DriveBackupFile backup) async {
    // يمكن إضافة إشعار للمستخدم هنا
    debugPrint('🎉 تمت مزامنة البيانات من ${backup.appProperties['device_id'] ?? 'جهاز آخر'}');
    debugPrint('📅 تاريخ النسخة: ${backup.createdTime}');
    
    final recordsCount = backup.appProperties['records_count'] ?? 'غير محدد';
    debugPrint('📊 عدد السجلات: $recordsCount');
  }

  /// إشعار خطأ في المزامنة
  Future<void> _notifySyncError() async {
    debugPrint('❌ فشلت المزامنة التلقائية');
  }

  /// الإعدادات والتحكم

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsEnabledKey, enabled);
    _isEnabled = enabled;
    
    if (enabled && _backupService?.isSignedIn == true) {
      await _startSyncMonitoring();
    } else {
      _stopSyncMonitoring();
    }
    
    debugPrint('🔧 المزامنة التلقائية: ${enabled ? "مُفعلة" : "معطلة"}');
  }

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsEnabledKey) ?? false;
  }

  Future<void> setSyncInterval(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsIntervalKey, minutes);
    
    // إعادة تشغيل المراقبة بالفترة الجديدة
    if (_isEnabled) {
      _stopSyncMonitoring();
      await _startSyncMonitoring();
    }
    
    debugPrint('⏰ فترة المزامنة: $minutes دقائق');
  }

  Future<int> getSyncInterval() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_prefsIntervalKey) ?? _defaultSyncIntervalMinutes;
  }

  Future<void> setConflictResolution(ConflictResolution resolution) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsConflictResolutionKey, resolution.name);
    debugPrint('🤝 استراتيجية حل التضارب: ${resolution.name}');
  }

  Future<ConflictResolution> getConflictResolution() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_prefsConflictResolutionKey) ?? 'newerWins';
    return ConflictResolution.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ConflictResolution.newerWins,
    );
  }

  /// مساعدات للـ timestamps

  Future<DateTime?> _getLastRemoteTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getString(_prefsLastRemoteTimestampKey);
    return timestamp != null ? DateTime.parse(timestamp) : null;
  }

  Future<void> _setLastRemoteTimestamp(DateTime timestamp) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsLastRemoteTimestampKey, timestamp.toIso8601String());
  }

  Future<void> _updateLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsLastSyncKey, DateTime.now().toIso8601String());
  }

  Future<DateTime?> getLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getString(_prefsLastSyncKey);
    return timestamp != null ? DateTime.parse(timestamp) : null;
  }

  /// معلومات الحالة

  Future<Map<String, dynamic>> getStatus() async {
    final isEnabled = await this.isEnabled();
    final syncInterval = await getSyncInterval();
    final lastSync = await getLastSyncTime();
    final conflictResolution = await getConflictResolution();

    return {
      'enabled': isEnabled,
      'is_syncing': _isSyncing,
      'sync_interval_minutes': syncInterval,
      'last_sync_check': lastSync?.toIso8601String(),
      'device_id': _deviceId,
      'conflict_resolution': conflictResolution.name,
      'signed_in': _backupService?.isSignedIn ?? false,
      'monitoring_active': _syncCheckTimer?.isActive ?? false,
    };
  }

  /// مزامنة يدوية فورية
  Future<void> forceSyncNow() async {
    if (_isSyncing) {
      debugPrint('⏸️ المزامنة جارية بالفعل...');
      return;
    }
    
    debugPrint('🚀 بدء المزامنة اليدوية الفورية...');
    await _performSyncCheck();
  }

  /// تنظيف الموارد
  void dispose() {
    _stopSyncMonitoring();
    debugPrint('🛑 مدير المزامنة الذكي: تم التنظيف');
  }

  /// معالجة طلب حل التضارب اليدوي (placeholder)
  Future<void> _requestManualConflictResolution(List<DataConflict> conflicts) async {
    debugPrint('🤔 يتطلب تدخل المستخدم لحل ${conflicts.length} تضارب');
    // يمكن إضافة واجهة لحل التضارب يدوياً
  }

  /// حل التضارب حسب أولوية الجهاز (placeholder)
  Future<void> _resolveConflictsDevicePriority(
    List<DataConflict> conflicts,
    Map<String, dynamic> backupData,
  ) async {
    debugPrint('📱 حل التضارب حسب أولوية الجهاز');
    // يمكن تطبيق منطق أولوية الأجهزة هنا
  }

  /// استعادة النسخة المحلية (في حالة فشل المزامنة)
  Future<void> _restoreLocalBackup(Map<String, dynamic> localData) async {
    debugPrint('🔄 استعادة النسخة المحلية...');
    await _backupService!.restoreFromBackup(localData);
  }
}

/// نموذج تضارب البيانات
class DataConflict {
  final String tableName;
  final String recordId;
  final Map<String, dynamic> localRecord;
  final Map<String, dynamic> remoteRecord;
  final DateTime localTimestamp;
  final DateTime remoteTimestamp;

  DataConflict({
    required this.tableName,
    required this.recordId,
    required this.localRecord,
    required this.remoteRecord,
    required this.localTimestamp,
    required this.remoteTimestamp,
  });
}