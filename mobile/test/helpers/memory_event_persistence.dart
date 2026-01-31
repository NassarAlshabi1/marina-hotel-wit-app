import 'package:marina_hotel_mobile/services/sync_core/events/sync_event.dart';
import 'package:marina_hotel_mobile/services/sync_core/persistence/event_persistence.dart';

class MemoryEventPersistence implements EventPersistence {
  final Map<String, EnhancedSyncEvent> _events = {};
  final List<String> _order = [];
  final Set<String> _failed = {};

  List<EnhancedSyncEvent> get events =>
      _order.map((id) => _events[id]!).toList();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> persist(EnhancedSyncEvent event) async {
    if (!_events.containsKey(event.id)) {
      _order.add(event.id);
    }
    _events[event.id] = event;
  }

  @override
  Future<void> persistBatch(List<EnhancedSyncEvent> events) async {
    for (final event in events) {
      await persist(event);
    }
  }

  @override
  Future<void> acknowledge(String eventId) async {
    final event = _events[eventId];
    if (event == null) return;
    _events[eventId] = event.withAcknowledged();
  }

  @override
  Future<void> acknowledgeBatch(List<String> eventIds) async {
    for (final id in eventIds) {
      await acknowledge(id);
    }
  }

  @override
  Future<List<EnhancedSyncEvent>> getUnacknowledged({
    int? limit,
    SyncPriority? minPriority,
    String? table,
  }) async {
    var list = events.where((e) => !e.acknowledged).toList();
    if (table != null) {
      list = list.where((e) => e.table == table).toList();
    }
    if (minPriority != null) {
      list = list.where((e) => e.priority <= minPriority).toList();
    }
    if (limit != null && list.length > limit) {
      list = list.sublist(0, limit);
    }
    return list;
  }

  @override
  Future<List<EnhancedSyncEvent>> getPending({
    int? limit,
    Duration? olderThan,
  }) async {
    var list = events.where((e) => !e.acknowledged).toList();
    if (olderThan != null) {
      final cutoff = DateTime.now().subtract(olderThan);
      list = list.where((e) => e.timestamp.isBefore(cutoff)).toList();
    }
    if (limit != null && list.length > limit) {
      list = list.sublist(0, limit);
    }
    return list;
  }

  @override
  Future<List<EnhancedSyncEvent>> getByCorrelationId(
    String correlationId,
  ) async {
    return events.where((e) => e.correlationId == correlationId).toList();
  }

  @override
  Future<EnhancedSyncEvent?> getById(String eventId) async {
    return _events[eventId];
  }

  @override
  Future<void> updateRetryCount(String eventId, int retryCount) async {
    final event = _events[eventId];
    if (event == null) return;
    _events[eventId] = event.copyWith(retryCount: retryCount);
  }

  @override
  Future<void> markFailed(String eventId, String error) async {
    _failed.add(eventId);
    await acknowledge(eventId);
  }

  @override
  Future<void> delete(String eventId) async {
    _events.remove(eventId);
    _order.remove(eventId);
    _failed.remove(eventId);
  }

  @override
  Future<void> deleteAcknowledged({Duration? olderThan}) async {
    final ids = <String>[];
    for (final event in events) {
      if (!event.acknowledged) continue;
      if (olderThan != null) {
        final cutoff = DateTime.now().subtract(olderThan);
        if (!event.timestamp.isBefore(cutoff)) continue;
      }
      ids.add(event.id);
    }
    for (final id in ids) {
      await delete(id);
    }
  }

  @override
  Future<void> clear() async {
    _events.clear();
    _order.clear();
    _failed.clear();
  }

  @override
  Future<int> countUnacknowledged() async {
    return events.where((e) => !e.acknowledged).length;
  }

  @override
  Future<int> countByTable(String table) async {
    return events
        .where((e) => !e.acknowledged && e.table == table)
        .length;
  }

  @override
  Future<Map<String, int>> getStats() async {
    final total = events.length;
    final pending = events.where((e) => !e.acknowledged).length;
    final failed = _failed.length;
    return {
      'total': total,
      'pending': pending,
      'acknowledged': total - pending,
      'failed': failed,
    };
  }

  @override
  Future<void> dispose() async {}
}
