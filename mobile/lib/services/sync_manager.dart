import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:battery_plus/battery_plus.dart';
import 'package:collection/collection.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synchronized/synchronized.dart';

import '../data/sync_models.dart';
import 'delta_sync_service.dart';
import 'google_drive_sync_service.dart';
import 'local_db.dart';
import 'sync_safety_layer.dart';

/// واجهة اختيارية لإرسال إشعارات FCM عند اكتمال الرفع
abstract class SyncTriggerDispatcher {
  Future<void> sendTrigger({required String syncId, required String sourceDeviceId});
}

class SyncAutomationConfig {
  const SyncAutomationConfig({
    this.debounceWindow = const Duration(milliseconds: 900),
    this.maxDebounceWindow = const Duration(seconds: 4),
    this.realtimePollInterval = const Duration(seconds: 45),
    this.realtimeCallbackUrl,
    this.realtimeTtl = const Duration(hours: 6),
    this.enableForegroundNotifications = false,
  }) : assert(maxDebounceWindow >= debounceWindow);

  final Duration debounceWindow;
  final Duration maxDebounceWindow;
  final Duration realtimePollInterval;
  final Uri? realtimeCallbackUrl;
  final Duration realtimeTtl;
  final bool enableForegroundNotifications;
}

/// مدير المزامنة الرئيسي المسؤول عن دمج البيانات ورفعها إلى Google Drive
class SyncManager {
  SyncManager({
    required this.db,
    required this.driveService,
    this.triggerDispatcher,
    SyncAutomationConfig automationConfig = const SyncAutomationConfig(),
    ForegroundSyncController? foregroundController,
  })  : _automationConfig = automationConfig,
        _foregroundController = foregroundController ?? ForegroundSyncController(),
        _statusController = StreamController<SyncStatus>.broadcast(),
        _auditDao = SyncAuditDao(db),
        _deltaSyncService = DeltaSyncService(db);

  final AppDatabase db;
  final GoogleDriveSyncService driveService;
  final SyncTriggerDispatcher? triggerDispatcher;
  final SyncAuditDao _auditDao;
  final StreamController<SyncStatus> _statusController;
  final SyncSafetyLayer _safetyLayer = SyncSafetyLayer.instance;
  final DeltaSyncService _deltaSyncService;
  final _syncLock = Lock();
  final SyncAutomationConfig _automationConfig;
  final ForegroundSyncController _foregroundController;
  final Battery _battery = Battery();
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  StreamSubscription<BatteryState>? _batteryStateSubscription;
  Timer? _batteryPollTimer;
  Timer? _debounceTimer;
  Timer? _realtimePollingTimer;
  Timer? _driveWatchRenewTimer;
  Timer? _foregroundDelayTimer;
  bool _hasNetworkConnection = true;
  bool _batteryHoldActive = false;
  bool _autoSyncPending = false;
  bool _pendingRemotePull = false;
  DateTime? _debounceFirstChangeAt;
  String? _currentChangeToken;
  DriveRealtimeWatchHandle? _watchHandle;
  int _foregroundRefs = 0;
  int? _lastBatteryLevel;
  DateTime? _lastBatteryCheck;
  bool _batteryCharging = false;

  bool _isInitialized = false;
  bool _isDrainingQueue = false;
  bool _pullInProgress = false;
  bool _syncInProgress = false;
  String? _deviceId;
  int _devicePriority = 100;
  String? _lastUploadedChecksum;
  String? _lastSyncId;
  String? _lastRemoteSyncId;

  Stream<SyncStatus> onSyncStatus() => _statusController.stream;

  /// تهيئة الخدمة مع خيار التشفير قبل أي مزامنة
  Future<void> initSyncService({bool enableEncryption = false, String? encryptionKey}) async {
    if (_isInitialized) {
      return;
    }
    await driveService.init(enableEncryption: enableEncryption, encryptionKey: encryptionKey);
    _deviceId = await _resolveDeviceId();
    await _loadSyncHistory();
    await _setupConnectivityMonitoring();
    await _setupBatteryMonitoring();
    await _initializeRealtimePull();
    _isInitialized = true;
    _statusController.add(SyncStatus(phase: SyncPhase.idle, message: 'المزامنة جاهزة'));
  }

  /// تغيير أولوية الجهاز في حالة التضارب (قيمة افتراضية 100)
  void setDevicePriority(int priority) {
    _devicePriority = priority;
  }

