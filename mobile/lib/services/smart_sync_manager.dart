import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/debug_logs.dart';
import 'daos/outbox_dao.dart';
import 'data_usage_manager.dart';
import 'google_drive_backup_service.dart';
import 'google_drive_delta_sync.dart';
import 'local_db.dart';
import 'sync_notification_manager.dart';
import 'sync_performance_optimizer.dart';

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
  
  String? get deviceId => _deviceId;
  
  void _log(String message) {
    DebugLogs.add('SmartSync', message);
    debugPrint(message);
  }
  
  static const String _prefsEnabledKey = 'smart_sync_enabled';
  static const String _prefsIntervalKey = 'smart_sync_interval';
  static const String _prefsLastSyncKey = 'smart_sync_last_check';
  static const String _prefsDeviceIdKey = 'smart_sync_device_id';
  static const String _prefsLastRemoteTimestampKey = 'smart_sync_last_remote_timestamp';
  static const String _prefsConflictResolutionKey = 'smart_sync_conflict_resolution';
  
  static const int _defaultSyncIntervalMinutes = 2; // تغيير من 1 إلى 2 لتقليل الحمل
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
    
    _log('🔄 مدير المزامنة الذكي: تم التهيئة بنجاح');
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
    final stored = prefs.getBool(_prefsEnabledKey);
    if (stored == null) {
      _isEnabled = true;
      await prefs.setBool(_prefsEnabledKey, true);
    } else {
      _isEnabled = stored;
    }
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
    
    _log('⏰ بدء مراقبة المزامنة المُحسَّنة كل $optimizedInterval دقائق');
  }

  /// فحص مزامنة محسن للأداء
  Future<void> _performOptimizedSyncCheck() async {
    final optimizer = SyncPerformanceOptimizer.instance;
    final dataManager = DataUsageManager.instance;
    
    // تحقق من قيود الأداء
    if (await optimizer.shouldSkipSync()) {
      _log('⏸️ تم تخطي المزامنة لتوفير الطاقة');
      return;
    }
    
    // تحقق من حد البيانات
    if (await dataManager.isLimitExceeded()) {
      _log('📊 تم تجاوز حد البيانات اليومي - تخطي المزامنة');
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
    _log('⏸️ تم إيقاف مراقبة المزامنة');
  }

  /// استدعاء هذه الدالة عند تغير حالة تسجيل الدخول في Google Drive
  Future<void> onGoogleDriveSignInChanged(bool isSignedIn) async {
    _log('🔔 تغيرت حالة تسجيل الدخول Google Drive: $isSignedIn');
    
    if (isSignedIn && _isEnabled) {
      _log('✅ بدء المراقبة بعد تسجيل الدخول...');
      await _startSyncMonitoring();
    } else {
      _log('⏹️ إيقاف المراقبة بعد تسجيل الخروج...');
      _stopSyncMonitoring();
    }
  }

  /// التحقق من وجود نسخ احتياطية جديدة
  Future<void> _performSyncCheck() async {
    if (_isSyncing || _backupService == null || !_backupService!.isSignedIn) {
      return;
    }

    try {
      _isSyncing = true;
      _log('🔍 فحص وجود نسخ احتياطية جديدة...');

      // جلب قائمة النسخ الاحتياطية من Google Drive
      final backupFiles = await _backupService!.listBackupFiles();
      if (backupFiles.isEmpty) {
        _log('📭 لا توجد نسخ احتياطية في Google Drive');
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
          _log('🆕 تم العثور على نسخة احتياطية جديدة من جهاز آخر');
          await _handleNewBackupFound(latestBackup);
        } else {
          _log('📱 النسخة الأحدث من نفس هذا الجهاز، لا حاجة للمزامنة');
        }
      } else {
        _log('✅ لا توجد نسخ احتياطية جديدة');
      }

      // تحديث timestamp آخر فحص
      await _updateLastSyncTime();
      
    } catch (e) {
      _log('❌ خطأ في فحص المزامنة: $e');
    } finally {
      _isSyncing = false;
    }
  }

  /// معالجة اكتشاف نسخة احتياطية جديدة مع تحسين الأداء
  Future<void> _handleNewBackupFound(DriveBackupFile newBackup) async {
    try {
      _log('🔄 بدء مزامنة النسخة الجديدة...');

      // تحميل بيانات النسخة الاحتياطية
      final backupData = await _backupService!.downloadBackup(newBackup.fileId);
      
      // تسجيل استهلاك البيانات
      final backupSize = newBackup.size ?? 0;
      if (backupSize > 0) {
        await DataUsageManager.instance.recordDataUsage(backupSize.toDouble());
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
      
      _log('✅ تمت المزامنة بنجاح');
      
    } catch (e) {
      _log('❌ خطأ في مزامنة البيانات: $e');
      
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
    // إنشاء نسخة احتياطية محلية قبل المزامنة
    final localBackupData = await _backupService!.exportDatabaseToJson();
    
    try {
      _log('📥 بدء استيراد البيانات الجديدة...');
      
      // مقارنة البيانات وتحديد التضارب
      final conflicts = await _detectDataConflicts(localBackupData, backupData);
      
      if (conflicts.isNotEmpty) {
        _log('⚠️ تم العثور على ${conflicts.length} تضارب في البيانات');
        
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
      
      // التحقق من وجود ملاحظات جديدة وإرسال إشعار
      await _checkForNewNotesAndNotify(backupData);

      // استيراد البيانات الجديدة
      await _mergeBackupData(backupData);
      
      _log('✅ تم دمج البيانات بنجاح');
      
    } catch (e) {
      _log('❌ خطأ في دمج البيانات، استعادة النسخة المحلية...');
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
    _log('🏆 حل التضارب: الأحدث يفوز');
    
    for (final conflict in conflicts) {
      if (conflict.remoteTimestamp.isAfter(conflict.localTimestamp)) {
        _log('📥 استبدال ${conflict.tableName}/${conflict.recordId} بالنسخة الأحدث');
        // النسخة البعيدة أحدث، سيتم استيرادها
      } else {
        _log('📱 الاحتفاظ بالنسخة المحلية لـ ${conflict.tableName}/${conflict.recordId}');
        // إزالة السجل من بيانات النسخ الاحتياطي ليتم تجاهله
        await _removeRecordFromBackupData(backupData, conflict.tableName, conflict.recordId);
      }
    }
  }

  /// التحقق من وجود ملاحظات إدارية جديدة وإرسال إشعارات
  Future<void> _checkForNewNotesAndNotify(Map<String, dynamic> backupData) async {
    try {
      // التحقق من وجود ملاحظات جديدة في ShiftNotes
      if (backupData.containsKey('shift_notes')) {
        final notes = backupData['shift_notes'] as List<dynamic>;
        if (notes.isEmpty) return;

        // جلب آخر وقت مزامنة لمعرفة ما هو الجديد
        final lastSync = await getLastSyncTime();
        if (lastSync == null) return; // أول مزامنة، لا داعي للإزعاج

        int newNotesCount = 0;
        String lastNoteTitle = '';
        String noteCreator = 'الإدارة';

        for (final noteData in notes) {
          if (noteData is Map<String, dynamic>) {
            // التحقق من تاريخ الملاحظة
            String? createdAtStr = noteData['created_at'];
            // في بعض الأحيان يكون التاريخ بتنسيق مختلف، نحاول التحليل
            if (createdAtStr != null) {
               try {
                 final createdAt = DateTime.parse(createdAtStr);
                 // إذا كانت الملاحظة أحدث من آخر مزامنة وليست من هذا الجهاز
                 // ملاحظة: نحن نفترض أن createdBy يحمل اسم المستخدم أو معرفه
                 // لكن هنا سنعتمد على الوقت بشكل أساسي
                 if (createdAt.isAfter(lastSync)) {
                   newNotesCount++;
                   lastNoteTitle = noteData['title'] ?? 'بدون عنوان';
                   noteCreator = noteData['created_by'] ?? 'مسؤول';
                 }
               } catch (e) {
                 _log('⚠️ تعذر تحليل تاريخ الملاحظة: $createdAtStr - $e');
               }
            }
          }
        }

        if (newNotesCount > 0) {
          final message = newNotesCount == 1 
              ? 'ملاحظة جديدة: $lastNoteTitle' 
              : '$newNotesCount ملاحظات إدارية جديدة';
          
          _log('🔔 🔔 تنبيه: $message');
          
          await SyncNotificationManager.instance.showSystemNotification(
            title: 'تنبيه إداري جديد 📝',
            body: message,
          );
        }
      }
    } catch (e) {
      _log('⚠️ خطأ في فحص الملاحظات الجديدة: $e');
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
    _log('🔄 بدء المزامنة الكاملة الدورية...');
    await _performSyncCheck();
  }

  /// إشعار نجاح المزامنة
  Future<void> _notifySuccessfulSync(DriveBackupFile backup) async {
    final deviceId = backup.appProperties['device_id'] ?? 'جهاز آخر';
    _log('🎉 تمت مزامنة البيانات من $deviceId');
    _log('📅 تاريخ النسخة: ${backup.createdTime}');
    
    final recordsCount = backup.appProperties['records_count'] ?? 'غير محدد';
    _log('📊 عدد السجلات: $recordsCount');
    
    // إرسال إشعار للمستخدم بوصول تغييرات جديدة
    try {
      await SyncNotificationManager.instance.showSystemNotification(
        title: '🔄 تحديث جديد من $deviceId',
        body: 'تم استلام تغييرات جديدة وتحديث البيانات',
      );
    } catch (e) {
      _log('⚠️ فشل إرسال الإشعار: $e');
    }
  }

  /// إشعار خطأ في المزامنة
  Future<void> _notifySyncError() async {
    _log('❌ فشلت المزامنة التلقائية');
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
    
    _log('🔧 المزامنة التلقائية: ${enabled ? "مُفعلة" : "معطلة"}');
  }

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_prefsEnabledKey)) {
      await prefs.setBool(_prefsEnabledKey, true);
      return true;
    }
    return prefs.getBool(_prefsEnabledKey) ?? true;
  }

  Future<void> setSyncInterval(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsIntervalKey, minutes);
    
    // إعادة تشغيل المراقبة بالفترة الجديدة
    if (_isEnabled) {
      _stopSyncMonitoring();
      await _startSyncMonitoring();
    }
    
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

  Future<void> _updateLastPushTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('smart_sync_last_push_ts', DateTime.now().millisecondsSinceEpoch);
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

  /// إشعار بأن هذا الجهاز قام برفع نسخة احتياطية جديدة
  Future<void> onLocalBackupUploaded() async {
    await _updateLastSyncTime();
    _log('📤 تم تسجيل رفع نسخة احتياطية من هذا الجهاز');
  }

  /// التحقق من وجود تغييرات محلية لم ترفع
  Future<bool> hasLocalChanges() async {
    try {
      // الطريقة الأكثر دقة: التحقق من وجود عناصر في outbox
      final db = DatabaseManager.instance;
      final outboxDao = OutboxDao(db);
      final outboxCount = await outboxDao.count();
      
      if (outboxCount > 0) {
        _log('📝 توجد تغييرات محلية في Outbox ($outboxCount)');
        return true;
      }
      
      _log('✅ لا توجد تغييرات محلية معلقة');
      return false;
    } catch (e) {
      _log('❌ خطأ في فحص التغييرات المحلية: $e');
      return false;
    }
  }

  /// مزامنة يدوية فورية
  Future<void> forceSyncNow() async {
    if (_isSyncing) {
      _log('⏸️ المزامنة جارية بالفعل...');
      return;
    }
    
    _log('🚀 بدء المزامنة اليدوية الفورية...');
    
    await pushLocalChanges();
    
    await pullRemoteChanges();
  }

  /// رفع التغييرات المحلية إلى Google Drive فوراً
  Future<bool> pushLocalChanges() async {
    // انتظر إذا كانت المزامنة جارية بدلاً من التخطي
    int retries = 0;
    while (_isSyncing && retries < 10) {
      await Future.delayed(const Duration(milliseconds: 500));
      retries++;
    }
    
    if (_isSyncing) {
      _log('⚠️ تخطي الرفع - المزامنة جارية لفترة طويلة');
      return false;
    }

    if (_backupService == null || !_backupService!.isSignedIn) {
      _log('⚠️ لا يمكن رفع التغييرات: غير مسجل الدخول في Google Drive');
      return false;
    }

    try {
      _isSyncing = true;
      _log('📤 رفع التغييرات المحلية إلى Google Drive...');
      
      // محاولة استخدام Delta Sync أولاً (أسرع وأخف)
      if (GoogleDriveDeltaSync.instance.isInitialized) {
        _log('🔄 استخدام Delta Sync للتحديثات السريعة...');
        final deltaResult = await GoogleDriveDeltaSync.instance.pushDeltaChanges();
        
        if (deltaResult.success) {
          await _updateLastSyncTime();
          await _updateLastPushTime();
          _log('✅ تم رفع ${deltaResult.changesCount} تغيير عبر Delta Sync');
          return true;
        } else if (deltaResult.changesCount == 0) {
          _log('✓ لا توجد تغييرات للرفع');
          await _updateLastPushTime();
          return true;
        } else {
          _log('⚠️ فشل Delta Sync: ${deltaResult.message} - fallback إلى Full');
        }
      }
      
      // Fallback: رفع النسخة الكاملة (للأمان)
      _log('📦 رفع النسخة الكاملة...');
      final backupData = await _backupService!.exportDatabaseToJson();
      final metadata = backupData['metadata'] as Map<String, dynamic>;
      metadata['device_id'] = _deviceId;
      metadata['sync_type'] = 'push';
      metadata['sync_timestamp'] = DateTime.now().toIso8601String();
      
      await _backupService!.uploadBackup(backupData, isSync: true);
      await _updateLastSyncTime();
      await _updateLastPushTime();
      
      _log('✅ تم رفع النسخة الكاملة بنجاح');
      return true;
    } catch (e) {
      _log('❌ خطأ في رفع التغييرات: $e');
      return false;
    } finally {
      _isSyncing = false;
    }
  }

  /// سحب التغييرات من Google Drive
  /// يُرجع true إذا كانت هناك تغييرات جديدة تم تطبيقها
  Future<bool> pullRemoteChanges() async {
    if (_backupService == null || !_backupService!.isSignedIn) {
      _log('⚠️ لا يمكن سحب التغييرات: غير مسجل الدخول');
      return false;
    }

    if (_isSyncing) {
      _log('⏸️ تخطي السحب - المزامنة جارية');
      return false;
    }

    try {
      _isSyncing = true;
      _log('📥 سحب التغييرات من Google Drive...');
      
      if (GoogleDriveDeltaSync.instance.isInitialized) {
        _log('🔄 استخدام Delta Sync للتحديثات السريعة...');
        final deltaResult = await GoogleDriveDeltaSync.instance.pullDeltaChanges();
        
        if (deltaResult.success && deltaResult.changesCount > 0) {
          await _updateLastSyncTime();
          _log('✅ تم سحب ${deltaResult.changesCount} تغيير عبر Delta Sync');
          return true;
        } else if (deltaResult.success && deltaResult.changesCount == 0) {
          _log('✓ لا توجد تغييرات للسحب');
          return false;
        } else {
          _log('⚠️ فشل Delta Sync: ${deltaResult.message} - fallback إلى Full');
        }
      }
      
      // جلب قائمة النسخ الاحتياطية
      final backupFiles = await _backupService!.listBackupFiles();
      if (backupFiles.isEmpty) {
        _log('📭 لا توجد نسخ احتياطية في Google Drive');
        return false;
      }

      // ترتيب حسب التاريخ (الأحدث أولاً)
      backupFiles.sort((a, b) => b.createdTime.compareTo(a.createdTime));
      final latestBackup = backupFiles.first;

      // التحقق من آخر timestamp محفوظ محلياً
      final lastRemoteTimestamp = await _getLastRemoteTimestamp();
      
      // إذا كانت النسخة أحدث من آخر سحب
      if (lastRemoteTimestamp == null || 
          latestBackup.createdTime.isAfter(lastRemoteTimestamp)) {
        
        // التحقق من أن النسخة ليست من نفس الجهاز
        final backupDeviceId = latestBackup.appProperties['device_id'];
        if (backupDeviceId == _deviceId) {
          _log('📱 النسخة الأحدث من نفس هذا الجهاز');
          return false;
        }
        
        _log('🆕 تم العثور على نسخة جديدة من جهاز: $backupDeviceId');
        
        // تحميل وتطبيق النسخة الاحتياطية
        final backupData = await _backupService!.downloadBackup(latestBackup.fileId);
        await _backupService!.restoreFromBackup(backupData);
        
        // تحديث timestamp
        await _setLastRemoteTimestamp(latestBackup.createdTime);
        await _updateLastSyncTime();
        
        _log('✅ تم تطبيق التغييرات الجديدة بنجاح');
        return true;
      }
      
      _log('ℹ️ لا توجد تغييرات جديدة');
      return false;
      
    } catch (e) {
      _log('❌ خطأ في سحب التغييرات: $e');
      return false;
    } finally {
      _isSyncing = false;
    }
  }

  /// تنظيف الموارد
  void dispose() {
    _stopSyncMonitoring();
    _log('🛑 مدير المزامنة الذكي: تم التنظيف');
  }

  /// معالجة طلب حل التضارب اليدوي (placeholder)
  Future<void> _requestManualConflictResolution(List<DataConflict> conflicts) async {
    _log('🤔 يتطلب تدخل المستخدم لحل ${conflicts.length} تضارب');
    // يمكن إضافة واجهة لحل التضارب يدوياً
  }

  /// حل التضارب حسب أولوية الجهاز (placeholder)
  Future<void> _resolveConflictsDevicePriority(
    List<DataConflict> conflicts,
    Map<String, dynamic> backupData,
  ) async {
    _log('📱 حل التضارب حسب أولوية الجهاز');
    // يمكن تطبيق منطق أولوية الأجهزة هنا
  }

  /// استعادة النسخة المحلية (في حالة فشل المزامنة)
  Future<void> _restoreLocalBackup(Map<String, dynamic> localData) async {
    _log('🔄 استعادة النسخة المحلية...');
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