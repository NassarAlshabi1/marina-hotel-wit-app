import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/appwrite_providers.dart';
import '../providers/repository_providers.dart';
import '../services/daos/outbox_dao.dart';
import '../services/daos/sync_log_dao.dart';
import '../services/appwrite_delta_sync.dart';
import '../services/appwrite_realtime_sync.dart';
import '../services/sync_core/conflict_resolver.dart';

class DashboardSyncButton extends ConsumerStatefulWidget {
  const DashboardSyncButton({super.key});

  @override
  ConsumerState<DashboardSyncButton> createState() =>
      _DashboardSyncButtonState();
}

class _DashboardSyncButtonState extends ConsumerState<DashboardSyncButton>
    with SingleTickerProviderStateMixin {
  bool _isPulling = false;
  bool _isPushing = false;
  bool _appwriteEnabled = true;
  Timer? _pendingChangesTimer;
  late AnimationController _pullAnimationController;
  late AnimationController _pushAnimationController;
  int _pendingChangesCount = 0;
  DateTime? _lastSyncTime;
  
  // كاش للبيانات الثابتة
  String? _cachedDeviceId;
  SharedPreferences? _prefs;
  DateTime? _lastPushClick;
  static const _debounceMs = 300;

  @override
  void initState() {
    super.initState();
    _pullAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _pushAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _initCache();
    _loadPendingChangesCount();

    _pendingChangesTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted && !_isPulling && !_isPushing) {
        _loadPendingChangesCount();
      }
    });
  }

  Future<void> _initCache() async {
    _prefs = await SharedPreferences.getInstance();
    _cachedDeviceId = _prefs?.getString('device_id');
    if (_cachedDeviceId == null) {
      _cachedDeviceId = 'device_${DateTime.now().millisecondsSinceEpoch}';
      await _prefs?.setString('device_id', _cachedDeviceId!);
    }
    _appwriteEnabled = _prefs?.getBool('appwrite_sync_enabled') ?? true;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _pendingChangesTimer?.cancel();
    _pullAnimationController.dispose();
    _pushAnimationController.dispose();
    super.dispose();
  }

  Future<void> _loadPendingChangesCount() async {
    try {
      final db = ref.read(databaseProvider);
      final count = await OutboxDao(db).count();
      if (mounted) setState(() => _pendingChangesCount = count);
    } catch (e) {
      debugPrint('❌ خطأ في تحميل عدد التغييرات: $e');
    }
  }

  bool get _isAppwriteSyncEnabled => 
    _prefs?.getBool('appwrite_sync_enabled') ?? false;

  /// سحب التغييرات من Appwrite (Pull فقط)
  Future<void> _pullChanges(BuildContext context) async {
    if (_isPulling) return;

    final stopwatch = Stopwatch()..start();
    final syncId = 'pull_${DateTime.now().millisecondsSinceEpoch}';
    final deviceId = _cachedDeviceId ?? 'unknown';
    final db = ref.read(databaseProvider);
    final syncLogDao = SyncLogDao(db);

    unawaited(syncLogDao.logSync(
      syncId: syncId,
      direction: 'pull',
      deviceId: deviceId,
      target: 'Appwrite',
      status: 'in_progress',
    ));

    _pullAnimationController.repeat();
    if (mounted) setState(() => _isPulling = true);

    try {
      if (!_isAppwriteSyncEnabled) {
        _showSnack('مزامنة Appwrite معطلة', Colors.orange);
        return;
      }

      final connState = ref.read(connectionStatusProvider);
      if (!connState.isConnected) {
        await ref.read(connectionStatusProvider.notifier).checkConnection();
        if (!ref.read(connectionStatusProvider).isConnected) {
          _showSnack('لا يوجد اتصال', Colors.red);
          return;
        }
      }

      _showLoading('⬇️ جاري السحب...');

      final deltaSync = AppwriteDeltaSync.instance;
      if (!deltaSync.isInitialized) {
        final appwriteService = ref.read(appwriteServiceProvider);
        await deltaSync.initialize(appwriteService, db);
      }

      final pullResult = await deltaSync.pullDeltaChanges();
      final pulledCount = pullResult.recordsPulled;

      // تنظيف Outbox بعد السحب
      if (pulledCount > 0) {
        unawaited(OutboxDao(db).removeAllPending());
      }

      int conflictsResolved = 0;
      if (pullResult.hasConflicts) {
        conflictsResolved = await _resolveConflicts();
      }

      AppwriteRealtimeSync().resetRemoteChangesFlag();

      stopwatch.stop();
      unawaited(syncLogDao.logSync(
        syncId: syncId,
        direction: 'pull',
        deviceId: deviceId,
        target: 'Appwrite',
        status: 'success',
        recordsPulled: pulledCount,
        durationMs: stopwatch.elapsedMilliseconds,
      ));

      if (mounted) {
        setState(() => _lastSyncTime = DateTime.now());
        _showSuccess('✅ تم السحب', '⬇️ $pulledCount سجل ${conflictsResolved > 0 ? '⚖️ $conflictsResolved' : ''}');
      }
    } catch (e) {
      debugPrint('❌ خطأ في السحب: $e');
      stopwatch.stop();
      unawaited(syncLogDao.logSync(
        syncId: syncId,
        direction: 'pull',
        deviceId: deviceId,
        target: 'Appwrite',
        status: 'failed',
        errorMessage: e.toString(),
        durationMs: stopwatch.elapsedMilliseconds,
      ));
      _showSnack('خطأ في السحب', Colors.red);
    } finally {
      _pullAnimationController.stop();
      _pullAnimationController.reset();
      await _loadPendingChangesCount();
      if (mounted) setState(() => _isPulling = false);
    }
  }

  /// رفع التغييرات المحلية (Push) مع تنظيف Outbox
  Future<void> _pushChanges(BuildContext context) async {
    final now = DateTime.now();
    if (_lastPushClick != null && 
        now.difference(_lastPushClick!).inMilliseconds < _debounceMs) {
      return;
    }
    _lastPushClick = now;
    
    if (_isPushing) return;
    if (_pendingChangesCount == 0) {
      _showSnack('لا توجد تغييرات', Colors.green);
      return;
    }

    if (!_isAppwriteSyncEnabled) {
      _showSnack('المزامنة معطلة', Colors.orange);
      return;
    }

    final stopwatch = Stopwatch()..start();
    final syncId = 'push_${now.millisecondsSinceEpoch}';
    final deviceId = _cachedDeviceId ?? 'unknown';
    final db = ref.read(databaseProvider);

    _pushAnimationController.repeat();
    if (mounted) setState(() => _isPushing = true);

    try {
      final connState = ref.read(connectionStatusProvider);
      if (!connState.isConnected) {
        await ref.read(connectionStatusProvider.notifier).checkConnection();
        if (!ref.read(connectionStatusProvider).isConnected) {
          _showSnack('لا يوجد اتصال', Colors.red);
          return;
        }
      }

      _showLoading('⬆️ جاري الرفع...');

      final deltaSync = AppwriteDeltaSync.instance;
      if (!deltaSync.isInitialized) {
        final appwriteService = ref.read(appwriteServiceProvider);
        await deltaSync.initialize(appwriteService, db);
      }

      final result = await deltaSync.pushDeltaChanges();

      // ✅ تنظيف Outbox فوراً بعد النجاح
      if (result.success && result.recordsPushed > 0) {
        final outboxDao = OutboxDao(db);
        final cleanedCount = await outboxDao.removeAllPending();
        debugPrint('🧹 تم تنظيف Outbox: $cleanedCount سجل');
        
        if (mounted) {
          setState(() => _pendingChangesCount = 0);
        }
      } else {
        await _loadPendingChangesCount();
      }

      stopwatch.stop();
      unawaited(_logSync(
        syncId: syncId,
        deviceId: deviceId,
        success: result.success,
        pushed: result.recordsPushed,
        duration: stopwatch.elapsedMilliseconds,
      ));

      if (mounted) {
        setState(() => _lastSyncTime = DateTime.now());
        if (result.success) {
          _showSuccess('✅ تم الرفع والتنظيف', '⬆️ ${result.recordsPushed} سجل');
        } else {
          _showSnack('فشل الرفع', Colors.red);
        }
      }

      ref.invalidate(smartSyncStatusProvider);
    } catch (e) {
      debugPrint('❌ خطأ: $e');
      stopwatch.stop();
      unawaited(_logSync(
        syncId: syncId,
        deviceId: deviceId,
        success: false,
        error: e.toString(),
        duration: stopwatch.elapsedMilliseconds,
      ));
      _showSnack('خطأ في الرفع', Colors.red);
    } finally {
      _pushAnimationController.stop();
      _pushAnimationController.reset();
      if (mounted) setState(() => _isPushing = false);
    }
  }

  Future<void> _logSync({
    required String syncId,
    required String deviceId,
    required bool success,
    int? pushed,
    String? error,
    required int duration,
  }) async {
    try {
      final db = ref.read(databaseProvider);
      await SyncLogDao(db).logSync(
        syncId: syncId,
        direction: 'push',
        deviceId: deviceId,
        target: 'Appwrite',
        status: success ? 'success' : 'failed',
        recordsPushed: pushed,
        errorMessage: error,
        durationMs: duration,
      );
    } catch (e) {
      debugPrint('❌ خطأ في التسجيل: $e');
    }
  }

  Future<int> _resolveConflicts() async {
    int resolvedCount = 0;
    try {
      final db = ref.read(databaseProvider);
      final outboxDao = OutboxDao(db);
      final conflicts = await outboxDao.getConflicts();

      if (conflicts.isEmpty) return 0;

      final resolver = ConflictResolver(
        deviceId: _cachedDeviceId ?? 'unknown',
        strategy: ConflictStrategy.newerWins,
      );

      for (final conflict in conflicts) {
        try {
          final localMap = <String, Map<String, dynamic>>{
            conflict.targetTable: {conflict.uuid: conflict.localPayload},
          };
          final remoteMap = <String, Map<String, dynamic>>{
            conflict.targetTable: {conflict.uuid: conflict.remotePayload},
          };

          final dataConflicts = await resolver.detectConflicts(localMap, remoteMap);

          if (dataConflicts.isNotEmpty) {
            final resolved = await resolver.resolveConflicts(dataConflicts);
            final winnerData = resolved[conflict.targetTable]?[conflict.uuid];
            if (winnerData != null) {
              await outboxDao.resolveConflict(conflict.id, winnerData, resolution: 'newer_wins');
              resolvedCount++;
            }
          } else {
            await outboxDao.resolveConflict(conflict.id, conflict.localPayload, resolution: 'auto_no_conflict');
          }
        } catch (e) {
          debugPrint('❌ خطأ في حل تعارض ${conflict.uuid}: $e');
        }
      }
      return resolvedCount;
    } catch (e) {
      debugPrint('❌ خطأ في حل التعارضات: $e');
      return 0;
    }
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showLoading(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            const SizedBox(width: 12),
            Text(msg),
          ],
        ),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 10),
      ),
    );
  }

  void _showSuccess(String title, String subtitle) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(subtitle, style: const TextStyle(fontSize: 12)),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _formatLastSyncTime(DateTime? lastSync) {
    if (lastSync == null) return '';
    final diff = DateTime.now().difference(lastSync);
    if (diff.inSeconds < 60) return 'منذ ${diff.inSeconds}ث';
    if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes}د';
    if (diff.inHours < 24) return 'منذ ${diff.inHours}س';
    return 'منذ ${diff.inDays}ي';
  }

  Widget _buildPullButton(bool hasRemoteChanges, int pendingCount) {
    final enabled = hasRemoteChanges && _appwriteEnabled && !_isPulling && !_isPushing;

    return Tooltip(
      message: hasRemoteChanges ? 'سحب $pendingCount تغيير' : 'لا توجد تحديثات',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  enabled ? Colors.blue.withOpacity(0.85) : Colors.grey.shade400,
                  enabled ? Colors.blue : Colors.grey.shade500,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: enabled ? Colors.blue.withOpacity(0.4) : Colors.transparent,
                  blurRadius: enabled ? 8 : 0,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: enabled ? () => _pullChanges(context) : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isPulling)
                        RotationTransition(
                          turns: _pullAnimationController,
                          child: const Icon(Icons.cloud_download, size: 16, color: Colors.white),
                        )
                      else
                        Icon(
                          hasRemoteChanges ? Icons.cloud_download : Icons.cloud_done,
                          size: 16,
                          color: Colors.white,
                        ),
                      const SizedBox(width: 6),
                      Text(
                        _isPulling ? 'جاري السحب...' : (hasRemoteChanges ? 'سحب' : 'لا جديد'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (hasRemoteChanges && !_isPulling && pendingCount > 0)
            Positioned(
              top: -8,
              right: -8,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.blue,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                child: Center(
                  child: Text(
                    pendingCount > 99 ? '99+' : '$pendingCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPushButton(bool hasChanges) {
    final enabled = hasChanges && !_isPulling && !_isPushing;

    return Tooltip(
      message: hasChanges ? 'رفع $_pendingChangesCount تغيير' : 'لا توجد تغييرات',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  enabled ? Colors.purple.withOpacity(0.85) : Colors.grey.shade400,
                  enabled ? Colors.purple : Colors.grey.shade500,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: enabled ? Colors.purple.withOpacity(0.4) : Colors.transparent,
                  blurRadius: enabled ? 8 : 0,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: enabled ? () => _pushChanges(context) : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isPushing)
                        RotationTransition(
                          turns: _pushAnimationController,
                          child: const Icon(Icons.cloud_upload, size: 16, color: Colors.white),
                        )
                      else
                        Icon(
                          hasChanges ? Icons.cloud_upload : Icons.cloud_done,
                          size: 16,
                          color: Colors.white,
                        ),
                      const SizedBox(width: 6),
                      Text(
                        _isPushing ? 'جاري الرفع...' : (hasChanges ? 'رفع' : 'محدّث'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (hasChanges && !_isPushing)
            Positioned(
              top: -8,
              right: -8,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                child: Center(
                  child: Text(
                    _pendingChangesCount > 99 ? '99+' : '$_pendingChangesCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppwriteRealtimeSync().hasRemoteChanges,
      builder: (context, hasRemoteChanges, child) {
        return ValueListenableBuilder<int>(
          valueListenable: AppwriteRealtimeSync().pendingRemoteChangesCount,
          builder: (context, pendingRemoteCount, child) {
            final hasLocalChanges = _pendingChangesCount > 0;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildPullButton(hasRemoteChanges, pendingRemoteCount),
                    const SizedBox(width: 8),
                    _buildPushButton(hasLocalChanges),
                  ],
                ),
                const SizedBox(height: 6),
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
                                        ? '$_pendingChangesCount تغيير محلي'
                                        : hasRemoteChanges
                                            ? '$pendingRemoteCount تحديث'
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
