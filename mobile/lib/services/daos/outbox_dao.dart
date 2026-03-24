import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../local_db.dart';
import '../adapters/adapter_registry.dart';

part 'outbox_dao.g.dart';

const _uuid = Uuid();

/// أولويات السجلات في Outbox
enum OutboxPriority {
  high('high'),
  normal('normal'),
  low('low');

  const OutboxPriority(this.value);
  final String value;
}

@DriftAccessor(tables: [Outbox])
class OutboxDao extends DatabaseAccessor<AppDatabase> with _$OutboxDaoMixin {
  OutboxDao(super.db) : adapters = AdapterRegistry(db);

  final AdapterRegistry adapters;

  // ==================== مراقبة العداد ====================

  Stream<int> watchCount() {
    final countExp = outbox.id.count();
    final query = selectOnly(outbox)
      ..addColumns([countExp])
      ..where(outbox.processingStatus.isIn(['pending', 'failed']));
    return query.map((row) => row.read(countExp) ?? 0).watchSingle();
  }

  Future<int> count() async {
    final countExp = outbox.id.count();
    final query = selectOnly(outbox)
      ..addColumns([countExp])
      ..where(outbox.processingStatus.isIn(['pending', 'failed']));
    final row = await query.getSingle();
    return row.read(countExp) ?? 0;
  }

  /// عداد السجلات حسب الحالة
  Future<Map<String, int>> countByStatus() async {
    final result = <String, int>{};
    final statuses = ['pending', 'processing', 'completed', 'failed', 'conflict'];
    
    for (final status in statuses) {
      final countExp = outbox.id.count();
      final query = selectOnly(outbox)
        ..addColumns([countExp])
        ..where(outbox.processingStatus.equals(status));
      final row = await query.getSingle();
      result[status] = row.read(countExp) ?? 0;
    }
    
    return result;
  }

  // ==================== إدارة السجلات ====================

  Future<void> resetErrors() async {
    await (update(outbox)..where((t) => t.processingStatus.equals('failed')))
        .write(OutboxCompanion(
      processingStatus: const Value('pending'),
      attempts: const Value(0),
      lastError: const Value(null),
      processingStartedAt: const Value(null),
      processingWorker: const Value(null),
      nextRetryAt: const Value(null),
    ));
  }

  Future<int> clearStale({int attemptsThreshold = 3}) async {
    final rows = await (delete(outbox)
          ..where((t) => 
              t.attempts.isBiggerOrEqualValue(attemptsThreshold) &
              t.processingStatus.isIn(['failed', 'conflict'])))
        .go();
    return rows;
  }

  /// إضافة أو تحديث سجل في Outbox
  Future<int> merge({
    required String entity,
    required String op,
    required String localUuid,
    int? serverId,
    required Map<String, dynamic> payload,
    required int clientTs,
    OutboxPriority priority = OutboxPriority.normal,
  }) async {
    final existing = await (select(outbox)
          ..where((t) =>
              t.entity.equals(entity) &
              t.localUuid.equals(localUuid) &
              t.processingStatus.equals('pending'))
          ..limit(1))
        .getSingleOrNull();

    final payloadJson = jsonEncode(payload);
    final idempKey = '$entity:$op:$localUuid:$clientTs';

    if (existing != null) {
      await (update(outbox)..where((t) => t.id.equals(existing.id))).write(
        OutboxCompanion(
          op: Value(op),
          payload: Value(payloadJson),
          clientTs: Value(clientTs),
          idempotencyKey: Value(idempKey),
          serverId: Value(serverId),
          priority: Value(priority.value),
        ),
      );
      return existing.id;
    }

    return into(outbox).insert(OutboxCompanion.insert(
      entity: entity,
      op: op,
      localUuid: localUuid,
      serverId: Value(serverId),
      payload: payloadJson,
      clientTs: clientTs,
      idempotencyKey: Value(idempKey),
      priority: Value(priority.value),
      maxAttempts: const Value(5),
    ));
  }

  // ==================== جلب السجلات للمعالجة ====================

