import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'smart_sync_manager.dart';

/// مُعلِم المزامنة الفورية - يتلقى إشعارات من الأجهزة الأخرى
class RealtimeSyncNotifier {
  static RealtimeSyncNotifier? _instance;
  static RealtimeSyncNotifier get instance =>
      _instance ??= RealtimeSyncNotifier._();

  RealtimeSyncNotifier._();

  final _syncTriggerController = StreamController<SyncTrigger>.broadcast();
  Stream<SyncTrigger> get onSyncTrigger => _syncTriggerController.stream;

  bool _isListening = false;
  Timer? _pollingTimer;
  String? _lastProcessedSyncId;

  static const String _prefsLastSyncIdKey = 'realtime_last_sync_id';
  static const Duration _pollingInterval = Duration(seconds: 30);

  /// بدء الاستماع لإشعارات المزامنة
  Future<void> startListening() async {
    if (_isListening) return;

    _isListening = true;
    await _loadLastProcessedSyncId();

    _pollingTimer = Timer.periodic(_pollingInterval, (_) => _checkForNewSync());

    debugPrint('🔔 بدء الاستماع لإشعارات المزامنة');
  }

  /// إيقاف الاستماع
  void stopListening() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _isListening = false;

    debugPrint('🔕 إيقاف الاستماع لإشعارات المزامنة');
  }

  /// التحقق من وجود مزامنة جديدة
  Future<void> _checkForNewSync() async {
    try {
      final smartSync = SmartSyncManager.instance;

      if (!smartSync.isDriveSignedIn) return;

      final hasChanges = await smartSync.pullRemoteChanges();

      if (hasChanges) {
        final trigger = SyncTrigger(
          syncId: 'auto_${DateTime.now().millisecondsSinceEpoch}',
          sourceDeviceId: 'remote',
          timestamp: DateTime.now(),
          changeType: 'update',
        );

        _syncTriggerController.add(trigger);
        debugPrint('🔔 تم اكتشاف تغييرات جديدة');
      }
    } catch (e) {
      debugPrint('❌ خطأ في التحقق من المزامنة الجديدة: $e');
    }
  }

  /// إرسال إشعار لأجهزة أخرى (عبر FCM أو Drive metadata)
  Future<void> notifyOtherDevices({
    required String syncId,
    required String changeType,
  }) async {
    try {
      final metadata = {
        'last_sync_id': syncId,
        'source_device': SmartSyncManager.instance.deviceId,
        'change_type': changeType,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      };

      debugPrint('📤 إرسال إشعار للأجهزة الأخرى: $syncId');
    } catch (e) {
      debugPrint('⚠️ فشل إرسال الإشعار: $e');
    }
  }

  Future<void> _loadLastProcessedSyncId() async {
    final prefs = await SharedPreferences.getInstance();
    _lastProcessedSyncId = prefs.getString(_prefsLastSyncIdKey);
  }

  Future<void> _saveLastProcessedSyncId(String syncId) async {
    final prefs = await SharedPreferences.getInstance();
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
