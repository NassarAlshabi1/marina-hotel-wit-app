import 'dart:async';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/debug_logs.dart';
import '../google_drive_backup_service.dart';
import '../google_drive_delta_sync.dart';
import '../sync_notification_manager.dart';
import '../sync_performance_optimizer.dart';
import '../data_usage_manager.dart';

import 'sync_scheduler.dart';
import 'conflict_resolver.dart';
import 'sync_metrics.dart';

export 'conflict_resolver.dart' show ConflictStrategy;

/// مدير المزامنة الأساسي المبسط - مسؤول عن التنسيق العام فقط
/// 
/// هذا المدير يستخدم المكونات المستقلة:
/// - SyncScheduler: للجدولة
/// - ConflictResolver: لحل التضارب
/// - SyncMetrics: للقياسات والإحصائيات
/// 
/// ملاحظة: هذا كلاس abstract - يجب إنشاء كلاس موروث منه لاستخدامه.
abstract class BaseSyncManager {
  BaseSyncManager();

  GoogleDriveBackupService? _backupService;
  late SyncScheduler _scheduler;
  late ConflictResolver _conflictResolver;
  late SyncMetrics _metrics;
  
  bool _isSyncing = false;
  bool _isEnabled = false;
  String? _deviceId;

  String? get deviceId => _deviceId;
  bool get isEnabled => _isEnabled;
  bool get isSyncing => _isSyncing;
  
  Stream<SyncStats> get statsStream => _metrics.statsStream;

  static const String _prefsEnabledKey = 'smart_sync_enabled';
  static const String _prefsDeviceIdKey = 'smart_sync_device_id';
  static const String _prefsConflictStrategyKey = 'smart_sync_conflict_strategy';
  static const String _prefsLastSyncKey = 'smart_sync_last_check';
  static const String _prefsLastRemoteTimestampKey = 'smart_sync_last_remote_timestamp';

  void _log(String message) {
    DebugLogs.add('BaseSyncManager', message);
    debugPrint(message);
  }

  /// تهيئة المدير - بسيطة ومنظمة
  Future<void> initialize(GoogleDriveBackupService backupService) async {
    _backupService = backupService;
    _deviceId = await _initializeDeviceId();
    
    _metrics = SyncMetrics.instance;
    await _metrics.loadHistory();
    
    _conflictResolver = ConflictResolver(
      deviceId: _deviceId!,
      strategy: await _loadConflictStrategy(),
    );
    
    _scheduler = SyncScheduler(
      onSyncTrigger: _performSync,
      isEnabled: () => _isEnabled && _backupService?.isSignedIn == true,
      quickCheckInterval: const Duration(minutes: 1),
      fullSyncInterval: const Duration(hours: 24),
    );
    
    await _loadSettings();
    
    await SyncPerformanceOptimizer.instance.initialize();
    
    if (_isEnabled && _backupService?.isSignedIn == true) {
      await _scheduler.start();
    }
    
    _log('🔄 BaseSyncManager: تم التهيئة بنجاح');
  }

  /// توليد معرف فريد للجهاز
  Future<String> _initializeDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? savedId = prefs.getString(_prefsDeviceIdKey);
    
    if (savedId != null) {
      _log('🆔 معرف الجهاز: $savedId');
      return savedId;
    }
    
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
    
