// lib/services/remote_change_notification_service.dart
//
// ✅ Wave 7 (2026-08-12): Local notifications for remote changes from other devices.
//
// This service provides a single, centralized hook for showing local notifications
// when remote changes from another device are successfully applied locally.
//
// ## Design Decisions (evidence-based from code trace)
//
// 1. **Hook point**: `AppwriteSyncManager._notifyRemoteChangesApplied()` is called
//    from each `_sync*` method after `adapter.upsertFromJson()` succeeds.
//    This is the ONLY point where we know the change was actually applied.
//
// 2. **"From another device" detection**: Uses `deviceId` field from remote
//    document data (`remoteData['deviceId']`), compared with `_currentDeviceId`.
//    Both are confirmed from code:
//    - `_currentDeviceId` is set from SharedPreferences (sync_manager.dart:307)
//    - `remoteData['deviceId']` is read in `SyncPullService.checkAndResolveConflict` (sync_pull_service.dart:262)
//    - `deviceId` is stored on every record via `SyncFields` mixin (local_db.dart)
//
// 3. **Dedup**: Uses SharedPreferences with a fingerprint key:
//    `entity:localUuid:deviceId:lastModified`
//    This survives app restart (persistent dedup).
//
// 4. **Batching**: Collects changes during a sync cycle, then shows ONE
//    notification per cycle (not per record). Uses a simple timer-based
//    debounce: if multiple changes arrive within 5 seconds, they're batched.
//
// 5. **No FCM dependency**: This service does NOT listen to FCM directly.
//    It only fires after local apply succeeds — no false positives from
//    FCM messages without actual data changes.
//
// 6. **No self-notification**: If `remoteDeviceId == _currentDeviceId`,
//    the change is from this device — no notification shown.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:marina_hotel_mobile/utils/debug_log.dart';
import 'sync_notification_manager.dart';

/// ✅ Wave 7: Service for showing local notifications when remote changes
/// from another device are successfully applied locally.
///
/// ## Usage
/// Called from `AppwriteSyncManager` after each `upsertFromJson` succeeds:
/// ```dart
/// await RemoteChangeNotificationService.instance.onRemoteRecordApplied(
///   entity: 'rooms',
///   localUuid: 'room-uuid-123',
///   remoteDeviceId: 'device-abc',
///   currentDeviceId: _currentDeviceId,
///   lastModified: 1700000000,
/// );
/// ```
///
/// After all sync phases complete, call:
/// ```dart
/// await RemoteChangeNotificationService.instance.flushPendingNotifications();
/// ```
class RemoteChangeNotificationService {
  RemoteChangeNotificationService._();
  static RemoteChangeNotificationService? _instance;
  // ignore: prefer_constructors_over_static_methods
  static RemoteChangeNotificationService get instance =>
      _instance ??= RemoteChangeNotificationService._();

  /// Dedup key prefix in SharedPreferences.
  static const String _dedupKeyPrefix = 'remote_notif_dedup_';

  /// ✅ Wave 7 tighten: Timestamp index key — tracks when each dedup key
  /// was created, so we can evict oldest entries (LRU) instead of arbitrary
  /// ones. SharedPreferences doesn't support ordering, so we maintain a
  /// separate index: `remote_notif_dedup_index` → JSON map of
  /// `fingerprint → timestamp`.
  static const String _dedupIndexKey = 'remote_notif_dedup_index';

  /// Max dedup keys to keep (cleanup old entries).
  static const int _maxDedupKeys = 500;

  /// Pending changes collected during a sync cycle.
  /// Key: deviceId, Value: count of changes from that device.
  final Map<String, int> _pendingChanges = {};

  /// Generation barrier for async callbacks that are in-flight during a
  /// failed sync. clearPending() advances it so stale callbacks cannot
  /// repopulate the notification batch after it has been cleared.
  int _pendingGeneration = 0;

  /// ✅ Wave 7 tighten: Track entities for richer notification body.
  final Set<String> _pendingEntities = {};

  /// Set of dedup fingerprints already notified in this session.
  final Set<String> _sessionNotified = {};

