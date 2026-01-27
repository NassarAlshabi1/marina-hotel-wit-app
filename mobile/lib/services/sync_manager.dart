import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/sync_models.dart';
import 'daos/outbox_dao.dart';
import 'google_drive_sync_service.dart';
import 'local_db.dart';
import 'sync_safety_layer.dart';
import 'sync_mutex.dart';
import 'sync_enums.dart';
import 'sync_config.dart';
import 'conflict_resolver.dart';
import 'vector_clock.dart';

/// واجهة اختيارية لإرسال إشعارات FCM عند اكتمال الرفع
abstract class SyncTriggerDispatcher {
  Future<void> sendTrigger(
      {required String syncId, required String sourceDeviceId});
}

class _SyncJob {
  _SyncJob(this.work) : completer = Completer<void>();

  final Future<void> Function() work;
  final Completer<void> completer;
}

/// مدير المزامنة الرئيسي المسؤول عن دمج البيانات ورفعها إلى Google Drive
class SyncManager {
  static SyncManager? _instance;

  static SyncManager get instance {
    final instance = _instance;
    if (instance == null) {
      throw StateError('SyncManager singleton is not configured');
    }
    return instance;
  }

  static void configureSingleton(SyncManager manager) {
    _instance ??= manager;
  }

  SyncManager({
    required this.db,
    required this.driveService,
    this.triggerDispatcher,
  })  : _statusController = StreamController<SyncStatus>.broadcast(),
        _auditDao = SyncAuditDao(db);

  final AppDatabase db;
  final GoogleDriveSyncService driveService;
  final SyncTriggerDispatcher? triggerDispatcher;
  final SyncAuditDao _auditDao;
  final StreamController<SyncStatus> _statusController;
  final SyncSafetyLayer _safetyLayer = SyncSafetyLayer.instance;
  final SyncMutex _drainMutex = SyncMutex();

  static const String _prefsLastDriveSyncEpochKey =
      'drive_auto_sync_last_epoch';

  bool _isInitialized = false;
  bool _isDrainingQueue = false;
  bool _pullInProgress = false;

  final Queue<_SyncJob> _syncJobs = Queue<_SyncJob>();
  bool _syncWorkerRunning = false;

  void _addSyncJob(_SyncJob job) {
    if (_syncJobs.length >= SyncConfig.maxQueueSize) {
      debugPrint('⚠️ طابور المزامنة ممتلئ، حذف أقدم عملية');
      final dropped = _syncJobs.removeFirst();
      dropped.completer
          .completeError(StateError('Sync job dropped due to queue overflow'));
    }
    _syncJobs.add(job);
  }

  StreamSubscription<int>? _outboxWatchSub;
  Timer? _outboxDebounceTimer;

  String? _deviceId;
  int _devicePriority = 100;
  String? _lastUploadedChecksum;
  String? _lastSyncId;
  String? _lastRemoteSyncId;

  Stream<SyncStatus> onSyncStatus() => _statusController.stream;

  /// تهيئة الخدمة مع خيار التشفير قبل أي مزامنة
  Future<void> initSyncService({
    bool enableEncryption = false,
    String? encryptionKey,
    bool allowInteractiveSignIn = true,
  }) async {
    if (_isInitialized) {
      return;
    }
    await driveService.init(
      enableEncryption: enableEncryption,
      encryptionKey: encryptionKey,
      allowInteractiveSignIn: allowInteractiveSignIn,
    );
    _deviceId = await _resolveDeviceId();
    await _loadSyncHistory();
    _isInitialized = true;
    _statusController
        .add(SyncStatus(phase: SyncPhase.idle, message: 'المزامنة جاهزة'));
  }

  /// تغيير أولوية الجهاز في حالة التضارب (قيمة افتراضية 100)
  void setDevicePriority(int priority) {
    _devicePriority = priority;
  }

