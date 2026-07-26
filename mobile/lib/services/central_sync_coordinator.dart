import 'dart:async';

import '../utils/debug_log.dart';
import 'auto_backup_manager.dart';
import 'unified_sync_orchestrator.dart';

class CentralSyncCoordinator {
  factory CentralSyncCoordinator() => _instance;

  CentralSyncCoordinator._internal();
  static final CentralSyncCoordinator _instance = CentralSyncCoordinator._internal();
  static CentralSyncCoordinator get instance => _instance;

  Timer? _debounceTimer;
  bool _isSyncing = false;
  DateTime? _lastSyncTime;
  int _syncCount = 0;

  static const Duration unifiedDebounce = Duration(seconds: 3);
  static const Duration syncCooldown = Duration(seconds: 10);

  void notifyLocalChange({required String table, required String operation}) {
    dlog(() => '🔔 CentralSyncCoordinator: تغيير في $table ($operation)');

    _debounceTimer?.cancel();
    _debounceTimer = Timer(unifiedDebounce, () async {
      // ✅ FIX (Crashlytics fatal "Connection reset by peer"):
      // Timer callbacks async لا تُلتقط استثناءاتها تلقائياً بواسطة
      // Flutter framework — تصل كـ unhandled async error إلى Crashlytics.
      // حتى لو كان _performSync يلتقط داخلياً، أي خطأ غير متوقع (مثل
      // SocketException أثناء write sync_log) سيصعد إلى هنا ويُسبب fatal.
      try {
        await _performSync(reason: 'local_change:$table:$operation');
      } catch (e, stackTrace) {
        derr(() => 'CentralSyncCoordinator: خطأ في المزامنة المؤجلة: $e');
        derr(() => 'Stack trace: $stackTrace');
        // لا نرمي — Timer callback لا يجب أن يرمي استثناء
      }
    });
  }

  /// إشعار موحد للأنظمة: يُبلغ AutoBackupManager ويلغي المزامنة التفاضلية.
  /// يستبدل النمط المتكرر في الشاشات الذي يستدعي كل خدمة على حدة.
  Future<void> notifyTableChange({required String table, required String operation}) async {
    await AutoBackupManager.instance.onDataChange(table, operation);
    notifyLocalChange(table: table, operation: operation);
  }

  Future<bool> syncNow({bool push = true, bool pull = true, String reason = 'manual'}) async {
    _debounceTimer?.cancel();
    return _performSync(push: push, pull: pull, reason: reason);
  }

  Future<bool> _performSync({
    required String reason,
    bool push = true,
    bool pull = true,
  }) async {
    if (_lastSyncTime != null) {
      final elapsed = DateTime.now().difference(_lastSyncTime!);
      if (elapsed < syncCooldown) {
        final remaining = syncCooldown - elapsed;
        dlog(() => '⏸️ Sync في cooldown ($elapsed < $syncCooldown), scheduling after $remaining');

        _debounceTimer?.cancel();
        _debounceTimer = Timer(remaining, () async {
          // ✅ إصلاح جذري: Timer callback async بدون try-catch يُسبب
          // unhandled async error → Crashlytics Fatal
          try {
            await _performSync(push: push, pull: pull, reason: 'cooldown_delayed:$reason');
          } catch (e, stackTrace) {
            derr(() => 'CentralSyncCoordinator: خطأ في cooldown delayed sync: $e');
            derr(() => 'Stack trace: $stackTrace');
          }
        });

        return true;
      }
    }

    if (_isSyncing) {
      dlog('⏸️ Sync قيد التنفيذ بالفعل');
      return false;
    }

    _isSyncing = true;
    _syncCount++;
    dlog(() => '🔄 [$_syncCount] بدء المزامنة: $reason (push: $push, pull: $pull)');

    try {
      final success = await UnifiedSyncOrchestrator.instance.syncNow(push: push, pull: pull, reason: reason);

      if (success) {
        _lastSyncTime = DateTime.now();
        dlog(() => '✅ [$_syncCount] المزامنة نجحت: $reason');
      } else {
        derr(() => '[$_syncCount] المزامنة فشلت: $reason');
      }

      return success;
    } catch (e, stackTrace) {
      derr(() => '[$_syncCount] خطأ في المزامنة: $e');
      derr(() => 'Stack trace: $stackTrace');
      return false;
    } finally {
      _isSyncing = false;
    }
  }

  void dispose() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _isSyncing = false;
  }

  /// تنظيف آمن للمثيل Singleton
  static void disposeInstance() {
    _instance.dispose();
  }

  Map<String, dynamic> getStatus() {
    return {
      'is_syncing': _isSyncing,
      'last_sync': _lastSyncTime?.toIso8601String(),
      'has_pending_debounce': _debounceTimer?.isActive ?? false,
      'sync_count': _syncCount,
      'cooldown_remaining': _lastSyncTime != null
          ? syncCooldown.inSeconds - DateTime.now().difference(_lastSyncTime!).inSeconds
          : 0,
    };
  }
}
