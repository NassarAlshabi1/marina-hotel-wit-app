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

import '../../utils/debug_log.dart';
import '../appwrite_sync_manager.dart';
import '../auto_outbox_sync_watcher.dart';

mixin SyncTriggerMixin {
  Timer? _syncDebounceTimer;
  static const Duration _debounceDuration = Duration(seconds: 2);

  /// Triggers a debounced pushLocalChanges.
  ///
  /// التفويض لـ AutoOutboxSyncWatcher (يملك الحماية داخلياً) — لا قفل هنا.
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

      // المسار الرئيسي: عبر watcher الموحّد (يملك SyncGuard داخلياً في
      // _doPush — لا نكتسب القفل هنا وإلا حجزناه على أنفسنا وأفشلنا الرفع
      // وسرّبنا الـ token لأن release كان داخل catchError فقط).
      if (!AutoOutboxSyncWatcher.instance.isRunning) {
        // Fallback: watcher لم يبدأ بعد — استخدم المسار المباشر
        // (المدير محمي داخلياً بـ _syncInProgress).
        final manager = AppwriteSyncManager.instance;
        unawaited(
          manager.pushLocalChanges().catchError((Object e) {
            dlog(() => '⚠️ Auto-sync push failed (direct): $e');
            return 0;
          }),
        );
        return;
      }

      // ✅ استدعاء الرفع (pushNow يفوّض لـ _doPush بلا قفل مسبق)
      unawaited(
        AutoOutboxSyncWatcher.instance.pushNow().catchError((Object e) {
          dlog(() => '⚠️ Auto-sync push failed (via watcher): $e');
        }),
      );
    } catch (e) {
      dlog(() => '⚠️ triggerSync error: $e');
    }
  }

  void cancelPendingSync() {
    _syncDebounceTimer?.cancel();
  }
}