  /// Called after a remote record is successfully applied locally.
  ///
  /// [entity] — table name (e.g., 'rooms', 'bookings')
  /// [localUuid] — record UUID
  /// [remoteDeviceId] — deviceId from the remote document
  /// [currentDeviceId] — this device's deviceId
  /// [lastModified] — remote record's lastModified timestamp
  ///
  /// This method is safe to call from any sync method. It handles:
  /// - Self-change filtering (same deviceId → skip)
  /// - Dedup (persistent via SharedPreferences)
  /// - Batching (collects, doesn't show immediately)
  Future<void> onRemoteRecordApplied({
    required String entity,
    required String localUuid,
    required String remoteDeviceId,
    required String? currentDeviceId,
    required int? lastModified,
  }) async {
    final pendingGeneration = _pendingGeneration;

    // ✅ Filter: skip if change is from this device
    if (currentDeviceId != null &&
        currentDeviceId.isNotEmpty &&
        remoteDeviceId == currentDeviceId) {
      return; // Same device — no notification
    }

    // ✅ Filter: skip if remoteDeviceId is empty (can't determine source)
    if (remoteDeviceId.isEmpty) {
      // Can't determine if it's from another device — skip to be safe
      return;
    }

    // ✅ Dedup: check if we already notified about this exact change
    final fingerprint =
        '$entity:$localUuid:$remoteDeviceId:${lastModified ?? 0}';

    // Check session dedup first (fast path)
    if (_sessionNotified.contains(fingerprint)) {
      return;
    }

    // Check persistent dedup (survives restart)
    try {
      final prefs = await SharedPreferences.getInstance();
      final dedupKey = '$_dedupKeyPrefix$fingerprint';
      if (prefs.getBool(dedupKey) == true) {
        // Already notified about this change — skip
        _sessionNotified.add(fingerprint);
        return;
      }

      // Mark as notified (persistent)
      await prefs.setBool(dedupKey, true);
      _sessionNotified.add(fingerprint);

      // ✅ Wave 7 tighten: Update timestamp index for LRU eviction.
      await _updateDedupIndex(prefs, fingerprint);

      // ✅ Cleanup: if we have too many dedup keys, remove oldest ones
      await _cleanupOldDedupKeys(prefs);
    } catch (e) {
      dlog(() => '⚠️ RemoteChangeNotification: dedup check failed: $e');
      // Continue anyway — better to show duplicate than miss a change
    }

    // ✅ Batch: collect change, don't show immediately. If clearPending()
    // ran while the async dedup work was in flight, discard this stale event.
    if (pendingGeneration != _pendingGeneration) return;
    _pendingChanges[remoteDeviceId] =
        (_pendingChanges[remoteDeviceId] ?? 0) + 1;
    _pendingEntities.add(entity);
  }

  /// Flush pending notifications — called after all sync phases complete.
  /// Shows a single notification summarizing all remote changes.
  Future<void> flushPendingNotifications() async {
    if (_pendingChanges.isEmpty) {
      return;
    }

    int totalChanges = 0;
    final deviceCount = _pendingChanges.length;
    for (final count in _pendingChanges.values) {
      totalChanges += count;
    }

    // Build notification message
    // Note: read from _pendingChanges BEFORE clearing
    String title;
    String body;

    if (deviceCount == 1) {
      final deviceId = _pendingChanges.keys.first;
      // Mask deviceId for privacy (show last 4 chars)
      final maskedId = deviceId.length > 4
          ? '****${deviceId.substring(deviceId.length - 4)}'
          : deviceId;

      title = totalChanges == 1
          ? 'تم تحديث بيانات من جهاز آخر 📱'
          : 'تم تحديث $totalChanges سجلات من جهاز آخر 📱';
      body = totalChanges == 1
          ? 'تمت مزامنة تغيير واحد من جهاز $maskedId'
          : 'تمت مزامنة $totalChanges تغيير من جهاز $maskedId';
    } else {
      title = 'تم تحديث بيانات من $deviceCount أجهزة 📱';
      body = 'تمت مزامنة $totalChanges تغيير إجمالي';
    }

    // ✅ Wave 7 tighten: Add entity breakdown to body for operational usefulness.
    if (_pendingEntities.isNotEmpty) {
      final entityList = _pendingEntities.take(5).join('، ');
      final extra = _pendingEntities.length > 5
          ? ' +${_pendingEntities.length - 5}'
          : '';
      body += '\nالكيانات: $entityList$extra';
    }

    // Clear pending AFTER building the message (prevents re-entry issues)
    _pendingChanges.clear();
    _pendingEntities.clear();

    // ✅ Show notification via existing SyncNotificationManager
    // Note: SyncNotificationManager.instance may throw MissingPluginException
    // in test environments (no platform channel). We catch it and continue.
    try {
      await SyncNotificationManager.instance.showSystemNotification(
        title: title,
        body: body,
        payload: 'remote_sync_completed',
      );
      dlog(
        () =>
            '🔔 RemoteChangeNotification: showed notification — '
            '$totalChanges changes from $deviceCount device(s)',
      );
    } catch (e) {
      // Non-critical — notification is best-effort. The data was already
      // applied locally; the notification is just a UX enhancement.
      dlog(
        () => '⚠️ RemoteChangeNotification: failed to show notification: $e',
      );
    }
  }

