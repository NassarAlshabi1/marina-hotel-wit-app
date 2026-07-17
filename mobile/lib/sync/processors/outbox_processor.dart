/// Outbox Processor
/// يدير التغييرات المحلية المعلقة ويرسلها للمزامنة
/// مع دعم إعادة المحاولة التلقائية والتتبع
library;

import 'dart:async';
import 'dart:convert';
import 'package:uuid/uuid.dart';

import '../models/sync_models.dart';
import '../vector_clock.dart';

/// معالج Outbox - يدير قائمة الانتظار للتغييرات المحلية
class OutboxProcessor {

  OutboxProcessor({
    required OutboxStorage storage,
    required VectorClockManager clockManager,
    required SyncConfiguration config,
  })  : _storage = storage,
        _clockManager = clockManager,
        _config = config;
  final OutboxStorage _storage;
  final VectorClockManager _clockManager;
  final SyncConfiguration _config;

  final _pendingCountController = StreamController<int>.broadcast();
  final _statusController = StreamController<OutboxStatus>.broadcast();

  Timer? _retryTimer;
  bool _isProcessing = false;

  /// Stream لعدد التغييرات المعلقة
  Stream<int> get pendingCountStream => _pendingCountController.stream;

  /// Stream لحالة Outbox
  Stream<OutboxStatus> get statusStream => _statusController.stream;

  /// تهيئة المعالج
  Future<void> initialize() async {
    await _storage.initialize();
    _startRetryTimer();
    unawaited(_notifyStatus());
  }

  /// إضافة تغيير جديد للـ Outbox
  Future<String> enqueue({
    required String table,
    required String uuid,
    required SyncOperation operation,
    required Map<String, dynamic> payload,
    String? parentId,
  }) async {
    // تسجيل الحدث وزيادة Vector Clock
    final newClock = _clockManager.recordLocalEvent();

    final change = DeltaChange(
      id: const Uuid().v4(),
      table: table,
      uuid: uuid,
      operation: operation,
      payload: payload,
      timestamp: DateTime.now(),
      vectorClock: newClock.toJson(),
      checksum: _calculateChecksum(payload),
      deviceId: _clockManager.deviceId,
    );

    await _storage.save(change);
    unawaited(_notifyPendingCount());
    unawaited(_notifyStatus());

    return change.id;
  }

  /// إضافة مجموعة تغييرات (معاملة واحدة)
  Future<List<String>> enqueueBatch(List<ChangeRequest> requests) async {
    final ids = <String>[];

    // استخدام نفس الـ Vector Clock للمعاملة كاملة
    final baseClock = _clockManager.currentClock;

    for (var i = 0; i < requests.length; i++) {
      final request = requests[i];

      // زيادة العداد لكل عنصر في المعاملة
      final newClock = baseClock.increment(_clockManager.deviceId);

      final change = DeltaChange(
        id: const Uuid().v4(),
        table: request.table,
        uuid: request.uuid,
        operation: request.operation,
        payload: request.payload,
        timestamp: DateTime.now().add(Duration(milliseconds: i)),
        vectorClock: newClock.toJson(),
        checksum: _calculateChecksum(request.payload),
        deviceId: _clockManager.deviceId,
      );

      await _storage.save(change);
      ids.add(change.id);
    }

    // تحديث Vector Clock بعد المعاملة
    _clockManager.recordLocalEvent();

    unawaited(_notifyPendingCount());
    unawaited(_notifyStatus());

    return ids;
  }

  /// جلب التغييرات المعلقة للرفع
  Future<List<DeltaChange>> fetchPending({int? limit}) async {
    return _storage.fetchPending(
      limit: limit ?? _config.batchSize,
      before: DateTime.now(),
    );
  }

  /// جلب التغييرات جاهزة لإعادة المحاولة
  Future<List<DeltaChange>> fetchReadyForRetry() async {
    return _storage.fetchPending(
      limit: _config.batchSize,
      before: DateTime.now(),
      onlyRetryable: true,
    );
  }

  /// تحديث حالة التغيير إلى "تم المزامنة"
  Future<void> markAsSynced(String id) async {
    await _storage.markAsSynced(id, DateTime.now());
    unawaited(_notifyPendingCount());
    unawaited(_notifyStatus());
  }

  /// تحديث حالة مجموعة تغييرات إلى "تم المزامنة"
  Future<void> markBatchAsSynced(List<String> ids) async {
    // استخدام Future.wait لتنفيذ جميع التحديثات بالتوازي بدلاً من التسلسل
    await Future.wait(ids.map((id) => _storage.markAsSynced(id, DateTime.now())));
    unawaited(_notifyPendingCount());
    unawaited(_notifyStatus());
  }

  /// معالجة فشل الرفع مع إعادة المحاولة
  Future<void> handleFailure(String id, String error) async {
    final change = await _storage.getById(id);
    if (change == null) {
      return;
    }

    final newRetryCount = change.retryCount + 1;

    if (newRetryCount >= _config.maxRetries) {
      // تجاوز الحد الأقصى - وضع كفاشل نهائي
      await _storage.markAsFailed(id, error, DateTime.now());
    } else {
      // جدولة إعادة المحاولة مع Exponential Backoff
      final delay = _calculateBackoffDelay(newRetryCount);
      final nextRetryAt = DateTime.now().add(delay);

      await _storage.scheduleRetry(
        id,
        error: error,
        retryCount: newRetryCount,
        nextRetryAt: nextRetryAt,
      );
    }

    unawaited(_notifyPendingCount());
    unawaited(_notifyStatus());
  }

