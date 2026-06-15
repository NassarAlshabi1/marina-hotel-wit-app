import 'dart:async';

import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'package:marina_hotel_mobile/utils/prefs_cache.dart';

import 'appwrite_config.dart';
import 'appwrite_service.dart';
import 'crashlytics_service.dart';
import 'package:marina_hotel_mobile/utils/app_logger.dart';

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
    AppwriteConfig.salaryWithdrawalsCollectionId,
    AppwriteConfig.shiftNotesCollectionId,
    AppwriteConfig.guestInfosCollectionId,
    // ❌ hotel_day_ledger - محلي فقط
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
    AppLogger.info('📡 AppwriteRealtimeSync initialized', tag: 'APP');
  }

  Future<void> start() async {
    if (_isListening || _realtime == null) {
      return;
    }

    final prefs = getSharedPrefs();
    if (!(prefs.getBool('appwrite_sync_enabled') ?? true)) {
      return;
    }

    final channels = _collections
        .map(
          (c) =>
              'databases.${AppwriteConfig.databaseId}.collections.$c.documents',
        )
        .toList();

    _subscription = _realtime!.subscribe(channels);
    _isListening = true;

    AppLogger.info('📡 Realtime: listening...', tag: 'APP');

    _subscription!.stream.listen(
      _onEvent,
      onError: (Object e) {
        AppLogger.error('❌ Realtime error: $e', tag: 'APP');
        CrashlyticsService.instance.recordSyncError(
          operation: 'realtime_listen',
          error: e.toString(),
          severity: CrashlyticsSeverity.warning,
          context: {'deviceId': _currentDeviceId ?? 'unknown'},
        );
        _isListening = false;
        _reconnect();
      },
      onDone: () {
        _isListening = false;
      },
    );
  }

  void _onEvent(RealtimeMessage message) {
    final payload = message.payload;
    final sourceDevice = payload['device_id'] ?? payload['lastModifiedBy'];

    // تجاهل التغييرات من نفس الجهاز (لأنها محلية بالفعل)
    if (sourceDevice == _currentDeviceId) {
      return;
    }

    // ✅ تحسين: تصفية أنواع الأحداث (create/update/delete فقط)
    // لا نهتم بـ permissions.update أو أحداث النظام
    final eventTypes = message.events;
    final isDataChange = eventTypes.any((e) =>
        e.endsWith('.create') ||
        e.endsWith('.update') ||
        e.endsWith('.delete'),);

    if (!isDataChange) {
      AppLogger.info('📡 Realtime: ignoring non-data event: $eventTypes', tag: 'APP');
      return;
    }

    // ✅ تحسين: تتبع آخر وقت تحديث (Delta Sync Safety)
    final updatedAt = payload['\$updatedAt'] ?? payload['\$createdAt'];
    if (updatedAt != null) {
      try {
        final serverTime = DateTime.parse(updatedAt as String);
        if (_lastServerUpdate == null || serverTime.isAfter(_lastServerUpdate!)) {
          _lastServerUpdate = serverTime;
        }
      } catch (e) {
        AppLogger.warning('⚠️ Realtime: could not parse update timestamp', tag: 'APP');
      }
    }

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      // ✅ تحسين: حماية من الفيضان (Flood Protection)
      // إذا كانت هناك تغييرات معلقة بالفعل، نزيد العداد فقط
      if (!_hasPendingChanges) {
        hasRemoteChanges.value = true;
        _hasPendingChanges = true;
        AppLogger.info('📡 Realtime: detected remote changes - UI activated', tag: 'APP');
      }

      // ✅ تحسين: زيادة عداد التغييرات
      pendingRemoteChangesCount.value++;
      AppLogger.info('📡 Realtime: pending changes count = ${pendingRemoteChangesCount.value}', tag: 'APP');
    });
  }

  /// ✅ تحسين: الحصول على آخر وقت تحديث معروف من السيرفر
  DateTime? get lastKnownServerUpdate => _lastServerUpdate;

  /// ✅ تحسين: تعيين آخر وقت تحديث يدوياً (مفيد للـ Delta Sync)
  void updateLastServerTimestamp(DateTime timestamp) {
    if (_lastServerUpdate == null || timestamp.isAfter(_lastServerUpdate!)) {
      _lastServerUpdate = timestamp;
      AppLogger.info('📡 Realtime: updated last server timestamp to $timestamp', tag: 'APP');
    }
  }

  /// إعادة تعيين حالة "توجد تغييرات من السيرفر"
  /// يُستدعى بعد انتهاء عملية السحب اليدوي بنجاح
  void resetRemoteChangesFlag() {
    hasRemoteChanges.value = false;
    _hasPendingChanges = false;
    pendingRemoteChangesCount.value = 0;
    AppLogger.info('📡 Realtime: remote changes flag reset - count cleared', tag: 'APP');
  }

    void _reconnect() {
      CrashlyticsService.instance.recordSyncError(
        operation: 'realtime_reconnect',
        error: 'Connection lost — reconnecting in 5s',
        severity: CrashlyticsSeverity.info,
        context: {'deviceId': _currentDeviceId ?? 'unknown'},
      );
      Future<void>.delayed(const Duration(seconds: 5), () {
        if (!_isListening) {
          start();
        }
      });
    }

  Future<void> stop() async {
    unawaited(_subscription?.close());
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
