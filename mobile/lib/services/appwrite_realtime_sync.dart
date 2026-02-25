import 'dart:async';
import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'appwrite_service.dart';
import 'appwrite_config.dart';

class AppwriteRealtimeSync {
  factory AppwriteRealtimeSync() => _instance;
  AppwriteRealtimeSync._internal();
  static final AppwriteRealtimeSync _instance =
      AppwriteRealtimeSync._internal();

  Realtime? _realtime;
  RealtimeSubscription? _subscription;
  String? _currentDeviceId;
  bool _isListening = false;
  Timer? _debounceTimer;

  // ✅ تحسين: عداد التغييرات المعلقة من السيرفر (للـ Badge)
  final pendingRemoteChangesCount = ValueNotifier<int>(0);

  // ✅ تحسين: ValueNotifier لإشعار الـ UI بوجود تغييرات جديدة من السيرفر
  final hasRemoteChanges = ValueNotifier<bool>(false);

  // ✅ تححسين: تتبع آخر وقت تحديث من السيرفر (للـ Delta Sync Safety)
  DateTime? _lastServerUpdate;

  // ✅ تحسين: حماية من الفيضان (Flood Protection)
  bool _hasPendingChanges = false;

  static const _collections = [
    AppwriteConfig.roomsCollectionId,
    AppwriteConfig.bookingsCollectionId,
    AppwriteConfig.bookingNotesCollectionId,
    AppwriteConfig.bookingNightsCollectionId,
    AppwriteConfig.paymentsCollectionId,
    AppwriteConfig.expensesCollectionId,
    AppwriteConfig.cashTransactionsCollectionId,
    AppwriteConfig.debtsCollectionId,
    AppwriteConfig.employeesCollectionId,
    AppwriteConfig.salaryCyclesCollectionId,
    AppwriteConfig.salaryPaymentsCollectionId,
    AppwriteConfig.shiftNotesCollectionId,
    AppwriteConfig.hotelDayLedgerCollectionId,
    AppwriteConfig.priceAdjustmentsCollectionId,
    AppwriteConfig.bookingPriceAdjustmentsCollectionId,
    AppwriteConfig.auditLogsCollectionId,
    AppwriteConfig.paymentVoidsCollectionId,
  ];

  Future<void> initialize({
    required String deviceId,
  }) async {
    _currentDeviceId = deviceId;
    _realtime = Realtime(AppwriteService().client);
    debugPrint('📡 AppwriteRealtimeSync initialized');
  }

