import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import '../../local_db.dart';
import '../events/sync_event.dart';
import 'event_persistence.dart';

class SqliteEventPersistence implements EventPersistence {
  static const _table = 'sync_event_queue';

  final AppDatabase _db;

  SqliteEventPersistence(this._db);

  @override
  Future<void> initialize() async {}

  @override
  Future<void> persist(EnhancedSyncEvent event) async {
    await _db.customInsert(
      'INSERT OR REPLACE INTO $_table '
      '(id, table_name, operation, entity_id, payload, previous_payload, priority, timestamp, scheduled_at, '
      'retry_count, max_retries, correlation_id, causation_id, metadata, source, acknowledged, error, created_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      variables: _eventVariables(event),
    );
  }

  @override
  Future<void> persistBatch(List<EnhancedSyncEvent> events) async {
    if (events.isEmpty) return;

    await _db.transaction(() async {
      for (final event in events) {
        await _db.customInsert(
          'INSERT OR REPLACE INTO $_table '
          '(id, table_name, operation, entity_id, payload, previous_payload, priority, timestamp, scheduled_at, '
          'retry_count, max_retries, correlation_id, causation_id, metadata, source, acknowledged, error, created_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          variables: _eventVariables(event),
        );
      }
    });
  }

  @override
  Future<void> acknowledge(String eventId) async {
    await _db.customUpdate(
      'UPDATE $_table SET acknowledged = 1 WHERE id = ?',
      variables: [Variable(eventId)],
    );
  }

  @override
  Future<void> acknowledgeBatch(List<String> eventIds) async {
    if (eventIds.isEmpty) return;
    final placeholders = List.filled(eventIds.length, '?').join(',');
    await _db.customUpdate(
      'UPDATE $_table SET acknowledged = 1 WHERE id IN ($placeholders)',
      variables: eventIds.map((id) => Variable(id)).toList(),
    );
  }

  @override
  Future<List<EnhancedSyncEvent>> getUnacknowledged({
    int? limit,
    SyncPriority? minPriority,
    String? table,
  }) async {
    final buffer = StringBuffer('SELECT * FROM $_table WHERE acknowledged = 0');
    final variables = <Variable>[];

    if (table != null) {
      buffer.write(' AND table_name = ?');
      variables.add(Variable(table));
    }

    buffer.write(' ORDER BY priority ASC, timestamp ASC');

    if (limit != null) {
      buffer.write(' LIMIT $limit');
    }

    final rows =
        await _db.customSelect(buffer.toString(), variables: variables).get();

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
    final buffer = StringBuffer('SELECT * FROM $_table WHERE acknowledged = 0');
    final variables = <Variable>[];

    if (olderThan != null) {
      final cutoff = DateTime.now().subtract(olderThan).millisecondsSinceEpoch;
      buffer.write(' AND timestamp < ?');
      variables.add(Variable(cutoff));
    }

    buffer.write(' ORDER BY timestamp ASC');

    if (limit != null) {
      buffer.write(' LIMIT $limit');
    }

    final rows =
        await _db.customSelect(buffer.toString(), variables: variables).get();

    return rows.map(_rowToEvent).toList();
  }

  @override
  Future<List<EnhancedSyncEvent>> getByCorrelationId(
    String correlationId,
  ) async {
    final rows = await _db.customSelect(
      'SELECT * FROM $_table WHERE correlation_id = ? ORDER BY timestamp ASC',
      variables: [Variable(correlationId)],
    ).get();

    return rows.map(_rowToEvent).toList();
  }

  @override
  Future<EnhancedSyncEvent?> getById(String eventId) async {
    final row = await _db.customSelect(
      'SELECT * FROM $_table WHERE id = ? LIMIT 1',
      variables: [Variable(eventId)],
    ).getSingleOrNull();

    return row != null ? _rowToEvent(row) : null;
  }

  @override
  Future<void> updateRetryCount(String eventId, int retryCount) async {
    await _db.customUpdate(
      'UPDATE $_table SET retry_count = ? WHERE id = ?',
      variables: [Variable(retryCount), Variable(eventId)],
    );
  }

  @override
  Future<void> markFailed(String eventId, String error) async {
    await _db.customUpdate(
      'UPDATE $_table SET acknowledged = 1, error = ? WHERE id = ?',
      variables: [Variable(error), Variable(eventId)],
    );
  }

  @override
  Future<void> delete(String eventId) async {
    await _db.customUpdate(
      'DELETE FROM $_table WHERE id = ?',
      variables: [Variable(eventId)],
    );
  }

