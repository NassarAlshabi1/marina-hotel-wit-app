import 'dart:async';

import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'appwrite_config.dart';
import 'appwrite_service.dart';
import 'crashlytics_service.dart';

import 'package:marina_hotel_mobile/utils/debug_log.dart';

typedef DeltaPullCallback = Future<bool> Function();

/// A bounded ingress queue for remote Realtime notifications.
/// It carries change hints only; documents are always read through Delta Pull.
class RemoteChangeQueue {
  final Set<String> _keys = <String>{};

  int get length => _keys.length;
  bool get isEmpty => _keys.isEmpty;

  void add({required String collection, String? documentId, String? event}) {
    _keys.add('$collection:${documentId ?? '*'}:${event ?? 'change'}');
  }

  Set<String> drain() {
    final changes = Set<String>.from(_keys);
    _keys.clear();
    return changes;
  }

  void restore(Iterable<String> changes) => _keys.addAll(changes);
  void clear() => _keys.clear();
}

/// Appwrite Realtime ingress for the existing AppwriteSyncManager Delta path.
///
/// Realtime is deliberately restricted to subscription management, event
/// filtering, queueing, coalescing, reconnect, and triggering Delta Pull.
/// It never applies payloads to Drift and never runs Full Sync or Outbox logic.
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
  bool _hasConnectedBefore = false;
  bool _pullInFlight = false;
  Timer? _debounceTimer;
  Timer? _pollingTimer;
  DeltaPullCallback? _deltaPull;

  final RemoteChangeQueue remoteChangeQueue = RemoteChangeQueue();
  final pendingRemoteChangesCount = ValueNotifier<int>(0);
  final hasRemoteChanges = ValueNotifier<bool>(false);
  DateTime? _lastServerUpdate;
  bool _hasPendingChanges = false;

  static const Duration _debounceWindow = Duration(milliseconds: 500);
  static const Duration _pollingInterval = Duration(seconds: 30);
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
    AppwriteConfig.priceAdjustmentsCollectionId,
    AppwriteConfig.bookingPriceAdjustmentsCollectionId,
    AppwriteConfig.auditLogsCollectionId,
    AppwriteConfig.paymentVoidsCollectionId,
  ];

  Future<void> initialize({
    required String deviceId,
    DeltaPullCallback? deltaPull,
  }) async {
    _currentDeviceId = deviceId;
    _deltaPull = deltaPull;
    _intentionallyStopped = false;
    // ✅ لا يُبنى Client هنا — البناء الكسول في [start] فقط؛ تبقى هذه
    // التهيئة معقّمة للاختبارات (بلا نظام ملفات/شبكة) وتكفي لدخول الطابور
    // عبر enqueueForTesting مع deltaPull محقون.
    dlog('[Realtime] initialized');
  }

  Future<void> start() async {
    if (_isListening) return;
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('appwrite_sync_enabled') ?? true)) return;

    _intentionallyStopped = false;
    final realtimeEnabled =
        prefs.getBool('appwrite_realtime_ws_enabled') ?? false;
    if (!realtimeEnabled) {
      dlog(
        '[Realtime] WebSocket disabled; polling fallback remains non-invasive',
      );
      _startPollingFallback();
      return;
    }

    // ✅ بناء كسول للـ Realtime (وليس في initialize) — يضمن جاهزية
    // AppwriteService (idempotent) في كل مسارات البدء دون أن يجعل
    // initialize() يلمس نظام الملفات/الشبكة في بيئة الاختبار.
    await AppwriteService().initialize();
    _realtime ??= Realtime(AppwriteService().client);

    final channels = _collections
        .map(
          (c) =>
              'databases.${AppwriteConfig.databaseId}.collections.$c.documents',
        )
        .toList();
    try {
      _subscription = _realtime!.subscribe(channels);
      _isListening = true;
      dlog('[Realtime] connected');
      dlog('[Realtime] subscribed: ${_collections.length} collections');
      final wasReconnect = _hasConnectedBefore;
      _hasConnectedBefore = true;
      if (wasReconnect) {
        dlog('[Realtime] reconnected');
        _scheduleDeltaPull(recovery: true);
      }
      _subscription!.stream.listen(
        _onEvent,
        onError: (Object e) {
          dlog(() => '[Realtime] disconnected: $e');
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
          dlog('[Realtime] disconnected');
          if (!_intentionallyStopped) _reconnect();
        },
      );
    } catch (e) {
      dlog(() => '[Realtime] unavailable; continuing without WebSocket: $e');
      _isListening = false;
      _startPollingFallback();
    }
  }

  void _startPollingFallback() {
    if (_pollingTimer != null) return;
    _pollingTimer = Timer.periodic(_pollingInterval, (_) {
      if (_intentionallyStopped) return;
      _markPending('polling', '*', 'change');
    });
  }

  void _stopPollingFallback() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  void _onEvent(RealtimeMessage message) {
    final payload = message.payload;
    final sourceDevice = payload['device_id'] ?? payload['lastModifiedBy'];
    if (sourceDevice == _currentDeviceId) return;
    final isDataChange = message.events.any(
      (e) =>
          e.endsWith('.create') ||
          e.endsWith('.update') ||
          e.endsWith('.delete'),
    );
    if (!isDataChange) return;

    final collection = _collectionFromEvents(message.events);
    final event = message.events.firstWhere(
      (e) =>
          e.endsWith('.create') ||
          e.endsWith('.update') ||
          e.endsWith('.delete'),
      orElse: () => 'change',
    );
    final documentId = payload[r'$id']?.toString();
    _markPending(collection, documentId, event);

    final updatedAt = payload[r'$updatedAt'] ?? payload[r'$createdAt'];
    if (updatedAt is String) {
      final parsed = DateTime.tryParse(updatedAt);
      if (parsed != null &&
          (_lastServerUpdate == null || parsed.isAfter(_lastServerUpdate!))) {
        _lastServerUpdate = parsed;
      }
    }
  }

  String _collectionFromEvents(List<String> events) {
    for (final event in events) {
      for (final collection in _collections) {
        if (event.contains(collection)) return collection;
      }
    }
    return 'unknown';
  }

  void _markPending(String collection, String? documentId, String event) {
    remoteChangeQueue.add(
      collection: collection,
      documentId: documentId,
      event: event,
    );
    hasRemoteChanges.value = true;
    _hasPendingChanges = true;
    pendingRemoteChangesCount.value = remoteChangeQueue.length;
    dlog('[Realtime] queued: $collection/$documentId');
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceWindow, () => _scheduleDeltaPull());
  }

  void _scheduleDeltaPull({bool recovery = false}) {
    if (_pullInFlight || _deltaPull == null || _intentionallyStopped) return;
    if (recovery) dlog('[DeltaSync] recovery pull started');
    dlog('[Realtime] triggering delta pull');
    _pullInFlight = true;
    final queuedChanges = remoteChangeQueue.drain();
    unawaited(_runDeltaPull(recovery, queuedChanges));
  }

  Future<void> _runDeltaPull(bool recovery, Set<String> queuedChanges) async {
    try {
      final changed = await _deltaPull!();
      dlog(() => '[DeltaSync] pull completed (changed=$changed)');
      resetRemoteChangesFlag();
    } catch (e, st) {
      remoteChangeQueue.restore(queuedChanges);
      dlog(() => '[DeltaSync] pull failed: $e');
      await CrashlyticsService.instance.recordSyncError(
        operation: recovery ? 'realtime_recovery_pull' : 'realtime_delta_pull',
        error: e.toString(),
        severity: CrashlyticsSeverity.warning,
        context: {'deviceId': _currentDeviceId ?? 'unknown'},
      );
    } finally {
      _pullInFlight = false;
      if (!remoteChangeQueue.isEmpty) {
        // إعادة جدولة بديبونس بدل الاستدعاء الفوري: يمنع الحلقة الساخنة
        // عند فشل متكرر (drain→فشل→استعادة→فوراً) ويجعل حالة الطابور
        // مستقرة بين المحاولات — نفس نافذة تجميع الأحداث.
        _debounceTimer?.cancel();
        _debounceTimer = Timer(_debounceWindow, () => _scheduleDeltaPull());
      }
    }
  }

  @visibleForTesting
  void enqueueForTesting({
    required String collection,
    String? documentId,
    String event = 'update',
  }) {
    _markPending(collection, documentId, event);
  }

  DateTime? get lastKnownServerUpdate => _lastServerUpdate;

  void updateLastServerTimestamp(DateTime timestamp) {
    if (_lastServerUpdate == null || timestamp.isAfter(_lastServerUpdate!)) {
      _lastServerUpdate = timestamp;
    }
  }

  void resetRemoteChangesFlag() {
    hasRemoteChanges.value = false;
    _hasPendingChanges = false;
    pendingRemoteChangesCount.value = 0;
  }

  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 6;

  void _reconnect() {
    if (_intentionallyStopped) return;
    _reconnectAttempts++;
    if (_reconnectAttempts > _maxReconnectAttempts) return;
    final delaySeconds = (5 * (1 << (_reconnectAttempts - 1))).clamp(5, 60);
    dlog('[Realtime] reconnecting in ${delaySeconds}s');
    unawaited(_subscription?.close());
    _subscription = null;
    Future<void>.delayed(Duration(seconds: delaySeconds), () {
      if (!_isListening && !_intentionallyStopped) unawaited(start());
    });
  }

  Future<void> stop() async {
    _intentionallyStopped = true;
    await _subscription?.close();
    _subscription = null;
    _isListening = false;
    _debounceTimer?.cancel();
    _stopPollingFallback();
    remoteChangeQueue.clear();
    resetRemoteChangesFlag();
  }

  void dispose() => unawaited(stop());
  bool get isListening => _isListening;
  bool get isPullInFlight => _pullInFlight;
}
