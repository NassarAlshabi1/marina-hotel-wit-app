import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../local_db.dart';
import '../unified_sync_orchestrator.dart';
import '../adapters/adapter_registry.dart';
import '../adapters/source.dart';

part 'outbox_dao.g.dart';

const _uuid = Uuid();

@DriftAccessor(tables: [Outbox])
class OutboxDao extends DatabaseAccessor<AppDatabase> with _$OutboxDaoMixin {
  OutboxDao(super.db) : adapters = AdapterRegistry(db);

  final AdapterRegistry adapters;

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
    return (delete(
      outbox,
    )..where((t) => t.attempts.isBiggerOrEqualValue(attemptsThreshold)))
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
    final normalizedPayload = await _payloadWithAdapter(
      entity,
      localUuid,
      payload,
    );
    final data = jsonEncode(normalizedPayload);

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

      await (update(outbox)..where((t) => t.id.isIn(ids))).write(
        OutboxCompanion(
          processingStatus: const Value('processing'),
          processingStartedAt: Value(DateTime.now().millisecondsSinceEpoch),
          processingWorker: Value(worker),
        ),
      );

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
      (update(outbox)..where((t) => t.id.equals(id))).write(
        OutboxCompanion(
          lastError: Value(message),
          attempts: Value(attempts),
          processingStatus: const Value('failed'),
        ),
      );

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
      const OutboxCompanion(processingStatus: Value('failed')),
    );
  }

  Future<void> retryFailed() async {
    await (update(
      outbox,
    )..where((t) => t.processingStatus.equals('failed')))
        .write(
      const OutboxCompanion(
        processingStatus: Value('pending'),
        processingStartedAt: Value(null),
        processingWorker: Value(null),
        attempts: Value(0),
      ),
    );
  }

  Future<int> cleanupStuckEntries({
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final thresholdTime =
        DateTime.now().subtract(timeout).millisecondsSinceEpoch;

    return await (update(outbox)
          ..where(
            (t) =>
                t.processingStatus.equals('processing') &
                t.processingStartedAt.isSmallerThanValue(thresholdTime),
          ))
        .write(
      const OutboxCompanion(
        processingStatus: Value('pending'),
        processingStartedAt: Value(null),
        processingWorker: Value(null),
      ),
    );
  }

  Future<int> cleanupCompleted({
    Duration olderThan = const Duration(days: 7),
  }) async {
    final thresholdTime =
        DateTime.now().subtract(olderThan).millisecondsSinceEpoch;

    return await (delete(outbox)
          ..where(
            (t) =>
                t.processingStatus.equals('completed') &
                t.processingStartedAt.isSmallerThanValue(thresholdTime),
          ))
        .go();
  }

  Future<Map<String, dynamic>> _payloadWithAdapter(
    String entity,
    String localUuid,
    Map<String, dynamic> fallback,
  ) async {
    switch (entity) {
      case 'bookings':
        final row = await (select(db.bookings)
              ..where((t) => t.localUuid.equals(localUuid))
              ..limit(1))
            .getSingleOrNull();
        if (row != null) {
          return adapters.bookings.toJsonForSource(row, src: Source.appwrite);
        }
        break;
      case 'payments':
        final row = await (select(db.payments)
              ..where((t) => t.localUuid.equals(localUuid))
              ..limit(1))
            .getSingleOrNull();
        if (row != null) {
          return adapters.payments.toJsonForSource(row, src: Source.appwrite);
        }
        break;
      case 'expenses':
        final row = await (select(db.expenses)
              ..where((t) => t.localUuid.equals(localUuid))
              ..limit(1))
            .getSingleOrNull();
        if (row != null) {
          return adapters.expenses.toJsonForSource(row, src: Source.appwrite);
        }
        break;
      case 'debts':
        final row = await (select(db.debts)
              ..where((t) => t.localUuid.equals(localUuid))
              ..limit(1))
            .getSingleOrNull();
        if (row != null) {
          return adapters.debts.toJsonForSource(row, src: Source.appwrite);
        }
        break;
      case 'rooms':
        final row = await (select(db.rooms)
              ..where((t) => t.localUuid.equals(localUuid))
              ..limit(1))
            .getSingleOrNull();
        if (row != null) {
          return adapters.rooms.toJsonForSource(row, src: Source.appwrite);
        }
        break;
      case 'employees':
        final row = await (select(db.employees)
              ..where((t) => t.localUuid.equals(localUuid))
              ..limit(1))
            .getSingleOrNull();
        if (row != null) {
          return adapters.employees.toJsonForSource(row, src: Source.appwrite);
        }
        break;
      case 'booking_notes':
        final row = await (select(db.bookingNotes)
              ..where((t) => t.localUuid.equals(localUuid))
              ..limit(1))
            .getSingleOrNull();
        if (row != null) {
          return adapters.bookingNotes.toJsonForSource(
            row,
            src: Source.appwrite,
          );
        }
        break;
      case 'booking_nights':
        final row = await (select(db.bookingNights)
              ..where((t) => t.localUuid.equals(localUuid))
              ..limit(1))
            .getSingleOrNull();
        if (row != null) {
          return adapters.nights.toJsonForSource(row, src: Source.appwrite);
        }
        break;
      case 'salary_cycles':
        final row = await (select(db.salaryCycles)
              ..where((t) => t.localUuid.equals(localUuid))
              ..limit(1))
            .getSingleOrNull();
        if (row != null) {
          return adapters.salaryCycles.toJsonForSource(
            row,
            src: Source.appwrite,
          );
        }
        break;
      case 'salary_payments':
        final row = await (select(db.salaryPayments)
              ..where((t) => t.localUuid.equals(localUuid))
              ..limit(1))
            .getSingleOrNull();
        if (row != null) {
          return adapters.salaryPayments.toJsonForSource(
            row,
            src: Source.appwrite,
          );
        }
        break;
      case 'cash_transactions':
        final row = await (select(db.cashTransactions)
              ..where((t) => t.localUuid.equals(localUuid))
              ..limit(1))
            .getSingleOrNull();
        if (row != null) {
          return adapters.cashTransactions.toJsonForSource(
            row,
            src: Source.appwrite,
          );
        }
        break;
      case 'shift_notes':
        final row = await (select(db.shiftNotes)
              ..where((t) => t.localUuid.equals(localUuid))
              ..limit(1))
            .getSingleOrNull();
        if (row != null) {
          return adapters.shiftNotes.toJsonForSource(row, src: Source.appwrite);
        }
        break;
    }
    return fallback;
  }
}