  /// جلب دفعة من السجلات المعلقة مع مراعاة الأولوية ووقت إعادة المحاولة
  Future<List<OutboxData>> takeBatch(int limit, {String? workerId}) async {
    final worker = workerId ?? _uuid.v4();
    final nowEpoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    // جلب السجلات المعلقة التي حان وقت معالجتها
    final pending = await (select(outbox)
          ..where((t) => 
              t.processingStatus.equals('pending') &
              (t.nextRetryAt.isNull() | t.nextRetryAt.isSmallerOrEqualValue(nowEpoch)))
          ..orderBy([
            // ترتيب حسب الأولوية (high أولاً)
            (t) => OrderingTerm(
              expression: t.priority.caseMatch(
                when: {
                  const Constant('high'): const Constant(0),
                  const Constant('normal'): const Constant(1),
                  const Constant('low'): const Constant(2),
                },
                orElse: const Constant(3),
              ),
            ),
            // ثم حسب وقت الإنشاء (الأقدم أولاً)
            (t) => OrderingTerm.asc(t.clientTs),
          ])
          ..limit(limit))
        .get();

    if (pending.isEmpty) return [];

    final ids = pending.map((e) => e.id).toList();
    await (update(outbox)..where((t) => t.id.isIn(ids))).write(
      OutboxCompanion(
        processingStatus: const Value('processing'),
        processingStartedAt: Value(nowEpoch),
        processingWorker: Value(worker),
        attempts: Value(pending.first.attempts + 1),
      ),
    );

    return pending;
  }

  // ==================== إدارة النجاح والفشل ====================

  /// ✅ مسح السجلات الناجحة فوراً (بدلاً من تحويلها إلى completed)
  Future<void> cleanupOnSuccess(List<int> ids) async {
    if (ids.isEmpty) return;
    
    // حذف السجلات الناجحة مباشرة
    await (delete(outbox)..where((t) => t.id.isIn(ids))).go();
    
    // تحديث وقت آخر رفع ناجح
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await (update(outbox)..where((t) => t.id.isIn(ids.isEmpty ? [-1] : ids))).write(
      OutboxCompanion(
        lastSuccessfulPushAt: Value(now),
      ),
    );
  }

  /// ✅ مسح سجل ناجح واحد
  Future<void> cleanupSingleSuccess(int id) async {
    await (delete(outbox)..where((t) => t.id.equals(id))).go();
  }

  /// ✅ مسح السجلات الناجحة حسب UUIDs
  Future<void> cleanupSuccessfulByUuids(List<String> uuids) async {
    if (uuids.isEmpty) return;
    await (delete(outbox)..where((t) => t.localUuid.isIn(uuids))).go();
  }

  /// ✅ مسح السجلات المعلقة القديمة (أقدم من X ساعات)
  /// يُستخدم لتنظيف السجلات التي قد تكون فاتتها المزامنة
  Future<int> cleanupOldPendingRecords({int maxAgeHours = 1}) async {
    final cutoffEpoch = DateTime.now()
        .subtract(Duration(hours: maxAgeHours))
        .millisecondsSinceEpoch ~/ 1000;
    
    // مسح السجلات المعلقة القديمة فقط (ليس الفاشلة أو المتضاربة)
    return (delete(outbox)
          ..where((t) =>
              t.processingStatus.equals('pending') &
              t.clientTs.isSmallerThanValue(cutoffEpoch)))
        .go();
  }

  /// جدولة إعادة المحاولة مع exponential backoff
  Future<void> scheduleRetry(int id, String error, int currentAttempts) async {
    // حساب التأخير: 2^attempts ثانية (2, 4, 8, 16, 32...)
    // مع حد أقصى ساعة واحدة
    final delaySeconds = math.min(
      math.pow(2, currentAttempts).toInt(),
      3600, // ساعة واحدة كحد أقصى
    );
    
    final nextRetry = DateTime.now().add(Duration(seconds: delaySeconds));
    final nextRetryEpoch = nextRetry.millisecondsSinceEpoch ~/ 1000;

    await (update(outbox)..where((t) => t.id.equals(id))).write(
      OutboxCompanion(
        processingStatus: const Value('pending'),
        lastError: Value(error),
        attempts: Value(currentAttempts),
        nextRetryAt: Value(nextRetryEpoch),
        processingStartedAt: const Value(null),
        processingWorker: const Value(null),
      ),
    );
  }

  /// تحديد السجل كفاشل نهائياً (تجاوز حد المحاولات)
  Future<void> markAsPermanentlyFailed(int id, String error) async {
    await (update(outbox)..where((t) => t.id.equals(id))).write(
      OutboxCompanion(
        processingStatus: const Value('failed'),
        lastError: Value('PERMANENT: $error'),
        processingStartedAt: const Value(null),
        processingWorker: const Value(null),
      ),
    );
  }

