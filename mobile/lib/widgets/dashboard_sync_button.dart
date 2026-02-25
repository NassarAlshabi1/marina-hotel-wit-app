import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

// ═══════════════════════════════════════════════════════════════
// 1. ENUMS & MODELS
// ═══════════════════════════════════════════════════════════════

enum SyncStatus { idle, pushing, syncing }

class SyncResult {
  final int recordsPushed;
  final int recordsCleaned;
  final List<String> syncedIds;
  
  SyncResult({
    required this.recordsPushed,
    required this.recordsCleaned,
    required this.syncedIds,
  });
}

// ═══════════════════════════════════════════════════════════════
// 2. DATABASE TABLES
// ═══════════════════════════════════════════════════════════════

@DataClassName('OutboxRecord')
class OutboxTable extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get recordId => text()();
  TextColumn get tableName => text()();
  TextColumn get operation => text()(); // create, update, delete
  TextColumn get payload => text()();
  BoolColumn get synced => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get retryAt => dateTime().nullable()();
  
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('SyncLog')
class SyncLogTable extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get syncId => text()();
  TextColumn get direction => text()();
  TextColumn get deviceId => text()();
  TextColumn get target => text()();
  TextColumn get status => text()();
  IntColumn? get recordsPushed => integer().nullable()();
  IntColumn? get recordsCleaned => integer().nullable()();
  IntColumn? get durationMs => integer().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  
  @override
  Set<Column> get primaryKey => {id};
}

// ═══════════════════════════════════════════════════════════════
// 3. DATABASE CLASS
// ═══════════════════════════════════════════════════════════════

    // مؤقت للتحديث الدوري
    _pendingChangesTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && !_isPulling && !_isPushing) {
        _loadPendingChangesCount();
        _loadAppwriteEnabled();
      }
    });
  }
}

// ═══════════════════════════════════════════════════════════════
// 4. DAOs
// ═══════════════════════════════════════════════════════════════

@DriftAccessor(tables: [OutboxTable])
class OutboxDao extends DatabaseAccessor<AppDatabase> with _$OutboxDaoMixin {
  OutboxDao(AppDatabase db) : super(db);
  
