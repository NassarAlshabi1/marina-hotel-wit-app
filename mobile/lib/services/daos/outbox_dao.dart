import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart';
import '../local_db.dart';
import '../sync_guardian.dart';
import '../google_drive_unified_sync_coordinator.dart';
import '../google_drive_auto_sync_engine.dart';

part 'outbox_dao.g.dart';

@DriftAccessor(tables: [Outbox])
class OutboxDao extends DatabaseAccessor<AppDatabase> with _$OutboxDaoMixin {
  OutboxDao(super.db);

  Stream<int> watchCount() {
    return (select(outbox)).watch().map((rows) => rows.length);
  }

  Future<int> count() async {
    final rows = await (select(outbox)).get();
    return rows.length;
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
    final existing = await (select(outbox)
          ..where((t) => t.localUuid.equals(localUuid) & t.op.equals(op)))
        .getSingleOrNull();
    final data = jsonEncode(payload);
    final result = existing != null
        ? await (update(outbox)..where((t) => t.id.equals(existing.id))).write(OutboxCompanion(
            payload: Value(data),
            serverId: Value(serverId),
            clientTs: Value(clientTs),
            attempts: const Value(0),
            lastError: const Value.absent(),
          ))
        : await into(outbox).insert(OutboxCompanion(
            entity: Value(entity),
            op: Value(op),
            localUuid: Value(localUuid),
            serverId: Value(serverId),
            payload: Value(data),
            clientTs: Value(clientTs),
          ));

    unawaited(SyncGuardian.instance.notifyLocalChange(table: entity, operation: op));
    GoogleDriveUnifiedSyncCoordinator.instance.notifyLocalChange(table: entity, operation: op);
    AutoSyncEngine.instance.notifyDataChange(table: entity, operation: op);
    return result;
  }

  Future<List<OutboxData>> takeBatch(int limit) {
    return (select(outbox)
          ..orderBy([(t) => OrderingTerm(expression: t.clientTs)])
          ..limit(limit))
        .get();
  }

  Future<void> removeById(int id) => (delete(outbox)..where((t) => t.id.equals(id))).go();

  Future<void> setError(int id, String message, int attempts) =>
      (update(outbox)..where((t) => t.id.equals(id))).write(OutboxCompanion(lastError: Value(message), attempts: Value(attempts)));
}