  /// التحقق مما إذا كان السجل تجاوز حد المحاولات
  bool isPermanentlyFailed(OutboxData entry) {
    return entry.attempts >= (entry.maxAttempts ?? 5);
  }

  // ==================== الحذف والإزالة ====================

  Future<void> removeById(int id) async {
    await (delete(outbox)..where((t) => t.id.equals(id))).go();
  }

  Future<void> removeByIds(List<int> ids) async {
    if (ids.isEmpty) return;
    await (delete(outbox)..where((t) => t.id.isIn(ids))).go();
  }

  Future<int> removeByEntityAndUuid(String entity, String localUuid) async {
    return (delete(outbox)
          ..where(
              (t) => t.entity.equals(entity) & t.localUuid.equals(localUuid)))
        .go();
  }

  Future<OutboxData?> findPendingByEntityAndUuid(
      String entity, String localUuid) async {
    final results = await (select(outbox)
          ..where((t) =>
              t.entity.equals(entity) &
              t.localUuid.equals(localUuid) &
              t.processingStatus.isIn(['pending', 'processing'])))
        .get();
    return results.isEmpty ? null : results.first;
  }

  Future<void> markAsConflict(int id, String error,
      {String? remotePayload}) async {
    await (update(outbox)..where((t) => t.id.equals(id))).write(
      OutboxCompanion(
        processingStatus: const Value('conflict'),
        lastError: Value(error),
        remotePayload: Value(remotePayload),
        processingStartedAt: const Value(null),
        processingWorker: const Value(null),
      ),
    );
  }

  Future<int> removeAllPending() async {
    return (delete(outbox)
          ..where((t) => t.processingStatus.isIn(['pending', 'failed'])))
        .go();
  }

  Future<void> removeByUuids(List<String> uuids) async {
    if (uuids.isEmpty) return;
    await (delete(outbox)..where((t) => t.localUuid.isIn(uuids))).go();
  }

  Future<void> removeByUuid(String uuid) async {
    await (delete(outbox)..where((t) => t.localUuid.equals(uuid))).go();
  }

