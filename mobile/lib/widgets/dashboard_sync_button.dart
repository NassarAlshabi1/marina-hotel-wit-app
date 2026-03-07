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

/// ⭐ نموذج تقدم المزامنة التفصيلي
class SyncProgress {
  const SyncProgress({
    this.currentOperation = '',
    this.currentEntity = '',
    this.processedCount = 0,
    this.totalCount = 0,
    this.errorCount = 0,
    this.successCount = 0,
    this.startTime,
  });

  final String currentOperation;
  final String currentEntity;
  final int processedCount;
  final int totalCount;
  final int errorCount;
  final int successCount;
  final DateTime? startTime;

  double get progressPercent =>
      totalCount > 0 ? processedCount / totalCount : 0.0;

  String get progressText {
    if (totalCount > 0) {
      return '$processedCount / $totalCount';
    }
    return processedCount > 0 ? '$processedCount' : '';
  }

  Duration get elapsed => startTime != null
      ? DateTime.now().difference(startTime!)
      : Duration.zero;

  SyncProgress copyWith({
    String? currentOperation,
    String? currentEntity,
    int? processedCount,
    int? totalCount,
    int? errorCount,
    int? successCount,
    DateTime? startTime,
  }) {
    return SyncProgress(
      currentOperation: currentOperation ?? this.currentOperation,
      currentEntity: currentEntity ?? this.currentEntity,
      processedCount: processedCount ?? this.processedCount,
      totalCount: totalCount ?? this.totalCount,
      errorCount: errorCount ?? this.errorCount,
      successCount: successCount ?? this.successCount,
      startTime: startTime ?? this.startTime,
    );
  }
}

/// ⭐ موحد حالة المزامنة - مصدر واحد للحقيقة
class SyncState {
  const SyncState({
    this.isPulling = false,
    this.isPushing = false,
    this.pendingChangesCount = 0,
    this.lastSyncTime,
    this.appwriteEnabled = false,
    this.errorMessage,
    this.progress = const SyncProgress(),
    this.lastPullTime,
    this.lastPushTime,
    this.lastPullCount = 0,
    this.lastPushCount = 0,
    this.syncErrorsCount = 0,
  });

  final bool isPulling;
  final bool isPushing;
  final int pendingChangesCount;
  final DateTime? lastSyncTime;
  final bool appwriteEnabled;
  final String? errorMessage;
  final SyncProgress progress;
  final DateTime? lastPullTime;
  final DateTime? lastPushTime;
  final int lastPullCount;
  final int lastPushCount;
  final int syncErrorsCount;

  bool get isSyncing => isPulling || isPushing;

  SyncState copyWith({
    bool? isPulling,
    bool? isPushing,
    int? pendingChangesCount,
    DateTime? lastSyncTime,
    bool? appwriteEnabled,
    String? errorMessage,
    SyncProgress? progress,
    DateTime? lastPullTime,
    DateTime? lastPushTime,
    int? lastPullCount,
    int? lastPushCount,
    int? syncErrorsCount,
  }) {
    return SyncState(
      isPulling: isPulling ?? this.isPulling,
      isPushing: isPushing ?? this.isPushing,
      pendingChangesCount: pendingChangesCount ?? this.pendingChangesCount,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      appwriteEnabled: appwriteEnabled ?? this.appwriteEnabled,
      errorMessage: errorMessage,
      progress: progress ?? this.progress,
      lastPullTime: lastPullTime ?? this.lastPullTime,
      lastPushTime: lastPushTime ?? this.lastPushTime,
      lastPullCount: lastPullCount ?? this.lastPullCount,
      lastPushCount: lastPushCount ?? this.lastPushCount,
      syncErrorsCount: syncErrorsCount ?? this.syncErrorsCount,
    );
  }
}

/// ⭐ StateNotifier لإدارة حالة المزامنة
class SyncStateNotifier extends StateNotifier<SyncState> {
  SyncStateNotifier(this.ref) : super(const SyncState()) {
    _init();
  }

