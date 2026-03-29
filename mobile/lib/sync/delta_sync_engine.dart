/// Delta Sync Engine
/// محرك المزامنة المتغيرة - يزامن فقط ما تغير
/// بناءً على Vector Clock و Outbox Pattern
library;

import 'dart:async';

import 'models/sync_models.dart';
import 'vector_clock.dart';

/// محرك المزامنة الدلتا المتغيرة
///
/// الميزات الرئيسية:
/// - مزامنة فقط التغييرات (Delta) بدلاً من البيانات الكاملة
/// - استخدام Vector Clock للتعرف على الترتيب الزمني
/// - دعم جميع أنواع العمليات (CREATE, UPDATE, DELETE)
/// - حل تلقائي للتعارضات
/// - Exponential backoff للمحاولات الفاشلة
class DeltaSyncEngine {
  DeltaSyncEngine({
    required SyncConfiguration config,
    required VectorClockManager clockManager,
    required OutboxDataSource outbox,
    required InboxDataSource inbox,
    required RemoteDataSource remote,
    required ConflictResolver conflictResolver,
  }) : _config = config,
       _clockManager = clockManager,
       _outbox = outbox,
       _inbox = inbox,
       _remote = remote,
       _conflictResolver = conflictResolver;
  final SyncConfiguration _config;
  final VectorClockManager _clockManager;
  final OutboxDataSource _outbox;
  final InboxDataSource _inbox;
  final RemoteDataSource _remote;
  final ConflictResolver _conflictResolver;

  final _eventController = StreamController<SyncEvent>.broadcast();

  /// Stream للأحداث
  Stream<SyncEvent> get events => _eventController.stream;

  /// مزامنة دلتا كاملة
  ///
  /// الترتيب: Pull أولاً ← Resolve ← Push
  /// هذا يضمن عدم الكتابة فوق بيانات أحدث على السيرفر
  Future<DeltaSyncResult> sync({
    SyncDirection direction = SyncDirection.bidirectional,
    DateTime? since,
  }) async {
    _emitEvent(SyncEventType.syncStarted);

    final stopwatch = Stopwatch()..start();
    var result = DeltaSyncResult(timestamp: DateTime.now());

    try {
      // ⬇️ المرحلة 1: سحب التغييرات من السيرفر (Pull)
      if (direction == SyncDirection.download ||
          direction == SyncDirection.bidirectional) {
        _emitEvent(SyncEventType.remoteChange);

        final pullResult = await _pullChanges(since: since);
        result = result.copyWith(
          downloadedCount: pullResult.successCount,
          conflicts: pullResult.conflicts,
        );
      }

      // ⬆️ المرحلة 2: رفع التغييرات المحلية (Push)
      if (direction == SyncDirection.upload ||
          direction == SyncDirection.bidirectional) {
        final pushResult = await _pushChanges();
        result = result.copyWith(
          uploadedCount: pushResult.successCount,
          errorCount: pushResult.failedCount,
          errors: pushResult.errors,
        );
      }

      stopwatch.stop();

      _emitEvent(SyncEventType.syncCompleted);

      return result.copyWith(
        success: result.errorCount == 0,
        conflictCount: result.conflicts.length,
      );
    } catch (e) {
      stopwatch.stop();
      _emitEvent(SyncEventType.syncFailed);

      return DeltaSyncResult(
        success: false,
        errorCount: 1,
        errors: [e.toString()],
        timestamp: DateTime.now(),
      );
    }
  }

  /// ⬇️ سحب التغييرات من السيرفر
  Future<PullResult> _pullChanges({DateTime? since}) async {
    final result = PullResult();

    try {
      // جلب التغييرات من السيرفر
      final remoteChanges = await _remote.fetchChanges(
        since:
            since ??
            await _outbox.getLastSyncTimestamp() ??
            DateTime.fromMillisecondsSinceEpoch(0),
        limit: _config.batchSize,
      );

      if (remoteChanges.isEmpty) {
        return result;
      }

      // حفظ في Inbox أولاً (لأمان البيانات)
      for (final change in remoteChanges) {
        await _inbox.save(change);
      }

      // تطبيق التغييرات مع فحص التعارضات
      for (final change in remoteChanges) {
        try {
          final applyResult = await _applyRemoteChange(change);

          if (applyResult.hasConflict) {
            result.conflicts.add(applyResult.conflict!);
          } else if (applyResult.success) {
            result.successCount++;
          }
        } catch (e) {
          result.errors.add('Failed to apply ${change.uuid}: $e');
        }
      }

      // تحديث Vector Clock
      for (final change in remoteChanges) {
        final remoteClock = VectorClock.fromJson(change.vectorClock);
        _clockManager.recordRemoteEvent(remoteClock);
      }

      // تحديث وقت آخر مزامنة
      await _outbox.updateLastSyncTimestamp(DateTime.now());
    } catch (e) {
      result.errors.add('Pull failed: $e');
    }

    return result;
  }