  /// إضافة تغيير محلي إلى طابور المزامنة
  Future<void> pushLocalChange(String table, Map<String, dynamic> row, String operation) async {
    await _ensureReady();
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final uuid = _extractUuid(row) ?? _generateUuid();
    final updatedAt = _extractUpdatedAt(row) ?? nowIso;
    final deviceId = await _ensureDeviceId();
    final payload = jsonEncode(row);

    await db.into(db.syncQueue).insertOnConflictUpdate(
      SyncQueueCompanion(
        uuid: drift.Value(uuid),
        targetTable: drift.Value(table),
        operation: drift.Value(operation),
        payload: drift.Value(payload),
        updatedAt: drift.Value(updatedAt),
        deviceId: drift.Value(deviceId),
        status: const drift.Value('pending'),
        createdAt: drift.Value(nowIso),
      ),
    );

    _scheduleAutoSync();
  }

  /// تشغيل مزامنة كاملة (رفع ثم سحب)
  Future<void> syncAllTables({bool force = false}) async {
    await _syncLock.synchronized(() async {
      if (_syncInProgress && !force) {
        debugPrint('⏳ Sync already in progress, skipping...');
        return;
      }
      _syncInProgress = true;
      try {
        await _ensureReady();
        await _deltaSyncService.repairMirrorIfNeeded();
        await _drainQueue(force: force);
        await pullAndMerge(force: force);
      } finally {
        _syncInProgress = false;
      }
    });
  }

  /// سحب آخر نسخة من Google Drive ودمجها مع قاعدة البيانات المحلية
  Future<void> pullAndMerge({bool force = false}) async {
    await _ensureReady();
    if (_pullInProgress) {
      return;
    }

    if (!_hasNetworkConnection) {
      _pendingRemotePull = true;
      return;
    }

    if (!force && !await _batteryAllowsSync()) {
      _pendingRemotePull = true;
      return;
    }

    _pullInProgress = true;
    _statusController.add(SyncStatus(phase: SyncPhase.pulling, message: 'جلب أحدث النسخ من Google Drive'));
    _retainForeground('جلب أحدث النسخ من Google Drive');

    SyncSafetySnapshot? safetySnapshot;
    try {
      final remoteResult = await driveService.downloadLatestSnapshot();
      if (remoteResult == null) {
        _statusController.add(SyncStatus(phase: SyncPhase.idle, message: 'لا توجد نسخة مزامنة على Drive'));
        return;
      }

      final deviceId = await _ensureDeviceId();
      final remoteSyncId = remoteResult.metadata.lastSyncId;

      if (!force && remoteSyncId.isNotEmpty && remoteSyncId == _lastRemoteSyncId) {
        _statusController.add(SyncStatus(phase: SyncPhase.idle, message: 'لا تغييرات جديدة منذ آخر سحب'));
        return;
      }

      if (!force && remoteResult.metadata.lastDeviceId == deviceId && remoteResult.metadata.checksum == _lastUploadedChecksum) {
        _statusController.add(SyncStatus(phase: SyncPhase.idle, message: 'البيانات على الجهاز محدثة بالفعل'));
        return;
      }

      final localTables = await db.getAllTablesAsJson();
      if (!force && compareChecksum(remoteResult.snapshot, localTables)) {
        _statusController.add(SyncStatus(phase: SyncPhase.idle, message: 'لا تغييرات بعد التحقق من checksum'));
        return;
      }

      final syncId = _generateSyncId();
      safetySnapshot = await _safetyLayer.captureSnapshot(db: db, syncId: syncId, phase: 'pull');

      final mergeResult = _mergeSnapshots(
        remoteSnapshot: remoteResult.snapshot,
        localTables: localTables,
        deviceId: deviceId,
        syncId: syncId,
      );

      await db.applyMergedData(mergeResult.mergedSnapshot.tables);

      await _auditDao.insertSyncLog(
        syncId: syncId,
        direction: 'pull',
        deviceId: deviceId,
        metadata: remoteResult.metadata.toJson(),
        appliedOperations: mergeResult.appliedOperations,
        conflicts: mergeResult.conflicts,
        checksumMatched: false,
      );

      await _safetyLayer.commitSnapshot(
        db: db,
        snapshot: safetySnapshot,
        direction: 'pull',
        checksum: remoteResult.metadata.checksum,
        deviceId: deviceId,
        metadata: {
          'remoteDevice': remoteResult.metadata.lastDeviceId,
          'version': remoteResult.metadata.version,
          'appliedOperations': mergeResult.appliedOperations.length,
          'conflicts': mergeResult.conflicts.length,
        },
      );
      safetySnapshot = null;

      if (remoteSyncId.isNotEmpty) {
        await _persistRemoteSignature(remoteSyncId);
      }
      await _persistSyncHistory(syncId);
      _pendingRemotePull = false;
      _statusController.add(SyncStatus(phase: SyncPhase.completing, message: 'تم تطبيق التغييرات الواردة'));
      unawaited(_refreshRealtimeToken(force: true));
    } catch (error, stack) {
      if (safetySnapshot != null) {
        await _safetyLayer.rollbackSnapshot(db: db, snapshot: safetySnapshot, error: error);
      }
      debugPrint('❌ فشل سحب البيانات: $error');
      debugPrint('$stack');
      _statusController.add(SyncStatus(phase: SyncPhase.error, message: 'خطأ أثناء سحب البيانات', error: error));
      rethrow;
    } finally {
      _pullInProgress = false;
      _statusController.add(SyncStatus(phase: SyncPhase.idle, message: 'انتهى السحب'));
      await _releaseForeground();
    }
  }

