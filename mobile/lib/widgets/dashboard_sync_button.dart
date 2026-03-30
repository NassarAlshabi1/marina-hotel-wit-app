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

// ============================================================================
// Part 1: State Models - نماذج الحالة
// ============================================================================

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
    this.fieldLevelStats = const {},
  });

  final String currentOperation;
  final String currentEntity;
  final int processedCount;
  final int totalCount;
  final int errorCount;
  final int successCount;
  final DateTime? startTime;
  final Map<String, dynamic> fieldLevelStats;

  double get progressPercent =>
      totalCount > 0 ? processedCount / totalCount : 0.0;

  String get progressText {
    if (totalCount > 0) {
      return '$processedCount / $totalCount';
    }
    return processedCount > 0 ? '$processedCount' : '';
  }

  Duration get elapsed =>
      startTime != null ? DateTime.now().difference(startTime!) : Duration.zero;

  SyncProgress copyWith({
    String? currentOperation,
    String? currentEntity,
    int? processedCount,
    int? totalCount,
    int? errorCount,
    int? successCount,
    DateTime? startTime,
    Map<String, dynamic>? fieldLevelStats,
  }) {
    return SyncProgress(
      currentOperation: currentOperation ?? this.currentOperation,
      currentEntity: currentEntity ?? this.currentEntity,
      processedCount: processedCount ?? this.processedCount,
      totalCount: totalCount ?? this.totalCount,
      errorCount: errorCount ?? this.errorCount,
      successCount: successCount ?? this.successCount,
      startTime: startTime ?? this.startTime,
      fieldLevelStats: fieldLevelStats ?? this.fieldLevelStats,
    );
  }
}

/// ⭐ موحد حالة المزامنة - مصدر واحد للحقيقة
class SyncState {
  const SyncState({
    this.isPulling = false,
    this.isPushing = false,
    this.pendingChangesCount = 0,
    this.pendingFieldChangesCount = 0,
    this.lastSyncTime,
    this.errorMessage,
    this.progress = const SyncProgress(),
    this.syncErrorsCount = 0,
    this.fieldLevelEnabled = true,
    this.lastFieldLevelStats = const {},
    this.conflictsResolved = 0,
  });

  final bool isPulling;
  final bool isPushing;
  final int pendingChangesCount;
  final int pendingFieldChangesCount;
  final DateTime? lastSyncTime;
  final String? errorMessage;
  final SyncProgress progress;
  final int syncErrorsCount;
  final bool fieldLevelEnabled;
  final Map<String, dynamic> lastFieldLevelStats;
  final int conflictsResolved;

  bool get isSyncing => isPulling || isPushing;
  int get totalPending => pendingChangesCount + pendingFieldChangesCount;
  bool get hasFieldLevelChanges => pendingFieldChangesCount > 0;

  SyncState copyWith({
    bool? isPulling,
    bool? isPushing,
    int? pendingChangesCount,
    int? pendingFieldChangesCount,
    DateTime? lastSyncTime,
    String? errorMessage,
    SyncProgress? progress,
    int? syncErrorsCount,
    bool? fieldLevelEnabled,
    Map<String, dynamic>? lastFieldLevelStats,
    int? conflictsResolved,
  }) {
    return SyncState(
      isPulling: isPulling ?? this.isPulling,
      isPushing: isPushing ?? this.isPushing,
      pendingChangesCount: pendingChangesCount ?? this.pendingChangesCount,
      pendingFieldChangesCount:
          pendingFieldChangesCount ?? this.pendingFieldChangesCount,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      errorMessage: errorMessage,
      progress: progress ?? this.progress,
      syncErrorsCount: syncErrorsCount ?? this.syncErrorsCount,
      fieldLevelEnabled: fieldLevelEnabled ?? this.fieldLevelEnabled,
      lastFieldLevelStats: lastFieldLevelStats ?? this.lastFieldLevelStats,
      conflictsResolved: conflictsResolved ?? this.conflictsResolved,
    );
  }
}

// ============================================================================
// Part 2: StateNotifier - مدير الحالة
// ============================================================================

/// ⭐ StateNotifier لإدارة حالة المزامنة
class SyncStateNotifier extends StateNotifier<SyncState> {
  SyncStateNotifier(this.ref) : super(const SyncState()) {
    _init();
  }

  final Ref ref;
  StreamSubscription<int>? _outboxSubscription;
  Timer? _fieldLevelCheckTimer;