  /// إضافة تغيير محلي إلى طابور المزامنة
  Future<void> pushLocalChange(
      String table, Map<String, dynamic> row, String operation) async {
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
            status: drift.Value(SyncQueueStatus.pending.value),
            createdAt: drift.Value(nowIso),
          ),
        );

    unawaited(_drainQueue());
  }

  /// تشغيل مزامنة كاملة (رفع ثم سحب) مع حماية من تداخل الطلبات.
  Future<void> syncAllTables({bool force = false}) async {
    return smartSync(force: force);
  }

  /// مزامنة ذكية (Upload/Download) مع قفل لمنع تشغيل مزامنتين بالتوازي.
  /// - يتحقق من الاتصال أولاً
  /// - يتخطى الرفع إذا كان Outbox فارغاً
  /// - يتخطى السحب إذا لم يتغير ملف Drive منذ آخر مزامنة ناجحة
  Future<void> smartSync({bool force = false}) async {
    await _ensureReady();
    return _withSyncLock(() async {
      final online = await _hasConnectivity();
      if (!online) {
        _statusController.add(SyncStatus(
            phase: SyncPhase.idle,
            message: 'لا يوجد اتصال - تم تخطي المزامنة'));
        return;
      }

      final outboxCount = await OutboxDao(db).count();
      final shouldUpload = force || outboxCount > 0;
      if (shouldUpload) {
        await _drainQueue(force: true);
      }

      final shouldPull = force || await _shouldPullByRemoteModifiedTime();
      if (shouldPull) {
        await pullAndMerge(force: force);
      }

      await _persistLastDriveSyncTime();
    });
  }

  /// تشغيل مزامنة تلقائية في الواجهة الأمامية عند تغيّر Outbox مع Debounce.
  void startOutboxDebouncedSync(
      {Duration debounce = const Duration(seconds: 30)}) {
    if (_outboxWatchSub != null) {
      return;
    }
    _outboxWatchSub = OutboxDao(db).watchCount().listen((_) {
      _outboxDebounceTimer?.cancel();
      _outboxDebounceTimer = Timer(debounce, () {
        unawaited(smartSync(force: false));
      });
    });
  }

  Future<void> stopOutboxDebouncedSync() async {
    await _outboxWatchSub?.cancel();
    _outboxWatchSub = null;
    _outboxDebounceTimer?.cancel();
    _outboxDebounceTimer = null;
  }

  Future<bool> _hasConnectivity() async {
    final results = await Connectivity().checkConnectivity();
    return results.any((r) => r != ConnectivityResult.none);
  }

  Future<bool> _shouldPullByRemoteModifiedTime() async {
    final prefs = await SharedPreferences.getInstance();
    final lastEpoch = prefs.getInt(_prefsLastDriveSyncEpochKey);
    final remoteModified = await driveService.getLatestSnapshotModifiedTime();
    if (remoteModified == null) {
      return false;
    }
    if (lastEpoch == null) {
      return true;
    }
    return remoteModified.toUtc().millisecondsSinceEpoch > lastEpoch;
  }

  Future<void> _persistLastDriveSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsLastDriveSyncEpochKey,
        DateTime.now().toUtc().millisecondsSinceEpoch);
  }

  Future<void> _withSyncLock(Future<void> Function() work) {
    final job = _SyncJob(work);
    _addSyncJob(job);
    _startSyncWorkerIfNeeded();
    return job.completer.future;
  }

  void _startSyncWorkerIfNeeded() {
    if (_syncWorkerRunning) {
      return;
    }
    _syncWorkerRunning = true;
    unawaited(_runSyncQueue());
  }

  Future<void> _runSyncQueue() async {
    try {
      while (_syncJobs.isNotEmpty) {
        final job = _syncJobs.removeFirst();
        try {
          await job.work();
          job.completer.complete();
        } catch (error, stack) {
          job.completer.completeError(error, stack);
        }
      }
    } finally {
      _syncWorkerRunning = false;
      if (_syncJobs.isNotEmpty) {
        _startSyncWorkerIfNeeded();
      }
    }
  }

  /// سحب آخر نسخة من Google Drive ودمجها مع قاعدة البيانات المحلية
  Future<void> pullAndMerge({bool force = false}) async {
    await _ensureReady();
    if (_pullInProgress) {
      return;
    }
    _pullInProgress = true;
    _statusController.add(SyncStatus(
        phase: SyncPhase.pulling, message: 'جلب أحدث النسخ من Google Drive'));

    SyncSafetySnapshot? safetySnapshot;
    try {
      final remoteResult = await driveService.downloadLatestSnapshot();
      if (remoteResult == null) {
        _statusController.add(SyncStatus(
            phase: SyncPhase.idle, message: 'لا توجد نسخة مزامنة على Drive'));
        return;
      }

      final deviceId = await _ensureDeviceId();
      final remoteSyncId = remoteResult.metadata.lastSyncId;

      if (!force &&
          remoteSyncId.isNotEmpty &&
          remoteSyncId == _lastRemoteSyncId) {
        _statusController.add(SyncStatus(
            phase: SyncPhase.idle, message: 'لا تغييرات جديدة منذ آخر سحب'));
        return;
      }

      if (!force &&
          remoteResult.metadata.lastDeviceId == deviceId &&
          remoteResult.metadata.checksum == _lastUploadedChecksum) {
        _statusController.add(SyncStatus(
            phase: SyncPhase.idle,
            message: 'البيانات على الجهاز محدثة بالفعل'));
        return;
      }

      final localTables = await db.getAllTablesAsJson();
      if (!force && compareChecksum(remoteResult.snapshot, localTables)) {
        _statusController.add(SyncStatus(
            phase: SyncPhase.idle,
            message: 'لا تغييرات بعد التحقق من checksum'));
        return;
      }

      final syncId = _generateSyncId();
      safetySnapshot = await _safetyLayer.captureSnapshot(
          db: db, syncId: syncId, phase: 'pull');

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

      _statusController.add(SyncStatus(
          phase: SyncPhase.completing, message: 'تم تطبيق التغييرات الواردة'));
    } catch (error, stack) {
      if (safetySnapshot != null) {
        await _safetyLayer.rollbackSnapshot(
            db: db, snapshot: safetySnapshot, error: error);
      }
      debugPrint('❌ فشل سحب البيانات: $error');
      debugPrint('$stack');
      _statusController.add(SyncStatus(
          phase: SyncPhase.error,
          message: 'خطأ أثناء سحب البيانات',
          error: error));
      rethrow;
    } finally {
      _pullInProgress = false;
      _statusController
          .add(SyncStatus(phase: SyncPhase.idle, message: 'انتهى السحب'));
    }
  }

  /// مقارنة Checksum المحلي مع البعيد لتحديد التطابق
  bool compareChecksum(SyncSnapshot remote, Map<String, dynamic> localTables) {
    final localChecksum = SyncChecksum.compute({'tables': localTables});
    return localChecksum == remote.metadata.checksum;
  }

  /// stream صفوف الجدول على دفعات لتجنب تحميل كل البيانات في الذاكرة
  Stream<List<Map<String, dynamic>>> _streamTableRows(String table,
      {int batchSize = 100}) async* {
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
          variables: [
            drift.Variable.withInt(batchSize),
            drift.Variable.withInt(offset)
          ],
        ).get();

        if (batch.isEmpty) break;

        final mappedBatch =
            batch.map((row) => Map<String, dynamic>.from(row.data)).toList();

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
    await prefs.setInt(
        '${prefix}_epoch', DateTime.now().millisecondsSinceEpoch);
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
    _deviceId ??= await _resolveDeviceId();
    return 'sync_history_${_deviceId!}';
  }

  Future<void> _drainQueue({bool force = false}) async {
    if (!await _drainMutex.acquire()) {
      debugPrint('⏸️ طابور المزامنة مشغول - تخطي');
      return;
    }
    await _ensureReady();
    if (_isDrainingQueue) {
      return;
    }

    final pending = await (db.select(db.syncQueue)
          ..where((tbl) => tbl.status.equals('pending'))
          ..orderBy([(tbl) => drift.OrderingTerm(expression: tbl.createdAt)]))
        .get();

    if (pending.isEmpty && !force) {
      return;
    }

    _isDrainingQueue = true;
    _statusController.add(SyncStatus(
        phase: SyncPhase.pushing,
        message: 'رفع التغييرات المعلقة',
        progress: 0));

    SyncSafetySnapshot? safetySnapshot;
    try {
      final deviceId = await _ensureDeviceId();
      final syncId = _generateSyncId();
      final localTables = await db.getAllTablesAsJson();
      final remoteResult = await driveService.downloadLatestSnapshot();
      final expectedVersion = remoteResult?.driveVersion ?? 0;
      final remoteSnapshot = remoteResult?.snapshot ?? _emptySnapshot();

      if (!force &&
          remoteResult != null &&
          remoteResult.metadata.lastDeviceId == deviceId &&
          compareChecksum(remoteResult.snapshot, localTables)) {
        await _markQueueStatus(
            pending.map((e) => e.id).toList(), SyncQueueStatus.synced.value);
        _statusController.add(SyncStatus(
            phase: SyncPhase.idle, message: 'لا توجد تغييرات جديدة للرفع'));
        return;
      }

      safetySnapshot = await _safetyLayer.captureSnapshot(
          db: db, syncId: syncId, phase: 'push');

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
      await _markQueueStatus(
          pending.map((e) => e.id).toList(), SyncQueueStatus.synced.value);

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
        await triggerDispatcher!
            .sendTrigger(syncId: _lastSyncId!, sourceDeviceId: deviceId);
      }

      _statusController.add(SyncStatus(
          phase: SyncPhase.completing,
          message: 'تم رفع التغييرات بنجاح',
          progress: 1));
    } catch (error, stack) {
      if (safetySnapshot != null) {
        await _safetyLayer.rollbackSnapshot(
            db: db, snapshot: safetySnapshot, error: error);
      }
      debugPrint('❌ فشل رفع التغييرات: $error');
      debugPrint('$stack');
      _statusController.add(SyncStatus(
          phase: SyncPhase.error, message: 'تعذر رفع التغييرات', error: error));
      rethrow;
    } finally {
      _isDrainingQueue = false;
      _drainMutex.release();
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
      final remoteList = (remoteTables[table] ?? [])
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
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
          final remoteTs = remoteDeleted ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
          final localTs = localDeleted ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
          if (localTs.isAfter(remoteTs)) {
            winner = localRow;
            operation = 'delete';
          } else {
            winner = remoteRow;
            operation = 'delete';
          }
        } else {
          final remoteUpdatedTs = remoteUpdated ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
          final localUpdatedTs = localUpdated ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
          if (localUpdatedTs.isAfter(remoteUpdatedTs)) {
            winner = localRow;
            operation = 'update';
          } else if (remoteUpdatedTs.isAfter(localUpdatedTs)) {
            winner = remoteRow;
            operation = 'remote';
          } else {
            final equality =
                const DeepCollectionEquality().equals(remoteRow, localRow);
            if (equality) {
              winner = remoteRow;
              operation = 'noop';
            } else {
              final conflictResolver = EnhancedConflictResolver(
                defaultStrategy: ConflictStrategy.fieldLevel,
                tableStrategies: {
                  'bookings': ConflictStrategy.fieldLevel,
                  'payments': ConflictStrategy.lastWriteWins,
                  'rooms': ConflictStrategy.lastWriteWins,
                  'expenses': ConflictStrategy.lastWriteWins,
                  'debts': ConflictStrategy.fieldLevel,
                  'guests': ConflictStrategy.fieldLevel,
                  'employees': ConflictStrategy.fieldLevel,
                  'services': ConflictStrategy.lastWriteWins,
                },
              );

              VectorClock? localVectorClock;
              VectorClock? remoteVectorClock;
              try {
                final localVc = localRow['vector_clock'] as String?;
                final remoteVc = remoteRow['vector_clock'] as String?;
                if (localVc != null && localVc.isNotEmpty) {
                  localVectorClock = VectorClock.fromJson(localVc);
                }
                if (remoteVc != null && remoteVc.isNotEmpty) {
                  remoteVectorClock = VectorClock.fromJson(remoteVc);
                }
              } catch (_) {}

              final context = ConflictContext(
                table: table,
                uuid: key,
                localData: localRow,
                remoteData: remoteRow,
                localVectorClock: localVectorClock,
                remoteVectorClock: remoteVectorClock,
                localTimestamp: localUpdatedTs,
                remoteTimestamp: remoteUpdatedTs,
                localDeviceId: deviceId,
                remoteDeviceId: remoteSnapshot.metadata.lastDeviceId,
                localDevicePriority: _devicePriority,
                remoteDevicePriority: remotePriority,
              );

              final resolution = conflictResolver.resolve(context);
              winner = resolution.mergedData ?? resolution.winner;

              final isLocalWinner = winner == localRow ||
                  (resolution.mergedData != null &&
                      resolution.strategy == ConflictStrategy.fieldLevel);

              operation = isLocalWinner ? 'conflict-local' : 'conflict-remote';

              conflicts.add(SyncConflictModel(
                table: table,
                uuid: key,
                localPayload: localRow,
                remotePayload: remoteRow,
                resolution: resolution.needsManualReview
                    ? 'pending'
                    : (isLocalWinner ? 'local-merged' : 'remote'),
              ));

              debugPrint(
                  '🔀 تعارض [$table/$key]: استراتيجية ${resolution.strategy.name}');
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
      unique =
          'marina_${ios.identifierForVendor ?? 'ios'}_${ios.model}_${ios.systemVersion}';
    } else {
      unique =
          'marina_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';
    }
    await prefs.setString('sync_device_id', unique);
    return unique;
  }

  SyncSnapshot _emptySnapshot() {
    final metadata = SyncMetadata(
      version: 0,
      lastUpdatedAt:
          DateTime.fromMillisecondsSinceEpoch(0).toUtc().toIso8601String(),
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