  /// مقارنة Checksum المحلي مع البعيد لتحديد التطابق
  bool compareChecksum(SyncSnapshot remote, Map<String, dynamic> localTables) {
    final localChecksum = SyncChecksum.compute({'tables': localTables});
    return localChecksum == remote.metadata.checksum;
  }

  /// حساب checksum باستخدام stream لتجنب memory issues
  Future<String> _computeStreamChecksum() async {
    final output = AccumulatorSink<Digest>();
    final input = sha256.startChunkedConversion(output);
    
    final tableOrder = [
      'rooms',
      'bookings',
      'booking_notes',
      'guests',
      'payments',
      'employees',
      'services',
      'settings',
      'expenses',
      'cash_transactions',
      'debts',
    ];

    for (final table in tableOrder) {
      await for (final batch in _streamTableRows(table, batchSize: 100)) {
        final batchJson = jsonEncode(batch);
        input.add(utf8.encode(batchJson));
      }
    }

    input.close();
    return output.events.single.toString();
  }

  /// stream صفوف الجدول على دفعات لتجنب تحميل كل البيانات في الذاكرة
  Stream<List<Map<String, dynamic>>> _streamTableRows(
    String table,
    {int batchSize = 100}
  ) async* {
    // Whitelist validation for security
    const allowedTables = {
      'rooms',
      'bookings',
      'booking_notes',
      'guests',
      'payments',
      'employees',
      'services',
      'settings',
      'expenses',
      'cash_transactions',
      'debts',
    };
    
    if (!allowedTables.contains(table)) {
      debugPrint('⚠️ Invalid table name: $table');
      return;
    }
    
    int offset = 0;
    while (true) {
      try {
        final batch = await db.customSelect(
          'SELECT * FROM $table ORDER BY local_uuid LIMIT ? OFFSET ?',
          variables: [drift.Variable.withInt(batchSize), drift.Variable.withInt(offset)],
        ).get();
        
        if (batch.isEmpty) break;
        
        final mappedBatch = batch.map((row) => Map<String, dynamic>.from(row.data)).toList();
        
        yield mappedBatch;
        offset += batchSize;
      } catch (e) {
        debugPrint('⚠️ Error streaming table $table at offset $offset: $e');
        break;
      }
    }
  }