  Future<void> setError(int id, String message, int attempts) async {
    // التحقق من تجاوز الحد الأقصى
    final entry = await (select(outbox)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    
    if (entry != null && attempts >= (entry.maxAttempts ?? 5)) {
      await markAsPermanentlyFailed(id, message);
    } else {
      await scheduleRetry(id, message, attempts);
    }
  }

  Future<void> markCompleted(List<int> ids) async {
    if (ids.isEmpty) return;
    // ✅ مسح فوري بدلاً من تحديث الحالة
    await cleanupOnSuccess(ids);
  }

  Future<void> markFailed(List<int> ids) async {
    if (ids.isEmpty) return;
    
    for (final id in ids) {
      final entry = await (select(outbox)..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      if (entry != null) {
        await setError(id, 'Batch processing failed', entry.attempts + 1);
      }
    }
  }

  Future<void> retryFailed() async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    
    await (update(outbox)..where((t) => 
        t.processingStatus.equals('failed') &
        (t.nextRetryAt.isNull() | t.nextRetryAt.isSmallerOrEqualValue(now))))
        .write(OutboxCompanion(
          processingStatus: const Value('pending'),
          processingStartedAt: const Value(null),
          processingWorker: const Value(null),
          nextRetryAt: const Value(null),
        ));
  }

  // ==================== التنظيف والصيانة ====================

  Future<int> cleanupStuckEntries({
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final cutoff =
        (DateTime.now().millisecondsSinceEpoch ~/ 1000) - timeout.inSeconds;
    final stuck = await (select(outbox)
          ..where((t) =>
              t.processingStatus.equals('processing') &
              t.processingStartedAt.isSmallerOrEqualValue(cutoff)))
        .get();

    if (stuck.isEmpty) return 0;

    for (final entry in stuck) {
      await scheduleRetry(entry.id, 'Processing timeout', entry.attempts);
    }
    
    return stuck.length;
  }

  Future<int> cleanupCompleted({
    Duration olderThan = const Duration(days: 7),
  }) async {
    final cutoff =
        (DateTime.now().millisecondsSinceEpoch ~/ 1000) - olderThan.inSeconds;
    final rows = await (delete(outbox)
          ..where((t) =>
              t.processingStatus.equals('completed') &
              t.clientTs.isSmallerOrEqualValue(cutoff)))
        .go();
    return rows;
  }

  /// تنظيف شامل للسجلات القديمة والفاشلة
  Future<Map<String, int>> performFullCleanup() async {
    final result = <String, int>{};
    
    // مسح السجلات العالقة
    result['stuck'] = await cleanupStuckEntries();
    
    // مسح السجلات المكتملة القديمة
    result['completed'] = await cleanupCompleted();
    
    // مسح السجلات الفاشلة نهائياً
    result['permanent_failed'] = await (delete(outbox)
          ..where((t) => 
              t.processingStatus.equals('failed') &
              t.attempts.isBiggerOrEqual(t.maxAttempts)))
          .go();
    
    return result;
  }

  // ==================== التعارضات ====================

  Future<List<ConflictRecord>> getConflicts() async {
    final conflicting = await (select(outbox)
          ..where((t) => t.processingStatus.equals('conflict'))
          ..orderBy([(t) => OrderingTerm.desc(t.clientTs)]))
        .get();

    return conflicting.map((entry) {
      final localPayload = jsonDecode(entry.payload) as Map<String, dynamic>;
      final remotePayload = entry.remotePayload != null
          ? jsonDecode(entry.remotePayload!) as Map<String, dynamic>
          : localPayload;
      return ConflictRecord(
        id: entry.id,
        uuid: entry.localUuid,
        targetTable: entry.entity,
        localPayload: localPayload,
        remotePayload: remotePayload,
        lastError: entry.lastError ?? 'Unknown conflict',
        timestamp: DateTime.fromMillisecondsSinceEpoch(entry.clientTs * 1000),
      );
    }).toList();
  }

  Future<void> resolveConflict(
    int id,
    Map<String, dynamic> resolvedData, {
    required String resolution,
  }) async {
    // ✅ مسح السجل بعد حل التعارض
    await (delete(outbox)..where((t) => t.id.equals(id))).go();
  }

  // ==================== الإحصائيات ====================

  Future<OutboxStats> getStats() async {
    final statusCounts = await countByStatus();
    
    final oldestPending = await (select(outbox)
          ..where((t) => t.processingStatus.equals('pending'))
          ..orderBy([(t) => OrderingTerm.asc(t.clientTs)])
          ..limit(1))
        .getSingleOrNull();

    final nextRetry = await (select(outbox)
          ..where((t) => 
              t.processingStatus.equals('pending') &
              t.nextRetryAt.isNotNull())
          ..orderBy([(t) => OrderingTerm.asc(t.nextRetryAt)])
          ..limit(1))
        .getSingleOrNull();

    return OutboxStats(
      pending: statusCounts['pending'] ?? 0,
      processing: statusCounts['processing'] ?? 0,
      completed: statusCounts['completed'] ?? 0,
      failed: statusCounts['failed'] ?? 0,
      conflicts: statusCounts['conflict'] ?? 0,
      oldestPendingAt: oldestPending != null
          ? DateTime.fromMillisecondsSinceEpoch(oldestPending.clientTs * 1000)
          : null,
      nextRetryAt: nextRetry?.nextRetryAt != null
          ? DateTime.fromMillisecondsSinceEpoch(nextRetry!.nextRetryAt! * 1000)
          : null,
    );
  }
}

/// سجل يمثل تعارض في البيانات
class ConflictRecord {
  ConflictRecord({
    required this.id,
    required this.uuid,
    required this.targetTable,
    required this.localPayload,
    required this.remotePayload,
    required this.lastError,
    required this.timestamp,
  });
  
  final int id;
  final String uuid;
  final String targetTable;
  final Map<String, dynamic> localPayload;
  final Map<String, dynamic> remotePayload;
  final String lastError;
  final DateTime timestamp;
}

/// إحصائيات Outbox
class OutboxStats {
  OutboxStats({
    required this.pending,
    required this.processing,
    required this.completed,
    required this.failed,
    required this.conflicts,
    this.oldestPendingAt,
    this.nextRetryAt,
  });
  
  final int pending;
  final int processing;
  final int completed;
  final int failed;
  final int conflicts;
  final DateTime? oldestPendingAt;
  final DateTime? nextRetryAt;
  
  int get total => pending + processing + completed + failed + conflicts;
  int get needsAttention => failed + conflicts;
  bool get hasPendingWork => pending > 0 || processing > 0;
}
