import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'appwrite_sync_manager.dart';
import 'google_drive_unified_sync_coordinator.dart';
import 'appwrite_service.dart';
import 'local_db.dart';

class CentralSyncCoordinator {
  static final CentralSyncCoordinator _instance =
      CentralSyncCoordinator._internal();
  factory CentralSyncCoordinator() => _instance;
  static CentralSyncCoordinator get instance => _instance;

  CentralSyncCoordinator._internal();

  Timer? _debounceTimer;
  bool _isSyncing = false;
  DateTime? _lastSyncTime;
  int _syncCount = 0;

  static const Duration unifiedDebounce = Duration(seconds: 3);
  static const Duration syncCooldown = Duration(seconds: 10);

  void notifyLocalChange({
    required String table,
    required String operation,
  }) {
    debugPrint('🔔 CentralSyncCoordinator: تغيير في $table ($operation)');

    _debounceTimer?.cancel();
    _debounceTimer = Timer(unifiedDebounce, () async {
      await _performSync(reason: 'local_change:$table:$operation');
    });
  }

  Future<bool> syncNow({
    bool push = true,
    bool pull = true,
    String reason = 'manual',
  }) async {
    _debounceTimer?.cancel();
    return await _performSync(
      push: push,
      pull: pull,
      reason: reason,
    );
  }

  Future<bool> _performSync({
    bool push = true,
    bool pull = true,
    required String reason,
  }) async {
    if (_lastSyncTime != null) {
      final elapsed = DateTime.now().difference(_lastSyncTime!);
      if (elapsed < syncCooldown) {
        final remaining = syncCooldown - elapsed;
        debugPrint(
            '⏸️ Sync في cooldown ($elapsed < $syncCooldown), scheduling after $remaining');

        _debounceTimer?.cancel();
        _debounceTimer = Timer(remaining, () async {
          await _performSync(
              push: push, pull: pull, reason: 'cooldown_delayed:$reason');
        });

        return true; // sync is queued
      }
    }

    if (_isSyncing) {
      debugPrint('⏸️ Sync قيد التنفيذ بالفعل');
      return false;
    }

    _isSyncing = true;
    _syncCount++;
    debugPrint(
        '🔄 [$_syncCount] بدء المزامنة: $reason (push: $push, pull: $pull)');

    try {
      final prefs = await SharedPreferences.getInstance();
      final appwriteEnabled = prefs.getBool('appwrite_sync_enabled') ?? true;
      final googleDriveEnabled =
          prefs.getBool('google_drive_sync_enabled') ?? false;

      bool success = true;

      if (appwriteEnabled) {
        success = await _syncWithAppwrite(push: push, pull: pull);
      } else if (googleDriveEnabled) {
        success = await _syncWithGoogleDrive(push: push, pull: pull);
      } else {
        debugPrint('⚠️ لا توجد أنظمة مزامنة مفعلة');
        return false;
      }

      if (success) {
        _lastSyncTime = DateTime.now();
        debugPrint('✅ [$_syncCount] المزامنة نجحت: $reason');
      } else {
        debugPrint('❌ [$_syncCount] المزامنة فشلت: $reason');
      }

      return success;
    } catch (e, stackTrace) {
      debugPrint('❌ [$_syncCount] خطأ في المزامنة: $e');
      debugPrint('Stack trace: ${stackTrace.toString()}');
      return false;
    } finally {
      _isSyncing = false;
    }
  }

  Future<bool> _syncWithAppwrite({
    required bool push,
    required bool pull,
  }) async {
    try {
      final database = DatabaseManager.instance;
      final appwriteService = AppwriteService();
      final syncManager = AppwriteSyncManager(
        appwriteService: appwriteService,
        database: database,
      );

      await syncManager.initialize();

      final result = await syncManager.sync(push: push, pull: pull);
      return result.isSuccess;
    } catch (e, stackTrace) {
      debugPrint('❌ خطأ في المزامنة مع Appwrite: $e');
      debugPrint('Stack trace: ${stackTrace.toString()}');
      return false;
    }
  }

  Future<bool> _syncWithGoogleDrive({
    required bool push,
    required bool pull,
  }) async {
    try {
      final coordinator = GoogleDriveUnifiedSyncCoordinator.instance;

      if (push) {
        final pushResult = await coordinator.pushChanges();
        if (!pushResult) return false;
      }

      if (pull) {
        final pullResult = await coordinator.pullChanges();
        if (!pullResult) return false;
      }

      return true;
    } catch (e, stackTrace) {
      debugPrint('❌ خطأ في المزامنة مع Google Drive: $e');
      debugPrint('Stack trace: ${stackTrace.toString()}');
      return false;
    }
  }

  void dispose() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }

  Map<String, dynamic> getStatus() {
    return {
      'is_syncing': _isSyncing,
      'last_sync': _lastSyncTime?.toIso8601String(),
      'has_pending_debounce': _debounceTimer?.isActive ?? false,
      'sync_count': _syncCount,
      'cooldown_remaining': _lastSyncTime != null
          ? syncCooldown.inSeconds -
              DateTime.now().difference(_lastSyncTime!).inSeconds
          : 0,
    };
  }
}
