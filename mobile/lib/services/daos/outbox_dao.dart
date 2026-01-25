import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../local_db.dart';
import '../unified_sync_orchestrator.dart';

part 'outbox_dao.g.dart';

const _uuid = Uuid();

@DriftAccessor(tables: [Outbox])
class OutboxDao extends DatabaseAccessor<AppDatabase> with _$OutboxDaoMixin {
  OutboxDao(super.db);

  Stream<int> watchCount() {
    final countExpr = outbox.id.count();
    final query = selectOnly(outbox)..addColumns([countExpr]);
    return query.watchSingle().map((row) => row.read(countExpr) ?? 0);
  }

  Future<int> count() async {
    final countExpr = outbox.id.count();
    final query = selectOnly(outbox)..addColumns([countExpr]);
    final row = await query.getSingle();
    return row.read(countExpr) ?? 0;
  }

  Future<void> resetErrors() async {
    await (update(outbox)).write(
      OutboxCompanion(
        attempts: const Value(0),
        lastError: const Value.absent(),
      ),
    );
  }

  Future<int> clearStale({int attemptsThreshold = 3}) async {
    return (delete(outbox)
          ..where((t) => t.attempts.isBiggerOrEqualValue(attemptsThreshold)))
        .go();
  }

  Future<int> merge({
    required String entity,
    required String op,
    required String localUuid,
    int? serverId,
    required Map<String, dynamic> payload,
    required int clientTs,
  }) async {
    final data = jsonEncode(payload);

    final id = await transaction(() async {
      final existing = await (select(outbox)
            ..where((t) => t.localUuid.equals(localUuid) & t.op.equals(op)))
          .getSingleOrNull();

      String idempotencyKey;
      if (existing != null) {
        final result = await customSelect(
          'SELECT idempotency_key FROM ${outbox.actualTableName} WHERE id = ?',
          variables: [Variable<int>(existing.id)],
          readsFrom: {outbox},
        ).getSingleOrNull();
        idempotencyKey =
            result?.data['idempotency_key'] as String? ?? _uuid.v4();
      } else {
        idempotencyKey = _uuid.v4();
      }

      late final int resultId;
      if (existing != null) {
        await (update(outbox)..where((t) => t.id.equals(existing.id))).write(
          OutboxCompanion(
            payload: Value(data),
            serverId: Value(serverId),
            clientTs: Value(clientTs),
            attempts: const Value(0),
            lastError: const Value.absent(),
          ),
        );
        resultId = existing.id;
      } else {
        resultId = await into(outbox).insert(
          OutboxCompanion(
            entity: Value(entity),
            op: Value(op),
            localUuid: Value(localUuid),
            serverId: Value(serverId),
            payload: Value(data),
            clientTs: Value(clientTs),
          ),
        );
      }

      if (existing == null) {
        await customUpdate(
          'UPDATE ${outbox.actualTableName} SET idempotency_key = ? WHERE id = ?',
          variables: [
            Variable<String>(idempotencyKey),
            Variable<int>(resultId),
          ],
          updates: {outbox},
        );
      }

      return resultId;
    });

    UnifiedSyncOrchestrator.instance.notifyLocalChange(
      table: entity,
      operation: op,
    );
    return id;
  }

  Future<List<OutboxData>> takeBatch(int limit, {String? workerId}) async {
    final worker = workerId ?? const Uuid().v4();

    return transaction(() async {
      final entries = await (select(outbox)
            ..where((t) => t.processingStatus.equals('pending'))
            ..orderBy([(t) => OrderingTerm(expression: t.clientTs)])
            ..limit(limit))
          .get();

      if (entries.isEmpty) {
        return [];
      }

      final ids = entries.map((e) => e.id).toList();

<<<<<<< Updated upstream
      await (update(outbox)..where((t) => t.id.isIn(ids))).write(
        RawValuesInsertable({
          'processing_status': Variable<String>('processing'),
          'processing_started_at':
              Variable<int>(DateTime.now().millisecondsSinceEpoch),
          'processing_worker': Variable<String>(worker),
        }),
      );
=======
      await (update(outbox)..where((t) => t.id.isIn(ids)))
          .write(OutboxCompanion(
        processingStatus: const Value('processing'),
        processingStartedAt: Value(DateTime.now().millisecondsSinceEpoch),
        processingWorker: Value(worker),
      ));
>>>>>>> Stashed changes

      return entries;
    });
  }