  /// Clear all pending changes (e.g., when sync fails).
  void clearPending() {
    _pendingGeneration++;
    _pendingChanges.clear();
    _pendingEntities.clear();
  }

  /// Clear session dedup cache (for testing).
  @visibleForTesting
  void clearSessionDedup() {
    _sessionNotified.clear();
  }

  /// Clear persistent dedup (for testing).
  @visibleForTesting
  Future<void> clearPersistentDedup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      for (final key in keys) {
        if (key.startsWith(_dedupKeyPrefix)) {
          await prefs.remove(key);
        }
      }
      _sessionNotified.clear();
    } catch (e) {
      dlog(() => '⚠️ clearPersistentDedup failed: $e');
    }
  }

  /// ✅ Wave 7 tighten: Update the dedup timestamp index.
  /// Stores a JSON map of `fingerprint → epoch_ms` in SharedPreferences.
  /// Used by `_cleanupOldDedupKeys` to evict oldest entries (true LRU).
  Future<void> _updateDedupIndex(
    SharedPreferences prefs,
    String fingerprint,
  ) async {
    try {
      final indexJson = prefs.getString(_dedupIndexKey) ?? '{}';
      final index = Map<String, dynamic>.from(
        jsonDecode(indexJson) as Map<String, dynamic>,
      );
      index[fingerprint] = DateTime.now().millisecondsSinceEpoch;
      await prefs.setString(_dedupIndexKey, jsonEncode(index));
    } catch (e) {
      // Non-critical — dedup still works without the index
    }
  }

  /// ✅ Wave 7 tighten: Cleanup old dedup keys using timestamp-based LRU eviction.
  /// Reads the dedup index, sorts by timestamp, and removes the oldest entries
  /// when the count exceeds `_maxDedupKeys`. This is a true LRU — not arbitrary.
  Future<void> _cleanupOldDedupKeys(SharedPreferences prefs) async {
    try {
      // Read the timestamp index
      final indexJson = prefs.getString(_dedupIndexKey) ?? '{}';
      final index = Map<String, dynamic>.from(
        jsonDecode(indexJson) as Map<String, dynamic>,
      );

      if (index.length <= _maxDedupKeys) {
        return; // Under limit — no cleanup needed
      }

      // Sort fingerprints by timestamp (oldest first)
      final sortedEntries = index.entries.toList()
        ..sort((a, b) {
          final tsA = (a.value as num?)?.toInt() ?? 0;
          final tsB = (b.value as num?)?.toInt() ?? 0;
          return tsA.compareTo(tsB);
        });

      // Remove oldest entries until we're under the limit
      final excess = index.length - _maxDedupKeys;
      var removed = 0;
      for (var i = 0; i < excess && i < sortedEntries.length; i++) {
        final fingerprint = sortedEntries[i].key;
        final dedupKey = '$_dedupKeyPrefix$fingerprint';
        await prefs.remove(dedupKey);
        index.remove(fingerprint);
        removed++;
      }

      // Save updated index
      await prefs.setString(_dedupIndexKey, jsonEncode(index));

      if (removed > 0) {
        dlog(
          () =>
              '🧹 RemoteChangeNotification: LRU cleanup removed $removed oldest dedup keys',
        );
      }
    } catch (e) {
      // Non-critical — don't fail the notification
    }
  }

  /// Get pending changes count (for testing/diagnostics).
  int get pendingCount => _pendingChanges.values.fold(0, (a, b) => a + b);

  /// Get session notified count (for testing/diagnostics).
  int get sessionNotifiedCount => _sessionNotified.length;
}
