import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backup_cache_service.dart';
import 'google_drive_backup_service.dart';
import 'local_db.dart';
import 'providers.dart';
import 'sync_performance_optimizer.dart';
import 'data_usage_manager.dart';
import 'sync_performance_tracker.dart';

enum ConflictResolution {
  newerWins,
  manualResolve,
  devicePriority,
}

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
  
  Future<void> initialize(GoogleDriveBackupService backupService) async {
    _backupService = backupService;
    await _initializeDeviceId();
    await _loadSettings();
    
    await SyncPerformanceOptimizer.instance.initialize();

    // محاولة تحميل من الكاش للعرض الفوري (بدون تعديل قاعدة البيانات)
    final cacheValid = await BackupCacheService.isCacheValid();
    if (cacheValid) {
      final data = await BackupCacheService.loadFromCache();
      if (data != null) {
        debugPrint('⚡️ تم تحميل نسخة Cached للعرض الفوري (${data.length} bytes)');
      }
    }
    
    if (_isEnabled && _backupService?.isSignedIn == true) {
      await _startSyncMonitoring();
    }
    
    debugPrint('🔄 مدير المزامنة الذكي: تم التهيئة بنجاح');
  }

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
        final androidId = androidInfo.id;
        _deviceId = 'marina_${deviceName}_${deviceModel}_${androidId}';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        deviceName = iosInfo.name;
        deviceModel = iosInfo.model;
        final iosId = iosInfo.identifierForVendor ?? 'unknown';
        _deviceId = 'marina_${deviceName}_${deviceModel}_${iosId}';
      }
      
      await prefs.setString(_prefsDeviceIdKey, _deviceId!);
      debugPrint('🆔 تم إنشاء معرف الجهاز الثابت: $_deviceId');
    } else {
      debugPrint('🆔 معرف الجهاز: $_deviceId');
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _isEnabled = prefs.getBool(_prefsEnabledKey) ?? false;
  }

  Future<void> _startSyncMonitoring() async {
    if (_syncCheckTimer?.isActive == true) return;
    
    final baseInterval = await getSyncInterval();
    final optimizer = SyncPerformanceOptimizer.instance;
    
    final optimizedInterval = await optimizer.isAdaptiveIntervalEnabled()
        ? await optimizer.calculateOptimizedInterval(baseInterval)
        : baseInterval;
    
    debugPrint('🔄 بدء مراقبة المزامنة');
    debugPrint('   الفترة الأساسية: ${baseInterval}min');
    debugPrint('   الفترة المحسنة: ${optimizedInterval}min');

    _syncCheckTimer = Timer.periodic(
      Duration(minutes: optimizedInterval),
      (timer) async {
        if (_isSyncing) {
          debugPrint('⏸️  تم تخطي المزامنة - مزامنة جارية بالفعل');
          return;
        }
        await _performOptimizedSyncCheck();
      },
    );
    
    _periodicSyncTimer = Timer.periodic(
      Duration(hours: _periodicFullSyncHours),
      (timer) async {
        if (_isSyncing) return;
        await _performFullSync();
      },
    );

    final lastSync = await _getLastRemoteTimestamp();
    final timeSinceLastSync = lastSync != null ? DateTime.now().difference(lastSync) : null;
    if (timeSinceLastSync == null || timeSinceLastSync.inMinutes > optimizedInterval) {
      debugPrint('🚀 مزامنة فورية عند البدء');
      Future.microtask(() => _performOptimizedSyncCheck());
    }
  }

  Future<void> _performOptimizedSyncCheck() async {
    final optimizer = SyncPerformanceOptimizer.instance;
    final dataManager = DataUsageManager.instance;
    
    if (await optimizer.shouldSkipSync()) {
      debugPrint('⏸️ تم تخطي المزامنة لتوفير الطاقة');
      return;
    }
    
    if (await dataManager.isLimitExceeded()) {
      debugPrint('📊 تم تجاوز حد البيانات اليومي - تخطي المزامنة');
      return;
    }
    
    try {
      await _performSyncCheck();
      optimizer.recordSyncSuccess();
    } catch (e) {
      optimizer.recordSyncFailure();
      rethrow;
    }
  }

  void _stopSyncMonitoring() {
    _syncCheckTimer?.cancel();
    _periodicSyncTimer?.cancel();
    _syncCheckTimer = null;
    _periodicSyncTimer = null;
    debugPrint('⏸️ تم إيقاف مراقبة المزامنة');
  }

  Future<void> onGoogleDriveSignInChanged(bool isSignedIn) async {
    debugPrint('🔔 تغيرت حالة تسجيل الدخول Google Drive: $isSignedIn');
    
    if (isSignedIn && _isEnabled) {
      debugPrint('✅ بدء المراقبة بعد تسجيل الدخول...');
      await _startSyncMonitoring();
    } else {
      debugPrint('⏹️ إيقاف المراقبة بعد تسجيل الخروج...');
      _stopSyncMonitoring();
    }
  }

  Future<void> _performSyncCheck() async {
    if (_isSyncing || _backupService == null || !_backupService!.isSignedIn) {
      return;
    }

    _isSyncing = true;
    final syncStart = DateTime.now();
    final mainSw = Stopwatch()..start();

    try {
      debugPrint('🔍 فحص وجود نسخ احتياطية جديدة...');

      final backupFiles = await _backupService!.listBackupFiles();
      if (backupFiles.isEmpty) {
        debugPrint('📭 لا توجد نسخ احتياطية في Google Drive');
        return;
      }

      backupFiles.sort((a, b) => b.createdTime.compareTo(a.createdTime));
      final latestBackup = backupFiles.first;

      final lastRemoteTimestamp = await _getLastRemoteTimestamp();
      
      if (lastRemoteTimestamp == null || latestBackup.createdTime.isAfter(lastRemoteTimestamp)) {
        final backupDeviceId = latestBackup.appProperties['device_id'];
        if (backupDeviceId != _deviceId) {
          debugPrint('🆕 تم العثور على نسخة احتياطية جديدة من جهاز آخر');
          await _handleNewBackupFound(latestBackup, syncStart);
        } else {
          debugPrint('📱 النسخة الأحدث من نفس هذا الجهاز، لا حاجة للمزامنة');
        }
      } else {
        debugPrint('✅ لا توجد نسخ احتياطية جديدة');
      }

      await _updateLastSyncTime();
      
    } catch (e) {
      debugPrint('❌ خطأ في فحص المزامنة: $e');
    } finally {
      mainSw.stop();
      _isSyncing = false;
    }
  }

  Future<void> _handleNewBackupFound(DriveBackupFile newBackup, DateTime syncStart) async {
    final mainStopwatch = Stopwatch()..start();
    final Map<String, int> timings = {};

    try {
      debugPrint('🔄 بدء مزامنة النسخة الجديدة...');

      var sw = Stopwatch()..start();
      final backupData = await _backupService!.downloadBackup(newBackup.fileId);
      sw.stop();
      timings['download'] = sw.elapsedMilliseconds;
      
      final backupSize = newBackup.size ?? 0;
      if (backupSize > 0) {
        await DataUsageManager.instance.recordDataUsage(backupSize.toDouble());
      }
      
      final conflictResolution = await getConflictResolution();
      
      sw = Stopwatch()..start();
      await _performDataSync(backupData, newBackup, conflictResolution);
      sw.stop();
      timings['merge'] = sw.elapsedMilliseconds;

      await _setLastRemoteTimestamp(newBackup.createdTime);
      await _notifySuccessfulSync(newBackup);
      SyncPerformanceOptimizer.instance.recordSyncSuccess();

      mainStopwatch.stop();

      final downloadedRecords = (backupData['metadata']?['total_records'] as int?) ?? 0;
      final dataSizeKb = (newBackup.size ?? utf8.encode(jsonEncode(backupData)).length) / 1024;

      await SyncPerformanceTracker.recordMetrics(
        SyncPerformanceMetrics(
          syncTime: syncStart,
          uploadedRecords: 0,
          downloadedRecords: downloadedRecords,
          durationMs: mainStopwatch.elapsedMilliseconds,
          dataSizeKb: dataSizeKb.toDouble(),
          syncType: 'full',
          success: true,
        ),
      );

      debugPrint('✅ تمت المزامنة بنجاح');
      
    } catch (e) {
      mainStopwatch.stop();
      debugPrint('❌ خطأ في مزامنة البيانات: $e');
      SyncPerformanceOptimizer.instance.recordSyncFailure();

      await SyncPerformanceTracker.recordMetrics(
        SyncPerformanceMetrics(
          syncTime: syncStart,
          uploadedRecords: 0,
          downloadedRecords: 0,
          durationMs: mainStopwatch.elapsedMilliseconds,
          dataSizeKb: 0,
          syncType: 'failed',
          success: false,
          errorMessage: e.toString(),
        ),
      );

      await _notifySyncError();
    }
  }

  Future<void> _performDataSync(
    Map<String, dynamic> backupData,
    DriveBackupFile sourceBackup,
    ConflictResolution conflictResolution,
  ) async {
    final db = getDatabase();
    final localBackupData = await _backupService!.exportDatabaseToJson();
    
    try {
      debugPrint('📥 بدء استيراد البيانات الجديدة...');
      
      final conflicts = await _detectDataConflicts(localBackupData, backupData);
      
      if (conflicts.isNotEmpty) {
        debugPrint('⚠️ تم العثور على ${conflicts.length} تضارب في البيانات');
        
        switch (conflictResolution) {
          case ConflictResolution.newerWins:
            await _resolveConflictsNewerWins(conflicts, backupData);
            break;
          case ConflictResolution.manualResolve:
            await _requestManualConflictResolution(conflicts);
            return;
          case ConflictResolution.devicePriority:
            await _resolveConflictsDevicePriority(conflicts, backupData);
            break;
        }
      }
      
      await _mergeBackupData(backupData);
      
      debugPrint('✅ تم دمج البيانات بنجاح');
      
    } catch (e) {
      debugPrint('❌ خطأ في دمج البيانات، استعادة النسخة المحلية...');
      await _restoreLocalBackup(localBackupData);
      rethrow;
    }
  }

  Future<List<DataConflict>> _detectDataConflicts(
    Map<String, dynamic> localData,
    Map<String, dynamic> remoteData,
  ) async {
    final conflicts = <DataConflict>[];
    
    final tables = ['bookings', 'payments', 'expenses', 'rooms'];
    
    for (final tableName in tables) {
      final localRecords = (localData[tableName] as List<dynamic>?) ?? [];
      final remoteRecords = (remoteData[tableName] as List<dynamic>?) ?? [];
      
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
      
      for (final uuid in localMap.keys) {
        if (remoteMap.containsKey(uuid)) {
          final localRecord = localMap[uuid];
          final remoteRecord = remoteMap[uuid];
          
          final localTimestamp = localRecord['last_modified'] as int?;
          final remoteTimestamp = remoteRecord['last_modified'] as int?;
          
          if (localTimestamp != null && remoteTimestamp != null) {
            final localTime = DateTime.fromMillisecondsSinceEpoch(localTimestamp);
            final remoteTime = DateTime.fromMillisecondsSinceEpoch(remoteTimestamp);
            
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

  Future<void> _resolveConflictsNewerWins(
    List<DataConflict> conflicts,
    Map<String, dynamic> backupData,
  ) async {
    debugPrint('🔍 حل ${conflicts.length} تضارب باستخدام "الأحدث يفوز"');
    
    final conflictsByTable = <String, List<DataConflict>>{};
    for (final conflict in conflicts) {
      conflictsByTable.putIfAbsent(conflict.tableName, () => []).add(conflict);
    }
    
    await Future.wait(
      conflictsByTable.entries.map((entry) async {
        final tableName = entry.key;
        final tableConflicts = entry.value;
        
        debugPrint('📋 معالجة ${tableConflicts.length} تضارب في $tableName');
        
        int remoteWins = 0;
        int localWins = 0;
        
        for (final conflict in tableConflicts) {
          final timeDiff = conflict.remoteTimestamp.difference(conflict.localTimestamp).abs();
          
          if (timeDiff.inSeconds < 60) {
            final remoteVersion = (conflict.remoteRecord['version'] as int?) ?? 0;
            final localVersion = (conflict.localRecord['version'] as int?) ?? 0;
            if (remoteVersion > localVersion) {
              remoteWins++;
            } else {
              await _removeRecordFromBackupData(backupData, conflict.tableName, conflict.recordId);
              localWins++;
            }
          } else if (conflict.remoteTimestamp.isAfter(conflict.localTimestamp)) {
            remoteWins++;
          } else {
            await _removeRecordFromBackupData(backupData, conflict.tableName, conflict.recordId);
            localWins++;
          }
        }
        
        debugPrint('  📊 $tableName: بعيد=$remoteWins, محلي=$localWins');
      }),
    );
  }

  Future<void> _mergeBackupData(Map<String, dynamic> backupData) async {
    await _backupService!.restoreFromBackup(backupData);
  }

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

  Future<void> _performFullSync() async {
    debugPrint('🔄 بدء المزامنة الكاملة الدورية...');
    await _performSyncCheck();
  }

  Future<void> _notifySuccessfulSync(DriveBackupFile backup) async {
    debugPrint('🎉 تمت مزامنة البيانات من ${backup.appProperties['device_id'] ?? 'جهاز آخر'}');
    debugPrint('📅 تاريخ النسخة: ${backup.createdTime}');
    
    final recordsCount = backup.appProperties['records_count'] ?? 'غير محدد';
    debugPrint('📊 عدد السجلات: $recordsCount');
  }

  Future<void> _notifySyncError() async {
    debugPrint('❌ فشلت المزامنة التلقائية');
  }

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

  Future<void> forceSyncNow() async {
    if (_isSyncing) {
      debugPrint('⏸️ المزامنة جارية بالفعل...');
      return;
    }
    
    debugPrint('🚀 بدء المزامنة اليدوية الفورية...');
    await _performSyncCheck();
  }

  void dispose() {
    _stopSyncMonitoring();
    debugPrint('🛑 مدير المزامنة الذكي: تم التنظيف');
  }

  Future<void> _requestManualConflictResolution(List<DataConflict> conflicts) async {
    debugPrint('🤔 يتطلب تدخل المستخدم لحل ${conflicts.length} تضارب');
  }

  Future<void> _resolveConflictsDevicePriority(
    List<DataConflict> conflicts,
    Map<String, dynamic> backupData,
  ) async {
    debugPrint('📱 حل التضارب حسب أولوية الجهاز');
  }

  Future<void> _restoreLocalBackup(Map<String, dynamic> localData) async {
    debugPrint('🔄 استعادة النسخة المحلية...');
    await _backupService!.restoreFromBackup(localData);
  }
}

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
