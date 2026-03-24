import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/repository_providers.dart';
import '../providers/appwrite_providers.dart' as appwrite_providers;
import '../providers/sync_log_providers.dart';
import '../services/daos/outbox_dao.dart';
import '../services/appwrite_delta_sync.dart';
import '../screens/settings/sync_history_screen.dart';

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
    this.errorMessage,
    this.progress = const SyncProgress(),
    this.syncErrorsCount = 0,
  });

  final bool isPulling;
  final bool isPushing;
  final int pendingChangesCount;
  final DateTime? lastSyncTime;
  final String? errorMessage;
  final SyncProgress progress;
  final int syncErrorsCount;

  bool get isSyncing => isPulling || isPushing;

  SyncState copyWith({
    bool? isPulling,
    bool? isPushing,
    int? pendingChangesCount,
    DateTime? lastSyncTime,
    String? errorMessage,
    SyncProgress? progress,
    int? syncErrorsCount,
  }) {
    return SyncState(
      isPulling: isPulling ?? this.isPulling,
      isPushing: isPushing ?? this.isPushing,
      pendingChangesCount: pendingChangesCount ?? this.pendingChangesCount,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      errorMessage: errorMessage,
      progress: progress ?? this.progress,
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

  void _init() {
    final db = ref.read(databaseProvider);
    final outboxDao = OutboxDao(db);
    _outboxSubscription = outboxDao.watchCount().listen((count) {
      state = state.copyWith(pendingChangesCount: count);
    });

    _loadSyncStats();
  }

  /// ⭐ تحميل إحصائيات المزامنة المحفوظة
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

  void setLastSyncTime(DateTime? time) async {
    state = state.copyWith(lastSyncTime: time);
    if (time != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('last_sync_time', time.millisecondsSinceEpoch);
    }
  }

  void setError(String? error) {
    state = state.copyWith(errorMessage: error);
  }

  void updateErrorsCount(int count) {
    state = state.copyWith(syncErrorsCount: count);
  }

  @override
  void dispose() {
    _outboxSubscription?.cancel();
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
  AnimationController? _pullAnimationController;
  AnimationController? _pushAnimationController;
  bool _isDisposed = false;

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
    _isDisposed = true;
    _pullAnimationController?.dispose();
    _pushAnimationController?.dispose();
    _pullAnimationController = null;
    _pushAnimationController = null;
    super.dispose();
  }

  void _safeStopAnimation(AnimationController? controller) {
    if (_isDisposed || controller == null) return;
    try {
      if (!mounted) return;
      if (controller.isAnimating) {
        controller.stop();
      }
      controller.reset();
    } catch (e) {
      debugPrint('⚠️ AnimationController error (ignored): $e');
    }
  }

  void _safeRepeatAnimation(AnimationController? controller) {
    if (_isDisposed || controller == null) return;
    try {
      if (!mounted) return;
      controller.repeat();
    } catch (e) {
      debugPrint('⚠️ AnimationController error (ignored): $e');
    }
  }

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

  /// تهيئة AppwriteDeltaSync إذا لم يكن مهيأً
  Future<bool> _ensureAppwriteDeltaSyncInitialized() async {
    final deltaSync = AppwriteDeltaSync.instance;
    if (deltaSync.isInitialized) return true;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final appwriteEnabled = prefs.getBool('appwrite_sync_enabled') ?? false;
      if (!appwriteEnabled) {
        debugPrint('⚠️ Appwrite sync is disabled in settings');
        return false;
      }
      
      final appwriteService = ref.read(appwrite_providers.appwriteServiceProvider);
      final db = ref.read(databaseProvider);
      await deltaSync.initialize(appwriteService, db);
      return deltaSync.isInitialized;
    } catch (e) {
      debugPrint('❌ فشل تهيئة AppwriteDeltaSync: $e');
      return false;
    }
  }

  /// سحب ورفع التغييرات باستخدام المزامنة التفاضلية AppwriteDeltaSync
  Future<void> _syncDifferential(BuildContext context) async {
    final syncState = ref.read(syncStateProvider);
    if (syncState.isSyncing) return;

    final syncNotifier = ref.read(syncStateProvider.notifier);
    syncNotifier.setPulling(true);
    syncNotifier.setPushing(true);
    _safeRepeatAnimation(_pullAnimationController);
    _safeRepeatAnimation(_pushAnimationController);

    final stopwatch = Stopwatch()..start();

    try {
      if (mounted) {
        _showSnackBar(
          context,
          '🔄 جاري المزامنة التفاضلية...',
          Colors.blue,
          showProgress: true,
        );
      }

      // ✅ استخدام AppwriteDeltaSync بدلاً من SyncService
      if (!await _ensureAppwriteDeltaSyncInitialized()) {
        throw Exception('فشل تهيئة خدمة المزامنة. تأكد من تفعيل Appwrite في الإعدادات.');
      }
      
      final deltaSync = AppwriteDeltaSync.instance;
      final result = await _withRetry(
        () => deltaSync.fullSync(),
        maxRetries: 3,
        operationName: 'المزامنة التفاضلية',
      );

      stopwatch.stop();
      
      syncNotifier.setLastSyncTime(DateTime.now());
      syncNotifier.updateErrorsCount(0);
      
      // تحديث إحصائيات المزامنة في شاشة الإعدادات
      ref.invalidate(appwrite_providers.syncStatsProvider);
      ref.invalidate(syncLogStatsProvider);
      // إبطال جميع فلاتر سجل المزامنة
      ref.invalidate(syncHistoryProvider);

      if (mounted) {
        final recordsText = result.recordsPushed > 0 ? '\n📤 ${result.recordsPushed} سجل تم رفعه' : '';
        final pulledText = result.recordsPulled > 0 ? '\n📥 ${result.recordsPulled} سجل تم سحبه' : '';
        final conflictText = result.hasConflicts ? '\n⚠️ ${result.conflictCount} تعارض' : '';
        _showSnackBar(
          context,
          '✅ تمت المزامنة بنجاح!$recordsText$pulledText$conflictText\n⏱️ ${stopwatch.elapsed.inSeconds}.${stopwatch.elapsed.inMilliseconds % 1000} ثانية',
          Colors.green,
        );
      }
    } catch (e) {
      debugPrint('❌ خطأ في المزامنة التفاضلية: $e');

      stopwatch.stop();
      
      // تحديث عداد الأخطاء
      final currentErrors = syncState.syncErrorsCount + 1;
      syncNotifier.updateErrorsCount(currentErrors);
      
      // تحديث إحصائيات المزامنة
      ref.invalidate(appwrite_providers.syncStatsProvider);
      ref.invalidate(syncLogStatsProvider);
      ref.invalidate(syncHistoryProvider);

      if (mounted) {
        _showSnackBar(
          context,
          '❌ تعذر المزامنة: ${e.toString()}',
          Colors.red,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'عرض السجل',
            textColor: Colors.white,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SyncHistoryScreen(),
                ),
              );
            },
          ),
        );
      }
    } finally {
      _safeStopAnimation(_pullAnimationController);
      _safeStopAnimation(_pushAnimationController);
      if (!_isDisposed) {
        ref.read(syncStateProvider.notifier).setPulling(false);
        ref.read(syncStateProvider.notifier).setPushing(false);
      }
    }
  }

  /// سحب التغييرات من السيرفر فقط باستخدام AppwriteDeltaSync
  Future<void> _pullChanges(BuildContext context) async {
    final syncState = ref.read(syncStateProvider);
    if (syncState.isSyncing) return;

    final syncNotifier = ref.read(syncStateProvider.notifier);
    syncNotifier.setPulling(true);
    _safeRepeatAnimation(_pullAnimationController);

    final stopwatch = Stopwatch()..start();

    try {
      if (mounted) {
        _showSnackBar(
          context,
          '🔄 جاري سحب التغييرات من السيرفر...',
          Colors.blue,
          showProgress: true,
        );
      }

      // ✅ استخدام AppwriteDeltaSync بدلاً من SyncService
      if (!await _ensureAppwriteDeltaSyncInitialized()) {
        throw Exception('فشل تهيئة خدمة المزامنة. تأكد من تفعيل Appwrite في الإعدادات.');
      }
      
      final deltaSync = AppwriteDeltaSync.instance;
      final result = await _withRetry(
        () => deltaSync.pullDeltaChanges(),
        maxRetries: 3,
        operationName: 'سحب التغييرات',
      );

      stopwatch.stop();

      syncNotifier.setLastSyncTime(DateTime.now());
      
      // تحديث إحصائيات المزامنة
      ref.invalidate(appwrite_providers.syncStatsProvider);
      ref.invalidate(syncLogStatsProvider);
      ref.invalidate(syncHistoryProvider);

      if (mounted) {
        final pulledText = result.recordsPulled > 0 ? '\n📥 ${result.recordsPulled} سجل تم سحبه' : '';
        _showSnackBar(
          context,
          '✅ تم سحب التغييرات بنجاح!$pulledText\n⏱️ ${stopwatch.elapsed.inSeconds}.${stopwatch.elapsed.inMilliseconds % 1000} ثانية',
          Colors.green,
        );
      }
    } catch (e) {
      debugPrint('❌ خطأ في سحب التغييرات: $e');

      stopwatch.stop();
      
      // تحديث إحصائيات المزامنة
      ref.invalidate(appwrite_providers.syncStatsProvider);
      ref.invalidate(syncLogStatsProvider);
      ref.invalidate(syncHistoryProvider);

      if (mounted) {
        _showSnackBar(
          context,
          '❌ تعذر سحب التغييرات: ${e.toString()}',
          Colors.red,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'عرض السجل',
            textColor: Colors.white,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SyncHistoryScreen(),
                ),
              );
            },
          ),
        );
      }
    } finally {
      _safeStopAnimation(_pullAnimationController);
      if (!_isDisposed) {
        ref.read(syncStateProvider.notifier).setPulling(false);
      }
    }
  }

  /// رفع التغييرات المحلية فقط باستخدام AppwriteDeltaSync
  Future<void> _pushChanges(BuildContext context) async {
    final syncState = ref.read(syncStateProvider);
    if (syncState.isSyncing) return;

    final syncNotifier = ref.read(syncStateProvider.notifier);
    syncNotifier.setPushing(true);
    _safeRepeatAnimation(_pushAnimationController);

    final stopwatch = Stopwatch()..start();

    try {
      if (mounted) {
        _showSnackBar(
          context,
          '🔄 جاري رفع التغييرات المحلية...',
          Colors.purple,
          showProgress: true,
        );
      }

      // ✅ استخدام AppwriteDeltaSync بدلاً من SyncService
      if (!await _ensureAppwriteDeltaSyncInitialized()) {
        throw Exception('فشل تهيئة خدمة المزامنة. تأكد من تفعيل Appwrite في الإعدادات.');
      }
      
      final deltaSync = AppwriteDeltaSync.instance;
      final result = await _withRetry(
        () => deltaSync.pushDeltaChanges(),
        maxRetries: 3,
        operationName: 'رفع التغييرات',
      );

      stopwatch.stop();

      syncNotifier.setLastSyncTime(DateTime.now());
      
      // تحديث إحصائيات المزامنة
      ref.invalidate(appwrite_providers.syncStatsProvider);
      ref.invalidate(syncLogStatsProvider);
      ref.invalidate(syncHistoryProvider);

      if (mounted) {
        final pushedText = result.recordsPushed > 0 ? '\n📤 ${result.recordsPushed} سجل تم رفعه' : '';
        final failedText = result.failedCount > 0 ? '\n⚠️ ${result.failedCount} فشل' : '';
        _showSnackBar(
          context,
          '✅ تم رفع التغييرات بنجاح!$pushedText$failedText\n⏱️ ${stopwatch.elapsed.inSeconds}.${stopwatch.elapsed.inMilliseconds % 1000} ثانية',
          result.failedCount > 0 ? Colors.orange : Colors.green,
        );
      }
    } catch (e) {
      debugPrint('❌ خطأ في رفع التغييرات: $e');

      stopwatch.stop();
      
      // تحديث عداد الأخطاء
      final currentErrors = syncState.syncErrorsCount + 1;
      syncNotifier.updateErrorsCount(currentErrors);
      
      // تحديث إحصائيات المزامنة
      ref.invalidate(appwrite_providers.syncStatsProvider);
      ref.invalidate(syncLogStatsProvider);
      ref.invalidate(syncHistoryProvider);

      if (mounted) {
        _showSnackBar(
          context,
          '❌ تعذر رفع التغييرات: ${e.toString()}',
          Colors.red,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'عرض السجل',
            textColor: Colors.white,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SyncHistoryScreen(),
                ),
              );
            },
          ),
        );
      }
    } finally {
      _safeStopAnimation(_pushAnimationController);
      if (!_isDisposed) {
        ref.read(syncStateProvider.notifier).setPushing(false);
      }
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

  Future<String> _getDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var deviceId = prefs.getString('deviceId');
      if (deviceId == null) {
        deviceId = 'device_${DateTime.now().millisecondsSinceEpoch}';
        await prefs.setString('deviceId', deviceId);
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
    required bool isEnabled,
    required bool isPulling,
  }) {
    final Color buttonColor = isPulling ? Colors.blue : Colors.blue.withOpacity(0.6);
    const IconData buttonIcon = Icons.cloud_download;
    final String buttonText = isPulling ? 'جاري السحب...' : 'سحب التغييرات';

    return Tooltip(
      message: 'اضغط لسحب التغييرات من السيرفر',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [buttonColor.withOpacity(0.85), buttonColor],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(10),
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
                  if (isPulling && _pullAnimationController != null)
                    RotationTransition(
                      turns: _pullAnimationController!,
                      child: const Icon(buttonIcon, size: 14, color: Colors.white),
                    )
                  else
                    const Icon(buttonIcon, size: 14, color: Colors.white),
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
    );
  }

  Widget _buildPushButton({
    required bool hasChanges,
    required int pendingCount,
    required bool isEnabled,
    required bool isPushing,
  }) {
    final Color buttonColor = isPushing || hasChanges ? Colors.purple : Colors.grey.shade400;
    const IconData buttonIcon = Icons.cloud_upload;
    final String buttonText = isPushing ? 'جاري الرفع...' : (hasChanges ? 'رفع التغييرات' : 'محدّث');

    return Tooltip(
      message: hasChanges ? 'اضغط لرفع $pendingCount تغيير' : 'جميع التغييرات مرفوعة',
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
                      if (isPushing && _pushAnimationController != null)
                        RotationTransition(
                          turns: _pushAnimationController!,
                          child: const Icon(buttonIcon, size: 14, color: Colors.white),
                        )
                      else
                        const Icon(buttonIcon, size: 14, color: Colors.white),
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

  @override
  Widget build(BuildContext context) {
    final syncState = ref.watch(syncStateProvider);
    final hasLocalChanges = syncState.pendingChangesCount > 0;

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
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildPullButton(
                isEnabled: !syncState.isSyncing,
                isPulling: syncState.isPulling,
              ),
              const SizedBox(width: 8),
              _buildPushButton(
                hasChanges: hasLocalChanges,
                pendingCount: syncState.pendingChangesCount,
                isEnabled: !syncState.isSyncing,
                isPushing: syncState.isPushing,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: syncState.isSyncing
                  ? Colors.blue.shade50
                  : hasLocalChanges
                      ? Colors.orange.shade50
                      : Colors.green.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: syncState.isSyncing
                    ? Colors.blue.shade200
                    : hasLocalChanges
                        ? Colors.orange.shade200
                        : Colors.green.shade200,
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  syncState.isSyncing ? Icons.sync : (hasLocalChanges ? Icons.sync_problem : Icons.check_circle),
                  size: 12,
                  color: syncState.isSyncing ? Colors.blue : (hasLocalChanges ? Colors.orange : Colors.green),
                ),
                const SizedBox(width: 5),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      syncState.isSyncing
                          ? 'جاري المزامنة التفاضلية...'
                          : hasLocalChanges
                              ? '${syncState.pendingChangesCount} تغيير محلي معلق'
                              : 'محدّث',
                      style: TextStyle(
                        fontSize: 11,
                        color: syncState.isSyncing
                            ? Colors.blue.shade900
                            : hasLocalChanges
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
      ),
    );
  }
}
