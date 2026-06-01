import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_logger.dart';
import '../utils/debug_logs.dart';
import 'daos/outbox_dao.dart';
import 'data_usage_manager.dart';
import 'google_drive_backup_service.dart';
import 'google_drive_delta_sync.dart';
import 'local_db.dart';
import 'sync_conflict_event_bus.dart';
import 'sync_constants.dart';
import 'sync_locks.dart';
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

  SmartSyncManager._();
  static SmartSyncManager? _instance;
  static SmartSyncManager get instance => _instance ??= SmartSyncManager._();

  GoogleDriveBackupService? _backupService;
  Timer? _syncCheckTimer;
  Timer? _periodicSyncTimer;
  bool _isSyncing = false;
  bool _isEnabled = false;
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
  static const String _prefsLastSyncKey = 'smart_sync_last_check';
  static const String _prefsDeviceIdKey = 'smart_sync_device_id';
  static const String _prefsLastRemoteTimestampKey =
      'smart_sync_last_remote_timestamp';
  static const String _prefsConflictResolutionKey =
      'smart_sync_conflict_resolution';

  static const int _defaultSyncIntervalMinutes =
      2; // تغيير من 1 إلى 2 لتقليل الحمل
  static const int _periodicFullSyncHours = 24;

  /// تهيئة مدير المزامنة
  Future<void> initialize(GoogleDriveBackupService backupService) async {
    _backupService = backupService;
    await _initializeDeviceId();
    await _loadSettings();

    // تهيئة مُحسِّن الأداء
    await SyncPerformanceOptimizer.instance.initialize();

    if (_isEnabled && (_backupService?.isSignedIn ?? false)) {
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
          deviceIdentifier =
              iosInfo.identifierForVendor ??
              'ios-${DateTime.now().millisecondsSinceEpoch}';
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
      _isEnabled = false;
      await prefs.setBool(_prefsEnabledKey, false);
    } else {
      _isEnabled = stored;
    }
  }

  /// بدء مراقبة المزامنة التلقائية مع تحسين الأداء
  Future<void> _startSyncMonitoring() async {
    if (_syncCheckTimer?.isActive ?? false) {
      return;
    }

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
      const Duration(hours: _periodicFullSyncHours),
      (timer) => _performFullSync(),
    );

    // تحقق فوري عند البدء (إذا لم تكن هناك قيود)
    if (!await optimizer.shouldSkipSync()) {
      unawaited(_performOptimizedSyncCheck());
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
    if (_isLoggedIn == isSignedIn) {
      return;
    }

    _log('🔔 تغيرت حالة تسجيل الدخول Google Drive: $isSignedIn');
    _log(
      '🔍 Debug: _backupService?.isSignedIn = ${_backupService?.isSignedIn}',
    );
    _log('🔍 Debug: _isEnabled = $_isEnabled');

    _isLoggedIn = isSignedIn;

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
    final canStart = await SyncLocks.smartSyncLock.synchronized(() async {
      if (_isSyncing || _backupService == null || !_backupService!.isSignedIn) {
        return false;
      }
      _isSyncing = true;
      return true;
    });

    if (!canStart) {
      return;
    }

    try {
      _log('🔍 فحص وجود نسخ احتياطية جديدة...');

      // جلب قائمة النسخ الاحتياطية من Google Drive
      final backupFiles = await _backupService!.listBackupFiles();
      if (backupFiles.isEmpty) {
        _log('📭 لا توجد نسخ احتياطية في Google Drive');
        return;
      }

      // ترتيب حسب التاريخ (الأحدث أولاً)
      backupFiles.sort((a, b) => (b.createdTime ?? b.modifiedTime).compareTo(a.createdTime ?? a.modifiedTime));
      final latestBackup = backupFiles.first;

      // التحقق من آخر timestamp محفوظ محلياً
      final lastRemoteTimestamp = await _getLastRemoteTimestamp();

      final latestBackupTime = latestBackup.createdTime ?? latestBackup.modifiedTime;
      if (lastRemoteTimestamp == null ||
          latestBackupTime.isAfter(lastRemoteTimestamp)) {
        // التحقق من أن النسخة ليست من نفس الجهاز
        final backupDeviceId = latestBackup.appProperties?['device_id'];
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
      await SyncLocks.smartSyncLock.synchronized(() async {
        _isSyncing = false;
      });
    }
  }

  /// معالجة اكتشاف نسخة احتياطية جديدة مع تحسين الأداء
  Future<void> _handleNewBackupFound(DriveBackupFile newBackup) async {
    try {
      _log('🔄 بدء مزامنة النسخة الجديدة...');

      // تحميل بيانات النسخة الاحتياطية
      final backupData = await _backupService!.downloadBackup(newBackup.fileId);

      // تسجيل استهلاك البيانات
      final backupSize = newBackup.size;
      if (backupSize > 0) {
        await DataUsageManager.instance.recordDataUsage(backupSize.toDouble());
      }

      // تحديد استراتيجية حل التضارب
      final conflictResolution = await getConflictResolution();

      // تنفيذ المزامنة
      await _performDataSync(backupData, newBackup, conflictResolution);

      // حفظ timestamp النسخة الجديدة
      await _setLastRemoteTimestamp(newBackup.createdTime ?? newBackup.modifiedTime);

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
          case ConflictResolution.manualResolve:
            await _requestManualConflictResolution(conflicts);
            return; // لا نكمل المزامنة التلقائية
          case ConflictResolution.devicePriority:
            await _resolveConflictsDevicePriority(conflicts, backupData);
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
          localMap[record['local_uuid'] as String] = record;
        }
      }

      for (final record in remoteRecords) {
        if (record is Map<String, dynamic> && record['local_uuid'] != null) {
          remoteMap[record['local_uuid'] as String] = record;
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
            final localTime = DateTime.fromMillisecondsSinceEpoch(
              localTimestamp,
            );
            final remoteTime = DateTime.fromMillisecondsSinceEpoch(
              remoteTimestamp,
            );

            // فرق أكثر من 30 ثانية يعتبر تضارب
            if (localTime.difference(remoteTime).inSeconds.abs() > 30) {
              conflicts.add(
                DataConflict(
                  tableName: tableName,
                  recordId: uuid,
                  localRecord: localRecord as Map<String, dynamic>,
                  remoteRecord: remoteRecord as Map<String, dynamic>,
                  localTimestamp: localTime,
                  remoteTimestamp: remoteTime,
                ),
              );
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
        _log(
          '📥 استبدال ${conflict.tableName}/${conflict.recordId} بالنسخة الأحدث',
        );
        // النسخة البعيدة أحدث، سيتم استيرادها — إرسال حدث تضارب (المحلي تم تجاهله)
        SyncConflictEventBus.instance.emitSimple(
          table: conflict.tableName,
          localUuid: conflict.recordId,
          winnerSide: 'remote',
          reason: 'النسخة البعيدة أحدث (${conflict.remoteTimestamp.toIso8601String()})',
        );
      } else {
        _log(
          '📱 الاحتفاظ بالنسخة المحلية لـ ${conflict.tableName}/${conflict.recordId}',
        );
        // المحلي أحدث — تسجيل تحذير لأن التغيير البعيد تم تجاهله
        AppLogger.warning(
          'تغيير السيرفر تم تجاهله (المحلي أحدث): ${conflict.tableName}/${conflict.recordId}',
          tag: 'SYNC_CONFLICT',
        );
        // إرسال حدث تضارب (السيرفر تم تجاهله)
        SyncConflictEventBus.instance.emitSimple(
          table: conflict.tableName,
          localUuid: conflict.recordId,
          winnerSide: 'local',
          reason: 'النسخة المحلية أحدث (${conflict.localTimestamp.toIso8601String()})',
        );
        // إزالة السجل من بيانات النسخ الاحتياطي ليتم تجاهله
        await _removeRecordFromBackupData(
          backupData,
          conflict.tableName,
          conflict.recordId,
        );
      }
    }
  }

  /// التحقق من وجود ملاحظات إدارية جديدة وإرسال إشعارات
  Future<void> _checkForNewNotesAndNotify(
    Map<String, dynamic> backupData,
  ) async {
    try {
      // التحقق من وجود ملاحظات جديدة في ShiftNotes
      if (backupData.containsKey('shift_notes')) {
        final notes = backupData['shift_notes'] as List<dynamic>;
        if (notes.isEmpty) {
          return;
        }

        // جلب آخر وقت مزامنة لمعرفة ما هو الجديد
        final lastSync = await getLastSyncTime();
        if (lastSync == null) {
          return; // أول مزامنة، لا داعي للإزعاج
        }

        int newNotesCount = 0;
        String lastNoteTitle = '';
        String noteCreator = 'الإدارة';

        for (final noteData in notes) {
          if (noteData is Map<String, dynamic>) {
            // التحقق من تاريخ الملاحظة
            final String? createdAtStr = noteData['created_at'] as String?;
            // في بعض الأحيان يكون التاريخ بتنسيق مختلف، نحاول التحليل
            if (createdAtStr != null) {
              try {
                final createdAt = DateTime.parse(createdAtStr);
                // إذا كانت الملاحظة أحدث من آخر مزامنة وليست من هذا الجهاز
                // ملاحظة: نحن نفترض أن createdBy يحمل اسم المستخدم أو معرفه
                // لكن هنا سنعتمد على الوقت بشكل أساسي
                if (createdAt.isAfter(lastSync)) {
                  newNotesCount++;
                  lastNoteTitle = (noteData['title'] as String?) ?? 'بدون عنوان';
                  noteCreator = (noteData['created_by'] as String?) ?? 'مسؤول';
                }
              } catch (e) {
                _log('⚠️ تعذر تحليل تاريخ الملاحظة: $createdAtStr - $e');
              }
            }
          }
        }

        if (newNotesCount > 0) {
          final message = newNotesCount == 1
              ? 'ملاحظة جديدة من $noteCreator: $lastNoteTitle'
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
    await DatabaseManager.runWithRestoreGuard(
      () => _backupService!.restoreFromBackup(backupData),
    );
  }

  /// إزالة سجل من بيانات النسخ الاحتياطي
  Future<void> _removeRecordFromBackupData(
    Map<String, dynamic> backupData,
    String tableName,
    String recordId,
  ) async {
    if (backupData.containsKey(tableName)) {
      final records = backupData[tableName] as List<dynamic>;
      records.removeWhere(
        (record) =>
            record is Map<String, dynamic> && record['local_uuid'] == recordId,
      );
    }
  }

  /// تنفيذ مزامنة كاملة
  Future<void> _performFullSync() async {
    _log('🔄 بدء المزامنة الكاملة الدورية...');
    await _performSyncCheck();
  }

  /// إشعار نجاح المزامنة
  Future<void> _notifySuccessfulSync(DriveBackupFile backup) async {
    final deviceId = backup.appProperties?['device_id'] ?? 'جهاز آخر';
    _log('🎉 تمت مزامنة البيانات من $deviceId');
    _log('📅 تاريخ النسخة: ${backup.createdTime}');

    final recordsCount = backup.appProperties?['records_count'] ?? 'غير محدد';
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

    if (enabled && (_backupService?.isSignedIn ?? false)) {
      await _startSyncMonitoring();
    } else {
      _stopSyncMonitoring();
    }

    _log('🔧 المزامنة التلقائية: ${enabled ? 'مُفعلة' : 'معطلة'}');
  }

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_prefsEnabledKey)) {
      await prefs.setBool(_prefsEnabledKey, false);
      return false;
    }
    return prefs.getBool(_prefsEnabledKey) ?? false;
  }

  /// تنفيذ مزامنة فورية (Push + Pull)
  Future<bool> syncNow() async {
    _log('🔄 بدء مزامنة فورية...');
    try {
      // دفع التغييرات المحلية أولاً
      await pushLocalChanges();
      // ثم سحب التغييرات من السحابة
      await pullRemoteChanges();
      _log('✅ تمت المزامنة الفورية بنجاح');
      return true;
    } catch (e) {
      _log('❌ فشل في المزامنة الفورية: $e');
      return false;
    }
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
    await prefs.setString(
      _prefsLastRemoteTimestampKey,
      timestamp.toIso8601String(),
    );
  }

  Future<void> _updateLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsLastSyncKey, DateTime.now().toIso8601String());
  }

  Future<void> _updateLastPushTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      'smart_sync_last_push_ts',
      DateTime.now().millisecondsSinceEpoch,
    );
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
    final isSyncing = await SyncLocks.smartSyncLock.synchronized(() => _isSyncing);
    if (isSyncing) {
      _log('⏸️ المزامنة جارية بالفعل...');
      return;
    }

    _log('🚀 بدء المزامنة اليدوية الفورية...');

    await pushLocalChanges();

    await pullRemoteChanges();
  }

  /// رفع التغييرات المحلية إلى Google Drive فوراً
  Future<bool> pushLocalChanges() async {
    int retries = 0;
    while (retries < 10) {
      final isSyncing = await SyncLocks.smartSyncLock.synchronized(
        () => _isSyncing,
      );
      if (!isSyncing) {
        break;
      }
      await Future<void>.delayed(SyncConstants.shortPollingDelay);
      retries++;
    }

    final canStart = await SyncLocks.smartSyncLock.synchronized(() async {
      if (_isSyncing) {
        _log('⚠️ تخطي الرفع - المزامنة جارية لفترة طويلة');
        return false;
      }
      if (_backupService == null || !_backupService!.isSignedIn) {
        return false;
      }
      _isSyncing = true;
      return true;
    });

    if (!canStart) {
      return false;
    }

    try {
      _log('📤 رفع التغييرات المحلية إلى Google Drive...');

      // استخدام Delta Sync فقط (رفع التغييرات الجديدة فقط)
      if (!GoogleDriveDeltaSync.instance.isInitialized) {
        _log('⚙️ تهيئة Delta Sync...');
        final db = DatabaseManager.instance;
        await GoogleDriveDeltaSync.instance.initialize(_backupService!, db);
      }

      _log('🔄 استخدام Delta Sync للتحديثات السريعة...');
      final deltaResult = await GoogleDriveDeltaSync.instance
          .pushDeltaChanges();

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
        _log('❌ فشل Delta Sync: ${deltaResult.message}');
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

  /// سحب التغييرات من Google Drive
  /// يُرجع true إذا كانت هناك تغييرات جديدة تم تطبيقها
  Future<bool> pullRemoteChanges() async {
    final canStart = await SyncLocks.smartSyncLock.synchronized(() async {
      if (_backupService == null || !_backupService!.isSignedIn) {
        return false;
      }
      if (_isSyncing) {
        _log('⏸️ تخطي السحب - المزامنة جارية');
        return false;
      }
      _isSyncing = true;
      return true;
    });

    if (!canStart) {
      return false;
    }

    try {
      _log('📥 سحب التغييرات من Google Drive...');

      if (GoogleDriveDeltaSync.instance.isInitialized) {
        _log('🔄 استخدام Delta Sync للتحديثات السريعة...');
        final deltaResult = await GoogleDriveDeltaSync.instance
            .pullDeltaChanges();

        if (deltaResult.success && (deltaResult.changesCount ?? 0) > 0) {
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
      backupFiles.sort((a, b) => (b.createdTime ?? b.modifiedTime).compareTo(a.createdTime ?? a.modifiedTime));
      final latestBackup = backupFiles.first;

      // التحقق من آخر timestamp محفوظ محلياً
      final lastRemoteTimestamp = await _getLastRemoteTimestamp();

      // إذا كانت النسخة أحدث من آخر سحب
      final latestBackupTime = latestBackup.createdTime ?? latestBackup.modifiedTime;
      if (lastRemoteTimestamp == null ||
          latestBackupTime.isAfter(lastRemoteTimestamp)) {
        // التحقق من أن النسخة ليست من نفس الجهاز
        final backupDeviceId = latestBackup.appProperties?['device_id'];
        if (backupDeviceId == _deviceId) {
          _log('📱 النسخة الأحدث من نفس هذا الجهاز');
          return false;
        }

        _log('🆕 تم العثور على نسخة جديدة من جهاز: $backupDeviceId');

        // تحميل وتطبيق النسخة الاحتياطية
        final backupData = await _backupService!.downloadBackup(
          latestBackup.fileId,
        );
        await DatabaseManager.runWithRestoreGuard(
          () => _backupService!.restoreFromBackup(backupData),
        );

        // تحديث timestamp
        await _setLastRemoteTimestamp(latestBackup.createdTime ?? latestBackup.modifiedTime);
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
      await SyncLocks.smartSyncLock.synchronized(() async {
        _isSyncing = false;
      });
    }
  }

  /// تنظيف الموارد
  void dispose() {
    _stopSyncMonitoring();
    _log('🛑 مدير المزامنة الذكي: تم التنظيف');
  }

  /// تنظيف الموارد الثابتة للـ singleton (يُستدعى عند إغلاق التطبيق)
  static Future<void> disposeInstance() async {
    _instance?.dispose();
    _instance = null;
  }

  /// معالجة طلب حل التضارب اليدوي (placeholder)
  Future<void> _requestManualConflictResolution(
    List<DataConflict> conflicts,
  ) async {
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
    await DatabaseManager.runWithRestoreGuard(
      () => _backupService!.restoreFromBackup(localData),
    );
  }
}

/// نموذج تضارب البيانات
class DataConflict {

  DataConflict({
    required this.tableName,
    required this.recordId,
    required this.localRecord,
    required this.remoteRecord,
    required this.localTimestamp,
    required this.remoteTimestamp,
  });
  final String tableName;
  final String recordId;
  final Map<String, dynamic> localRecord;
  final Map<String, dynamic> remoteRecord;
  final DateTime localTimestamp;
  final DateTime remoteTimestamp;
}