  /// تطبيق تغيير بعيد مع فحص التعارض
  Future<ApplyChangeResult> _applyRemoteChange(DeltaChange change) async {
    // جلب السجل المحلي المقابل
    final localRecord = await _outbox.getLocalRecord(change.table, change.uuid);

    if (localRecord == null) {
      // لا يوجد سجل محلي - تطبيق مباشر
      await _outbox.applyChange(change);
      return ApplyChangeResult.success();
    }

    // مقارنة Vector Clocks
    final remoteClock = VectorClock.fromJson(change.vectorClock);
    final localClockStr = localRecord['vector_clock'] as String?;

    if (localClockStr == null) {
      // السجل المحلي بدون Vector Clock - السجل البعيد أحدث
      await _outbox.applyChange(change);
      return ApplyChangeResult.success();
    }

    final localClock = VectorClock.fromJson(localClockStr);
    final comparison = remoteClock.compare(localClock);

    switch (comparison) {
      case VectorClockComparison.remoteNewer:
        // السجل البعيد أحدث - تطبيق
        await _outbox.applyChange(change);
        return ApplyChangeResult.success();

      case VectorClockComparison.localNewer:
        // السجل المحلي أحدث - تخطي
        return ApplyChangeResult.skipped();

      case VectorClockComparison.concurrent:
        // ⚠️ تعارض حقيقي - حل التعارض
        _emitEvent(
          SyncEventType.conflictDetected,
          table: change.table,
          uuid: change.uuid,
        );

        final conflict = SyncConflict(
          id: 'conflict_${change.uuid}_${DateTime.now().millisecondsSinceEpoch}',
          table: change.table,
          uuid: change.uuid,
          remoteChange: change,
          localRecord: localRecord,
          detectedAt: DateTime.now(),
        );

        // حل التعارض تلقائياً
        final resolution = await _conflictResolver.resolve(conflict);

        if (resolution.winner == Winner.remote) {
          await _outbox.applyChange(change);
        }
        // إذا كان المحلي فائزاً، نتركه كما هو

        _emitEvent(
          SyncEventType.conflictResolved,
          table: change.table,
          uuid: change.uuid,
        );

        return ApplyChangeResult.conflict(conflict);

      case VectorClockComparison.equal:
        // متساويان - لا شيء يُعمل
        return ApplyChangeResult.skipped();
    }
  }

  /// ⬆️ رفع التغييرات المحلية
  Future<PushResult> _pushChanges() async {
    final result = PushResult();

    try {
      // جلب التغييرات المعلقة
      final pendingChanges = await _outbox.fetchPending(
        batchSize: _config.batchSize,
      );

      if (pendingChanges.isEmpty) {
        return result;
      }

      // تحديث Vector Clock لكل تغيير
      final changesToPush = <DeltaChange>[];

      for (final change in pendingChanges) {
        // تسجيل الحدث وزيادة العداد
        final newClock = _clockManager.recordLocalEvent();

        final updatedChange = DeltaChange(
          id: change.id,
          table: change.table,
          uuid: change.uuid,
          operation: change.operation,
          payload: change.payload,
          timestamp: DateTime.now(),
          vectorClock: newClock.toJson(),
          checksum: _calculateChecksum(change.payload),
          deviceId: _clockManager.deviceId,
          retryCount: change.retryCount,
        );

        changesToPush.add(updatedChange);
      }

      // رفع إلى السيرفر
      final pushResult = await _remote.pushChanges(changesToPush);

      // تحديث حالة التغييرات
      for (var i = 0; i < changesToPush.length; i++) {
        final change = changesToPush[i];
        final success = pushResult.successfulIds.contains(change.id);

        if (success) {
          await _outbox.markAsSynced(change.id);
          result.successCount++;
        } else {
          final error = pushResult.errors[change.id] ?? 'Unknown error';
          await _handlePushFailure(change, error);
          result.failedCount++;
          result.errors.add('${change.id}: $error');
        }
      }
    } catch (e) {
      result.errors.add('Push failed: $e');
    }

    return result;
  }

