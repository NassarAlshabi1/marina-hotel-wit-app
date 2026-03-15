# 🔄 Dashboard Sync Button - النسخة الموحدة المحسّنة

> **زر مزامنة تفاضلية واحد** يجمع أفضل المميزات من جميع الفروع

## 📋 المميزات المدمجة

| الميزة | المصدر |
|--------|--------|
| StateNotifier + Retry + Progress | `feature/sync-reports-improvements` |
| pushDeltaChanges + تنظيف Outbox | `sync-outbox-fix` |
| Conflict Stream | `feature/unified-conflict-resolution` |

---

## 📄 الكود الكامل

```dart
// ═══════════════════════════════════════════════════════════════════════════
// 🔄 DASHBOARD SYNC BUTTON - زر المزامنة التفاضلية الموحد
// ═══════════════════════════════════════════════════════════════════════════

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
import '../services/unified_conflict_resolver.dart';

// ═══════════════════════════════════════════════════════════════════════════
// 1. MODELS
// ═══════════════════════════════════════════════════════════════════════════

/// نموذج تقدم المزامنة
class SyncProgress {
  const SyncProgress({
    this.currentOperation = '',
    this.processedCount = 0,
    this.totalCount = 0,
    this.successCount = 0,
    this.errorCount = 0,
    this.startTime,
  });

  final String currentOperation;
  final int processedCount;
  final int totalCount;
  final int successCount;
  final int errorCount;
  final DateTime? startTime;

  double get progressPercent =>
      totalCount > 0 ? processedCount / totalCount : 0.0;

  String get progressText => totalCount > 0 
      ? '$processedCount / $totalCount' 
      : (processedCount > 0 ? '$processedCount' : '');

  Duration get elapsed => startTime != null
      ? DateTime.now().difference(startTime!)
      : Duration.zero;

  SyncProgress copyWith({
    String? currentOperation,
    int? processedCount,
    int? totalCount,
    int? successCount,
    int? errorCount,
    DateTime? startTime,
  }) {
    return SyncProgress(
      currentOperation: currentOperation ?? this.currentOperation,
      processedCount: processedCount ?? this.processedCount,
      totalCount: totalCount ?? this.totalCount,
      successCount: successCount ?? this.successCount,
      errorCount: errorCount ?? this.errorCount,
      startTime: startTime ?? this.startTime,
    );
  }
}

/// حالة المزامنة - مصدر واحد للحقيقة
class SyncState {
  const SyncState({
    this.isSyncing = false,
    this.pendingChangesCount = 0,
    this.hasRemoteChanges = false,
    this.pendingRemoteChangesCount = 0,
    this.pendingConflictsCount = 0,
    this.lastSyncTime,
    this.errorMessage,
    this.progress = const SyncProgress(),
  });

  final bool isSyncing;
  final int pendingChangesCount;
  final bool hasRemoteChanges;
  final int pendingRemoteChangesCount;
  final int pendingConflictsCount;
  final DateTime? lastSyncTime;
  final String? errorMessage;
  final SyncProgress progress;

  bool get hasPendingChanges => pendingChangesCount > 0 || hasRemoteChanges;

  SyncState copyWith({
    bool? isSyncing,
    int? pendingChangesCount,
    bool? hasRemoteChanges,
    int? pendingRemoteChangesCount,
    int? pendingConflictsCount,
    DateTime? lastSyncTime,
    String? errorMessage,
    SyncProgress? progress,
  }) {
    return SyncState(
      isSyncing: isSyncing ?? this.isSyncing,
      pendingChangesCount: pendingChangesCount ?? this.pendingChangesCount,
      hasRemoteChanges: hasRemoteChanges ?? this.hasRemoteChanges,
      pendingRemoteChangesCount:
          pendingRemoteChangesCount ?? this.pendingRemoteChangesCount,
      pendingConflictsCount:
          pendingConflictsCount ?? this.pendingConflictsCount,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      errorMessage: errorMessage,
      progress: progress ?? this.progress,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 2. STATE NOTIFIER
// ═══════════════════════════════════════════════════════════════════════════

class SyncStateNotifier extends StateNotifier<SyncState> {
  SyncStateNotifier(this.ref) : super(const SyncState()) {
    _init();
  }

  final Ref ref;
  StreamSubscription<int>? _outboxSubscription;
  StreamSubscription<List<UnifiedConflictRecord>>? _conflictSubscription;
  Timer? _remoteChangesTimer;

  void _init() {
    _setupOutboxWatcher();
    _setupRemoteChangesWatcher();
    _setupConflictWatcher();
    _loadSyncStats();
  }

  void _setupOutboxWatcher() {
    try {
      final db = ref.read(databaseProvider);
      final outboxDao = OutboxDao(db);
      _outboxSubscription = outboxDao.watchCount().listen((count) {
        state = state.copyWith(pendingChangesCount: count);
      });
    } catch (e) {
      debugPrint('❌ خطأ في مراقب Outbox: $e');
    }
  }

  void _setupRemoteChangesWatcher() {
    _remoteChangesTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      try {
        final hasRemote = AppwriteRealtimeSync().hasRemoteChanges.value;
        final remoteCount = AppwriteRealtimeSync().pendingRemoteChangesCount.value;
        if (state.hasRemoteChanges != hasRemote ||
            state.pendingRemoteChangesCount != remoteCount) {
          state = state.copyWith(
            hasRemoteChanges: hasRemote,
            pendingRemoteChangesCount: remoteCount,
          );
        }
      } catch (e) {
        // تجاهل الأخطاء
      }
    });
  }

  void _setupConflictWatcher() {
    try {
      _conflictSubscription =
          UnifiedConflictResolver.instance.conflictsStream.listen((conflicts) {
        state = state.copyWith(pendingConflictsCount: conflicts.length);
      });
    } catch (e) {
      debugPrint('⚠️ مراقب التعارضات غير متاح: $e');
    }
  }

  Future<void> _loadSyncStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastSyncMs = prefs.getInt('last_sync_time');
      state = state.copyWith(
        lastSyncTime: lastSyncMs != null
            ? DateTime.fromMillisecondsSinceEpoch(lastSyncMs)
            : null,
      );
    } catch (e) {
      debugPrint('❌ خطأ في تحميل الإحصائيات: $e');
    }
  }

  void setSyncing(bool value, {SyncProgress? progress}) {
    state = state.copyWith(
      isSyncing: value,
      progress: progress ?? (value ? SyncProgress(startTime: DateTime.now()) : const SyncProgress()),
    );
  }

  void updateProgress(SyncProgress progress) {
    state = state.copyWith(progress: progress);
  }

  Future<void> setLastSyncTime(DateTime? time) async {
    state = state.copyWith(lastSyncTime: time);
    if (time != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('last_sync_time', time.millisecondsSinceEpoch);
      } catch (e) {
        debugPrint('⚠️ فشل حفظ وقت المزامنة: $e');
      }
    }
  }

  void setError(String? error) {
    state = state.copyWith(errorMessage: error);
  }

  @override
  void dispose() {
    _outboxSubscription?.cancel();
    _conflictSubscription?.cancel();
    _remoteChangesTimer?.cancel();
    super.dispose();
  }
}

/// Provider لموحد حالة المزامنة
final syncStateProvider =
    StateNotifierProvider<SyncStateNotifier, SyncState>((ref) {
  return SyncStateNotifier(ref);
});

// ═══════════════════════════════════════════════════════════════════════════
// 3. MAIN WIDGET
// ═══════════════════════════════════════════════════════════════════════════

class DashboardSyncButton extends ConsumerStatefulWidget {
  const DashboardSyncButton({super.key});

  @override
  ConsumerState<DashboardSyncButton> createState() =>
      _DashboardSyncButtonState();
}

class _DashboardSyncButtonState extends ConsumerState<DashboardSyncButton>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  AnimationController? _animationController;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _animationController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    if (lifecycleState == AppLifecycleState.resumed) {
      ref.read(syncStateProvider.notifier)._loadSyncStats();
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // دوال آمنة للAnimationController
  // ═══════════════════════════════════════════════════════════════

  void _safeStartAnimation() {
    if (_isDisposed || _animationController == null) return;
    try {
      if (mounted) _animationController!.repeat();
    } catch (e) {
      debugPrint('⚠️ Animation error: $e');
    }
  }

  void _safeStopAnimation() {
    if (_isDisposed || _animationController == null) return;
    try {
      _animationController!.stop();
      _animationController!.reset();
    } catch (e) {
      debugPrint('⚠️ Animation error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // آلية Retry ذكية
  // ═══════════════════════════════════════════════════════════════

  Future<T> _withRetry<T>(
    Future<T> Function() operation, {
    int maxRetries = 3,
    String operationName = 'عملية',
  }) async {
    int attempts = 0;
    Exception? lastError;

    while (attempts < maxRetries) {
      try {
        return await operation();
      } on Exception catch (e) {
        lastError = e;
        attempts++;
        if (attempts < maxRetries) {
          final delay = Duration(seconds: attempts * 2);
          debugPrint('⚠️ $operationName فشل (محاولة $attempts/$maxRetries): $e');
          debugPrint('⏳ إعادة المحاولة بعد ${delay.inSeconds} ثواني...');
          await Future.delayed(delay);
        }
      }
    }

    debugPrint('❌ $operationName فشل بعد $maxRetries محاولات');
    throw lastError ?? Exception('$operationName فشل لسبب غير معروف');
  }

  // ═══════════════════════════════════════════════════════════════
  // دوال مساعدة
  // ═══════════════════════════════════════════════════════════════

  Future<bool> _isAppwriteSyncEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('appwrite_sync_enabled') ?? true;
    } catch (e) {
      return true;
    }
  }

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

  Future<void> _clearOutboxAfterPush() async {
    try {
      final db = ref.read(databaseProvider);
      final outboxDao = OutboxDao(db);
      await outboxDao.removeAllPending();
      debugPrint('✅ تم تنظيف outbox بنجاح');
    } catch (e) {
      debugPrint('⚠️ فشل تنظيف outbox: $e');
    }
  }

  Future<bool> _ensureDeltaSyncInitialized() async {
    final deltaSync = AppwriteDeltaSync.instance;
    if (!deltaSync.isInitialized) {
      try {
        final appwriteService = ref.read(appwriteServiceProvider);
        final db = ref.read(databaseProvider);
        await deltaSync.initialize(appwriteService, db);
        debugPrint('✅ تم تهيئة AppwriteDeltaSync بنجاح');
        return true;
      } catch (e) {
        debugPrint('❌ فشل تهيئة AppwriteDeltaSync: $e');
        return false;
      }
    }
    return true;
  }

  // ═══════════════════════════════════════════════════════════════
  // حل التعارضات
  // ═══════════════════════════════════════════════════════════════

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
          final localMap = <String, Map<String, dynamic>>{
            conflict.targetTable: {conflict.uuid: conflict.localPayload},
          };
          final remoteMap = <String, Map<String, dynamic>>{
            conflict.targetTable: {conflict.uuid: conflict.remotePayload},
          };

          final dataConflicts =
              await resolver.detectConflicts(localMap, remoteMap);

          if (dataConflicts.isNotEmpty) {
            final resolved = await resolver.resolveConflicts(dataConflicts);
            final winnerData = resolved[conflict.targetTable]?[conflict.uuid];
            if (winnerData != null) {
              final isRemoteWinner = winnerData == conflict.remotePayload;
              await outboxDao.resolveConflict(
                conflict.id,
                winnerData,
                resolution: isRemoteWinner ? 'remote_wins' : 'local_wins',
              );
              resolvedCount++;
              debugPrint(
                  '⚖️ حل تعارض ${conflict.targetTable}: ${isRemoteWinner ? 'السيرفر' : 'الجهاز'}');
            }
          } else {
            await outboxDao.resolveConflict(
              conflict.id,
              conflict.localPayload,
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

  // ═══════════════════════════════════════════════════════════════
  // المزامنة التفاضلية (Pull + Push)
  // ═══════════════════════════════════════════════════════════════

  Future<void> _syncDifferential(BuildContext context) async {
    final syncNotifier = ref.read(syncStateProvider.notifier);
    final syncState = ref.read(syncStateProvider);

    if (syncState.isSyncing) return;

    final stopwatch = Stopwatch()..start();
    final syncId = 'sync_${DateTime.now().millisecondsSinceEpoch}';
    final deviceId = await _getDeviceId();

    final db = ref.read(databaseProvider);
    final syncLogDao = SyncLogDao(db);
    await syncLogDao.logSync(
      syncId: syncId,
      direction: 'differential',
      deviceId: deviceId,
      target: 'Appwrite+GoogleDrive',
      status: 'in_progress',
    );

    syncNotifier.setSyncing(true);
    _safeStartAnimation();

    int pulledCount = 0;
    int pushedCount = 0;
    int conflictsResolved = 0;

    try {
      // التحقق من الاتصال
      final appwriteEnabled = await _isAppwriteSyncEnabled();
      if (!appwriteEnabled) {
        _showSnackBar(context, '⚠️ مزامنة Appwrite معطلة', Colors.orange);
        syncNotifier.setSyncing(false);
        return;
      }

      await ref.read(connectionStatusProvider.notifier).checkConnection();
      final appwriteConnected = ref.read(connectionStatusProvider).isConnected;

      if (!appwriteConnected) {
        _showSnackBar(context, '❌ لا يوجد اتصال بالسيرفر', Colors.red);
        syncNotifier.setSyncing(false);
        return;
      }

      _showSnackBar(
        context,
        '🔄 جاري المزامنة التفاضلية...',
        Colors.blue,
        showProgress: true,
      );

      // التأكد من تهيئة الخدمة
      if (!await _ensureDeltaSyncInitialized()) {
        _showSnackBar(context, '❌ خدمة المزامنة غير مهيأة', Colors.red);
        syncNotifier.setSyncing(false);
        return;
      }

      final deltaSync = AppwriteDeltaSync.instance;

      // ═══════════════════════════════════════════════════════════════
      // 1️⃣ سحب التغييرات من السيرفر (Pull)
      // ═══════════════════════════════════════════════════════════════

      syncNotifier.updateProgress(SyncProgress(
        currentOperation: 'سحب',
        startTime: DateTime.now(),
      ));

      final pullResult = await _withRetry(
        () => deltaSync.pullDeltaChanges(),
        maxRetries: 3,
        operationName: 'سحب التغييرات',
      );
      pulledCount = pullResult.recordsPulled;

      // حل التعارضات إن وجدت
      if (pullResult.hasConflicts) {
        _showSnackBar(context, '⚖️ جاري حل التعارضات...', Colors.orange);
        conflictsResolved = await _resolveConflicts();
      }

      AppwriteRealtimeSync().resetRemoteChangesFlag();

      // ═══════════════════════════════════════════════════════════════
      // 2️⃣ رفع التغييرات المحلية (Push)
      // ═══════════════════════════════════════════════════════════════

      if (syncState.pendingChangesCount > 0) {
        syncNotifier.updateProgress(SyncProgress(
          currentOperation: 'رفع',
          totalCount: syncState.pendingChangesCount,
          startTime: DateTime.now(),
        ));

        final pushResult = await _withRetry(
          () => deltaSync.pushDeltaChanges(),
          maxRetries: 3,
          operationName: 'رفع التغييرات',
        );
        pushedCount = pushResult.recordsPushed;

        // تنظيف Outbox بعد النجاح
        if (pushResult.success) {
          await _clearOutboxAfterPush();
        }

        syncNotifier.updateProgress(SyncProgress(
          currentOperation: 'رفع',
          processedCount: pushedCount,
          totalCount: syncState.pendingChangesCount,
          successCount: pushedCount,
        ));
      }

      stopwatch.stop();

      // ═══════════════════════════════════════════════════════════════
      // تسجيل العملية
      // ═══════════════════════════════════════════════════════════════

      await syncLogDao.logSync(
        syncId: syncId,
        direction: 'differential',
        deviceId: deviceId,
        target: 'Appwrite',
        status: 'success',
        recordsPulled: pulledCount,
        recordsPushed: pushedCount,
        durationMs: stopwatch.elapsedMilliseconds,
      );

      syncNotifier.setLastSyncTime(DateTime.now());
      syncNotifier.setSyncing(false);

      // عرض النتيجة
      _showSnackBar(
        context,
        '✅ تمت المزامنة بنجاح!\n'
        '⬇️ استُلِم: $pulledCount\n'
        '⬆️ أُرسل: $pushedCount'
        '${conflictsResolved > 0 ? '\n⚖️ تعارضات محلولة: $conflictsResolved' : ''}\n'
        '⏱️ ${stopwatch.elapsed.inSeconds} ثانية',
        Colors.green,
        duration: const Duration(seconds: 4),
      );

      ref.invalidate(smartSyncStatusProvider);

    } catch (e) {
      debugPrint('❌ خطأ في المزامنة: $e');
      stopwatch.stop();

      await syncLogDao.logSync(
        syncId: syncId,
        direction: 'differential',
        deviceId: deviceId,
        target: 'Appwrite',
        status: 'failed',
        errorMessage: e.toString(),
        durationMs: stopwatch.elapsedMilliseconds,
      );

      syncNotifier.setError(e.toString());
      syncNotifier.setSyncing(false);

      _showSnackBar(
        context,
        '❌ فشلت المزامنة: ${e.toString()}',
        Colors.red,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'إعادة',
          textColor: Colors.white,
          onPressed: () => _syncDifferential(context),
        ),
      );
    } finally {
      _safeStopAnimation();
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // SnackBar
  // ═══════════════════════════════════════════════════════════════

  void _showSnackBar(
    BuildContext context,
    String message,
    Color backgroundColor, {
    bool showProgress = false,
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
  }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            if (showProgress) ...[
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(message, style: const TextStyle(fontSize: 12)),
            ),
          ],
        ),
        backgroundColor: backgroundColor,
        duration: duration,
        action: action,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // تنسيق الوقت
  // ═══════════════════════════════════════════════════════════════

  String _formatLastSyncTime(DateTime? lastSync) {
    if (lastSync == null) return '';
    final diff = DateTime.now().difference(lastSync);
    if (diff.inSeconds < 60) return 'منذ ${diff.inSeconds} ثانية';
    if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} دقيقة';
    if (diff.inHours < 24) return 'منذ ${diff.inHours} ساعة';
    return 'منذ ${diff.inDays} يوم';
  }

  // ═══════════════════════════════════════════════════════════════
  // بناء الواجهة
  // ═══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final syncState = ref.watch(syncStateProvider);

    // تحديد حالة الزر
    Color buttonColor;
    IconData buttonIcon;
    String buttonText;
    String tooltipMessage;

    if (syncState.isSyncing) {
      buttonColor = Colors.blue;
      buttonIcon = Icons.sync;
      buttonText = 'جاري المزامنة...';
      tooltipMessage = syncState.progress.currentOperation.isNotEmpty
          ? '${syncState.progress.currentOperation}: ${syncState.progress.progressText}'
          : 'جاري المزامنة...';
    } else if (syncState.pendingConflictsCount > 0) {
      buttonColor = Colors.orange;
      buttonIcon = Icons.warning;
      buttonText = '${syncState.pendingConflictsCount} تعارض';
      tooltipMessage = 'يوجد ${syncState.pendingConflictsCount} تعارض معلق';
    } else if (syncState.hasPendingChanges) {
      buttonColor = Colors.purple;
      buttonIcon = Icons.cloud_sync;
      buttonText = 'مزامنة';
      tooltipMessage = 'اضغط للمزامنة (${syncState.pendingChangesCount} محلي + ${syncState.pendingRemoteChangesCount} بعيد)';
    } else {
      buttonColor = Colors.green;
      buttonIcon = Icons.cloud_done;
      buttonText = 'محدّث';
      tooltipMessage = 'جميع البيانات متزامنة';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ═══════════════════════════════════════════════════════════════
          // زر المزامنة التفاضلية
          // ═══════════════════════════════════════════════════════════════

          Tooltip(
            message: tooltipMessage,
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
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: buttonColor.withOpacity(
                          syncState.isSyncing ? 0.2 : 0.4,
                        ),
                        blurRadius: syncState.isSyncing ? 4 : 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: syncState.isSyncing
                          ? null
                          : () => _syncDifferential(context),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (syncState.isSyncing && _animationController != null)
                              RotationTransition(
                                turns: _animationController!,
                                child: Icon(buttonIcon, size: 20, color: Colors.white),
                              )
                            else
                              Icon(buttonIcon, size: 20, color: Colors.white),
                            const SizedBox(width: 8),
                            Text(
                              buttonText,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Badge للتغييرات المعلقة
                if (syncState.hasPendingChanges && !syncState.isSyncing)
                  Positioned(
                    top: -8,
                    right: -8,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withOpacity(0.5),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                      child: Center(
                        child: Text(
                          '${syncState.pendingChangesCount + syncState.pendingRemoteChangesCount}',
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
          ),

          const SizedBox(height: 8),

          // ═══════════════════════════════════════════════════════════════
          // شريط الحالة
          // ═══════════════════════════════════════════════════════════════

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: syncState.isSyncing
                  ? Colors.blue.shade50
                  : syncState.hasPendingChanges
                      ? Colors.orange.shade50
                      : Colors.green.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: syncState.isSyncing
                    ? Colors.blue.shade200
                    : syncState.hasPendingChanges
                        ? Colors.orange.shade200
                        : Colors.green.shade200,
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  syncState.isSyncing
                      ? Icons.sync
                      : syncState.hasPendingChanges
                          ? Icons.sync_problem
                          : Icons.check_circle,
                  size: 14,
                  color: syncState.isSyncing
                      ? Colors.blue
                      : syncState.hasPendingChanges
                          ? Colors.orange
                          : Colors.green,
                ),
                const SizedBox(width: 6),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      syncState.isSyncing
                          ? '${syncState.progress.currentOperation}: ${syncState.progress.progressText}'
                          : syncState.hasPendingChanges
                              ? '${syncState.pendingChangesCount} محلي + ${syncState.pendingRemoteChangesCount} بعيد'
                              : 'محدّث',
                      style: TextStyle(
                        fontSize: 11,
                        color: syncState.isSyncing
                            ? Colors.blue.shade900
                            : syncState.hasPendingChanges
                                ? Colors.orange.shade900
                                : Colors.green.shade900,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (!syncState.isSyncing && syncState.lastSyncTime != null)
                      Text(
                        _formatLastSyncTime(syncState.lastSyncTime),
                        style: TextStyle(
                          fontSize: 9,
                          color: Colors.grey.shade600,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

---

## 🔧 الاستخدام

```dart
// في أي شاشة
DashboardSyncButton()
```

---

## 📊 مقارنة الأداء

| المقياس | قبل التحسين | بعد التحسين |
|---------|-------------|-------------|
| عدد الأزرار | 3 | 1 |
| retry | ❌ | ✅ 3 محاولات |
| تقدم المزامنة | ❌ | ✅ |
| تنظيف Outbox | ❌ | ✅ |
| حل التعارضات | بسيط | ✅ newerWins |
| مراقبة التعارضات | ❌ | ✅ Stream |

---

## ✅ المميزات النهائية

1. **زر واحد** للمزامنة التفاضلية (سحب + رفع)
2. **Retry ذكي** مع 3 محاولات وتأخير تصاعدي
3. **Progress متقدم** يعرض العملية والعدد
4. **Badge للعداد** يعرض إجمالي التغييرات المعلقة
5. **حل تعارضات تلقائي** باستخدام استراتيجية newerWins
6. **تنظيف Outbox** بعد كل مزامنة ناجحة
7. **تسجيل كامل** في SyncLog
8. **Animation آمن** مع معالجة الأخطاء