  /// إلغاء تغيير محدد
  Future<void> cancel(String id) async {
    await _storage.delete(id);
    unawaited(_notifyPendingCount());
    unawaited(_notifyStatus());
  }

  /// إلغاء جميع التغييرات المعلقة لجدول محدد
  Future<void> cancelByTable(String table) async {
    await _storage.deleteByTable(table);
    unawaited(_notifyPendingCount());
    unawaited(_notifyStatus());
  }

  /// الحصول على عدد التغييرات المعلقة
  Future<int> get pendingCount => _storage.pendingCount();

  /// الحصول على إحصائيات Outbox
  Future<OutboxStats> getStats() async {
    return _storage.getStats();
  }

  /// معالجة إعادة المحاولة التلقائية
  Future<void> processRetries() async {
    if (_isProcessing) {
      return;
    }

    _isProcessing = true;
    _statusController.add(OutboxStatus(pendingCount: 0, failedCount: 0, isProcessing: true));

    try {
      final retryable = await fetchReadyForRetry();

      // استخدام Future.wait لتحديث جميع المحاولات بالتوازي بدلاً من التسلسل
      await Future.wait(retryable.map((change) async {
        // تحديث Vector Clock للمحاولة الجديدة
        final newClock = _clockManager.recordLocalEvent();

        final updatedChange = DeltaChange(
          id: change.id,
          table: change.table,
          uuid: change.uuid,
          operation: change.operation,
          payload: change.payload,
          timestamp: DateTime.now(),
          vectorClock: newClock.toJson(),
          checksum: change.checksum,
          deviceId: change.deviceId,
          retryCount: change.retryCount,
          lastError: change.lastError,
        );

        await _storage.save(updatedChange);
      }),);
    } finally {
      _isProcessing = false;
      unawaited(_notifyStatus());
    }
  }

  /// تنظيف السجلات القديمة المُزامنة
  Future<int> cleanup({Duration? olderThan}) async {
    final cutoff = DateTime.now().subtract(olderThan ?? const Duration(days: 7));
    return _storage.deleteSyncedBefore(cutoff);
  }

  /// بدء مؤقت إعادة المحاولة
  void _startRetryTimer() {
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => processRetries(),
    );
  }

  /// إيقاف مؤقت إعادة المحاولة
  void stopRetryTimer() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  /// إشعار بعدد التغييرات المعلقة
  Future<void> _notifyPendingCount() async {
    final count = await _storage.pendingCount();
    _pendingCountController.add(count);
  }

  /// إشعار بحالة Outbox
  Future<void> _notifyStatus() async {
    final stats = await _storage.getStats();
    _statusController.add(OutboxStatus(
      pendingCount: stats.pendingCount,
      failedCount: stats.failedCount,
      isProcessing: _isProcessing,
    ),);
  }

  /// حساب تأخير Exponential Backoff
  Duration _calculateBackoffDelay(int retryCount) {
    // 2^retryCount seconds, max 1 hour
    final seconds = (2 * (1 << (retryCount - 1))).clamp(2, 3600);
    return Duration(seconds: seconds);
  }

  /// حساب checksum للبيانات
  String? _calculateChecksum(Map<String, dynamic> data) {
    if (data.isEmpty) {
      return null;
    }

    final sorted = Map.fromEntries(
      data.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );

    final json = jsonEncode(sorted);
    return json.hashCode.toRadixString(16);
  }

  /// التخلص من الموارد
  void dispose() {
    stopRetryTimer();
    _pendingCountController.close();
    _statusController.close();
  }
}

/// طلب تغيير
class ChangeRequest {

  ChangeRequest({
    required this.table,
    required this.uuid,
    required this.operation,
    required this.payload,
  });
  final String table;
  final String uuid;
  final SyncOperation operation;
  final Map<String, dynamic> payload;
}

/// حالة Outbox
class OutboxStatus {

  OutboxStatus({
    required this.pendingCount,
    required this.failedCount,
    this.isProcessing = false,
  });
  final int pendingCount;
  final int failedCount;
  final bool isProcessing;

  bool get hasPending => pendingCount > 0;
  bool get hasFailed => failedCount > 0;

  @override
  String toString() =>
      'OutboxStatus(pending: $pendingCount, failed: $failedCount, processing: $isProcessing)';
}

/// إحصائيات Outbox
class OutboxStats {

  OutboxStats({
    required this.pendingCount,
    required this.syncingCount,
    required this.syncedCount,
    required this.failedCount,
    this.oldestPending,
  });
  final int pendingCount;
  final int syncingCount;
  final int syncedCount;
  final int failedCount;
  final DateTime? oldestPending;
}

/// واجهة تخزين Outbox
abstract class OutboxStorage {
  Future<void> initialize();
  Future<void> save(DeltaChange change);
  Future<DeltaChange?> getById(String id);
  Future<List<DeltaChange>> fetchPending({
    required int limit,
    required DateTime before,
    bool onlyRetryable = false,
  });
  Future<void> markAsSynced(String id, DateTime timestamp);
  Future<void> markAsFailed(String id, String error, DateTime timestamp);
  Future<void> scheduleRetry(
    String id, {
    required String error,
    required int retryCount,
    required DateTime nextRetryAt,
  });
  Future<void> delete(String id);
  Future<void> deleteByTable(String table);
  Future<int> deleteSyncedBefore(DateTime cutoff);
  Future<int> pendingCount();
  Future<OutboxStats> getStats();
}