  final Ref ref;
  StreamSubscription<int>? _outboxSubscription;
  StreamSubscription<SyncErrorRecord>? _errorSubscription;

  void _init() {
    // ⭐ استخدام Stream بدلاً من Polling
    final db = ref.read(databaseProvider);
    final outboxDao = OutboxDao(db);
    _outboxSubscription = outboxDao.watchCount().listen((count) {
      state = state.copyWith(pendingChangesCount: count);
    });

    // ⭐ الاستماع لأخطاء المزامنة
    _errorSubscription = AppwriteDeltaSync.instance.errorsStream.listen((error) {
      state = state.copyWith(syncErrorsCount: AppwriteDeltaSync.instance.syncErrors.length);
    });

    _loadAppwriteEnabled();
    _loadSyncStats();
  }

  Future<void> _loadAppwriteEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('appwrite_sync_enabled') ?? false;
      state = state.copyWith(appwriteEnabled: enabled);
    } catch (e) {
      debugPrint('❌ خطأ في تحميل حالة Appwrite: $e');
    }
  }

  /// ⭐ تحميل إحصائيات المزامنة المحفوظة
  Future<void> _loadSyncStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastPullMs = prefs.getInt('last_pull_time');
      final lastPushMs = prefs.getInt('last_push_time');
      final lastPullCount = prefs.getInt('last_pull_count') ?? 0;
      final lastPushCount = prefs.getInt('last_push_count') ?? 0;

      state = state.copyWith(
        lastPullTime: lastPullMs != null
            ? DateTime.fromMillisecondsSinceEpoch(lastPullMs)
            : null,
        lastPushTime: lastPushMs != null
            ? DateTime.fromMillisecondsSinceEpoch(lastPushMs)
            : null,
        lastPullCount: lastPullCount,
        lastPushCount: lastPushCount,
        syncErrorsCount: AppwriteDeltaSync.instance.syncErrors.length,
      );
    } catch (e) {
      debugPrint('❌ خطأ في تحميل إحصائيات المزامنة: $e');
    }
  }

  void setPulling(bool value) {
    if (value) {
      state = state.copyWith(
        isPulling: true,
        progress: SyncProgress(
          currentOperation: 'سحب',
          startTime: DateTime.now(),
        ),
      );
    } else {
      state = state.copyWith(
        isPulling: false,
        progress: const SyncProgress(),
      );
    }
  }

  void setPushing(bool value) {
    if (value) {
      state = state.copyWith(
        isPushing: true,
        progress: SyncProgress(
          currentOperation: 'رفع',
          startTime: DateTime.now(),
        ),
      );
    } else {
      state = state.copyWith(
        isPushing: false,
        progress: const SyncProgress(),
      );
    }
  }

  void updateProgress(SyncProgress progress) {
    state = state.copyWith(progress: progress);
  }

  void setLastSyncTime(DateTime? time) {
    state = state.copyWith(lastSyncTime: time);
  }

  void setLastPullStats(DateTime time, int count) async {
    state = state.copyWith(
      lastPullTime: time,
      lastPullCount: count,
      lastSyncTime: time,
    );
    // حفظ محلياً
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_pull_time', time.millisecondsSinceEpoch);
    await prefs.setInt('last_pull_count', count);
  }

  void setLastPushStats(DateTime time, int count) async {
    state = state.copyWith(
      lastPushTime: time,
      lastPushCount: count,
      lastSyncTime: time,
    );
    // حفظ محلياً
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_push_time', time.millisecondsSinceEpoch);
    await prefs.setInt('last_push_count', count);
  }

  void setError(String? error) {
    state = state.copyWith(errorMessage: error);
  }

  void updateErrorsCount() {
    state = state.copyWith(
      syncErrorsCount: AppwriteDeltaSync.instance.syncErrors.length,
    );
  }

  @override
  void dispose() {
    _outboxSubscription?.cancel();
    _errorSubscription?.cancel();
    super.dispose();
  }
}

