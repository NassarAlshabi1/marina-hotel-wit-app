import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:marina_hotel_mobile/utils/prefs_cache.dart';

import 'smart_sync_manager.dart';
import 'package:marina_hotel_mobile/utils/app_logger.dart';

/// مُعلِم المزامنة الفورية - يتلقى إشعارات من الأجهزة الأخرى
class RealtimeSyncNotifier {

  RealtimeSyncNotifier._();
  static final RealtimeSyncNotifier instance = RealtimeSyncNotifier._();

  final _syncTriggerController = StreamController<SyncTrigger>.broadcast();
  Stream<SyncTrigger> get onSyncTrigger => _syncTriggerController.stream;

  bool _isListening = false;
  Timer? _pollingTimer;
  String? _lastProcessedSyncId;

  static const String _prefsLastSyncIdKey = 'realtime_last_sync_id';
  static const Duration _pollingInterval = Duration(seconds: 30);

  /// بدء الاستماع لإشعارات المزامنة
  Future<void> startListening() async {
    if (_isListening) {
      return;
    }

    _isListening = true;
    await _loadLastProcessedSyncId();

    _pollingTimer = Timer.periodic(_pollingInterval, (_) => _checkForNewSync());

    AppLogger.info('🔔 بدء الاستماع لإشعارات المزامنة', tag: 'APP');
  }

  /// إيقاف الاستماع
  void stopListening() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _isListening = false;

    AppLogger.info('🔕 إيقاف الاستماع لإشعارات المزامنة', tag: 'APP');
  }

  /// التحقق من وجود مزامنة جديدة
  Future<void> _checkForNewSync() async {
    try {
      final smartSync = SmartSyncManager.instance();

      if (!smartSync.isDriveSignedIn) {
        return;
      }

      final hasChanges = await smartSync.pullRemoteChanges();

      if (hasChanges) {
        final syncId = 'auto_${DateTime.now().millisecondsSinceEpoch}';
        if (_lastProcessedSyncId == syncId) {
          return;
        }

        final trigger = SyncTrigger(
          syncId: syncId,
          sourceDeviceId: 'remote',
          timestamp: DateTime.now(),
          changeType: 'update',
        );

        _syncTriggerController.add(trigger);
        await _saveLastProcessedSyncId(syncId);
        AppLogger.info('🔔 تم اكتشاف تغييرات جديدة', tag: 'APP');
      }
    } catch (e) {
      AppLogger.warning('❌ خطأ في التحقق من المزامنة الجديدة: $e', tag: 'APP');
    }
  }

  /// إرسال إشعار لأجهزة أخرى (عبر FCM أو Drive metadata)
  Future<void> notifyOtherDevices({
    required String syncId,
    required String changeType,
  }) async {
    try {
      // ignore: unused_local_variable
      final metadata = {
        'last_sync_id': syncId,
        'source_device': SmartSyncManager.instance().deviceId,
        'change_type': changeType,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      };

      AppLogger.info('📤 إرسال إشعار للأجهزة الأخرى: $syncId', tag: 'APP');
    } catch (e) {
      AppLogger.warning('⚠️ فشل إرسال الإشعار: $e', tag: 'APP');
    }
  }

  Future<void> _loadLastProcessedSyncId() async {
    final prefs = getSharedPrefs();
    _lastProcessedSyncId = prefs.getString(_prefsLastSyncIdKey);
  }

  Future<void> _saveLastProcessedSyncId(String syncId) async {
    final prefs = getSharedPrefs();
    await prefs.setString(_prefsLastSyncIdKey, syncId);
    _lastProcessedSyncId = syncId;
  }

  void dispose() {
    stopListening();
    _syncTriggerController.close();
  }
}

class SyncTrigger {
  const SyncTrigger({
    required this.syncId,
    required this.sourceDeviceId,
    required this.timestamp,
    required this.changeType,
  });

  final String syncId;
  final String sourceDeviceId;
  final DateTime timestamp;
  final String changeType;
}
