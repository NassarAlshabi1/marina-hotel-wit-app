import 'dart:convert';
import 'package:drift/drift.dart';
import '../local_db.dart';

part 'outbox_dao.g.dart';

@DriftAccessor(tables: [Outbox])
class OutboxDao extends DatabaseAccessor<AppDatabase> with _$OutboxDaoMixin {
  OutboxDao(AppDatabase db) : super(db);

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
    if (existing != null) {
      return (update(outbox)..where((t) => t.id.equals(existing.id))).write(OutboxCompanion(
        payload: Value(data),
        serverId: Value(serverId),
        clientTs: Value(clientTs),
        attempts: const Value(0),
        lastError: const Value.absent(),
      ));
    } else {
      return into(outbox).insert(OutboxCompanion(
        entity: Value(entity),
        op: Value(op),
        localUuid: Value(localUuid),
        serverId: Value(serverId),
        payload: Value(data),
        clientTs: Value(clientTs),
      ));
    }
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
