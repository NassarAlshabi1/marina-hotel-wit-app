import 'dart:async';

import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'appwrite_config.dart';
import 'appwrite_service.dart';
import 'remote_change_queue.dart';
import 'crashlytics_service.dart';
import 'package:marina_hotel_mobile/utils/debug_log.dart';

class AppwriteRealtimeSync {
  factory AppwriteRealtimeSync() => _instance;
  AppwriteRealtimeSync._internal();
  static final AppwriteRealtimeSync _instance =
      AppwriteRealtimeSync._internal();

  Realtime? _realtime;
  RealtimeSubscription? _subscription;
  String? _currentDeviceId;
  bool _isListening = false;
  bool _intentionallyStopped = false;
  Timer? _debounceTimer;
  RemoteChangeQueue? _remoteChangeQueue;
  RemoteChangeBatchHandler? _remoteChangeHandler;
  Future<void> Function()? _onReconnected;
  bool _hasEstablishedConnection = false;

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
    AppwriteConfig.blacklistCollectionId,
    AppwriteConfig.appSettingsCollectionId,
    AppwriteConfig.inventoryItemsCollectionId,
    AppwriteConfig.inventoryTransactionsCollectionId,
    AppwriteConfig.salaryCarryOverLogsCollectionId,
    // ❌ hotel_day_ledger - محلي فقط
    AppwriteConfig.priceAdjustmentsCollectionId,
    AppwriteConfig.bookingPriceAdjustmentsCollectionId,
    AppwriteConfig.auditLogsCollectionId,
    AppwriteConfig.paymentVoidsCollectionId,
  ];

  Future<void> initialize({required String deviceId}) async {
    _currentDeviceId = deviceId;
    _realtime = Realtime(AppwriteService().client);
    _remoteChangeQueue ??= RemoteChangeQueue(
      onFlush: (changes) async {
        final handler = _remoteChangeHandler;
        if (handler != null) await handler(changes);
      },
    );
    dlog('📡 AppwriteRealtimeSync initialized');
  }

  Future<void> start() async {
    if (_isListening || _realtime == null) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('appwrite_sync_enabled') ?? true)) {
      return;
    }

    // Appwrite Cloud Realtime هو قناة الأحداث الأساسية. عند تعذر WebSocket،
    // نستخدم polling/Delta recovery فقط، ولا نعتمد على FCM أو Messaging.
    final realtimeEnabled =
        prefs.getBool('appwrite_realtime_ws_enabled') ?? true;
    if (!realtimeEnabled) {
      dlog(
        '📡 Realtime: WebSocket disabled — relying on Delta polling recovery',
      );
      _startPollingFallback();
      return;
    }

    // ✅ إعادة تعيين علامة التوقف الإرادي — start() تعني أن المستخدم يريد الاستماع
    _intentionallyStopped = false;

    final channels = _collections
        .map(
          (c) =>
              'databases.${AppwriteConfig.databaseId}.collections.$c.documents',
        )
        .toList();

    try {
      final isRecovery = _hasEstablishedConnection;
      _subscription = _realtime!.subscribe(channels);
      _isListening = true;
      _hasEstablishedConnection = true;

      dlog(
        isRecovery
            ? '📡 Realtime: reconnected and subscriptions established'
            : '📡 Realtime: listening via WebSocket...',
      );
      if (isRecovery) {
        final recoveryHandler = _onReconnected;
        if (recoveryHandler != null) {
          unawaited(recoveryHandler());
        }
      }

      _subscription!.stream.listen(
        _onEvent,
        onError: (Object e) {
          dlog(() => '❌ Realtime WebSocket error: $e');
          CrashlyticsService.instance.recordSyncError(
            operation: 'realtime_listen',
            error: e.toString(),
            severity: CrashlyticsSeverity.warning,
            context: {'deviceId': _currentDeviceId ?? 'unknown'},
          );
          _isListening = false;
          // ✅ إذا فشل WebSocket، ننتقل لـ polling fallback
          _startPollingFallback();
        },
        onDone: () {
          _isListening = false;
          if (!_intentionallyStopped) {
            _reconnect();
          }
        },
      );
    } catch (e) {
      dlog('❌ Realtime: WebSocket not available — falling back to polling');
      dlog(() => '   Error: $e');
      // ✅ WebSocket غير متاح — نعتمد على polling
      _startPollingFallback();
    }
  }

  // ✅ Polling fallback: فحص دوري للتغييرات كل 30 ثانية
  // يُستخدم عندما WebSocket غير متاح أو معطّل
  Timer? _pollingTimer;
  static const Duration _pollingInterval = Duration(seconds: 30);

  void _startPollingFallback() {
    if (_pollingTimer != null) return;

    dlog(
      () =>
          '📡 Realtime: started polling fallback (every ${_pollingInterval.inSeconds}s)',
    );

    _pollingTimer = Timer.periodic(_pollingInterval, (_) {
      if (_intentionallyStopped) return;

      // إشعار الـ UI بوجود تغييرات محتملة (سيتم التحقق عبر auto-sync)
      // auto-sync يعمل كل 2 دقيقة ويسحب التغييرات فعلياً
      // الـ polling هنا مجرد علامة للـ UI — لا يقوم بـ pull ثقيل
      if (!_hasPendingChanges) {
        hasRemoteChanges.value = true;
        _hasPendingChanges = true;
        dlog('📡 Realtime: polling check — UI flag set (auto-sync will pull)');
      }
    });
  }

  void _stopPollingFallback() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  void _onEvent(RealtimeMessage message) {
    final payload = message.payload;
    final eventTypes = message.events;
    final sourceDevice = payload['device_id'] ?? payload['lastModifiedBy'];

    // ✅ إصلاح P2-13: تصفير عداد إعادة الاتصال عند استلام حدث صحي — يعني
    // الاتصال سليم، لذا أي انقطاع مستقبلي يبدأ من backoff قصير.
    _reconnectAttempts = 0;

    // تجاهل التغييرات من نفس الجهاز (لأنها محلية بالفعل)
    if (sourceDevice == _currentDeviceId) {
      return;
    }

    // ✅ تحسين: تصفية أنواع الأحداث (create/update/delete فقط)
    // لا نهتم بـ permissions.update أو أحداث النظام
    final isDataChange = eventTypes.any(
      (e) =>
          e.endsWith('.create') ||
          e.endsWith('.update') ||
          e.endsWith('.delete'),
    );

    if (!isDataChange) {
      dlog(() => '📡 Realtime: ignoring non-data event: $eventTypes');
      return;
    }

    final documentId = payload[r'$id']?.toString();
    final collectionId = _collections.firstWhere(
      (collection) => eventTypes.any(
        (event) => event.contains('collections.$collection.documents'),
      ),
      orElse: () => '',
    );
    if (documentId != null && collectionId.isNotEmpty) {
      final operation = eventTypes.any((e) => e.endsWith('.delete'))
          ? RemoteOperation.delete
          : eventTypes.any((e) => e.endsWith('.create'))
          ? RemoteOperation.create
          : RemoteOperation.update;
      _remoteChangeQueue?.add(
        PendingRemoteRecord(
          collectionId: collectionId,
          documentId: documentId,
          operation: operation,
          serverUpdatedAt: DateTime.tryParse(
            (payload[r'$updatedAt'] ?? payload[r'$createdAt'])?.toString() ??
                '',
          ),
          payload: Map<String, dynamic>.from(payload),
        ),
      );
    }

    // ✅ تحسين: تتبع آخر وقت تحديث (Delta Sync Safety)
    final updatedAt = payload[r'$updatedAt'] ?? payload[r'$createdAt'];
    if (updatedAt != null) {
      try {
        final serverTime = DateTime.parse(updatedAt as String);
        if (_lastServerUpdate == null ||
            serverTime.isAfter(_lastServerUpdate!)) {
          _lastServerUpdate = serverTime;
        }
      } catch (e) {
        dlog('⚠️ Realtime: could not parse update timestamp');
      }
    }

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      // ✅ تحسين: حماية من الفيضان (Flood Protection)
      // إذا كانت هناك تغييرات معلقة بالفعل، نزيد العداد فقط
      if (!_hasPendingChanges) {
        hasRemoteChanges.value = true;
        _hasPendingChanges = true;
        dlog('📡 Realtime: detected remote changes - UI activated');
      }

      // ✅ تحسين: زيادة عداد التغييرات
      pendingRemoteChangesCount.value++;
      dlog(
        () =>
            '📡 Realtime: pending changes count = ${pendingRemoteChangesCount.value}',
      );
    });
  }

  /// يربط أحداث Realtime بمسار Delta trigger batch.
  void setRemoteChangeHandler(RemoteChangeBatchHandler handler) {
    _remoteChangeHandler = handler;
  }

  /// يطلق Delta recovery بعد إعادة إنشاء اشتراك Realtime.
  void setReconnectRecoveryHandler(Future<void> Function() handler) {
    _onReconnected = handler;
  }

  /// يضيف تغييراً معروف المعرف إلى طابور Realtime.
  void enqueueRemoteRecord(PendingRemoteRecord change) {
    _remoteChangeQueue?.add(change);
  }

  /// ✅ تحسين: الحصول على آخر وقت تحديث معروف من السيرفر
  DateTime? get lastKnownServerUpdate => _lastServerUpdate;

  /// ✅ تحسين: تعيين آخر وقت تحديث يدوياً (مفيد للـ Delta Sync)
  void updateLastServerTimestamp(DateTime timestamp) {
    if (_lastServerUpdate == null || timestamp.isAfter(_lastServerUpdate!)) {
      _lastServerUpdate = timestamp;
      dlog(() => '📡 Realtime: updated last server timestamp to $timestamp');
    }
  }

  /// إعادة تعيين حالة "توجد تغييرات من السيرفر"
  /// يُستدعى بعد انتهاء عملية السحب اليدوي بنجاح
  void resetRemoteChangesFlag() {
    hasRemoteChanges.value = false;
    _hasPendingChanges = false;
    pendingRemoteChangesCount.value = 0;
    dlog('📡 Realtime: remote changes flag reset - count cleared');
  }

  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 6;

  void _reconnect() {
    // ✅ إصلاح P2-13: عدم إعادة الاتصال بعد stop() الإرادي
    if (_intentionallyStopped) {
      return;
    }

    _reconnectAttempts++;

    // ✅ إصلاح P2-13: حد أقصى لمحاولات إعادة الاتصال لتجنب إهدار البطارية
    // بعد 6 محاولات (5s → 10s → 20s → 40s → 60s → 60s = ~3.5 min total)
    if (_reconnectAttempts > _maxReconnectAttempts) {
      dlog(
        () =>
            '📡 Realtime: max reconnect attempts ($_maxReconnectAttempts) reached — giving up',
      );
      CrashlyticsService.instance.recordSyncError(
        operation: 'realtime_reconnect_giveup',
        error:
            'Max reconnect attempts reached after $_maxReconnectAttempts tries',
        severity: CrashlyticsSeverity.warning,
        context: {'deviceId': _currentDeviceId ?? 'unknown'},
      );
      return;
    }

    // ✅ P1-14 fix: backoff أسّي محدود (5s → 10s → 20s → 40s → 60s capped)
    final delaySeconds = (_reconnectAttempts == 1)
        ? 5
        : (5 * (1 << (_reconnectAttempts - 1))).clamp(5, 60);

    CrashlyticsService.instance.recordSyncError(
      operation: 'realtime_reconnect',
      error:
          'Connection lost — reconnecting in ${delaySeconds}s (attempt $_reconnectAttempts/$_maxReconnectAttempts)',
      severity: CrashlyticsSeverity.info,
      context: {
        'deviceId': _currentDeviceId ?? 'unknown',
        'attempt': _reconnectAttempts,
      },
    );

    // ✅ P1-14 fix: إغلاق الاشتراك القديم قبل إعادة الاشتراك
    _subscription?.close().catchError((_) {});
    _subscription = null;
    _isListening = false;

    Future<void>.delayed(Duration(seconds: delaySeconds), () {
      // ✅ تحقق مزدوج: عدم إعادة الاتصال إذا تم استدعاء stop() أثناء الانتظار
      if (!_isListening && !_intentionallyStopped) {
        start();
      }
    });
  }

  Future<void> stop() async {
    // ✅ إصلاح P2-13: تعليم التوقف كإرادي لمنع _reconnect من إعادة الاتصال.
    _remoteChangeQueue?.dispose();
    _onReconnected = null;
    _hasEstablishedConnection = false;
    _intentionallyStopped = true;
    unawaited(_subscription?.close());
    _subscription = null;
    _isListening = false;
    _debounceTimer?.cancel();
    _stopPollingFallback(); // ✅ تنظيف polling fallback
    // عند التوقف، نعيد تعيين الحالة
    hasRemoteChanges.value = false;
    _hasPendingChanges = false;
    pendingRemoteChangesCount.value = 0;
  }

  void dispose() => stop();

  bool get isListening => _isListening;
}
