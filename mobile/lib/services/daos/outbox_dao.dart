import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../local_db.dart';
import '../adapters/adapter_registry.dart';

part 'outbox_dao.g.dart';

const _uuid = Uuid();

@DriftAccessor(tables: [Outbox])
class OutboxDao extends DatabaseAccessor<AppDatabase> with _$OutboxDaoMixin {
  OutboxDao(super.db) : adapters = AdapterRegistry(db);

  final AdapterRegistry adapters;

  Stream<int> watchCount() {
    final countExp = outbox.id.count();
    final query = selectOnly(outbox)
      ..addColumns([countExp])
      ..where(outbox.processingStatus.isIn(['pending', 'failed']));
    return query
        .map((row) => row.read(countExp) ?? 0)
        .watchSingle();
  }

  Future<int> count() async {
    final countExp = outbox.id.count();
    final query = selectOnly(outbox)
      ..addColumns([countExp])
      ..where(outbox.processingStatus.isIn(['pending', 'failed']));
    final row = await query.getSingle();
    return row.read(countExp) ?? 0;
  }

  Future<void> resetErrors() async {
    await (update(outbox)
          ..where(
              (t) => t.processingStatus.equals('failed')))
        .write(const OutboxCompanion(
      processingStatus: Value('pending'),
      attempts: Value(0),
      lastError: Value(null),
      processingStartedAt: Value(null),
      processingWorker: Value(null),
    ));
  }

  Future<int> clearStale({int attemptsThreshold = 3}) async {
    final rows = await (delete(outbox)
          ..where((t) => t.attempts.isBiggerOrEqualValue(attemptsThreshold)))
        .go();
    return rows;
  }

  Future<int> merge({
    required String entity,
    required String op,
    required String localUuid,
    int? serverId,
    required Map<String, dynamic> payload,
    required int clientTs,
  }) async {
    final existing = await (select(outbox)
          ..where((t) =>
              t.entity.equals(entity) &
              t.localUuid.equals(localUuid) &
              t.processingStatus.equals('pending'))
          ..limit(1))
        .getSingleOrNull();

    final payloadJson = jsonEncode(payload);
    final idempKey = '${entity}:${op}:${localUuid}:$clientTs';

    if (existing != null) {
      await (update(outbox)..where((t) => t.id.equals(existing.id))).write(
        OutboxCompanion(
          op: Value(op),
          payload: Value(payloadJson),
          clientTs: Value(clientTs),
          idempotencyKey: Value(idempKey),
          serverId: Value(serverId),
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
    ));
  }

  Future<List<OutboxData>> takeBatch(int limit, {String? workerId}) async {
    final worker = workerId ?? _uuid.v4();
    final nowEpoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final pending = await (select(outbox)
          ..where((t) => t.processingStatus.equals('pending'))
          ..orderBy([(t) => OrderingTerm.asc(t.clientTs)])
          ..limit(limit))
        .get();

    if (pending.isEmpty) return [];

    final ids = pending.map((e) => e.id).toList();
    await (update(outbox)..where((t) => t.id.isIn(ids))).write(
      OutboxCompanion(
        processingStatus: const Value('processing'),
        processingStartedAt: Value(nowEpoch),
        processingWorker: Value(worker),
      ),
    );

    return pending;
  }

  Future<void> removeById(int id) async {
    await (delete(outbox)..where((t) => t.id.equals(id))).go();
  }

  Future<void> removeByIds(List<int> ids) async {
    if (ids.isEmpty) return;
    await (delete(outbox)..where((t) => t.id.isIn(ids))).go();
  }

  Future<int> removeByEntityAndUuid(String entity, String localUuid) async {
    return (delete(outbox)
          ..where((t) =>
              t.entity.equals(entity) & t.localUuid.equals(localUuid)))
        .go();
  }

  Future<OutboxData?> findPendingByEntityAndUuid(String entity, String localUuid) async {
    final results = await (select(outbox)
          ..where((t) =>
              t.entity.equals(entity) &
              t.localUuid.equals(localUuid) &
              t.processingStatus.isIn(['pending', 'processing'])))
        .get();
    return results.isEmpty ? null : results.first;
  }

  Future<void> markAsConflict(int id, String error, {String? remotePayload}) async {
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

  Future<void> setError(int id, String message, int attempts) async {
    await (update(outbox)..where((t) => t.id.equals(id))).write(
      OutboxCompanion(
        lastError: Value(message),
        attempts: Value(attempts),
        processingStatus: const Value('failed'),
        processingStartedAt: const Value(null),
        processingWorker: const Value(null),
      ),
    );
  }

  Future<void> markCompleted(List<int> ids) async {
    if (ids.isEmpty) return;
    await (update(outbox)..where((t) => t.id.isIn(ids))).write(
      const OutboxCompanion(
        processingStatus: Value('completed'),
        processingStartedAt: Value(null),
        processingWorker: Value(null),
      ),
    );
  }

  Future<void> markFailed(List<int> ids) async {
    if (ids.isEmpty) return;
    await (update(outbox)..where((t) => t.id.isIn(ids))).write(
      const OutboxCompanion(
        processingStatus: Value('failed'),
        processingStartedAt: Value(null),
        processingWorker: Value(null),
      ),
    );
  }

  Future<void> retryFailed() async {
    await (update(outbox)
          ..where((t) => t.processingStatus.equals('failed')))
        .write(const OutboxCompanion(
      processingStatus: Value('pending'),
      processingStartedAt: Value(null),
      processingWorker: Value(null),
    ));
  }

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

    final ids = stuck.map((e) => e.id).toList();
    await (update(outbox)..where((t) => t.id.isIn(ids))).write(
      const OutboxCompanion(
        processingStatus: Value('pending'),
        processingStartedAt: Value(null),
        processingWorker: Value(null),
      ),
    );
    return ids.length;
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

  /// جلب التعارضات من Outbox (السجلات التي فشلت بسبب تعارض)
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

  /// حل تعارض محدد
  Future<void> resolveConflict(
    int id,
    Map<String, dynamic> resolvedData, {
    required String resolution,
  }) async {
    // تحديث السجل ليعكس الحل
    await (update(outbox)..where((t) => t.id.equals(id))).write(
      OutboxCompanion(
        processingStatus: const Value('completed'),
        lastError: Value(null),
        attempts: const Value(0),
        payload: Value(jsonEncode(resolvedData)),
      ),
    );
  }
}

/// سجل يمثل تعارض في البيانات
class ConflictRecord {
  final int id;
  final String uuid;
  final String targetTable;
  final Map<String, dynamic> localPayload;
  final Map<String, dynamic> remotePayload;
  final String lastError;
  final DateTime timestamp;

  ConflictRecord({
    required this.id,
    required this.uuid,
    required this.targetTable,
    required this.localPayload,
    required this.remotePayload,
    required this.lastError,
    required this.timestamp,
  });
}