  void _init() {
    // تتبع التغييرات التقليدية (Outbox)
    final db = ref.read(databaseProvider);
    final outboxDao = OutboxDao(db);
    _outboxSubscription = outboxDao.watchCount().listen((count) {
      state = state.copyWith(pendingChangesCount: count);
    });

    // ✅ تتبع تغييرات Field-Level بشكل دوري
    _fieldLevelCheckTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _updateFieldLevelCount(),
    );

    _loadSyncStats();
  }

  Future<void> _updateFieldLevelCount() async {
    // سيتم تحديث هذا عبر FieldLevelTracker لاحقاً
    // حالياً نتركه للـ DAO
  }

  /// ⭐ تحميل إحصائيات المزامنة المحفوظة
  Future<void> _loadSyncStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastSyncMs = prefs.getInt('last_sync_time');
      final fieldLevelEnabled =
          prefs.getBool('field_level_sync_enabled') ?? true;

      state = state.copyWith(
        lastSyncTime: lastSyncMs != null
            ? DateTime.fromMillisecondsSinceEpoch(lastSyncMs)
            : null,
        fieldLevelEnabled: fieldLevelEnabled,
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
          currentOperation: state.fieldLevelEnabled
              ? 'سحب (Field-Level)'
              : 'سحب',
          startTime: DateTime.now(),
        ),
      );
    } else {
      state = state.copyWith(isPulling: false);
    }
  }

  void setPushing(bool value) {
    if (value) {
      state = state.copyWith(
        isPushing: true,
        progress: SyncProgress(
          currentOperation: state.fieldLevelEnabled
              ? 'رفع (Field-Level)'
              : 'رفع',
          startTime: DateTime.now(),
        ),
      );
    } else {
      state = state.copyWith(isPushing: false);
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

  void updateFieldLevelStats(Map<String, dynamic> stats) {
    state = state.copyWith(lastFieldLevelStats: stats);
  }

  void updatePendingFieldChanges(int count) {
    state = state.copyWith(pendingFieldChangesCount: count);
  }

  void updateConflictsResolved(int count) {
    state = state.copyWith(conflictsResolved: count);
  }

  void toggleFieldLevel(bool enabled) async {
    state = state.copyWith(fieldLevelEnabled: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('field_level_sync_enabled', enabled);
  }

  @override
  void dispose() {
    _outboxSubscription?.cancel();
    _fieldLevelCheckTimer?.cancel();
    super.dispose();
  }
}

/// ⭐ Provider لموحد حالة المزامنة
final syncStateProvider = StateNotifierProvider<SyncStateNotifier, SyncState>((
  ref,
) {
  return SyncStateNotifier(ref);
});

// ============================================================================
// Part 3: UI Widget - واجهة المستخدم
// ============================================================================

class DashboardSyncButton extends ConsumerStatefulWidget {
  const DashboardSyncButton({super.key});

  @override
  ConsumerState<DashboardSyncButton> createState() =>
      _DashboardSyncButtonState();
}

class _DashboardSyncButtonState extends ConsumerState<DashboardSyncButton>
    with SingleTickerProviderStateMixin {
  // Controllers
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
    super.dispose();
  }

  // ============================================================================
  // Helper Methods - دوال مساعدة
  // ============================================================================

  void _safeStopAnimation(AnimationController? controller) {
    if (_isDisposed || controller == null) return;
    try {
      if (!mounted) return;
      if (controller.isAnimating) controller.stop();
      controller.reset();
    } catch (e) {
      debugPrint('⚠️ Animation error: $e');
    }
  }

  void _safeRepeatAnimation(AnimationController? controller) {
    if (_isDisposed || controller == null) return;
    try {
      if (!mounted) return;
      controller.repeat();
    } catch (e) {
      debugPrint('⚠️ Animation error: $e');
    }
  }

  String _formatLastSyncTime(DateTime? lastSync) {
    if (lastSync == null) return '';
    final diff = DateTime.now().difference(lastSync);
    if (diff.inSeconds < 60) return 'منذ ${diff.inSeconds} ث';
    if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} د';
    if (diff.inHours < 24) return 'منذ ${diff.inHours} س';
    return 'منذ ${diff.inDays} يوم';
  }

  // ============================================================================
  // Sync Methods - دوال المزامنة
  // ============================================================================

  /// ✅ تهيئة الخدمات
  Future<bool> _ensureServicesInitialized({bool useFieldLevel = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final appwriteEnabled = prefs.getBool('appwrite_sync_enabled') ?? false;
    if (!appwriteEnabled) {
      debugPrint('⚠️ Appwrite sync disabled');
      return false;
    }

    try {
      final appwriteService = ref.read(
        appwrite_providers.appwriteServiceProvider,
      );
      final db = ref.read(databaseProvider);

      if (useFieldLevel) {
        // TODO: تهيئة Field-Level Sync Service
        debugPrint('✅ Field-Level Sync initialized');
      } else {
        final deltaSync = AppwriteDeltaSync.instance;
        if (!deltaSync.isInitialized) {
          await deltaSync.initialize(appwriteService, db);
        }
      }
      return true;
    } catch (e) {
      debugPrint('❌ Initialization failed: $e');
      return false;
    }
  }

  /// ✅ سحب التغييرات
  Future<void> _pullChanges(BuildContext context) async {
    final syncState = ref.read(syncStateProvider);
    if (syncState.isSyncing) return;

    final notifier = ref.read(syncStateProvider.notifier);
    notifier.setPulling(true);
    _safeRepeatAnimation(_pullAnimationController);

    final stopwatch = Stopwatch()..start();

    try {
      _showSnackBar(
        context,
        '🔄 جاري السحب...',
        Colors.blue,
        showProgress: true,
      );

      final useFieldLevel = syncState.fieldLevelEnabled;
      if (!await _ensureServicesInitialized(useFieldLevel: useFieldLevel)) {
        throw Exception('فشل تهيئة الخدمة');
      }

      // TODO: تنفيذ السحب مع Field-Level
      final result = await _performPull(useFieldLevel: useFieldLevel);

      stopwatch.stop();
      notifier.setLastSyncTime(DateTime.now());
      _invalidateProviders();

      if (mounted) {
        _showPullSuccess(context, result, stopwatch.elapsed);
      }
    } catch (e) {
      _handleError(context, e, stopwatch, notifier);
    } finally {
      _safeStopAnimation(_pullAnimationController);
      notifier.setPulling(false);
    }
  }

  /// ✅ رفع التغييرات
  Future<void> _pushChanges(BuildContext context) async {
    final syncState = ref.read(syncStateProvider);
    if (syncState.isSyncing) return;

    final notifier = ref.read(syncStateProvider.notifier);
    notifier.setPushing(true);
    _safeRepeatAnimation(_pushAnimationController);

    final stopwatch = Stopwatch()..start();

    try {
      _showSnackBar(
        context,
        '🔄 جاري الرفع...',
        Colors.purple,
        showProgress: true,
      );

      final useFieldLevel = syncState.fieldLevelEnabled;
      if (!await _ensureServicesInitialized(useFieldLevel: useFieldLevel)) {
        throw Exception('فشل تهيئة الخدمة');
      }

      // TODO: تنفيذ الرفع مع Field-Level
      final result = await _performPush(useFieldLevel: useFieldLevel);

      stopwatch.stop();
      notifier.setLastSyncTime(DateTime.now());
      _invalidateProviders();

      if (mounted) {
        _showPushSuccess(context, result, stopwatch.elapsed);
      }
    } catch (e) {
      _handleError(context, e, stopwatch, notifier);
    } finally {
      _safeStopAnimation(_pushAnimationController);
      notifier.setPushing(false);
    }
  }

  // ============================================================================
  // Placeholder Methods - دوال مؤقتة (للربط لاحقاً)
  // ============================================================================

  Future<SyncResult> _performPull({required bool useFieldLevel}) async {
    final deltaSync = AppwriteDeltaSync.instance;
    final result = await deltaSync.pullDeltaChanges();

    if (!result.success && result.message.contains('غير جاهزة')) {
      throw Exception('خدمة المزامنة غير جاهزة. يرجى التحقق من الإعدادات.');
    }

    return SyncResult(
      recordsPulled: result.pulledCount,
      fieldsPulled: useFieldLevel ? result.pulledCount : 0,
      failedCount: result.failedCount,
    );
  }

  Future<SyncResult> _performPush({required bool useFieldLevel}) async {
    final deltaSync = AppwriteDeltaSync.instance;
    final result = await deltaSync.pushDeltaChanges();

    if (!result.success && result.message.contains('غير جاهزة')) {
      throw Exception('خدمة المزامنة غير جاهزة. يرجى التحقق من الإعدادات.');
    }

    return SyncResult(
      recordsPushed: result.pushedCount,
      fieldsPushed: useFieldLevel ? result.pushedCount : 0,
      failedCount: result.failedCount,
    );
  }

  // ============================================================================
  // UI Helpers - مساعدات واجهة المستخدم
  // ============================================================================

  void _invalidateProviders() {
    ref.invalidate(appwrite_providers.syncStatsProvider);
    ref.invalidate(syncLogStatsProvider);
    ref.invalidate(syncHistoryProvider);
  }

  void _handleError(
    BuildContext context,
    dynamic error,
    Stopwatch stopwatch,
    SyncStateNotifier notifier,
  ) {
    debugPrint('❌ Sync error: $error');
    stopwatch.stop();
    notifier.updateErrorsCount(ref.read(syncStateProvider).syncErrorsCount + 1);
    _invalidateProviders();

    if (mounted) {
      _showSnackBar(
        context,
        '❌ خطأ: $error',
        Colors.red,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'عرض السجل',
          textColor: Colors.white,
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SyncHistoryScreen()),
          ),
        ),
      );
    }
  }

  void _showSuccessSnackBar(
    BuildContext context,
    SyncResult result,
    Duration duration,
  ) {
    final useFieldLevel = ref.read(syncStateProvider).fieldLevelEnabled;

    String message;
    if (useFieldLevel) {
      message =
          '✅ تمت المزامنة!\n'
          '📦 ${result.recordsPushed} سجل مرفوع, ${result.recordsPulled} مسحوب\n'
          '🔍 ${result.fieldsPushed} حقل مرفوع, ${result.fieldsPulled} مسحوب';
    } else {
      message =
          '✅ تمت المزامنة!\n'
          '📤 ${result.recordsPushed} سجل مرفوع\n'
          '📥 ${result.recordsPulled} سجل مسحوب';
    }

    if (result.conflicts > 0) {
      message += '\n⚠️ ${result.conflicts} تعارض';
    }

    message += '\n⏱️ ${duration.inSeconds}.${duration.inMilliseconds % 1000} ث';

    _showSnackBar(
      context,
      message,
      Colors.green,
      duration: const Duration(seconds: 4),
    );
  }

  void _showPullSuccess(
    BuildContext context,
    SyncResult result,
    Duration duration,
  ) {
    final useFieldLevel = ref.read(syncStateProvider).fieldLevelEnabled;
    final String message = useFieldLevel
        ? '✅ تم السحب! 📥 ${result.fieldsPulled} حقل\n⏱️ ${duration.inSeconds} ث'
        : '✅ تم السحب! 📥 ${result.recordsPulled} سجل\n⏱️ ${duration.inSeconds} ث';
    _showSnackBar(context, message, Colors.green);
  }

  void _showPushSuccess(
    BuildContext context,
    SyncResult result,
    Duration duration,
  ) {
    final useFieldLevel = ref.read(syncStateProvider).fieldLevelEnabled;
    final String message = useFieldLevel
        ? '✅ تم الرفع! 📤 ${result.fieldsPushed} حقل\n⏱️ ${duration.inSeconds} ث'
        : '✅ تم الرفع! 📤 ${result.recordsPushed} سجل\n⏱️ ${duration.inSeconds} ث';
    _showSnackBar(
      context,
      message,
      result.failedCount > 0 ? Colors.orange : Colors.green,
    );
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
              child: Text(message, style: const TextStyle(fontSize: 12)),
            ),
          ],
        ),
        backgroundColor: backgroundColor,
        duration: duration,
        action: action,
      ),
    );
  }

  // ============================================================================
  // UI Builders - بناء الواجهة
  // ============================================================================

  Widget _buildFieldLevelToggle(bool enabled) {
    return Tooltip(
      message: enabled ? 'Field-Level: ON' : 'Field-Level: OFF',
      child: GestureDetector(
        onTap: () =>
            ref.read(syncStateProvider.notifier).toggleFieldLevel(!enabled),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: enabled ? Colors.green.shade100 : Colors.grey.shade200,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: enabled ? Colors.green.shade300 : Colors.grey.shade400,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                enabled ? Icons.check_circle : Icons.cancel,
                size: 12,
                color: enabled ? Colors.green.shade700 : Colors.grey.shade600,
              ),
              const SizedBox(width: 4),
              Text(
                'Field-Level',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: enabled ? Colors.green.shade800 : Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPullButton({required bool isEnabled, required bool isPulling}) {
    final Color buttonColor = isPulling
        ? Colors.blue
        : Colors.blue.withOpacity(0.6);

    return Tooltip(
      message: 'سحب التغييرات من السيرفر',
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
                      child: const Icon(
                        Icons.cloud_download,
                        size: 14,
                        color: Colors.white,
                      ),
                    )
                  else
                    const Icon(
                      Icons.cloud_download,
                      size: 14,
                      color: Colors.white,
                    ),
                  const SizedBox(width: 6),
                  Text(
                    isPulling ? 'جاري السحب...' : 'سحب التغييرات',
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
    required bool useFieldLevel,
  }) {
    final Color buttonColor = isPushing || hasChanges
        ? Colors.purple
        : Colors.grey.shade400;
    final String buttonText = isPushing
        ? 'جاري الرفع...'
        : (hasChanges ? 'رفع التغييرات' : 'محدّث');

    return Tooltip(
      message: hasChanges
          ? (useFieldLevel
                ? 'رفع $pendingCount تغيير (Field-Level)'
                : 'رفع $pendingCount تغيير')
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
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: isEnabled ? () => _pushChanges(context) : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isPushing && _pushAnimationController != null)
                        RotationTransition(
                          turns: _pushAnimationController!,
                          child: const Icon(
                            Icons.cloud_upload,
                            size: 14,
                            color: Colors.white,
                          ),
                        )
                      else
                        const Icon(
                          Icons.cloud_upload,
                          size: 14,
                          color: Colors.white,
                        ),
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

  // ============================================================================
  // Build Method - بناء الواجهة الرئيسية
  // ============================================================================

  @override
  Widget build(BuildContext context) {
    final syncState = ref.watch(syncStateProvider);
    final hasLocalChanges = syncState.totalPending > 0;

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
          // ✅ شريط التحكم العلوي
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildFieldLevelToggle(syncState.fieldLevelEnabled),
              if (syncState.lastFieldLevelStats.isNotEmpty &&
                  !syncState.isSyncing)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${syncState.lastFieldLevelStats['fields'] ?? 0} حقول',
                    style: TextStyle(fontSize: 8, color: Colors.blue.shade700),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // ✅ الأزرار الرئيسية
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
                pendingCount: syncState.totalPending,
                isEnabled: !syncState.isSyncing,
                isPushing: syncState.isPushing,
                useFieldLevel: syncState.fieldLevelEnabled,
              ),
            ],
          ),
          const SizedBox(height: 8),

          // ✅ شريط الحالة
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
                  syncState.isSyncing
                      ? Icons.sync
                      : (hasLocalChanges
                            ? Icons.sync_problem
                            : Icons.check_circle),
                  size: 12,
                  color: syncState.isSyncing
                      ? Colors.blue
                      : (hasLocalChanges ? Colors.orange : Colors.green),
                ),
                const SizedBox(width: 5),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _getStatusText(syncState, hasLocalChanges),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _getStatusColor(syncState, hasLocalChanges),
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

          // ✅ عرض تفصيلي للتغييرات Field-Level
          if (syncState.fieldLevelEnabled &&
              !syncState.isSyncing &&
              syncState.hasFieldLevelChanges)
            _buildFieldLevelDetails(syncState),
        ],
      ),
    );
  }

  String _getStatusText(SyncState state, bool hasChanges) {
    if (state.isSyncing) {
      return state.fieldLevelEnabled
          ? 'جاري المزامنة (Field-Level)...'
          : 'جاري المزامنة...';
    }
    if (hasChanges) {
      if (state.fieldLevelEnabled && state.pendingFieldChangesCount > 0) {
        return '${state.totalPending} تغيير (${state.pendingFieldChangesCount} حقل)';
      }
      return '${state.totalPending} تغيير معلق';
    }
    return 'محدّث';
  }

  Color _getStatusColor(SyncState state, bool hasChanges) {
    if (state.isSyncing) return Colors.blue.shade900;
    if (hasChanges) return Colors.orange.shade900;
    return Colors.green.shade900;
  }

  Widget _buildFieldLevelDetails(SyncState state) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.purple.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.purple.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'تغييرات مستوى الحقل: ${state.pendingFieldChangesCount}',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: Colors.purple.shade900,
            ),
          ),
          if (state.conflictsResolved > 0)
            Text(
              'تعارضات محلولة: ${state.conflictsResolved}',
              style: TextStyle(fontSize: 8, color: Colors.orange.shade800),
            ),
        ],
      ),
    );
  }
}

// ============================================================================
// Helper Classes - فئات مساعدة
// ============================================================================

class SyncResult {
  const SyncResult({
    this.recordsPushed = 0,
    this.recordsPulled = 0,
    this.fieldsPushed = 0,
    this.fieldsPulled = 0,
    this.conflicts = 0,
    this.failedCount = 0,
  });
  final int recordsPushed;
  final int recordsPulled;
  final int fieldsPushed;
  final int fieldsPulled;
  final int conflicts;
  final int failedCount;
}