  Future<void> _persistSyncHistory(String syncId) async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = await _historyPrefix();
    await prefs.setString('${prefix}_id', syncId);
    await prefs.setInt('${prefix}_epoch', DateTime.now().millisecondsSinceEpoch);
    _lastSyncId = syncId;
  }

  Future<void> _persistRemoteSignature(String? remoteSyncId) async {
    if (remoteSyncId == null || remoteSyncId.isEmpty) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final prefix = await _historyPrefix();
    await prefs.setString('${prefix}_remote', remoteSyncId);
    _lastRemoteSyncId = remoteSyncId;
  }

  Future<void> _loadSyncHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = await _historyPrefix();
    _lastSyncId = prefs.getString('${prefix}_id');
    _lastRemoteSyncId = prefs.getString('${prefix}_remote');
  }

  Future<String> _historyPrefix() async {
    if (_deviceId == null) {
      _deviceId = await _resolveDeviceId();
    }
    return 'sync_history_${_deviceId!}';
  }

  void _scheduleAutoSync() {
    _autoSyncPending = true;
    _debounceTimer?.cancel();
    final now = DateTime.now();
    _debounceFirstChangeAt ??= now;
    if (!_hasNetworkConnection || _batteryHoldActive) {
      return;
    }
    final elapsed = now.difference(_debounceFirstChangeAt!);
    if (elapsed >= _automationConfig.maxDebounceWindow || _automationConfig.debounceWindow <= Duration.zero) {
      _debounceFirstChangeAt = null;
      _autoSyncPending = false;
      unawaited(_drainQueue());
      return;
    }
    final delay = _automationConfig.debounceWindow;
    _debounceTimer = Timer(delay, () {
      _debounceTimer = null;
      _debounceFirstChangeAt = null;
      if (_hasNetworkConnection && !_batteryHoldActive) {
        _autoSyncPending = false;
        unawaited(_drainQueue());
      } else {
        _autoSyncPending = true;
      }
    });
  }

  Future<void> _setupConnectivityMonitoring() async {
    try {
      final initial = await _connectivity.checkConnectivity();
      _handleConnectivityChange(initial);
    } catch (error) {
      debugPrint('⚠️ تعذر فحص الشبكة: $error');
    }
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _handleConnectivityChange,
      onError: (error) => debugPrint('⚠️ تعذر مراقبة الشبكة: $error'),
    );
  }

  void _handleConnectivityChange(List<ConnectivityResult> results) {
    final connected = results.any((result) => result != ConnectivityResult.none);
    final wasConnected = _hasNetworkConnection;
    _hasNetworkConnection = connected;
    if (!connected) {
      return;
    }
    if (!wasConnected || (!_batteryHoldActive && (_autoSyncPending || _pendingRemotePull))) {
      _runPendingSyncIfPossible();
    }
  }

  Future<void> _setupBatteryMonitoring() async {
    await _refreshBatteryState();
    await _batteryStateSubscription?.cancel();
    _batteryStateSubscription = _battery.onBatteryStateChanged.listen((state) {
      _batteryCharging = state == BatteryState.charging || state == BatteryState.full;
      if (_batteryCharging && _batteryHoldActive) {
        _batteryHoldActive = false;
        _runPendingSyncIfPossible();
      }
    }, onError: (error) => debugPrint('⚠️ تعذر مراقبة البطارية: $error'));
    _batteryPollTimer?.cancel();
    _batteryPollTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      unawaited(_refreshBatteryState());
    });
  }

  Future<void> _refreshBatteryState() async {
    try {
      final level = await _battery.batteryLevel;
      _lastBatteryLevel = level;
      _lastBatteryCheck = DateTime.now();
      final wasHeld = _batteryHoldActive;
      _batteryHoldActive = level < 20 && !_batteryCharging;
      if (wasHeld && !_batteryHoldActive) {
        _runPendingSyncIfPossible();
      }
    } catch (error) {
      debugPrint('⚠️ تعذر تحديث حالة البطارية: $error');
    }
  }

  Future<int?> _currentBatteryLevel() async {
    final now = DateTime.now();
    if (_lastBatteryLevel != null && _lastBatteryCheck != null && now.difference(_lastBatteryCheck!) < const Duration(minutes: 1)) {
      return _lastBatteryLevel;
    }
    try {
      final level = await _battery.batteryLevel;
      _lastBatteryLevel = level;
      _lastBatteryCheck = now;
      return level;
    } catch (error) {
      debugPrint('⚠️ مستوى البطارية غير متاح: $error');
      return _lastBatteryLevel;
    }
  }

  Future<bool> _batteryAllowsSync({bool force = false}) async {
    if (force) {
      _batteryHoldActive = false;
      return true;
    }
    final level = await _currentBatteryLevel();
    if (level == null) {
      return true;
    }
    final allowed = level >= 20 || _batteryCharging;
    _batteryHoldActive = !allowed;
    return allowed;
  }

  void _runPendingSyncIfPossible() {
    if (_batteryHoldActive || !_hasNetworkConnection) {
      return;
    }
    if (_autoSyncPending) {
      _autoSyncPending = false;
      unawaited(_drainQueue());
    }
    if (_pendingRemotePull) {
      _pendingRemotePull = false;
      unawaited(pullAndMerge());
    }
  }

  Future<void> _initializeRealtimePull() async {
    await _refreshRealtimeToken(force: true);
    if (_automationConfig.realtimePollInterval > Duration.zero) {
      _realtimePollingTimer?.cancel();
      _realtimePollingTimer = Timer.periodic(_automationConfig.realtimePollInterval, (_) {
        unawaited(_handleRealtimeTick());
      });
    }
    if (_automationConfig.realtimeCallbackUrl != null) {
      await _startRealtimeWatch();
    }
  }

  Future<void> _refreshRealtimeToken({bool force = false}) async {
    if (!force && _currentChangeToken != null) {
      return;
    }
    try {
      final token = await driveService.fetchStartPageToken();
      if (token != null) {
        _currentChangeToken = token;
      }
    } catch (error) {
      debugPrint('⚠️ تعذر تحديث رمز تغييرات Drive: $error');
    }
  }

  Future<void> _handleRealtimeTick() async {
    if (_syncInProgress || _pullInProgress) {
      _pendingRemotePull = true;
      return;
    }
    if (!_hasNetworkConnection) {
      _pendingRemotePull = true;
      return;
    }
    if (_currentChangeToken == null) {
      await _refreshRealtimeToken(force: true);
    }
    final token = _currentChangeToken;
    if (token == null) {
      return;
    }
    try {
      final poll = await driveService.pollRemoteChanges(token);
      if (poll == null) {
        return;
      }
      _currentChangeToken = poll.nextPageToken;
      if (!poll.hasChanges) {
        return;
      }
      if (await _batteryAllowsSync()) {
        _pendingRemotePull = false;
        await pullAndMerge();
      } else {
        _pendingRemotePull = true;
      }
    } catch (error) {
      debugPrint('⚠️ فشل فحص تغييرات Drive: $error');
      _currentChangeToken = null;
    }
  }

  Future<void> _startRealtimeWatch() async {
    final callback = _automationConfig.realtimeCallbackUrl;
    if (callback == null) {
      return;
    }
    await _stopRealtimeWatch();
    try {
      final handle = await driveService.startRealtimeWatch(
        callbackUrl: callback,
        ttl: _automationConfig.realtimeTtl,
      );
      if (handle == null) {
        return;
      }
      _watchHandle = handle;
      _currentChangeToken ??= handle.pageToken;
      final renewAfter = handle.expiration.difference(DateTime.now()) - const Duration(minutes: 5);
      _driveWatchRenewTimer?.cancel();
      final wait = renewAfter.isNegative ? const Duration(minutes: 5) : renewAfter;
      _driveWatchRenewTimer = Timer(wait, () {
        unawaited(_startRealtimeWatch());
      });
    } catch (error) {
      debugPrint('⚠️ تعذر تفعيل مراقبة التغييرات: $error');
    }
  }

  Future<void> _stopRealtimeWatch() async {
    _driveWatchRenewTimer?.cancel();
    final handle = _watchHandle;
    if (handle == null) {
      return;
    }
    _watchHandle = null;
    try {
      await driveService.stopRealtimeWatch(handle);
    } catch (error) {
      debugPrint('⚠️ تعذر إيقاف مراقبة التغييرات: $error');
    }
  }

  void _retainForeground(String description) {
    if (!_automationConfig.enableForegroundNotifications) {
      return;
    }
    _foregroundRefs++;
    if (_foregroundRefs == 1) {
      _foregroundDelayTimer?.cancel();
      _foregroundDelayTimer = Timer(const Duration(seconds: 3), () {
        unawaited(_foregroundController.ensureRunning(title: 'Marina Sync', text: description));
      });
    } else {
      unawaited(_foregroundController.ensureRunning(title: 'Marina Sync', text: description));
    }
  }

  Future<void> _releaseForeground() async {
    if (!_automationConfig.enableForegroundNotifications) {
      return;
    }
    if (_foregroundRefs <= 0) {
      _foregroundRefs = 0;
      _foregroundDelayTimer?.cancel();
      return;
    }
    _foregroundRefs--;
    if (_foregroundRefs == 0) {
      _foregroundDelayTimer?.cancel();
      await _foregroundController.stop();
    }
  }

  Future<void> dispose() async {
    await _connectivitySubscription?.cancel();
    await _batteryStateSubscription?.cancel();
    _batteryPollTimer?.cancel();
    _debounceTimer?.cancel();
    _realtimePollingTimer?.cancel();
    await _stopRealtimeWatch();
    await _releaseForeground();
  }

  Future<void> _drainQueue({bool force = false}) async {
    await _ensureReady();
    if (_isDrainingQueue) {
      return;
    }

    final pending = await (db.select(db.syncQueue)
          ..where((tbl) => tbl.status.equals('pending'))
          ..orderBy([(tbl) => drift.OrderingTerm(expression: tbl.createdAt)])).
        get();

    if (pending.isEmpty && !force) {
      return;
    }

    if (!_hasNetworkConnection) {
      _autoSyncPending = pending.isNotEmpty || _autoSyncPending;
      return;
    }

    if (!force && !await _batteryAllowsSync()) {
      _autoSyncPending = pending.isNotEmpty || _autoSyncPending;
      return;
    }

    _isDrainingQueue = true;
    _statusController.add(SyncStatus(phase: SyncPhase.pushing, message: 'رفع التغييرات المعلقة', progress: 0));
    _retainForeground('رفع التغييرات المعلقة');

    SyncSafetySnapshot? safetySnapshot;
    try {
      final deviceId = await _ensureDeviceId();
      final syncId = _generateSyncId();
      final localTables = await db.getAllTablesAsJson();
      final remoteResult = await driveService.downloadLatestSnapshot();
      final expectedVersion = remoteResult?.driveVersion ?? 0;
      final remoteSnapshot = remoteResult?.snapshot ?? _emptySnapshot();

      if (!force && remoteResult != null && remoteResult.metadata.lastDeviceId == deviceId && compareChecksum(remoteResult.snapshot, localTables)) {
        await _markQueueStatus(pending.map((e) => e.id).toList(), 'synced');
        _statusController.add(SyncStatus(phase: SyncPhase.idle, message: 'لا توجد تغييرات جديدة للرفع'));
        return;
      }

      safetySnapshot = await _safetyLayer.captureSnapshot(db: db, syncId: syncId, phase: 'push');

      final mergeResult = _mergeSnapshots(
        remoteSnapshot: remoteSnapshot,
        localTables: localTables,
        deviceId: deviceId,
        syncId: syncId,
      );

      final uploadIndex = await driveService.uploadSnapshot(
        snapshot: mergeResult.mergedSnapshot,
        deviceId: deviceId,
        expectedVersion: expectedVersion,
      );

      await db.applyMergedData(mergeResult.mergedSnapshot.tables);
      await _markQueueStatus(pending.map((e) => e.id).toList(), 'synced');

      await _auditDao.insertSyncLog(
        syncId: syncId,
        direction: 'push',
        deviceId: deviceId,
        metadata: {
          'version': uploadIndex.version,
          'checksum': uploadIndex.checksum,
          'lastDeviceId': uploadIndex.lastDeviceId,
          'updatedAt': uploadIndex.updatedAt,
          'snapshotSize': uploadIndex.snapshotSize,
          'totalParts': uploadIndex.totalParts,
        },
        appliedOperations: mergeResult.appliedOperations,
        conflicts: mergeResult.conflicts,
        checksumMatched: false,
      );

      await _safetyLayer.commitSnapshot(
        db: db,
        snapshot: safetySnapshot,
        direction: 'push',
        checksum: uploadIndex.checksum,
        deviceId: deviceId,
        metadata: {
          'remoteVersion': uploadIndex.version,
          'snapshotSize': uploadIndex.snapshotSize,
          'appliedOperations': mergeResult.appliedOperations.length,
          'conflicts': mergeResult.conflicts.length,
        },
      );
      safetySnapshot = null;

      _lastUploadedChecksum = uploadIndex.checksum;
      _lastSyncId = mergeResult.mergedSnapshot.metadata.lastSyncId;
      await _persistSyncHistory(_lastSyncId!);
      await _persistRemoteSignature(uploadIndex.lastSyncId);

      if (triggerDispatcher != null && _lastSyncId != null) {
        await triggerDispatcher!.sendTrigger(syncId: _lastSyncId!, sourceDeviceId: deviceId);
      }

      _autoSyncPending = false;
      _debounceFirstChangeAt = null;
      _statusController.add(SyncStatus(phase: SyncPhase.completing, message: 'تم رفع التغييرات بنجاح', progress: 1));
      unawaited(_refreshRealtimeToken(force: true));
    } catch (error, stack) {
      if (safetySnapshot != null) {
        await _safetyLayer.rollbackSnapshot(db: db, snapshot: safetySnapshot, error: error);
      }
      debugPrint('❌ فشل رفع التغييرات: $error');
      debugPrint('$stack');
      _statusController.add(SyncStatus(phase: SyncPhase.error, message: 'تعذر رفع التغييرات', error: error));
      rethrow;
    } finally {
      _isDrainingQueue = false;
      _statusController.add(SyncStatus(phase: SyncPhase.idle, message: 'طابور المزامنة فارغ'));
      await _releaseForeground();
    }
  }

  SyncMergeResult _mergeSnapshots({
    required SyncSnapshot remoteSnapshot,
    required Map<String, dynamic> localTables,
    required String deviceId,
    required String syncId,
  }) {
    final mergedTables = <String, List<Map<String, dynamic>>>{};
    final operations = <SyncOperation>[];
    final conflicts = <SyncConflictModel>[];
    final remotePriority = remoteSnapshot.metadata.devicePriority;
    final nowIso = DateTime.now().toUtc().toIso8601String();

    final remoteTables = remoteSnapshot.tables;
    final allTableNames = <String>{...remoteTables.keys, ...localTables.keys};

    for (final table in allTableNames) {
      final remoteList = (remoteTables[table] ?? []).map((row) => Map<String, dynamic>.from(row)).toList();
      final localList = (localTables[table] as List<dynamic>? ?? [])
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();

      final remoteMap = <String, Map<String, dynamic>>{};
      for (final row in remoteList) {
        final uuid = _extractUuid(row);
        if (uuid != null) {
          remoteMap[uuid] = row;
        }
      }

      final localMap = <String, Map<String, dynamic>>{};
      for (final row in localList) {
        final uuid = _extractUuid(row);
        if (uuid != null) {
          localMap[uuid] = row;
        }
      }

      final mergedList = <Map<String, dynamic>>[];

      final allKeys = <String>{...remoteMap.keys, ...localMap.keys};
      for (final key in allKeys) {
        final remoteRow = remoteMap[key];
        final localRow = localMap[key];

        if (remoteRow == null && localRow != null) {
          mergedList.add(localRow);
          operations.add(SyncOperation(
            table: table,
            uuid: key,
            operation: 'insert',
            payload: localRow,
            timestamp: _extractUpdatedAt(localRow) ?? nowIso,
          ));
          continue;
        }

        if (remoteRow != null && localRow == null) {
          mergedList.add(remoteRow);
          continue;
        }

        if (remoteRow == null || localRow == null) {
          continue;
        }

        final remoteUpdated = _parseDateTime(_extractUpdatedAt(remoteRow));
        final localUpdated = _parseDateTime(_extractUpdatedAt(localRow));
        final remoteDeleted = _parseDateTime(_extractDeletedAt(remoteRow));
        final localDeleted = _parseDateTime(_extractDeletedAt(localRow));

        Map<String, dynamic> winner;
        String operation;

        if (remoteDeleted != null || localDeleted != null) {
          final remoteTs = remoteDeleted ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
          final localTs = localDeleted ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
          if (localTs.isAfter(remoteTs)) {
            winner = localRow;
            operation = 'delete';
          } else {
            winner = remoteRow;
            operation = 'delete';
          }
        } else {
          final remoteUpdatedTs = remoteUpdated ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
          final localUpdatedTs = localUpdated ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
          if (localUpdatedTs.isAfter(remoteUpdatedTs)) {
            winner = localRow;
            operation = 'update';
          } else if (remoteUpdatedTs.isAfter(localUpdatedTs)) {
            winner = remoteRow;
            operation = 'remote';
          } else {
            final equality = const DeepCollectionEquality().equals(remoteRow, localRow);
            if (equality) {
              winner = remoteRow;
              operation = 'noop';
            } else {
              if (_devicePriority >= remotePriority) {
                winner = localRow;
                operation = 'conflict-local';
                conflicts.add(SyncConflictModel(
                  table: table,
                  uuid: key,
                  localPayload: localRow,
                  remotePayload: remoteRow,
                  resolution: 'local',
                ));
              } else {
                winner = remoteRow;
                operation = 'conflict-remote';
                conflicts.add(SyncConflictModel(
                  table: table,
                  uuid: key,
                  localPayload: localRow,
                  remotePayload: remoteRow,
                  resolution: 'remote',
                ));
              }
            }
          }
        }

        mergedList.add(winner);
        if (operation != 'noop' && !operation.startsWith('remote')) {
          operations.add(SyncOperation(
            table: table,
            uuid: key,
            operation: operation,
            payload: winner,
            timestamp: _extractUpdatedAt(winner) ?? nowIso,
          ));
        }
      }

      mergedTables[table] = mergedList;
    }

    final metadata = SyncMetadata(
      version: remoteSnapshot.metadata.version,
      lastUpdatedAt: nowIso,
      devicePriority: _devicePriority,
      snapshotSize: remoteSnapshot.metadata.snapshotSize,
      lastSyncId: syncId,
      checksum: remoteSnapshot.metadata.checksum,
      lastDeviceId: deviceId,
    );

    return SyncMergeResult(
      mergedSnapshot: SyncSnapshot(metadata: metadata, tables: mergedTables),
      appliedOperations: operations,
      conflicts: conflicts,
    );
  }

  Future<void> _markQueueStatus(List<int> ids, String status) async {
    if (ids.isEmpty) {
      return;
    }
    await db.batch((batch) {
      for (final id in ids) {
        batch.update(
          db.syncQueue,
          SyncQueueCompanion(status: drift.Value(status)),
          where: (tbl) => tbl.id.equals(id),
        );
      }
    });
  }

  Future<void> _ensureReady() async {
    if (!_isInitialized) {
      throw StateError('لم يتم تهيئة SyncManager بعد.');
    }
    await _ensureDeviceId();
  }

  Future<String> _ensureDeviceId() async {
    _deviceId ??= await _resolveDeviceId();
    return _deviceId!;
  }

  Future<String> _resolveDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString('sync_device_id');
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final deviceInfo = DeviceInfoPlugin();
    String unique;
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = await deviceInfo.androidInfo;
      unique = 'marina_${android.id}_${android.device}_${android.model}';
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      final ios = await deviceInfo.iosInfo;
      unique = 'marina_${ios.identifierForVendor ?? 'ios'}_${ios.model}_${ios.systemVersion}';
    } else {
      unique = 'marina_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';
    }
    await prefs.setString('sync_device_id', unique);
    return unique;
  }

  SyncSnapshot _emptySnapshot() {
    final metadata = SyncMetadata(
      version: 0,
      lastUpdatedAt: DateTime.fromMillisecondsSinceEpoch(0).toUtc().toIso8601String(),
      devicePriority: 0,
      snapshotSize: 0,
      lastSyncId: '',
      checksum: '',
      lastDeviceId: '',
    );
    return SyncSnapshot(metadata: metadata, tables: {
      'rooms': <Map<String, dynamic>>[],
      'bookings': <Map<String, dynamic>>[],
      'booking_notes': <Map<String, dynamic>>[],
      'guests': <Map<String, dynamic>>[],
      'payments': <Map<String, dynamic>>[],
      'employees': <Map<String, dynamic>>[],
      'services': <Map<String, dynamic>>[],
      'settings': <Map<String, dynamic>>[],
      'expenses': <Map<String, dynamic>>[],
      'cash_transactions': <Map<String, dynamic>>[],
      'debts': <Map<String, dynamic>>[],
    });
  }

  String _generateSyncId() {
    final random = Random.secure();
    final millis = DateTime.now().toUtc().millisecondsSinceEpoch;
    final suffix = random.nextInt(1 << 32).toRadixString(16);
    return 'sync_$millis$suffix';
  }

  String _generateUuid() {
    final random = Random.secure();
    final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    final randPart = random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
    return 'auto-$timestamp-$randPart';
  }

  String? _extractUuid(Map<String, dynamic> row) {
    return (row['uuid'] ?? row['local_uuid'] ?? row['localUuid']) as String?;
  }

  String? _extractUpdatedAt(Map<String, dynamic> row) {
    return (row['updatedAt'] ?? row['updated_at']) as String?;
  }

  String? _extractDeletedAt(Map<String, dynamic> row) {
    return (row['deletedAt'] ?? row['deleted_at']) as String?;
  }

  DateTime? _parseDateTime(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    return DateTime.tryParse(value)?.toUtc();
  }
}

