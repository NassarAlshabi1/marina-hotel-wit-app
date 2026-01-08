import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../local_db.dart';
import '../sync_guardian.dart';
import '../google_drive_unified_sync_coordinator.dart';
import '../google_drive_auto_sync_engine.dart';

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
    return (delete(outbox)..where((t) => t.attempts.isBiggerOrEqualValue(attemptsThreshold))).go();
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
        idempotencyKey = result?.data['idempotency_key'] as String? ?? _uuid.v4();
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

    _notifyAllSyncEngines(entity, op);
    return id;
  }

  void _notifyAllSyncEngines(String entity, String op) {
    Future.microtask(() async {
      try {
        await SyncGuardian.instance.notifyLocalChange(table: entity, operation: op);
      } catch (e, s) {
        debugPrint('Error notifying SyncGuardian: $e\n$s');
      }
  void _notifyAllSyncEngines(String entity, String op) {
    Future.microtask(() async {
      try {
        await SyncGuardian.instance.notifyLocalChange(table: entity, operation: op);
      } catch (e, s) {
        // تجاهل أخطاء الإشعار - لا نريد إيقاف العملية الأساسية
        debugPrint('Error notifying SyncGuardian: $e\n$s');
      }
    });
    try {
      GoogleDriveUnifiedSyncCoordinator.instance.notifyLocalChange(table: entity, operation: op);
    } catch (e, s) {
      debugPrint('Error notifying GoogleDriveUnifiedSyncCoordinator: $e\n$s');
    }
    try {
      AutoSyncEngine.instance.notifyDataChange(table: entity, operation: op);
    } catch (e, s) {
      debugPrint('Error notifying AutoSyncEngine: $e\n$s');
    }
  }

  Future<List<OutboxData>> takeBatch(int limit) {
    return (select(outbox)
          ..orderBy([(t) => OrderingTerm(expression: t.clientTs)])
          ..limit(limit))
        .get();
  }

  Future<void> removeById(int id) => (delete(outbox)..where((t) => t.id.equals(id))).go();

  Future<void> removeByIds(List<int> ids) {
    if (ids.isEmpty) {
      return Future.value();
    }
    return (delete(outbox)..where((t) => t.id.isIn(ids))).go();
  }
  
  Future<void> setError(int id, String message, int attempts) =>
      (update(outbox)..where((t) => t.id.equals(id))).write(OutboxCompanion(lastError: Value(message), attempts: Value(attempts)));
}