    await prefs.setString(_prefsDeviceIdKey, deviceIdentifier);
    _log('🆔 تم إنشاء معرف الجهاز: $deviceIdentifier');
    return deviceIdentifier;
  }

  /// تحميل إعدادات المزامنة
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _isEnabled = prefs.getBool(_prefsEnabledKey) ?? true;
    
    if (_isEnabled && prefs.getBool(_prefsEnabledKey) == null) {
      await prefs.setBool(_prefsEnabledKey, true);
    }
  }

  /// تحميل استراتيجية حل التضارب
  Future<ConflictStrategy> _loadConflictStrategy() async {
    final prefs = await SharedPreferences.getInstance();
    final strategyIndex = prefs.getInt(_prefsConflictStrategyKey) ?? 0;
    return ConflictStrategy.values[strategyIndex];
  }

  /// تنفيذ مزامنة واحدة - المنطق الأساسي
  Future<void> _performSync() async {
    if (_isSyncing || _backupService == null || !_backupService!.isSignedIn) {
      return;
    }
    
    final optimizer = SyncPerformanceOptimizer.instance;
    
    if (await optimizer.shouldSkipSync()) {
      _log('⏸️ تم تخطي المزامنة لتوفير الطاقة');
      return;
    }
    
    final dataManager = DataUsageManager.instance;
    if (await dataManager.isLimitExceeded()) {
      _log('⏸️ تم تخطي المزامنة بسبب قيود البيانات');
      return;
    }
    
    _isSyncing = true;
    _metrics.startSync();
    
    try {
      await _performSyncInternal();
      optimizer.recordSyncSuccess();
      await dataManager.recordDataUsage(0.5);
    } catch (e, stack) {
      optimizer.recordSyncFailure();
      _log('❌ خطأ في المزامنة: $e');
      debugPrintStack(stackTrace: stack);
      rethrow;
    } finally {
      _isSyncing = false;
    }
  }

  /// المنطق الداخلي للمزامنة
  Future<void> _performSyncInternal() async {
    final prefs = await SharedPreferences.getInstance();
    final lastRemoteTimestamp = prefs.getString(_prefsLastRemoteTimestampKey);
    
    _log('🔄 بدء المزامنة...');
    
    final backupsList = await _backupService!.listBackups();
    if (backupsList.isEmpty) {
      _log('ℹ️ لا توجد نسخ احتياطية');
      _metrics.recordSuccess();
      return;
    }
    
    final latestBackup = backupsList.first;
    final remoteTimestamp = latestBackup.appProperties['timestamp'] ?? '';
    
    if (lastRemoteTimestamp == remoteTimestamp && (lastRemoteTimestamp?.isNotEmpty ?? false)) {
      _log('✅ لا توجد تحديثات جديدة');
      _metrics.recordSuccess();
      return;
    }
    
    _log('📥 تحميل النسخة الاحتياطية الجديدة...');
    final backupData = await _backupService!.downloadBackup(latestBackup.fileId);
    
    final localData = await _getLocalData();
    
    final conflicts = await _conflictResolver.detectConflicts(localData, backupData);
    
    int conflictsResolved = 0;
    if (conflicts.isNotEmpty) {
      _log('⚔️ اكتشف ${conflicts.length} تضارب');
      final resolvedData = await _conflictResolver.resolveConflicts(conflicts);
      await _mergeResolvedData(resolvedData);
      conflictsResolved = conflicts.length;
    }
    
    await _mergeData(backupData);
    
    await prefs.setString(_prefsLastRemoteTimestampKey, remoteTimestamp);
    await prefs.setString(_prefsLastSyncKey, DateTime.now().toIso8601String());
    
    await SyncNotificationManager.instance.showSystemNotification(
      title: '✅ تمت المزامنة بنجاح',
      body: 'تم مزامنة البيانات من ${latestBackup.appProperties['device_id'] ?? 'جهاز آخر'}',
    );
    
    _metrics.recordSuccess(
      recordsSynced: _countRecords(backupData),
      conflictsResolved: conflictsResolved,
    );
    
    _log('✅ اكتملت المزامنة بنجاح');
  }

  /// جلب البيانات المحلية - يجب تنفيذها في الكلاس الموروث
  Future<Map<String, dynamic>> _getLocalData();

  /// دمج البيانات - يجب تنفيذها في الكلاس الموروث
  Future<void> _mergeData(Map<String, dynamic> data);

  /// دمج البيانات المحلولة من التضارب - يجب تنفيذها في الكلاس الموروث
  Future<void> _mergeResolvedData(Map<String, Map<String, dynamic>> resolvedData);

  /// حساب عدد السجلات
  int _countRecords(Map<String, dynamic> data) {
    int count = 0;
    for (final table in data.values) {
      if (table is Map) {
        count += table.length;
      }
    }
    return count;
  }

  /// تفعيل المزامنة
  Future<void> enable() async {
    if (_isEnabled) return;
    
    _isEnabled = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsEnabledKey, true);
    
    if (_backupService?.isSignedIn == true) {
      await _scheduler.start();
    }
    
    _log('✅ تم تفعيل المزامنة');
  }

  /// تعطيل المزامنة
  Future<void> disable() async {
    if (!_isEnabled) return;
    
    _isEnabled = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsEnabledKey, false);
    
    await _scheduler.stop();
    
    _log('⏸️ تم تعطيل المزامنة');
  }

  /// مزامنة فورية
  Future<void> syncNow() async {
    await _performSync();
  }

  /// تغيير استراتيجية حل التضارب
  Future<void> setConflictStrategy(ConflictStrategy strategy) async {
    _conflictResolver = _conflictResolver.copyWith(strategy: strategy);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsConflictStrategyKey, strategy.index);
    _log('⚙️ تم تغيير استراتيجية التضارب إلى: $strategy');
  }

  /// معرفة الاستراتيجية الحالية
  ConflictStrategy get currentConflictStrategy => _conflictResolver.strategy;

  /// استدعاء عند تغير حالة تسجيل الدخول
  Future<void> onGoogleDriveSignInChanged(bool isSignedIn) async {
    _log('🔔 تغيرت حالة Google Drive: $isSignedIn');
    
    if (isSignedIn && _isEnabled) {
      await _scheduler.start();
      await syncNow();
    } else {
      await _scheduler.stop();
    }
  }

  /// تنظيف الموارد
  void dispose() {
    _scheduler.dispose();
    _metrics.dispose();
  }
}
