import '../events/sync_event.dart';

abstract class EventPersistence {
  Future<void> initialize();

  Future<void> persist(EnhancedSyncEvent event);

  Future<void> persistBatch(List<EnhancedSyncEvent> events);

  Future<void> acknowledge(String eventId);

  Future<void> acknowledgeBatch(List<String> eventIds);

  Future<List<EnhancedSyncEvent>> getUnacknowledged({
    int? limit,
    SyncPriority? minPriority,
    String? table,
  });

  Future<List<EnhancedSyncEvent>> getPending({int? limit, Duration? olderThan});

  Future<List<EnhancedSyncEvent>> getByCorrelationId(String correlationId);

  Future<EnhancedSyncEvent?> getById(String eventId);

  Future<void> updateRetryCount(String eventId, int retryCount);

  Future<void> markFailed(String eventId, String error);

  Future<void> delete(String eventId);

  Future<void> deleteAcknowledged({Duration? olderThan});

  Future<void> clear();

  Future<int> countUnacknowledged();

  Future<int> countByTable(String table);

  Future<Map<String, int>> getStats();

  Future<void> dispose();
}

class EventPersistenceStats {
  final int total;
  final int pending;
  final int acknowledged;
  final int failed;
  final Map<String, int> byTable;
  final Map<SyncPriority, int> byPriority;

  const EventPersistenceStats({
    required this.total,
    required this.pending,
    required this.acknowledged,
    required this.failed,
    required this.byTable,
    required this.byPriority,
  });
}