class ForegroundSyncController {
  ForegroundSyncController();

  static const MethodChannel _channel = MethodChannel('marina.sync/foreground');
  bool _active = false;

  Future<void> ensureRunning({required String title, required String text}) async {
    try {
      if (_active) {
        await _channel.invokeMethod('update', {'title': title, 'text': text});
        return;
      }
      await _channel.invokeMethod('start', {'title': title, 'text': text});
      _active = true;
    } catch (error) {
      debugPrint('⚠️ تعذر تشغيل خدمة المزامنة في المقدمة: $error');
      _active = false;
    }
  }

  Future<void> stop() async {
    if (!_active) {
      return;
    }
    try {
      await _channel.invokeMethod('stop');
    } catch (error) {
      debugPrint('⚠️ تعذر إيقاف خدمة المزامنة في المقدمة: $error');
    } finally {
      _active = false;
    }
  }
}

/// A [Sink] that accumulates all data added to it in a list.
class AccumulatorSink<T> implements Sink<T> {
  bool _isClosed = false;
  final List<T> _events = [];

  List<T> get events => List.unmodifiable(_events);

  @override
  void add(T data) {
    if (_isClosed) {
      throw StateError('Cannot add to a closed sink.');
    }
    _events.add(data);
  }

  @override
  void close() {
    _isClosed = true;
  }
}
