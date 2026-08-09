// SyncTriggerMixin — automatically triggers pushLocalChanges after
// any outbox merge in a repository.
//
// This ensures every CRUD operation that writes to the outbox also
// triggers an immediate debounced push, without requiring each screen
// to manually call pushLocalChanges().
//
// ✅ Code Review Fix (2026-08-06): توحيد مسار الـ sync.
// سابقاً، كان SyncTriggerMixin يستدعي manager.pushLocalChanges() مباشرة،
// بينما AutoOutboxSyncWatcher يستدعي manager.sync(pull: false) عبر _pushFn.
// هذا يُسبت تكرار sync محتمل على الأجهزة الضعيفة (double network/CPU work).
// الإصلاح: تحويل triggerSync() لاستخدام AutoOutboxSyncWatcher.pushNow()
// الذي يستفيد من guard `_pushing` الموجود في الـ watcher، مما يمنع
// أي تداخل بين المسارين. مسار واحد = sync واحد.

import 'dart:async';

import '../appwrite_sync_manager.dart';
import '../auto_outbox_sync_watcher.dart';
import 'sync_guard.dart';
import 'package:marina_hotel_mobile/utils/debug_log.dart';

mixin SyncTriggerMixin {
  Timer? _syncDebounceTimer;
  static const Duration _debounceDuration = Duration(seconds: 2);

  /// Triggers a debounced pushLocalChanges.
  ///
  /// ✅ P2-1 FIX: استخدام SyncGuard لمنع الـ Race Condition
  /// بين AutoOutboxSyncWatcher والـ Manual Trigger.
  void triggerSync() {
    _syncDebounceTimer?.cancel();
    _syncDebounceTimer = Timer(_debounceDuration, _doSync);
  }

  /// Triggers an immediate (non-debounced) push.
  void triggerSyncNow() {
    _syncDebounceTimer?.cancel();
    _doSync();
  }

  void _doSync() {
    try {
      final deviceId = AppwriteSyncManager.currentDeviceIdStatic;
      if (deviceId == null || deviceId.isEmpty) {
        dlog('⚠️ triggerSync: no device ID, skipping');
        return;
      }

      // ✅ P2-1 FIX: احجز القفل التنافي فوراً قبل أي عمل asynchronous
      // يمنع الـ Race Condition بين الـ Watcher والـ Manual Trigger
      if (!SyncGuard.canStart(label: 'sync_trigger_manual')) {
        dlog('⏸️ Trigger sync skipped — another sync is active (${SyncGuard.activeLabel})');
        return;
      }
      SyncGuard.markStarted(label: 'sync_trigger_manual');

      // ✅ المسار الرئيسي: عبر watcher الموحّد
      if (!AutoOutboxSyncWatcher.instance.isRunning) {
        // Fallback: watcher لم يبدأ بعد — استخدم المسار المباشر
        final manager = AppwriteSyncManager.instance;
        if (manager == null) {
          dlog('⚠️ triggerSync: sync manager not initialized');
          SyncGuard.markFinished();
          return;
        }
        unawaited(
          manager.pushLocalChanges().catchError((Object e) {
            dlog(() => '⚠️ Auto-sync push failed (direct): $e');
            SyncGuard.markFinished();
          }),
        );
        return;
      }

      // ✅ استدعاء الرفع
      unawaited(
        AutoOutboxSyncWatcher.instance.pushNow().catchError((Object e) {
          dlog(() => '⚠️ Auto-sync push failed (via watcher): $e');
          SyncGuard.markFinished();
        }),
      );
    } catch (e) {
      dlog(() => '⚠️ triggerSync error: $e');
      SyncGuard.markFinished();
    }
  }

  void cancelPendingSync() {
    _syncDebounceTimer?.cancel();
  }
}