  @override
  Future<void> deleteAcknowledged({Duration? olderThan}) async {
    final buffer = StringBuffer('DELETE FROM $_table WHERE acknowledged = 1');
    final variables = <Variable>[];

    if (olderThan != null) {
      final cutoff = DateTime.now().subtract(olderThan).millisecondsSinceEpoch;
      buffer.write(' AND timestamp < ?');
      variables.add(Variable(cutoff));
    }

    await _db.customUpdate(buffer.toString(), variables: variables);
  }

  @override
  Future<void> clear() async {
    await _db.customUpdate('DELETE FROM $_table');
  }

  @override
  Future<int> countUnacknowledged() async {
    final row = await _db
        .customSelect(
          'SELECT COUNT(*) AS count FROM $_table WHERE acknowledged = 0',
        )
        .getSingle();
    return row.read<int>('count');
  }

  @override
  Future<int> countByTable(String table) async {
    final row = await _db.customSelect(
      'SELECT COUNT(*) AS count FROM $_table WHERE table_name = ? AND acknowledged = 0',
      variables: [Variable(table)],
    ).getSingle();
    return row.read<int>('count');
  }

  @override
  Future<Map<String, int>> getStats() async {
    final totalRow = await _db
        .customSelect('SELECT COUNT(*) AS count FROM $_table')
        .getSingle();
    final total = totalRow.read<int>('count');

    final pendingRow = await _db
        .customSelect(
          'SELECT COUNT(*) AS count FROM $_table WHERE acknowledged = 0',
        )
        .getSingle();
    final pending = pendingRow.read<int>('count');

    final failedRow = await _db
        .customSelect(
          'SELECT COUNT(*) AS count FROM $_table WHERE error IS NOT NULL',
        )
        .getSingle();
    final failed = failedRow.read<int>('count');

    return {
      'total': total,
      'pending': pending,
      'acknowledged': total - pending,
      'failed': failed,
    };
  }

  @override
  Future<void> dispose() async {}

  List<Variable> _eventVariables(EnhancedSyncEvent event) {
    return [
      Variable(event.id),
      Variable(event.table),
      Variable(event.operation.name),
      Variable(event.entityId),
      Variable(event.payload != null ? jsonEncode(event.payload) : null),
      Variable(
        event.previousPayload != null
            ? jsonEncode(event.previousPayload)
            : null,
      ),
      Variable(event.priority.name),
      Variable(event.timestamp.millisecondsSinceEpoch),
      Variable(event.scheduledAt?.millisecondsSinceEpoch),
      Variable(event.retryCount),
      Variable(event.maxRetries),
      Variable(event.correlationId),
      Variable(event.causationId),
      Variable(event.metadata != null ? jsonEncode(event.metadata) : null),
      Variable(event.source),
      Variable(event.acknowledged ? 1 : 0),
      const Variable(null),
      Variable(DateTime.now().millisecondsSinceEpoch),
    ];
  }

  EnhancedSyncEvent _rowToEvent(QueryRow row) {
    final payload = row.read<String?>('payload');
    final previousPayload = row.read<String?>('previous_payload');
    final metadata = row.read<String?>('metadata');
    final acknowledged = row.read<int>('acknowledged') == 1;

    return EnhancedSyncEvent(
      id: row.read<String>('id'),
      table: row.read<String>('table_name'),
      operation: SyncOperation.values.byName(row.read<String>('operation')),
      entityId: row.read<String>('entity_id'),
      payload:
          payload != null ? jsonDecode(payload) as Map<String, dynamic> : null,
      previousPayload: previousPayload != null
          ? jsonDecode(previousPayload) as Map<String, dynamic>
          : null,
      priority: SyncPriority.values.byName(row.read<String>('priority')),
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        row.read<int>('timestamp'),
      ),
      scheduledAt: row.read<int?>('scheduled_at') != null
          ? DateTime.fromMillisecondsSinceEpoch(row.read<int?>('scheduled_at')!)
          : null,
      retryCount: row.read<int>('retry_count'),
      maxRetries: row.read<int>('max_retries'),
      correlationId: row.read<String?>('correlation_id'),
      causationId: row.read<String?>('causation_id'),
      metadata: metadata != null
          ? jsonDecode(metadata) as Map<String, dynamic>
          : null,
      source: row.read<String>('source'),
      acknowledged: acknowledged,
    );
  }
}
