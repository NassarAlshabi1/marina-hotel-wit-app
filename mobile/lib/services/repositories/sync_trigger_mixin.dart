// SyncTriggerMixin — automatically triggers pushLocalChanges after
// any outbox merge in a repository.
//
// This ensures every CRUD operation that writes to the outbox also
// triggers an immediate debounced push, without requiring each screen
// to manually call pushLocalChanges().

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../appwrite_sync_manager.dart';

mixin SyncTriggerMixin {
  Timer? _syncDebounceTimer;
  static const Duration _debounceDuration = Duration(seconds: 2);

  /// Triggers a debounced pushLocalChanges.
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
        debugPrint('⚠️ triggerSync: no device ID, skipping');
        return;
      }
      final manager = AppwriteSyncManager.instance;
      if (manager == null) {
        debugPrint('⚠️ triggerSync: sync manager not initialized');
        return;
      }
      unawaited(
        manager.pushLocalChanges().catchError((Object e) {
          debugPrint('⚠️ Auto-sync push failed: $e');
          return 0;
        }),
      );
    } catch (e) {
      debugPrint('⚠️ triggerSync error: $e');
    }
  }

  void cancelPendingSync() {
    _syncDebounceTimer?.cancel();
  }
}