  Future<List<OutboxTableData>> getPendingRecords() async {
    return (select(outboxTable)
          ..where((tbl) => tbl.synced.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }
  
  Future<int> getPendingCount() async {
    final result = await (selectOnly(outboxTable)
        ..addColumns([outboxTable.id.count()])
        ..where(outboxTable.synced.equals(false)))
        .map((row) => row.read(outboxTable.id.count())!)
        .getSingle();
    return result ?? 0;
  }
  
  Future<int> clearSyncedRecords(List<String> syncedRecordIds) async {
    if (syncedRecordIds.isEmpty) return 0;
    
    await customStatement('''
      DELETE FROM outbox_table 
      WHERE record_id IN (${syncedRecordIds.map((_) => '?').join(',')})
      AND synced = 0
    ''', syncedRecordIds);
    
    return syncedRecordIds.length;
  }
  
  Future<void> markAsSynced(List<String> recordIds) async {
    await (update(outboxTable)..where((tbl) => outboxTable.recordId.isInValues(recordIds)))
        .write(const OutboxTableCompanion(synced: Value(true)));
  }
}

@DriftAccessor(tables: [SyncLogTable])
class SyncLogDao extends DatabaseAccessor<AppDatabase> with _$SyncLogDaoMixin {
  SyncLogDao(AppDatabase db) : super(db);
  
  Future<void> logSync({
    required String syncId,
    required String direction,
    required String deviceId,
    required String target,
    required String status,
    int? recordsPushed,
    int? recordsCleaned,
    int? durationMs,
  }) async {
    await into(syncLogTable).insertOnConflictUpdate(SyncLogTableCompanion.insert(
      syncId: syncId,
      direction: direction,
      deviceId: deviceId,
      target: target,
      status: status,
      recordsPushed: Value(recordsPushed),
      recordsCleaned: Value(recordsCleaned),
      durationMs: Value(durationMs),
      createdAt: DateTime.now(),
    ));
  }
}

// ═══════════════════════════════════════════════════════════════
// 5. APPWRITE SERVICE (Mock)
class AppwriteService {
  static final AppwriteService _instance = AppwriteService._internal();
  factory AppwriteService() => _instance;
  AppwriteService._internal();
  
  Future<bool> sendRecord(OutboxTableData record) async {
    await Future.delayed(Duration(milliseconds: 500 + Random().nextInt(1000)));
    
    // Simulate network issues 5% of the time
    if (Random().nextDouble() < 0.05) {
      throw Exception('Network timeout');
    }
    
    debugPrint('✅ Synced record ${record.recordId} to Appwrite');
    return true;
  }
}

  /// تنظيف outbox بعد الرفع
  Future<void> _clearOutboxAfterPush() async {
    try {
      final db = ref.read(databaseProvider);
      final outboxDao = OutboxDao(db);
      await outboxDao.removeAllPending();
      debugPrint('✅ تم تنظيف outbox بنجاح');
    } catch (e) {
      debugPrint('⚠️ فشل تنظيف outbox: $e');
      // لا نرمي الخطأ حتى لا يؤثر على تجربة المستخدم
    }
  }

  /// سحب التغييرات من Appwrite (Pull فقط - بدون دفع)
  Future<void> _pullChanges(BuildContext context) async {
    final stopwatch = Stopwatch()..start();
    final outboxDao = OutboxDao(_database!);
    final syncLogDao = SyncLogDao(_database!);
    
    final pendingRecords = await outboxDao.getPendingRecords();
    List<String> syncedIds = [];

    for (final record in pendingRecords) {
      try {
        final success = await _appwriteService!.sendRecord(record);
        if (success) {
          syncedIds.add(record.recordId);
        }
      } catch (e) {
        debugPrint('❌ Failed to sync ${record.recordId}: $e');
        // Keep failed records for retry
        continue;
      }
    }

    // تسجيل بداية العملية
    final db = ref.read(databaseProvider);
    final syncLogDao = SyncLogDao(db);
    await syncLogDao.logSync(
      syncId: syncId,
      direction: 'push',
      deviceId: deviceId,
      target: 'Appwrite',
      status: 'success',
      recordsPushed: syncedIds.length,
      recordsCleaned: recordsCleaned,
      durationMs: stopwatch.elapsedMilliseconds,
    );
    if (_isPulling) return;

    return SyncResult(
      recordsPushed: syncedIds.length,
      recordsCleaned: recordsCleaned,
      syncedIds: syncedIds,
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 7. RIVERPOD PROVIDERS
// ═══════════════════════════════════════════════════════════════

final databaseProvider = Provider<AppDatabase>((ref) => AppDatabase());
final appwriteServiceProvider = Provider<AppwriteService>((ref) => AppwriteService());
final deltaSyncProvider = Provider<AppwriteDeltaSync>((ref) {
  final deltaSync = AppwriteDeltaSync();
  // Initialize on provider creation
  WidgetsBinding.instance.addPostFrameCallback((_) {
    deltaSync.initialize(
      appwriteService: ref.read(appwriteServiceProvider),
      database: ref.read(databaseProvider),
    );
  });
  return deltaSync;
});

final pendingChangesCountProvider = FutureProvider<int>((ref) async {
  final db = ref.watch(databaseProvider);
  final outboxDao = OutboxDao(db);
  return outboxDao.getPendingCount();
});

// ═══════════════════════════════════════════════════════════════
// 8. MAIN WIDGET - DashboardSyncButton
// ═══════════════════════════════════════════════════════════════

class DashboardSyncButton extends ConsumerStatefulWidget {
  const DashboardSyncButton({super.key});

      final deltaSync = AppwriteDeltaSync.instance;
      if (!deltaSync.isInitialized) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('خدمة المزامنة غير مهيأة'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

class _DashboardSyncButtonState extends ConsumerState<DashboardSyncButton>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  
  SyncStatus _syncStatus = SyncStatus.idle;
  DateTime? _lastSyncTime;
  late AnimationController _animationController;
  late Animation<double> _rotationAnimation;
  Timer? _retryTimer;

      // 2️⃣ حل التعارضات إن وجدت
      int conflictsResolved = 0;
      if (pullResult.hasConflicts) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚖️ جاري حل التعارضات...'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );
        }
        conflictsResolved = await _resolveConflicts();
      }
    }
  }

  Future<void> _handlePush() async {
    final pendingCountAsync = ref.read(pendingChangesCountProvider);
    final pendingCount = pendingCountAsync.value ?? 0;
    
    if (pendingCount == 0 || _syncStatus != SyncStatus.idle) return;

    setState(() {
      _syncStatus = SyncStatus.pushing;
      _animationController.repeat();
    });

    try {
      final deltaSync = ref.read(deltaSyncProvider);
      final result = await deltaSync.pushDeltaChanges();

      if (mounted) {
        setState(() {
          _lastSyncTime = DateTime.now();
          _syncStatus = SyncStatus.idle;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.cloud_done, color: Colors.white),
                    const SizedBox(width: 8),
                    const Text(
                      '✅ تم سحب التغييرات بنجاح!',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '⬇️ استُلِم: $pulledCount ${conflictsResolved > 0 ? '  ⚖️ تعارضات محلولة: $conflictsResolved' : ''}',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ خطأ في سحب التغييرات: $e');

      // ✅ تسجيل فشل العملية
      stopwatch.stop();
      await syncLogDao.logSync(
        syncId: syncId,
        direction: 'pull',
        deviceId: deviceId,
        target: 'Appwrite',
        status: 'failed',
        errorMessage: e.toString(),
        durationMs: stopwatch.elapsedMilliseconds,
      );

        if (mounted) {
          _showSuccessSnackBar(result);
        }
      }
    } finally {
      _pullAnimationController.stop();
      _pullAnimationController.reset();
      if (mounted) {
        _showErrorSnackBar(e.toString());
      }
      setState(() => _syncStatus = SyncStatus.idle);
    } finally {
      _animationController.stop();
      _animationController.reset();
    }
  }

  /// رفع التغييرات المحلية (Push فقط)
  Future<void> _pushChanges(BuildContext context) async {
    final stopwatch = Stopwatch()..start();
    final syncId = 'push_${DateTime.now().millisecondsSinceEpoch}';
    String? deviceId;
    try {
      deviceId = await _getDeviceId();
    } catch (e) {
      deviceId = 'unknown';
    }

    // تسجيل بداية العملية
    final db = ref.read(databaseProvider);
    final syncLogDao = SyncLogDao(db);
    await syncLogDao.logSync(
      syncId: syncId,
      direction: 'push',
      deviceId: deviceId,
      target: 'Appwrite+GoogleDrive',
      status: 'in_progress',
    );
    if (_isPushing) return;

    if (_pendingChangesCount == 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.cloud_done, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text(
                  '✅ تم المزامنة بنجاح!',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    _pushAnimationController.repeat();
    if (mounted) {
      setState(() => _isPushing = true);
    } else {
      _isPushing = true;
    }

    try {
      final smartSyncManager = ref.read(smartSyncManagerProvider);
      final appwriteSyncManager = ref.read(appwriteSyncManagerProvider);

      final smartEnabled = await smartSyncManager.isEnabled();
      final isGoogleDriveSignedIn = ref.read(
        smartSyncGoogleDriveSignInStatusProvider,
      );
      final appwriteEnabled = await _isAppwriteSyncEnabled();

  @override
  Widget build(BuildContext context) {
    final pendingCountAsync = ref.watch(pendingChangesCountProvider);

    return Container(
      padding: EdgeInsets.all(16),
      margin: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 📊 Pending Count Badge
          pendingCountAsync.when(
            data: (count) => AnimatedContainer(
              duration: Duration(milliseconds: 400),
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: count > 0 
                    ? Color.lerp(Colors.orange.shade100, Colors.red.shade100, count / 50)
                    : Colors.green.shade100,
                borderRadius: BorderRadius.circular(25),
                border: Border.all(
                  color: count > 0 ? Colors.orange.shade400 : Colors.green.shade400,
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (count > 0 ? Colors.orange : Colors.green).withOpacity(0.3),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      bool appwriteConnected = false;
      if (appwriteEnabled) {
        await ref.read(connectionStatusProvider.notifier).checkConnection();
        appwriteConnected = ref.read(connectionStatusProvider).isConnected;
      }

      final targets = <String>[];
      if (smartEnabled && isGoogleDriveSignedIn) targets.add('Google Drive');
      if (appwriteEnabled && appwriteConnected) targets.add('Appwrite');

      if (targets.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('لا توجد وجهات مزامنة متاحة حالياً'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '⬆️ جاري رفع التغييرات إلى ${targets.join(' + ')}...',
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 5),
          ),
        );
      }

      final results = <String, Map<String, dynamic>>{};

      // رفع إلى Appwrite أولاً
      if (appwriteEnabled && appwriteConnected) {
        try {
          final deltaSync = AppwriteDeltaSync.instance;
          if (deltaSync.isInitialized) {
            final pushResult = await deltaSync.pushDeltaChanges();
            final pushedCount = pushResult.recordsPushed;

            results['Appwrite'] = {
              'success': pushResult.success,
              'pushed': pushedCount,
            };
          } else {
            final result = await appwriteSyncManager.pushLocalChanges();
            results['Appwrite'] = {
              'success': result,
              'pushed': _pendingChangesCount,
            };
          }
        } catch (e) {
          results['Appwrite'] = {
            'success': false,
            'pushed': 0,
            'error': e.toString(),
          };
          debugPrint('❌ خطأ في رفع التغييرات إلى Appwrite: $e');
        }
      }

      // رفع إلى Google Drive (بدون سحب - نسخ احتياطي فقط)
      if (smartEnabled && isGoogleDriveSignedIn) {
        try {
          final result = await smartSyncManager.pushLocalChanges();
          results['Google Drive'] = {
            'success': result,
            'pushed': _pendingChangesCount,
          };
        } catch (e) {
          results['Google Drive'] = {
            'success': false,
            'pushed': 0,
            'error': e.toString(),
          };
          debugPrint('❌ خطأ في رفع التغييرات إلى Google Drive: $e');
        }
      }

      await _loadPendingChangesCount();

      // حساب الإحصائيات
      int totalPushed = 0;
      final successTargets = <String>[];
      final failedTargets = <String>[];

      for (final entry in results.entries) {
        final data = entry.value;
        if (data['success'] == true) {
          successTargets.add(entry.key);
          totalPushed += (data['pushed'] as int?) ?? 0;
        } else {
          failedTargets.add(entry.key);
        }
      }

      // ✅ تنظيف outbox بعد الرفع (إذا نجح رفع إلى أي وجهة)
      if (successTargets.isNotEmpty) {
        await _clearOutboxAfterPush();
      }

      // ✅ تسجيل نجاح العملية
      stopwatch.stop();
      await syncLogDao.logSync(
        syncId: syncId,
        direction: 'push',
        deviceId: deviceId,
        target: successTargets.join('+'),
        status: failedTargets.isEmpty ? 'success' : (successTargets.isNotEmpty ? 'partial' : 'failed'),
        recordsPushed: totalPushed,
        durationMs: stopwatch.elapsedMilliseconds,
      );

      if (mounted) {
        setState(() {
          _lastSyncTime = DateTime.now();
        });

        if (failedTargets.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    count > 0 ? Icons.pending_outlined : Icons.verified,
                    color: count > 0 ? Colors.orange.shade700 : Colors.green.shade700,
                    size: 20,
                  ),
                  SizedBox(width: 8),
                  Text(
                    count > 0 ? '$count قيد الانتظار' : '✅ محدّث',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: count > 0 ? Colors.orange.shade800 : Colors.green.shade800,
                    ),
                  ),
                  if (count > 0)
                    Container(
                      margin: EdgeInsets.only(left: 8),
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade200,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${(count / 1000).toStringAsFixed(1)}KB',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
            ),
            loading: () => Container(
              height: 40,
              width: 140,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(25),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey),
                  ),
                  SizedBox(width: 12),
                  SizedBox(
                    width: 80,
                    height: 16,
                    child: LinearProgressIndicator(
                      backgroundColor: Colors.grey.shade300,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.grey),
                    ),
                  ),
                ],
              ),
            ),
            error: (error, stack) => Container(
              height: 40,
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.red.shade100,
                borderRadius: BorderRadius.circular(25),
                border: Border.all(color: Colors.red.shade400, width: 2),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                  SizedBox(width: 8),
                  Text('خطأ في العداد', style: TextStyle(color: Colors.red.shade700)),
                ],
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
        }
      }

      ref.invalidate(smartSyncStatusProvider);
    } catch (e) {
      debugPrint('❌ فشل رفع التغييرات: $e');

      // ✅ تسجيل فشل العملية
      stopwatch.stop();
      await syncLogDao.logSync(
        syncId: syncId,
        direction: 'push',
        deviceId: deviceId,
        target: 'Appwrite+GoogleDrive',
        status: 'failed',
        errorMessage: e.toString(),
        durationMs: stopwatch.elapsedMilliseconds,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.white),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'تعذر رفع التغييرات. تحقق من الاتصال وبيانات الدخول',
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
            action: SnackBarAction(
              label: 'إعادة',
              textColor: Colors.white,
              onPressed: () => _pushChanges(context),
            ),
          ),
        );
      }
    } finally {
      _pushAnimationController.stop();
      _pushAnimationController.reset();
      if (mounted) {
        setState(() => _isPushing = false);
      }
    }
  }

  /// حل التعارضات بين البيانات المحلية والبعيدة
  Future<int> _resolveConflicts() async {
    int resolvedCount = 0;
    try {
      final db = ref.read(databaseProvider);
      final outboxDao = OutboxDao(db);

      final conflicts = await outboxDao.getConflicts();

      if (conflicts.isEmpty) return 0;

      final resolver = ConflictResolver(
        deviceId: await _getDeviceId(),
        strategy: ConflictStrategy.newerWins,
      );

      for (final conflict in conflicts) {
        try {
          final localData = conflict.localPayload;
          final remoteData = conflict.remotePayload;

          final localMap = <String, Map<String, dynamic>>{
            conflict.targetTable: {conflict.uuid: localData},
          };
          final remoteMap = <String, Map<String, dynamic>>{
            conflict.targetTable: {conflict.uuid: remoteData},
          };

          final dataConflicts = await resolver.detectConflicts(localMap, remoteMap);

          if (dataConflicts.isNotEmpty) {
            final resolved = await resolver.resolveConflicts(dataConflicts);

            final winnerData = resolved[conflict.targetTable]?[conflict.uuid];
            if (winnerData != null) {
              await outboxDao.resolveConflict(
                conflict.id,
                winnerData,
                resolution: 'newer_wins',
              );
              resolvedCount++;
            }
          } else {
            await outboxDao.resolveConflict(
              conflict.id,
              localData,
              resolution: 'auto_no_conflict',
            );
          }
        } catch (e) {
          debugPrint('❌ خطأ في حل تعارض ${conflict.uuid}: $e');
        }
      }

      debugPrint('✅ تم حل $resolvedCount تعارض');
      return resolvedCount;
    } catch (e) {
      debugPrint('❌ خطأ في حل التعارضات: $e');
      return 0;
    }
  }

  /// الحصول على معرف الجهاز
  Future<String> _getDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var deviceId = prefs.getString('device_id');
      if (deviceId == null) {
        deviceId = 'device_${DateTime.now().millisecondsSinceEpoch}';
        await prefs.setString('device_id', deviceId);
      }
      return deviceId;
    } catch (e) {
      return 'unknown_device';
    }
  }

  String _formatLastSyncTime(DateTime? lastSync) {
    if (lastSync == null) return '';

    final now = DateTime.now();
    final difference = now.difference(lastSync);

    if (difference.inSeconds < 60) {
      return 'منذ ${difference.inSeconds} ثانية';
    } else if (difference.inMinutes < 60) {
      return 'منذ ${difference.inMinutes} دقيقة';
    } else if (difference.inHours < 24) {
      return 'منذ ${difference.inHours} ساعة';
    } else {
      return 'منذ ${difference.inDays} يوم';
    }
  }

  // ✅ تحسين: إضافة معامل pendingCount لعرض عدد التغييرات
  Widget _buildPullButton(bool hasRemoteChanges, bool isGoogleDriveSignedIn, int pendingCount) {
    // زر السحب متاح فقط إذا كان يوجد تغييرات جديدة في Appwrite
    final bool pullEnabled = hasRemoteChanges && _appwriteEnabled && !_isPulling && !_isPushing;

    Color buttonColor;
    IconData buttonIcon;
    String buttonText;

    if (_isPulling) {
      buttonColor = Colors.blue;
      buttonIcon = Icons.cloud_download;
      buttonText = 'جاري السحب...';
    } else if (hasRemoteChanges) {
      buttonColor = Colors.blue;
      buttonIcon = Icons.cloud_download;
      buttonText = 'سحب التغييرات';
    } else {
      buttonColor = Colors.grey.shade400;
      buttonIcon = Icons.cloud_download;
      buttonText = 'لا توجد تحديثات';
    }

    return Tooltip(
      message: hasRemoteChanges
          ? 'اضغط لسحب التغييرات الجديدة من السيرفر'
          : 'لا توجد تغييرات جديدة في السحابة',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [buttonColor.withOpacity(0.85), buttonColor],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: buttonColor.withOpacity(pullEnabled ? 0.4 : 0.1),
                  blurRadius: pullEnabled ? 8 : 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: pullEnabled
                    ? () => _pullChanges(context)
                    : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Pulsing ring for pending items
                      if (pendingCountAsyncValue > 0)
                        AnimatedContainer(
                          duration: Duration(milliseconds: 1500),
                          width: _syncStatus == SyncStatus.pushing ? 0 : 76,
                          height: _syncStatus == SyncStatus.pushing ? 0 : 76,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.orange.withOpacity(0.6),
                              width: 3,
                            ),
                          ),
                        ),
                      
                      // Main icon
                      Transform.rotate(
                        angle: _syncStatus == SyncStatus.pushing 
                            ? _rotationAnimation.value * 2 * pi 
                            : 0,
                        child: Icon(
                          _syncStatus == SyncStatus.pushing 
                              ? Icons.sync 
                              : Icons.cloud_upload,
                          size: 32,
                          color: Colors.white,
                          shadows: [
                            Shadow(
                              color: Colors.black26,
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                      
                      // Success dot
                      if (_syncStatus == SyncStatus.pushing)
                        Positioned(
                          bottom: 6,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.9),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.white.withOpacity(0.5),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          
          SizedBox(height: 12),
          
          // ⏰ Last Sync Time
          if (_lastSyncTime != null) ...[
            Text(
              'آخر تحديث: ${_formatRelativeTime(_lastSyncTime!)}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }

  Widget _buildPushButton(bool hasChanges, bool isGoogleDriveSignedIn) {
    // زر الدفع متاح فقط إذا كان يوجد تغييرات محلية
    final bool pushEnabled = hasChanges && !_isPulling && !_isPushing;

    Color buttonColor;
    IconData buttonIcon;
    String buttonText;

    if (_isPushing) {
      buttonColor = Colors.purple;
      buttonIcon = Icons.cloud_upload;
      buttonText = 'جاري الرفع...';
    } else if (hasChanges) {
      buttonColor = Colors.purple;
      buttonIcon = Icons.cloud_upload;
      buttonText = 'رفع التغييرات';
    } else {
      buttonColor = Colors.grey.shade400;
      buttonIcon = Icons.cloud_done;
      buttonText = 'محدّث';
    }

    return Tooltip(
      message: hasChanges
          ? 'اضغط لرفع $_pendingChangesCount تغيير إلى السحابة'
          : 'جميع التغييرات مرفوعة',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [buttonColor.withOpacity(0.85), buttonColor],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: buttonColor.withOpacity(pushEnabled ? 0.4 : 0.1),
                  blurRadius: pushEnabled ? 8 : 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _formatExactTime(_lastSyncTime!),
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.green.shade800,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
          
          SizedBox(height: 8),
          
          // 📱 Auto-sync indicator
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.autorenew, size: 14, color: Colors.grey.shade500),
              SizedBox(width: 4),
              Text(
                'مزامنة تلقائية كل 5د',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ],
          ),
        ],
      ),
    );
  }

  LinearGradient _getButtonGradient(int pendingCount) {
    if (_syncStatus == SyncStatus.pushing) {
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.blue.shade400,
          Colors.blue.shade600,
          Colors.indigo.shade700,
        ],
      );
    }
    
    if (pendingCount > 0) {
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.orange.shade400,
          Colors.orange.shade500,
          Colors.deepOrange.shade600,
        ],
      );
    }
    
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Colors.green.shade400,
        Colors.green.shade500,
        Colors.teal.shade600,
      ],
    );
  }

  Color _getButtonColor(int pendingCount) {
    if (_syncStatus == SyncStatus.pushing) return Colors.blue.shade500;
    if (pendingCount > 0) return Colors.orange.shade500;
    return Colors.green.shade500;
  }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                // صف الأزرار: زر السحب + زر الدفع
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // زر السحب من السيرفر - ✅ تحديث: تمرير عداد التغييرات
                    _buildPullButton(hasRemoteChanges, isGoogleDriveSignedIn, pendingRemoteCount),
                    const SizedBox(width: 8),
                    // زر الدفع إلى السيرفر
                    _buildPushButton(hasLocalChanges, isGoogleDriveSignedIn),
                  ],
                ),
                const SizedBox(height: 6),
                // شريط الحالة
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _isPulling || _isPushing
                        ? Colors.blue.shade50
                        : (hasLocalChanges || hasRemoteChanges)
                            ? Colors.orange.shade50
                            : Colors.green.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _isPulling || _isPushing
                          ? Colors.blue.shade200
                          : (hasLocalChanges || hasRemoteChanges)
                              ? Colors.orange.shade200
                              : Colors.green.shade200,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        hasLocalChanges || hasRemoteChanges
                            ? Icons.sync_problem
                            : (_isPulling || _isPushing ? Icons.sync : Icons.check_circle),
                        size: 12,
                        color: _isPulling || _isPushing
                            ? Colors.blue
                            : (hasLocalChanges || hasRemoteChanges)
                                ? Colors.orange
                                : Colors.green,
                      ),
                      const SizedBox(width: 5),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _isPulling
                                ? 'جاري السحب...'
                                : _isPushing
                                    ? 'جاري الرفع...'
                                    : hasLocalChanges
                                        ? '$_pendingChangesCount تغيير محلي معلق'
                                        : hasRemoteChanges
                                            ? '$pendingRemoteCount تحديث من السيرفر'
                                            : 'محدّث',
                            style: TextStyle(
                              fontSize: 11,
                              color: _isPulling || _isPushing
                                  ? Colors.blue.shade900
                                  : (hasLocalChanges || hasRemoteChanges)
                                      ? Colors.orange.shade900
                                      : Colors.green.shade900,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (!_isPulling && !_isPushing && _lastSyncTime != null)
                            Text(
                              _formatLastSyncTime(_lastSyncTime),
                              style: TextStyle(
                                fontSize: 8,
                                color: Colors.grey.shade600,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