  Future<void> start() async {
    if (_isListening || _realtime == null) return;

    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('appwrite_sync_enabled') ?? false)) return;

    final channels = _collections
        .map(
          (c) =>
              'databases.${AppwriteConfig.databaseId}.collections.$c.documents',
        )
        .toList();

    try {
      debugPrint('📡 Realtime: subscribing to ${channels.length} channels...');
      _subscription = _realtime!.subscribe(channels);
      _isListening = true;

      debugPrint('📡 Realtime: connection established, listening for events...');

      _subscription!.stream.listen(
        (message) {
          try {
            _onEvent(message);
          } catch (e) {
            debugPrint('⚠️ Realtime: error processing event: $e');
          }
        },
        onError: (e) {
          debugPrint('❌ Realtime stream error: $e');
          _isListening = false;
          _reconnect();
        },
        onDone: () {
          debugPrint('📡 Realtime stream closed (onDone)');
          _isListening = false;
          // إعادة الاتصال التلقائي عند انقطاع الـ Stream
          _reconnect();
        },
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('❌ Realtime: subscription failed: $e');
      _isListening = false;
      _reconnect();
    }
  }

  void _onEvent(RealtimeMessage message) {
    final payload = message.payload;
    // استخراج معرف الجهاز المصدر مع دعم لعدة أسماء حقول محتملة
    final sourceDevice = payload['device_id'] ?? 
                         payload['lastModifiedBy'] ?? 
                         payload['deviceId'];

    // تجاهل التغييرات من نفس الجهاز فقط إذا كنا متأكدين من تطابق المعرف
    if (sourceDevice != null && _currentDeviceId != null && sourceDevice == _currentDeviceId) {
      debugPrint('📡 Realtime: skipping local change from this device ($sourceDevice)');
      return;
    }

    // ✅ تحسين: تصفية أنواع الأحداث (create/update/delete فقط)
    final eventTypes = message.events;
    final isDataChange = eventTypes.any((e) =>
        e.contains('.create') ||
        e.contains('.update') ||
        e.contains('.delete'));

    if (!isDataChange) {
      debugPrint('📡 Realtime: ignoring non-data event: $eventTypes');
      return;
    }

    debugPrint('📡 Realtime: change detected in ${message.channels} - Source: ${sourceDevice ?? 'unknown'}');

    // ✅ تحسين: تتبع آخر وقت تحديث (Delta Sync Safety)
    final updatedAt = payload['\$updatedAt'] ?? payload['\$createdAt'];
    if (updatedAt != null) {
      try {
        final serverTime = DateTime.parse(updatedAt);
        if (_lastServerUpdate == null ||
            serverTime.isAfter(_lastServerUpdate!)) {
          _lastServerUpdate = serverTime;
        }
      } catch (e) {
        debugPrint('⚠️ Realtime: could not parse update timestamp');
      }
    }

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      // ✅ تحسين: حماية من الفيضان (Flood Protection)
      // إذا كانت هناك تغييرات معلقة بالفعل، نزيد العداد فقط
      if (!_hasPendingChanges) {
        hasRemoteChanges.value = true;
        _hasPendingChanges = true;
        debugPrint('📡 Realtime: detected remote changes - UI activated');
      }

      // ✅ تحسين: زيادة عداد التغييرات
      pendingRemoteChangesCount.value++;
      debugPrint(
          '📡 Realtime: pending changes count = ${pendingRemoteChangesCount.value}');
    });
  }

  /// ✅ تحسين: الحصول على آخر وقت تحديث معروف من السيرفر
  DateTime? get lastKnownServerUpdate => _lastServerUpdate;

  /// ✅ تحسين: تعيين آخر وقت تحديث يدوياً (مفيد للـ Delta Sync)
  void updateLastServerTimestamp(DateTime timestamp) {
    if (_lastServerUpdate == null || timestamp.isAfter(_lastServerUpdate!)) {
      _lastServerUpdate = timestamp;
      debugPrint('📡 Realtime: updated last server timestamp to $timestamp');
    }
  }

  /// إعادة تعيين حالة "توجد تغييرات من السيرفر"
  /// يُستدعى بعد انتهاء عملية السحب اليدوي بنجاح
  void resetRemoteChangesFlag() {
    hasRemoteChanges.value = false;
    _hasPendingChanges = false;
    pendingRemoteChangesCount.value = 0;
    debugPrint('📡 Realtime: remote changes flag reset - count cleared');
  }

  void _reconnect() {
    if (_isListening) return;
    
    // استخدام تأخير متزايد أو ثابت لإعادة الاتصال
    debugPrint('📡 Realtime: attempting to reconnect in 5 seconds...');
    Future.delayed(const Duration(seconds: 5), () async {
      if (!_isListening) {
        final prefs = await SharedPreferences.getInstance();
        if (prefs.getBool('appwrite_sync_enabled') ?? false) {
          debugPrint('📡 Realtime: reconnecting now...');
          await start();
        } else {
          debugPrint('📡 Realtime: sync is disabled, skipping reconnect');
        }
      }
    });
  }

  Future<void> stop() async {
    _subscription?.close();
    _subscription = null;
    _isListening = false;
    _debounceTimer?.cancel();
    // عند التوقف، نعيد تعيين الحالة
    hasRemoteChanges.value = false;
    _hasPendingChanges = false;
    pendingRemoteChangesCount.value = 0;
  }

  void dispose() => stop();

  bool get isListening => _isListening;
}