  /// معالجة فشل الرفع
  Future<void> _handlePushFailure(DeltaChange change, String error) async {
    final newRetryCount = change.retryCount + 1;

    if (newRetryCount >= _config.maxRetries) {
      // تجاوز الحد الأقصى - تحديد كفاشل نهائي
      await _outbox.markAsFailed(change.id, error);
    } else {
      // Exponential backoff
      final delaySeconds = _calculateBackoffDelay(newRetryCount);
      final nextRetryAt = DateTime.now().add(Duration(seconds: delaySeconds));

      await _outbox.scheduleRetry(
        change.id,
        error: error,
        retryCount: newRetryCount,
        nextRetryAt: nextRetryAt,
      );
    }
  }

  /// حساب تأخير Exponential Backoff
  /// 1st retry: 2 seconds
  /// 2nd retry: 4 seconds
  /// 3rd retry: 8 seconds
  int _calculateBackoffDelay(int retryCount) {
    return (2 * (1 << (retryCount - 1))).clamp(2, 3600); // max 1 hour
  }

  /// حساب checksum للتحقق من سلامة البيانات
  String? _calculateChecksum(Map<String, dynamic> data) {
    if (data.isEmpty) return null;

    final sortedKeys = data.keys.toList()..sort();
    final buffer = StringBuffer();

    for (final key in sortedKeys) {
      buffer.write('$key:${data[key]}|');
    }

    return buffer.toString().hashCode.toString();
  }

  /// إصدار حدث
  void _emitEvent(SyncEventType type, {String? table, String? uuid}) {
    _eventController.add(
      SyncEvent(
        id: 'event_${DateTime.now().millisecondsSinceEpoch}',
        type: type,
        table: table,
        uuid: uuid,
        timestamp: DateTime.now(),
      ),
    );
  }

  /// التحقق من وجود تغييرات معلقة
  Future<bool> hasPendingChanges() async {
    final count = await _outbox.pendingCount();
    return count > 0;
  }

  /// الحصول على عدد التغييرات المعلقة
  Future<int> pendingChangesCount() async {
    return _outbox.pendingCount();
  }

  /// إلغاء الاشتراك
  void dispose() {
    _eventController.close();
  }
}

/// نتيجة سحب التغييرات
class PullResult {
  int successCount = 0;
  List<SyncConflict> conflicts = [];
  List<String> errors = [];
}

/// نتيجة رفع التغييرات
class PushResult {
  int successCount = 0;
  int failedCount = 0;
  List<String> errors = [];
}

/// نتيجة تطبيق تغيير
class ApplyChangeResult {
  ApplyChangeResult._({
    required this.success,
    this.skipped = false,
    this.hasConflict = false,
    this.conflict,
  });

  factory ApplyChangeResult.success() => ApplyChangeResult._(success: true);

  factory ApplyChangeResult.skipped() =>
      ApplyChangeResult._(success: false, skipped: true);

  factory ApplyChangeResult.conflict(SyncConflict conflict) =>
      ApplyChangeResult._(
        success: false,
        hasConflict: true,
        conflict: conflict,
      );
  final bool success;
  final bool skipped;
  final bool hasConflict;
  final SyncConflict? conflict;
}

/// مصدر بيانات Outbox (التغييرات المحلية)
abstract class OutboxDataSource {
  Future<List<DeltaChange>> fetchPending({required int batchSize});
  Future<void> markAsSynced(String id);
  Future<void> markAsFailed(String id, String error);
  Future<void> scheduleRetry(
    String id, {
    required String error,
    required int retryCount,
    required DateTime nextRetryAt,
  });
  Future<int> pendingCount();
  Future<DateTime?> getLastSyncTimestamp();
  Future<void> updateLastSyncTimestamp(DateTime timestamp);
  Future<Map<String, dynamic>?> getLocalRecord(String table, String uuid);
  Future<void> applyChange(DeltaChange change);
}

/// مصدر بيانات Inbox (التغييرات الواردة)
abstract class InboxDataSource {
  Future<void> save(DeltaChange change);
  Future<List<DeltaChange>> fetchUnapplied();
  Future<void> markAsApplied(String id);
}

/// مصدر البيانات البعيدة
abstract class RemoteDataSource {
  Future<List<DeltaChange>> fetchChanges({
    required DateTime since,
    required int limit,
  });
  Future<PushChangesResult> pushChanges(List<DeltaChange> changes);
}

/// نتيجة رفع التغييرات
class PushChangesResult {
  PushChangesResult({this.successfulIds = const [], this.errors = const {}});
  final List<String> successfulIds;
  final Map<String, String> errors;
}

/// محلل التعارضات
abstract class ConflictResolver {
  Future<ConflictResolutionResult> resolve(SyncConflict conflict);
}
