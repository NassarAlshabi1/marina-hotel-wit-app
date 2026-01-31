import 'dart:async';

import 'package:flutter/foundation.dart';

import 'events/sync_event.dart';
import 'persistence/event_persistence.dart';

typedef EventFilter = bool Function(EnhancedSyncEvent event);
typedef EventHandler = Future<void> Function(EnhancedSyncEvent event);

class EnhancedEventBus {
  final EventPersistence _persistence;
  final _controller = StreamController<EnhancedSyncEvent>.broadcast();
  final _acknowledgments = <String, Completer<void>>{};
  final _handlers = <String, List<EventHandler>>{};
  bool _initialized = false;
  bool _disposed = false;

  EnhancedEventBus(this._persistence);

  Stream<EnhancedSyncEvent> get stream => _controller.stream;
  bool get isInitialized => _initialized;
  bool get isDisposed => _disposed;

  Future<void> initialize() async {
    if (_initialized) return;
    await _persistence.initialize();
    _initialized = true;
  }

  Stream<EnhancedSyncEvent> where({
    String? table,
    SyncPriority? minPriority,
    SyncOperation? operation,
    EventFilter? filter,
  }) {
    return stream.where((event) {
      if (table != null && event.table != table) return false;
      if (operation != null && event.operation != operation) return false;
      if (minPriority != null && event.priority > minPriority) return false;
      if (filter != null && !filter(event)) return false;
      return true;
    });
  }

  Stream<EnhancedSyncEvent> forTable(String table) => where(table: table);

  Stream<EnhancedSyncEvent> forTables(List<String> tables) {
    return stream.where((event) => tables.contains(event.table));
  }

  Stream<EnhancedSyncEvent> criticalOnly() =>
      where(minPriority: SyncPriority.critical);

  Stream<EnhancedSyncEvent> highPriorityAndAbove() =>
      where(minPriority: SyncPriority.high);

  void registerHandler(String handlerId, EventHandler handler) {
    _handlers.putIfAbsent(handlerId, () => []).add(handler);
  }

  void unregisterHandler(String handlerId) {
    _handlers.remove(handlerId);
  }

  Future<void> publish(EnhancedSyncEvent event) async {
    if (_disposed) {
      debugPrint('EventBus: Cannot publish to disposed bus');
      return;
    }

    await _persistence.persist(event);

    if (!_controller.isClosed) {
      _controller.add(event);
    }

    await _invokeHandlers(event);
  }

  Future<void> publishBatch(List<EnhancedSyncEvent> events) async {
    if (_disposed || events.isEmpty) return;

    await _persistence.persistBatch(events);

    for (final event in events) {
      if (!_controller.isClosed) {
        _controller.add(event);
      }
    }

    for (final event in events) {
      await _invokeHandlers(event);
    }
  }

  Future<void> publishCreate({
    required String table,
    required String entityId,
    required Map<String, dynamic> payload,
    SyncPriority priority = SyncPriority.normal,
    String? correlationId,
    Map<String, dynamic>? metadata,
  }) async {
    await publish(
      EnhancedSyncEvent.create(
        table: table,
        entityId: entityId,
        payload: payload,
        priority: priority,
        correlationId: correlationId,
        metadata: metadata,
      ),
    );
  }

  Future<void> publishUpdate({
    required String table,
    required String entityId,
    required Map<String, dynamic> payload,
    Map<String, dynamic>? previousPayload,
    SyncPriority priority = SyncPriority.normal,
    String? correlationId,
    Map<String, dynamic>? metadata,
  }) async {
    await publish(
      EnhancedSyncEvent.update(
        table: table,
        entityId: entityId,
        payload: payload,
        previousPayload: previousPayload,
        priority: priority,
        correlationId: correlationId,
        metadata: metadata,
      ),
    );
  }