/// ⭐ Provider لموحد حالة المزامنة
final syncStateProvider = StateNotifierProvider<SyncStateNotifier, SyncState>((ref) {
  return SyncStateNotifier(ref);
});

class DashboardSyncButton extends ConsumerStatefulWidget {
  const DashboardSyncButton({super.key});

  @override
  ConsumerState<DashboardSyncButton> createState() =>
      _DashboardSyncButtonState();
}

class _DashboardSyncButtonState extends ConsumerState<DashboardSyncButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pullAnimationController;
  late AnimationController _pushAnimationController;

  @override
  void initState() {
    super.initState();
    _pullAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pushAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
  }

  @override
  void dispose() {
    _pullAnimationController.dispose();
    _pushAnimationController.dispose();
    super.dispose();
  }

  Future<bool> _isAppwriteSyncEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('appwrite_sync_enabled') ?? false;
  }

  /// التأكد من تهيئة خدمة المزامنة التفاضلية
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

  /// ⭐ إصلاح: تنظيف Outbox فقط للعناصر التي نجح رفعها
  Future<void> _clearSuccessfulOutboxItems(List<String> successfulUuids) async {
    if (successfulUuids.isEmpty) return;
    
    try {
      final db = ref.read(databaseProvider);
      final outboxDao = OutboxDao(db);
      await outboxDao.removeByUuids(successfulUuids);
      debugPrint('✅ تم تنظيف ${successfulUuids.length} عنصر ناجح من outbox');
    } catch (e) {
      debugPrint('⚠️ فشل تنظيف outbox: $e');
      // لا نرمي الخطأ - البيانات مرفوعة بالفعل
    }
  }

  /// ⭐ إصلاح: Retry logic محسن
  Future<T> _withRetry<T>(
    Future<T> Function() operation, {
    int maxRetries = 3,
    String operationName = 'operation',
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

  /// سحب التغييرات من Appwrite (Pull فقط)
  Future<void> _pullChanges(BuildContext context) async {
    final syncState = ref.read(syncStateProvider);
    if (syncState.isSyncing) return;

    final syncNotifier = ref.read(syncStateProvider.notifier);
    syncNotifier.setPulling(true);
    _pullAnimationController.repeat();

    final stopwatch = Stopwatch()..start();
    final syncId = 'pull_${DateTime.now().millisecondsSinceEpoch}';
    String? deviceId;
    
    try {
      deviceId = await _getDeviceId();
    } catch (e) {
      deviceId = 'unknown';
    }

    final db = ref.read(databaseProvider);
    final syncLogDao = SyncLogDao(db);
    await syncLogDao.logSync(
      syncId: syncId,
      direction: 'pull',
      deviceId: deviceId,
      target: 'Appwrite',
      status: 'in_progress',
    );

    try {
      final appwriteEnabled = await _isAppwriteSyncEnabled();
      if (!appwriteEnabled) {
        if (mounted) {
          _showSnackBar(
            context,
            'مزامنة Appwrite معطلة - يرجى تفعيلها من الإعدادات',
            Colors.orange,
          );
        }
        return;
      }

      await ref.read(connectionStatusProvider.notifier).checkConnection();
      final appwriteConnected = ref.read(connectionStatusProvider).isConnected;

      if (!appwriteConnected) {
        if (mounted) {
          _showSnackBar(context, 'لا يوجد اتصال بـ Appwrite', Colors.red);
        }
        return;
      }

      if (mounted) {
        _showSnackBar(
          context,
          '⬇️ جاري سحب التغييرات من السيرفر...',
          Colors.blue,
          showProgress: true,
        );
      }

      // ⭐ استخدام Retry logic
      final initialized = await _withRetry(
        _ensureDeltaSyncInitialized,
        maxRetries: 2,
        operationName: 'تهيئة المزامنة',
      );

      if (!initialized) {
        if (mounted) {
          _showSnackBar(
            context,
            'خدمة المزامنة غير مهيأة - تعذر التهيئة',
            Colors.red,
          );
        }
        return;
      }

      final deltaSync = AppwriteDeltaSync.instance;

      // ⭐ استخدام Retry logic للسحب
      final pullResult = await _withRetry(
        () => deltaSync.pullDeltaChanges(),
        maxRetries: 3,
        operationName: 'سحب التغييرات',
      );

      final pulledCount = pullResult.recordsPulled;

      // حل التعارضات إن وجدت
      int conflictsResolved = 0;
      if (pullResult.hasConflicts) {
        if (mounted) {
          _showSnackBar(context, '⚖️ جاري حل التعارضات...', Colors.orange);
        }
        conflictsResolved = await _resolveConflicts();
      }

      // إعادة تعيين علامة "توجد تغييرات من السيرفر"
      AppwriteRealtimeSync().resetRemoteChangesFlag();

      // ✅ تسجيل نجاح العملية
      stopwatch.stop();
      await syncLogDao.logSync(
        syncId: syncId,
        direction: 'pull',
        deviceId: deviceId,
        target: 'Appwrite',
        status: 'success',
        recordsPulled: pulledCount,
        durationMs: stopwatch.elapsedMilliseconds,
      );

      // ⭐ تحديث إحصائيات السحب
      syncNotifier.setLastPullStats(DateTime.now(), pulledCount);
      syncNotifier.updateErrorsCount();

      if (mounted) {
        _showSnackBar(
          context,
          '✅ تم سحب التغييرات بنجاح!\n⬇️ استُلِم: $pulledCount${conflictsResolved > 0 ? ' ⚖️ تعارضات محلولة: $conflictsResolved' : ''}\n⏱️ ${stopwatch.elapsed.inSeconds}.${stopwatch.elapsed.inMilliseconds % 1000} ثانية',
          Colors.green,
        );
      }
    } catch (e) {
      debugPrint('❌ خطأ في سحب التغييرات: $e');

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
        _showSnackBar(
          context,
          'تعذر سحب التغييرات: ${e.toString()}',
          Colors.red,
        );
      }
    } finally {
      _pullAnimationController.stop();
      _pullAnimationController.reset();
      ref.read(syncStateProvider.notifier).setPulling(false);
    }
  }

  /// رفع التغييرات المحلية (Push فقط)
  Future<void> _pushChanges(BuildContext context) async {
    final syncState = ref.read(syncStateProvider);
    if (syncState.isSyncing) return;

    if (syncState.pendingChangesCount == 0) {
      if (mounted) {
        _showSnackBar(context, '✅ لا توجد تغييرات جديدة للرفع', Colors.green);
      }
      return;
    }

    final syncNotifier = ref.read(syncStateProvider.notifier);
    syncNotifier.setPushing(true);
    _pushAnimationController.repeat();

    final stopwatch = Stopwatch()..start();
    final syncId = 'push_${DateTime.now().millisecondsSinceEpoch}';
    String? deviceId;
    
    try {
      deviceId = await _getDeviceId();
    } catch (e) {
      deviceId = 'unknown';
    }

    final db = ref.read(databaseProvider);
    final syncLogDao = SyncLogDao(db);
    await syncLogDao.logSync(
      syncId: syncId,
      direction: 'push',
      deviceId: deviceId,
      target: 'Appwrite+GoogleDrive',
      status: 'in_progress',
    );

    try {
      final smartSyncManager = ref.read(smartSyncManagerProvider);
      final appwriteSyncManager = ref.read(appwriteSyncManagerProvider);

      final smartEnabled = await smartSyncManager.isEnabled();
      final isGoogleDriveSignedIn = ref.read(
        smartSyncGoogleDriveSignInStatusProvider,
      );
      final appwriteEnabled = await _isAppwriteSyncEnabled();

      if (!smartEnabled && !appwriteEnabled) {
        if (mounted) {
          _showSnackBar(
            context,
            'ℹ️ المزامنة معطلة - يرجى تفعيلها من الإعدادات',
            Colors.orange,
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
          _showSnackBar(context, 'لا توجد وجهات مزامنة متاحة حالياً', Colors.orange);
        }
        return;
      }

      if (mounted) {
        _showSnackBar(
          context,
          '⬆️ جاري رفع التغييرات إلى ${targets.join(' + ')}...',
          Colors.blue,
          showProgress: true,
          duration: const Duration(seconds: 5),
        );
      }

      final results = <String, Map<String, dynamic>>{};
      // ⭐ تتبع الـ UUIDs التي نجح رفعها
      final successfulUuids = <String>[];

      // رفع إلى Appwrite أولاً
      if (appwriteEnabled && appwriteConnected) {
        try {
          final initialized = await _withRetry(
            _ensureDeltaSyncInitialized,
            maxRetries: 2,
            operationName: 'تهيئة المزامنة',
          );

          final deltaSync = AppwriteDeltaSync.instance;
          if (initialized && deltaSync.isInitialized) {
            // ⭐ استخدام Retry logic للرفع
            final pushResult = await _withRetry(
              () => deltaSync.pushDeltaChanges(),
              maxRetries: 3,
              operationName: 'رفع إلى Appwrite',
            );

            results['Appwrite'] = {
              'success': pushResult.success,
              'pushed': pushResult.recordsPushed,
              'uuids': pushResult.pushedUuids, // ⭐ نحتاج لإضافة هذا في DeltaSync
            };

            if (pushResult.success && pushResult.pushedUuids.isNotEmpty) {
              successfulUuids.addAll(pushResult.pushedUuids);
            }
          } else {
            final result = await appwriteSyncManager.pushLocalChanges();
            results['Appwrite'] = {
              'success': result,
              'pushed': syncState.pendingChangesCount,
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

      // رفع إلى Google Drive
      if (smartEnabled && isGoogleDriveSignedIn) {
        try {
          final result = await _withRetry(
            () => smartSyncManager.pushLocalChanges(),
            maxRetries: 2,
            operationName: 'رفع إلى Google Drive',
          );
          results['Google Drive'] = {
            'success': result,
            'pushed': syncState.pendingChangesCount,
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

      // ⭐ إصلاح: تنظيف Outbox فقط للعناصر التي نجح رفعها
      if (successfulUuids.isNotEmpty) {
        await _clearSuccessfulOutboxItems(successfulUuids);
      } else if (successTargets.isNotEmpty) {
        // Fallback: إذا لم نحصل على UUIDs، ننظف الكل فقط إذا نجح كل شيء
        final db = ref.read(databaseProvider);
        final outboxDao = OutboxDao(db);
        await outboxDao.removeAllPending();
      }

      // تسجيل نتيجة العملية
      stopwatch.stop();
      await syncLogDao.logSync(
        syncId: syncId,
        direction: 'push',
        deviceId: deviceId,
        target: successTargets.join('+'),
        status: failedTargets.isEmpty
            ? 'success'
            : (successTargets.isNotEmpty ? 'partial' : 'failed'),
        recordsPushed: totalPushed,
        durationMs: stopwatch.elapsedMilliseconds,
      );

      // ⭐ تحديث إحصائيات الرفع
      if (totalPushed > 0) {
        syncNotifier.setLastPushStats(DateTime.now(), totalPushed);
      }
      syncNotifier.updateErrorsCount();

      if (mounted) {
        if (failedTargets.isEmpty) {
          _showSnackBar(
            context,
            '✅ تم رفع التغييرات بنجاح!\n⬆️ أُرسل: $totalPushed\n☁️ عبر: ${successTargets.join(' + ')}\n⏱️ ${stopwatch.elapsed.inSeconds}.${stopwatch.elapsed.inMilliseconds % 1000} ثانية',
            Colors.green,
            duration: const Duration(seconds: 4),
          );
        } else if (successTargets.isEmpty) {
          _showSnackBar(
            context,
            '❌ فشل رفع التغييرات',
            Colors.red,
            action: SnackBarAction(
              label: 'إعادة',
              textColor: Colors.white,
              onPressed: () => _pushChanges(context),
            ),
          );
        } else {
          _showSnackBar(
            context,
            '⚠️ نجح جزئياً\n✅ نجح: ${successTargets.join(', ')}\n❌ فشل: ${failedTargets.join(', ')}',
            Colors.orange,
            duration: const Duration(seconds: 4),
          );
        }
      }

      ref.invalidate(smartSyncStatusProvider);
    } catch (e) {
      debugPrint('❌ فشل رفع التغييرات: $e');

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
        _showSnackBar(
          context,
          'تعذر رفع التغييرات. تحقق من الاتصال وبيانات الدخول',
          Colors.red,
          action: SnackBarAction(
            label: 'إعادة',
            textColor: Colors.white,
            onPressed: () => _pushChanges(context),
          ),
        );
      }
    } finally {
      _pushAnimationController.stop();
      _pushAnimationController.reset();
      ref.read(syncStateProvider.notifier).setPushing(false);
    }
  }

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
              child: Text(
                message,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        backgroundColor: backgroundColor,
        duration: duration,
        action: action,
      ),
    );
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
              final isRemoteWinner = winnerData == conflict.remotePayload;
              final resolutionLabel =
                  isRemoteWinner ? 'remote_wins_latest' : 'local_wins_latest';

              await outboxDao.resolveConflict(
                conflict.id,
                winnerData,
                resolution: resolutionLabel,
              );
              resolvedCount++;

              debugPrint(
                  '⚖️ حل تعارض ${conflict.targetTable}: الفائز هو الأحدث (${isRemoteWinner ? 'السيرفر' : 'الجهاز'})');
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

  Widget _buildPullButton({
    required bool hasRemoteChanges,
    required int pendingRemoteCount,
    required bool isEnabled,
    required bool isPulling,
  }) {
    final Color buttonColor;
    final IconData buttonIcon;
    final String buttonText;

    if (isPulling) {
      buttonColor = Colors.blue;
      buttonIcon = Icons.cloud_download;
      buttonText = 'جاري السحب...';
    } else if (hasRemoteChanges) {
      buttonColor = Colors.blue;
      buttonIcon = Icons.cloud_download;
      buttonText = 'سحب التغييرات';
    } else {
      buttonColor = Colors.blue.withOpacity(0.6);
      buttonIcon = Icons.cloud_download;
      buttonText = 'سحب التغييرات';
    }

    return Tooltip(
      message: 'اضغط لسحب التغييرات من السيرفر',
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
                  color: buttonColor.withOpacity(isEnabled ? 0.4 : 0.1),
                  blurRadius: isEnabled ? 8 : 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: isEnabled ? () => _pullChanges(context) : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isPulling)
                        RotationTransition(
                          turns: _pullAnimationController,
                          child: Icon(buttonIcon, size: 14, color: Colors.white),
                        )
                      else
                        Icon(buttonIcon, size: 14, color: Colors.white),
                      const SizedBox(width: 6),
                      Text(
                        buttonText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (hasRemoteChanges && !isPulling && pendingRemoteCount > 0)
            Positioned(
              top: -6,
              right: -6,
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: Colors.blue,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withOpacity(0.5),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                child: Center(
                  child: Text(
                    pendingRemoteCount > 99 ? '99+' : '$pendingRemoteCount',
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

  Widget _buildPushButton({
    required bool hasChanges,
    required int pendingCount,
    required bool isEnabled,
    required bool isPushing,
  }) {
    final Color buttonColor;
    final IconData buttonIcon;
    final String buttonText;

    if (isPushing) {
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
          ? 'اضغط لرفع $pendingCount تغيير إلى السحابة'
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
                  color: buttonColor.withOpacity(isEnabled ? 0.4 : 0.1),
                  blurRadius: isEnabled ? 8 : 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: isEnabled ? () => _pushChanges(context) : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isPushing)
                        RotationTransition(
                          turns: _pushAnimationController,
                          child: Icon(buttonIcon, size: 14, color: Colors.white),
                        )
                      else
                        Icon(buttonIcon, size: 14, color: Colors.white),
                      const SizedBox(width: 6),
                      Text(
                        buttonText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (hasChanges && !isPushing)
            Positioned(
              top: -6,
              right: -6,
              child: Container(
                padding: const EdgeInsets.all(5),
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
                constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
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

  /// ⭐ بناء زر عرض الأخطاء
  Widget _buildErrorsButton(BuildContext context, int errorsCount) {
    return Tooltip(
      message: '$errorsCount خطأ مزامنة - اضغط للتفاصيل',
      child: GestureDetector(
        onTap: () => _showSyncErrorsDialog(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.red.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.red.shade300),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 14, color: Colors.red.shade700),
              const SizedBox(width: 4),
              Text(
                '$errorsCount',
                style: TextStyle(
                  color: Colors.red.shade700,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// ⭐ عرض نافذة الأخطاء
  void _showSyncErrorsDialog(BuildContext context) {
    final errors = AppwriteDeltaSync.instance.syncErrors;

    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.error_outline, color: Colors.red.shade600),
              const SizedBox(width: 8),
              Text('أخطاء المزامنة (${errors.length})'),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: errors.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle, color: Colors.green, size: 48),
                        SizedBox(height: 8),
                        Text('لا توجد أخطاء'),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: errors.length,
                    itemBuilder: (context, index) {
                      final error = errors[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        color: Colors.red.shade50,
                        child: ListTile(
                          leading: Icon(
                            _getOperationIcon(error.operation),
                            color: _getOperationColor(error.operation),
                          ),
                          title: Text(
                            '${_translateEntity(error.entity)} - ${error.localUuid.substring(0, 8)}...',
                            style: const TextStyle(fontSize: 12),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                error.errorMessage,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 10),
                              ),
                              Text(
                                'المحاولات: ${error.retryCount}/3',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: error.retryCount >= 2 ? Colors.red : Colors.grey,
                                ),
                              ),
                            ],
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.refresh, size: 18),
                            onPressed: () async {
                              Navigator.pop(context);
                              await _retryAllErrors();
                            },
                          ),
                          isThreeLine: true,
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق'),
            ),
            if (errors.isNotEmpty) ...[
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await AppwriteDeltaSync.instance.clearAllErrors();
                  ref.read(syncStateProvider.notifier).updateErrorsCount();
                },
                child: const Text('مسح الكل', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(context);
                  await _retryAllErrors();
                },
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('إعادة المحاولة'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// ⭐ إعادة محاولة جميع الأخطاء
  Future<void> _retryAllErrors() async {
    try {
      final result = await AppwriteDeltaSync.instance.retryAllFailed();
      ref.read(syncStateProvider.notifier).updateErrorsCount();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.success
                  ? 'تم إعادة محاولة ${result.recordsPushed} سجل بنجاح'
                  : 'فشلت إعادة المحاولة: ${result.message}',
            ),
            backgroundColor: result.success ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// ⭐ الحصول على أيقونة العملية
  IconData _getOperationIcon(String operation) {
    switch (operation) {
      case 'insert':
        return Icons.add_circle_outline;
      case 'update':
        return Icons.edit_outlined;
      case 'delete':
        return Icons.delete_outline;
      default:
        return Icons.sync_problem;
    }
  }

  /// ⭐ الحصول على لون العملية
  Color _getOperationColor(String operation) {
    switch (operation) {
      case 'insert':
        return Colors.green;
      case 'update':
        return Colors.blue;
      case 'delete':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  /// ⭐ ترجمة اسم الكيان
  String _translateEntity(String entity) {
    const translations = {
      'rooms': 'الغرف',
      'bookings': 'الحجوزات',
      'payments': 'المدفوعات',
      'expenses': 'المصروفات',
      'employees': 'الموظفين',
      'debts': 'الديون',
      'booking_notes': 'ملاحظات الحجز',
      'booking_nights': 'الليالي',
      'cash_transactions': 'المعاملات النقدية',
      'salary_cycles': 'دورات الرواتب',
      'salary_payments': 'مدفوعات الرواتب',
      'salary_withdrawals': 'سحوبات الرواتب',
      'shift_notes': 'ملاحظات الوردية',
    };
    return translations[entity] ?? entity;
  }

  @override
  Widget build(BuildContext context) {
    // ⭐ استخدام موحد الحالة من Riverpod
    final syncState = ref.watch(syncStateProvider);
    final isGoogleDriveSignedIn = ref.watch(smartSyncGoogleDriveSignInStatusProvider);

    return ValueListenableBuilder<bool>(
      valueListenable: AppwriteRealtimeSync().hasRemoteChanges,
      builder: (context, hasRemoteChanges, child) {
        return ValueListenableBuilder<int>(
          valueListenable: AppwriteRealtimeSync().pendingRemoteChangesCount,
          builder: (context, pendingRemoteCount, child) {
            final hasLocalChanges = syncState.pendingChangesCount > 0;
            final canSync = syncState.appwriteEnabled && !syncState.isSyncing;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildPullButton(
                      hasRemoteChanges: hasRemoteChanges,
                      pendingRemoteCount: pendingRemoteCount,
                      isEnabled: canSync,
                      isPulling: syncState.isPulling,
                    ),
                    const SizedBox(width: 8),
                    _buildPushButton(
                      hasChanges: hasLocalChanges,
                      pendingCount: syncState.pendingChangesCount,
                      isEnabled: hasLocalChanges && !syncState.isSyncing,
                      isPushing: syncState.isPushing,
                    ),
                    // ⭐ زر عرض الأخطاء (يظهر فقط إذا وجدت أخطاء)
                    if (syncState.syncErrorsCount > 0) ...[
                      const SizedBox(width: 4),
                      _buildErrorsButton(context, syncState.syncErrorsCount),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: syncState.isSyncing
                        ? Colors.blue.shade50
                        : (hasLocalChanges || hasRemoteChanges || syncState.syncErrorsCount > 0)
                            ? Colors.orange.shade50
                            : Colors.green.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: syncState.isSyncing
                          ? Colors.blue.shade200
                          : (hasLocalChanges || hasRemoteChanges || syncState.syncErrorsCount > 0)
                              ? Colors.orange.shade200
                              : Colors.green.shade200,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        syncState.syncErrorsCount > 0
                            ? Icons.error_outline
                            : hasLocalChanges || hasRemoteChanges
                                ? Icons.sync_problem
                                : (syncState.isSyncing ? Icons.sync : Icons.check_circle),
                        size: 12,
                        color: syncState.syncErrorsCount > 0
                            ? Colors.red
                            : syncState.isSyncing
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
                            syncState.syncErrorsCount > 0
                                ? '${syncState.syncErrorsCount} خطأ مزامنة'
                                : syncState.isPulling
                                    ? 'جاري السحب...'
                                    : syncState.isPushing
                                        ? 'جاري الرفع...'
                                        : hasLocalChanges
                                            ? '${syncState.pendingChangesCount} تغيير محلي معلق'
                                            : hasRemoteChanges
                                                ? '$pendingRemoteCount تحديث من السيرفر'
                                                : 'محدّث',
                            style: TextStyle(
                              fontSize: 11,
                              color: syncState.syncErrorsCount > 0
                                  ? Colors.red.shade900
                                  : syncState.isSyncing
                                      ? Colors.blue.shade900
                                      : (hasLocalChanges || hasRemoteChanges)
                                          ? Colors.orange.shade900
                                          : Colors.green.shade900,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (!syncState.isSyncing && syncState.lastSyncTime != null)
                            Text(
                              _formatLastSyncTime(syncState.lastSyncTime),
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