  Future<void> removeById(int id) =>
      (delete(outbox)..where((t) => t.id.equals(id))).go();

  Future<void> removeByIds(List<int> ids) {
    if (ids.isEmpty) {
      return Future.value();
    }
    return (delete(outbox)..where((t) => t.id.isIn(ids))).go();
  }

  Future<void> setError(int id, String message, int attempts) =>
      (update(outbox)..where((t) => t.id.equals(id))).write(OutboxCompanion(
          lastError: Value(message), attempts: Value(attempts)));

  Future<void> markCompleted(List<int> ids) async {
    if (ids.isEmpty) return;
<<<<<<< Updated upstream
    await (update(outbox)..where((t) => t.id.isIn(ids))).write(
      RawValuesInsertable({
        'processing_status': Variable<String>('completed'),
        'processing_started_at': const Variable<int>(null),
        'processing_worker': const Variable<String>(null),
      }),
    );
=======
    await (update(outbox)..where((t) => t.id.isIn(ids)))
        .write(const OutboxCompanion(
      processingStatus: Value('completed'),
      processingStartedAt: Value.absent(),
      processingWorker: Value.absent(),
    ));
>>>>>>> Stashed changes
  }

  Future<void> markFailed(List<int> ids) async {
    if (ids.isEmpty) return;
<<<<<<< Updated upstream
    await (update(outbox)..where((t) => t.id.isIn(ids))).write(
      RawValuesInsertable({
        'processing_status': Variable<String>('failed'),
      }),
    );
=======
    await (update(outbox)..where((t) => t.id.isIn(ids)))
        .write(const OutboxCompanion(
      processingStatus: Value('failed'),
    ));
>>>>>>> Stashed changes
  }

  Future<void> retryFailed() async {
    await (update(outbox)..where((t) => t.processingStatus.equals('failed')))
<<<<<<< Updated upstream
        .write(RawValuesInsertable({
      'processing_status': Variable<String>('pending'),
      'processing_started_at': const Variable<int>(null),
      'processing_worker': const Variable<String>(null),
      'attempts': const Variable<int>(0),
    }));
=======
        .write(const OutboxCompanion(
      processingStatus: Value('pending'),
      processingStartedAt: Value.absent(),
      processingWorker: Value.absent(),
      attempts: Value(0),
    ));
>>>>>>> Stashed changes
  }

  Future<int> cleanupStuckEntries(
      {Duration timeout = const Duration(minutes: 5)}) async {
    final thresholdTime =
        DateTime.now().subtract(timeout).millisecondsSinceEpoch;

    return await (update(outbox)
          ..where((t) =>
              t.processingStatus.equals('processing') &
              t.processingStartedAt.isSmallerThanValue(thresholdTime)))
<<<<<<< Updated upstream
        .write(RawValuesInsertable({
      'processing_status': Variable<String>('pending'),
      'processing_started_at': const Variable<int>(null),
      'processing_worker': const Variable<String>(null),
    }));
=======
        .write(const OutboxCompanion(
      processingStatus: Value('pending'),
      processingStartedAt: Value.absent(),
      processingWorker: Value.absent(),
    ));
>>>>>>> Stashed changes
  }

  Future<int> cleanupCompleted(
      {Duration olderThan = const Duration(days: 7)}) async {
    final thresholdTime =
        DateTime.now().subtract(olderThan).millisecondsSinceEpoch;

    return await (delete(outbox)
          ..where((t) =>
              t.processingStatus.equals('completed') &
              t.processingStartedAt.isSmallerThanValue(thresholdTime)))
        .go();
  }
}