  Future<void> publishDelete({
    required String table,
    required String entityId,
    Map<String, dynamic>? previousPayload,
    SyncPriority priority = SyncPriority.normal,
    String? correlationId,
    Map<String, dynamic>? metadata,
  }) async {
    await publish(
      EnhancedSyncEvent.delete(
        table: table,
        entityId: entityId,
        previousPayload: previousPayload,
        priority: priority,
        correlationId: correlationId,
        metadata: metadata,
      ),
    );
  }

  Future<void> acknowledge(String eventId) async {
    await _persistence.acknowledge(eventId);
    _acknowledgments[eventId]?.complete();
    _acknowledgments.remove(eventId);
  }

  Future<void> acknowledgeBatch(List<String> eventIds) async {
    await _persistence.acknowledgeBatch(eventIds);
    for (final id in eventIds) {
      _acknowledgments[id]?.complete();
      _acknowledgments.remove(id);
    }
  }

  Future<void> waitForAcknowledgment(
    String eventId, {
    Duration? timeout,
  }) async {
    final completer = Completer<void>();
    _acknowledgments[eventId] = completer;

    if (timeout != null) {
      return completer.future.timeout(
        timeout,
        onTimeout: () {
          _acknowledgments.remove(eventId);
          throw TimeoutException('Event acknowledgment timeout', timeout);
        },
      );
    }

    return completer.future;
  }

  Future<void> replayUnacknowledged({int? limit}) async {
    final events = await _persistence.getUnacknowledged(limit: limit);
    for (final event in events) {
      if (!_controller.isClosed) {
        _controller.add(event);
      }
      await _invokeHandlers(event);
    }
    debugPrint('EventBus: Replayed ${events.length} unacknowledged events');
  }

  Future<void> retryFailed({int? limit}) async {
    final events = await _persistence.getPending(
      limit: limit,
      olderThan: const Duration(minutes: 5),
    );

    for (final event in events) {
      if (event.canRetry) {
        final retryEvent = event.withRetry();
        await _persistence.updateRetryCount(event.id, retryEvent.retryCount);

        if (!_controller.isClosed) {
          _controller.add(retryEvent);
        }
        await _invokeHandlers(retryEvent);
      } else {
        await _persistence.markFailed(
          event.id,
          'Max retries exceeded (${event.maxRetries})',
        );
      }
    }
  }

  Future<int> pendingCount() => _persistence.countUnacknowledged();

  Future<int> pendingCountForTable(String table) =>
      _persistence.countByTable(table);

  Future<Map<String, int>> getStats() => _persistence.getStats();

  Future<void> cleanup({Duration olderThan = const Duration(days: 7)}) async {
    await _persistence.deleteAcknowledged(olderThan: olderThan);
  }

  Future<void> clear() async {
    await _persistence.clear();
    _acknowledgments.clear();
  }

  Future<void> _invokeHandlers(EnhancedSyncEvent event) async {
    for (final handlers in _handlers.values) {
      for (final handler in handlers) {
        try {
          await handler(event);
        } catch (e) {
          debugPrint('EventBus: Handler error: $e');
        }
      }
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    await _controller.close();
    await _persistence.dispose();

    for (final completer in _acknowledgments.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('EventBus disposed'));
      }
    }
    _acknowledgments.clear();
    _handlers.clear();
  }
}

class ScopedEventBus {
  final EnhancedEventBus _parent;
  final String _scope;
  final List<StreamSubscription> _subscriptions = [];

  ScopedEventBus(this._parent, this._scope);

  Stream<EnhancedSyncEvent> get stream => _parent.forTable(_scope);

  Future<void> publish(EnhancedSyncEvent event) async {
    assert(event.table == _scope, 'Event table must match scope');
    await _parent.publish(event);
  }

  StreamSubscription<EnhancedSyncEvent> listen(
    void Function(EnhancedSyncEvent) onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final sub = stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
    _subscriptions.add(sub);
    return sub;
  }

  Future<void> dispose() async {
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
  }
}
