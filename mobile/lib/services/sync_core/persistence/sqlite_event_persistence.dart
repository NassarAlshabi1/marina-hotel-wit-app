import 'dart:convert';

import 'package:drift/drift.dart';

import '../../local_db.dart';
import '../events/sync_event.dart';
import 'event_persistence.dart';

class SqliteEventPersistence implements EventPersistence {
  final AppDatabase _db;

  SqliteEventPersistence(this._db);

  @override
  Future<void> initialize() async {}

  @override
  Future<void> persist(EnhancedSyncEvent event) async {
    await _db.into(_db.syncEventQueue).insert(
          SyncEventQueueCompanion.insert(
            id: event.id,
            tableName: event.table,
            operation: event.operation.name,
            entityId: event.entityId,
            payload: Value(event.payload != null ? jsonEncode(event.payload) : null),
            previousPayload: Value(
                event.previousPayload != null ? jsonEncode(event.previousPayload) : null),
            priority: event.priority.name,
            timestamp: event.timestamp.millisecondsSinceEpoch,
            scheduledAt: Value(event.scheduledAt?.millisecondsSinceEpoch),
            retryCount: Value(event.retryCount),
            maxRetries: Value(event.maxRetries),
            correlationId: Value(event.correlationId),
            causationId: Value(event.causationId),
            metadata: Value(event.metadata != null ? jsonEncode(event.metadata) : null),
            source: Value(event.source),
            acknowledged: Value(event.acknowledged),
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  @override
  Future<void> persistBatch(List<EnhancedSyncEvent> events) async {
    await _db.batch((batch) {
      for (final event in events) {
        batch.insert(
          _db.syncEventQueue,
          SyncEventQueueCompanion.insert(
            id: event.id,
            tableName: event.table,
            operation: event.operation.name,
            entityId: event.entityId,
            payload: Value(event.payload != null ? jsonEncode(event.payload) : null),
            previousPayload: Value(
                event.previousPayload != null ? jsonEncode(event.previousPayload) : null),
            priority: event.priority.name,
            timestamp: event.timestamp.millisecondsSinceEpoch,
            scheduledAt: Value(event.scheduledAt?.millisecondsSinceEpoch),
            retryCount: Value(event.retryCount),
            maxRetries: Value(event.maxRetries),
            correlationId: Value(event.correlationId),
            causationId: Value(event.causationId),
            metadata: Value(event.metadata != null ? jsonEncode(event.metadata) : null),
            source: Value(event.source),
            acknowledged: Value(event.acknowledged),
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }

  @override
  Future<void> acknowledge(String eventId) async {
    await (_db.update(_db.syncEventQueue)
          ..where((t) => t.id.equals(eventId)))
        .write(const SyncEventQueueCompanion(acknowledged: Value(true)));
  }

  @override
  Future<void> acknowledgeBatch(List<String> eventIds) async {
    await (_db.update(_db.syncEventQueue)
          ..where((t) => t.id.isIn(eventIds)))
        .write(const SyncEventQueueCompanion(acknowledged: Value(true)));
  }

  @override
  Future<List<EnhancedSyncEvent>> getUnacknowledged({
    int? limit,
    SyncPriority? minPriority,
    String? table,
  }) async {
    var query = _db.select(_db.syncEventQueue)
      ..where((t) => t.acknowledged.equals(false));

    if (table != null) {
      query = query..where((t) => t.tableName.equals(table));
    }

    query = query
      ..orderBy([
        (t) => OrderingTerm(
              expression: t.priority,
              mode: OrderingMode.asc,
            ),
        (t) => OrderingTerm(
              expression: t.timestamp,
              mode: OrderingMode.asc,
            ),
      ]);

    if (limit != null) {
      query = query..limit(limit);
    }

    final rows = await query.get();
    var events = rows.map(_rowToEvent).toList();

    if (minPriority != null) {
      events = events.where((e) => e.priority <= minPriority).toList();
    }

    return events;
  }

  @override
  Future<List<EnhancedSyncEvent>> getPending({
    int? limit,
    Duration? olderThan,
  }) async {
    var query = _db.select(_db.syncEventQueue)
      ..where((t) => t.acknowledged.equals(false));

    if (olderThan != null) {
      final cutoff =
          DateTime.now().subtract(olderThan).millisecondsSinceEpoch;
      query = query..where((t) => t.timestamp.isSmallerThanValue(cutoff));
    }

    query = query
      ..orderBy([
        (t) => OrderingTerm(expression: t.timestamp, mode: OrderingMode.asc),
      ]);

    if (limit != null) {
      query = query..limit(limit);
    }

    final rows = await query.get();
    return rows.map(_rowToEvent).toList();
  }

  @override
  Future<List<EnhancedSyncEvent>> getByCorrelationId(
      String correlationId) async {
    final query = _db.select(_db.syncEventQueue)
      ..where((t) => t.correlationId.equals(correlationId))
      ..orderBy([
        (t) => OrderingTerm(expression: t.timestamp, mode: OrderingMode.asc),
      ]);

    final rows = await query.get();
    return rows.map(_rowToEvent).toList();
  }

  @override
  Future<EnhancedSyncEvent?> getById(String eventId) async {
    final query = _db.select(_db.syncEventQueue)
      ..where((t) => t.id.equals(eventId));

    final row = await query.getSingleOrNull();
    return row != null ? _rowToEvent(row) : null;
  }

  @override
  Future<void> updateRetryCount(String eventId, int retryCount) async {
    await (_db.update(_db.syncEventQueue)
          ..where((t) => t.id.equals(eventId)))
        .write(SyncEventQueueCompanion(retryCount: Value(retryCount)));
  }

  @override
  Future<void> markFailed(String eventId, String error) async {
    await (_db.update(_db.syncEventQueue)
          ..where((t) => t.id.equals(eventId)))
        .write(SyncEventQueueCompanion(
          acknowledged: const Value(true),
          error: Value(error),
        ));
  }

  @override
  Future<void> delete(String eventId) async {
    await (_db.delete(_db.syncEventQueue)
          ..where((t) => t.id.equals(eventId)))
        .go();
  }

  @override
  Future<void> deleteAcknowledged({Duration? olderThan}) async {
    var query = _db.delete(_db.syncEventQueue)
      ..where((t) => t.acknowledged.equals(true));

    if (olderThan != null) {
      final cutoff =
          DateTime.now().subtract(olderThan).millisecondsSinceEpoch;
      query = query..where((t) => t.timestamp.isSmallerThanValue(cutoff));
    }

    await query.go();
  }

  @override
  Future<void> clear() async {
    await _db.delete(_db.syncEventQueue).go();
  }

  @override
  Future<int> countUnacknowledged() async {
    final count = _db.syncEventQueue.id.count();
    final query = _db.selectOnly(_db.syncEventQueue)
      ..addColumns([count])
      ..where(_db.syncEventQueue.acknowledged.equals(false));

    final result = await query.getSingle();
    return result.read(count) ?? 0;
  }

  @override
  Future<int> countByTable(String table) async {
    final count = _db.syncEventQueue.id.count();
    final query = _db.selectOnly(_db.syncEventQueue)
      ..addColumns([count])
      ..where(_db.syncEventQueue.tableName.equals(table))
      ..where(_db.syncEventQueue.acknowledged.equals(false));

    final result = await query.getSingle();
    return result.read(count) ?? 0;
  }

  @override
  Future<Map<String, int>> getStats() async {
    final totalCount = _db.syncEventQueue.id.count();
    final totalQuery = _db.selectOnly(_db.syncEventQueue)
      ..addColumns([totalCount]);
    final totalResult = await totalQuery.getSingle();
    final total = totalResult.read(totalCount) ?? 0;

    final pendingQuery = _db.selectOnly(_db.syncEventQueue)
      ..addColumns([totalCount])
      ..where(_db.syncEventQueue.acknowledged.equals(false));
    final pendingResult = await pendingQuery.getSingle();
    final pending = pendingResult.read(totalCount) ?? 0;

    final failedQuery = _db.selectOnly(_db.syncEventQueue)
      ..addColumns([totalCount])
      ..where(_db.syncEventQueue.error.isNotNull());
    final failedResult = await failedQuery.getSingle();
    final failed = failedResult.read(totalCount) ?? 0;

    return {
      'total': total,
      'pending': pending,
      'acknowledged': total - pending,
      'failed': failed,
    };
  }

  @override
  Future<void> dispose() async {}

  EnhancedSyncEvent _rowToEvent(SyncEventQueueData row) {
    return EnhancedSyncEvent(
      id: row.id,
      table: row.tableName,
      operation: SyncOperation.values.byName(row.operation),
      entityId: row.entityId,
      payload: row.payload != null
          ? jsonDecode(row.payload!) as Map<String, dynamic>
          : null,
      previousPayload: row.previousPayload != null
          ? jsonDecode(row.previousPayload!) as Map<String, dynamic>
          : null,
      priority: SyncPriority.values.byName(row.priority),
      timestamp: DateTime.fromMillisecondsSinceEpoch(row.timestamp),
      scheduledAt: row.scheduledAt != null
          ? DateTime.fromMillisecondsSinceEpoch(row.scheduledAt!)
          : null,
      retryCount: row.retryCount,
      maxRetries: row.maxRetries,
      correlationId: row.correlationId,
      causationId: row.causationId,
      metadata: row.metadata != null
          ? jsonDecode(row.metadata!) as Map<String, dynamic>
          : null,
      source: row.source,
      acknowledged: row.acknowledged,
    );
  }
}
