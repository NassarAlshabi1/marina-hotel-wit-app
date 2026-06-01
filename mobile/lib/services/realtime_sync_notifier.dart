import 'dart:async';
import 'package:flutter/foundation.dart';
import '../utils/app_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// مُعلِم المزامنة الفورية - يتلقى إشعارات من الأجهزة الأخرى
/// تمت إزالة SmartSyncManager — يعتمد فقط على Appwrite Sync الآن
class RealtimeSyncNotifier {

  RealtimeSyncNotifier._();
  static RealtimeSyncNotifier? _instance;
  static RealtimeSyncNotifier get instance =>
      _instance ??= RealtimeSyncNotifier._();

  final _syncTriggerController = StreamController<SyncTrigger>.broadcast();
  Stream<SyncTrigger> get onSyncTrigger => _syncTriggerController.stream;

  bool _isListening = false;
  Timer? _pollingTimer;
  String? _lastProcessedSyncId;

  static const String _prefsLastSyncIdKey = 'realtime_last_sync_id';
  static const Duration _pollingInterval = Duration(minutes: 2);

  /// بدء الاستماع لإشعارات المزامنة
  Future<void> startListening() async {
    if (_isListening) {
      return;
    }

    _isListening = true;
    await _loadLastProcessedSyncId();

    _pollingTimer = Timer.periodic(_pollingInterval, (_) => _checkForNewSync());

    AppLogger.info('بدء الاستماع لإشعارات المزامنة');
  }

  /// إيقاف الاستماع
  void stopListening() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _isListening = false;

    debugPrint('🔕 إيقاف الاستماع لإشعارات المزامنة');
  }

  /// التحقق من وجود مزامنة جديدة
  /// SmartSyncManager تمت إزالته — استخدام Appwrite Realtime Sync
  Future<void> _checkForNewSync() async {
    // تمت إزالة SmartSyncManager. المزامنة تتم عبر Appwrite Delta Sync
    // يمكن إضافة فحص Appwrite Realtime هنا في المستقبل
    AppLogger.debug('RealtimeSyncNotifier: فحص المزامنة عبر Appwrite (قريباً)');
  }

  /// إرسال إشعار لأجهزة أخرى (عبر FCM)
  Future<void> notifyOtherDevices({
    required String syncId,
    required String changeType,
  }) async {
    try {
      AppLogger.info('إرسال إشعار للأجهزة الأخرى: $syncId ($changeType)');
      // TODO: استخدام FCM لإشعار الأجهزة الأخرى
    } catch (e) {
      AppLogger.warning('فشل إرسال الإشعار: $e');
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
