// ╔═══════════════════════════════════════════════════════════════════════════╗
// ║                     PROPOSED UNIFIED SYNC ARCHITECTURE                      ║
// ║                          Marina Hotel WIT App                               ║
// ╚═══════════════════════════════════════════════════════════════════════════╝

import 'dart:async';

// ════════════════════════════════════════════════════════════════════════════
// 1. ENHANCED SYNC EVENT - مصدر الحقيقة الواحد
// ════════════════════════════════════════════════════════════════════════════

enum SyncPriority { critical, high, normal, low }

enum SyncOperation { create, update, delete, restore }

class EnhancedSyncEvent {
  final String id;
  final String table;
  final SyncOperation operation;
  final String entityId;
  final Map<String, dynamic>? payload;
  final SyncPriority priority;
  final DateTime timestamp;
  final int retryCount;
  final String? correlationId;
  final Map<String, dynamic>? metadata;

  EnhancedSyncEvent({
    required this.id,
    required this.table,
    required this.operation,
    required this.entityId,
    this.payload,
    this.priority = SyncPriority.normal,
    DateTime? timestamp,
    this.retryCount = 0,
    this.correlationId,
    this.metadata,
  }) : timestamp = timestamp ?? DateTime.now();

  EnhancedSyncEvent copyWithRetry() {
    return EnhancedSyncEvent(
      id: id,
      table: table,
      operation: operation,
      entityId: entityId,
      payload: payload,
      priority: priority,
      timestamp: timestamp,
      retryCount: retryCount + 1,
      correlationId: correlationId,
      metadata: metadata,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'table': table,
        'operation': operation.name,
        'entityId': entityId,
        'payload': payload,
        'priority': priority.name,
        'timestamp': timestamp.toIso8601String(),
        'retryCount': retryCount,
        'correlationId': correlationId,
        'metadata': metadata,
      };

  factory EnhancedSyncEvent.fromJson(Map<String, dynamic> json) {
    return EnhancedSyncEvent(
      id: json['id'] as String,
      table: json['table'] as String,
      operation: SyncOperation.values.byName(json['operation'] as String),
      entityId: json['entityId'] as String,
      payload: json['payload'] as Map<String, dynamic>?,
      priority: SyncPriority.values.byName(json['priority'] as String),
      timestamp: DateTime.parse(json['timestamp'] as String),
      retryCount: json['retryCount'] as int? ?? 0,
      correlationId: json['correlationId'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// 2. ENHANCED EVENT BUS - مع Persistence و Acknowledgment
// ════════════════════════════════════════════════════════════════════════════

abstract class EventPersistence {
  Future<void> persist(EnhancedSyncEvent event);
  Future<void> acknowledge(String eventId);
  Future<List<EnhancedSyncEvent>> getUnacknowledged();
  Future<void> clear();
}

class EnhancedEventBus {
  final EventPersistence _persistence;
  final _controller = StreamController<EnhancedSyncEvent>.broadcast();
  final _acknowledgments = <String, Completer<void>>{};

  EnhancedEventBus(this._persistence);

  Stream<EnhancedSyncEvent> get stream => _controller.stream;

  Stream<EnhancedSyncEvent> where({
    String? table,
    SyncPriority? minPriority,
    SyncOperation? operation,
  }) {
    return stream.where((event) {
      if (table != null && event.table != table) return false;
      if (operation != null && event.operation != operation) return false;
      if (minPriority != null && event.priority.index > minPriority.index) {
        return false;
      }
      return true;
    });
  }

  Future<void> publish(EnhancedSyncEvent event) async {
    await _persistence.persist(event);
    if (!_controller.isClosed) {
      _controller.add(event);
    }
  }

  Future<void> acknowledge(String eventId) async {
    await _persistence.acknowledge(eventId);
    _acknowledgments[eventId]?.complete();
    _acknowledgments.remove(eventId);
  }

  Future<void> replayUnacknowledged() async {
    final events = await _persistence.getUnacknowledged();
    for (final event in events) {
      if (!_controller.isClosed) {
        _controller.add(event);
      }
    }
  }

  Future<void> dispose() async {
    await _controller.close();
    for (final completer in _acknowledgments.values) {
      completer.completeError('EventBus disposed');
    }
    _acknowledgments.clear();
  }
}

// ════════════════════════════════════════════════════════════════════════════
// 3. SYNC TARGET ADAPTER INTERFACE - واجهة موحدة للأهداف
// ════════════════════════════════════════════════════════════════════════════

enum SyncTargetType { appwrite, googleDrive, localJson }

abstract class SyncTargetResult {
  bool get success;
  String? get error;
  int get affectedCount;
}

class SyncPushResult implements SyncTargetResult {
  @override
  final bool success;
  @override
  final String? error;
  @override
  final int affectedCount;
  final List<String> syncedIds;
  final List<String> failedIds;

  SyncPushResult({
    required this.success,
    this.error,
    this.affectedCount = 0,
    this.syncedIds = const [],
    this.failedIds = const [],
  });
}

class SyncPullResult implements SyncTargetResult {
  @override
  final bool success;
  @override
  final String? error;
  @override
  final int affectedCount;
  final int created;
  final int updated;
  final int deleted;
  final List<ConflictInfo> conflicts;

  SyncPullResult({
    required this.success,
    this.error,
    this.affectedCount = 0,
    this.created = 0,
    this.updated = 0,
    this.deleted = 0,
    this.conflicts = const [],
  });
}

class ConflictInfo {
  final String entityId;
  final String table;
  final Map<String, dynamic> localData;
  final Map<String, dynamic> remoteData;
  final DateTime localTimestamp;
  final DateTime remoteTimestamp;

  ConflictInfo({
    required this.entityId,
    required this.table,
    required this.localData,
    required this.remoteData,
    required this.localTimestamp,
    required this.remoteTimestamp,
  });
}

abstract class SyncTargetAdapter {
  SyncTargetType get type;
  String get name;
  bool get isAvailable;
  bool get isEnabled;

  Future<void> initialize();
  Future<bool> checkConnection();

  Future<SyncPushResult> push(List<EnhancedSyncEvent> events);
  Future<SyncPullResult> pull({DateTime? since, List<String>? tables});

  Future<void> dispose();
}

// ════════════════════════════════════════════════════════════════════════════
// 4. SYNC ROUTER - محرك القرارات المركزي
// ════════════════════════════════════════════════════════════════════════════

enum RoutingStrategy { all, primaryFirst, roundRobin, priority }

class SyncRouterConfig {
  final RoutingStrategy strategy;
  final Duration debounceWindow;
  final int maxBatchSize;
  final int maxRetries;
  final bool enableParallel;

  const SyncRouterConfig({
    this.strategy = RoutingStrategy.all,
    this.debounceWindow = const Duration(seconds: 2),
    this.maxBatchSize = 50,
    this.maxRetries = 3,
    this.enableParallel = true,
  });
}

class EnhancedSyncRouter {
  final EnhancedEventBus _eventBus;
  final Map<SyncTargetType, SyncTargetAdapter> _adapters = {};
  final SyncRouterConfig _config;

  StreamSubscription<EnhancedSyncEvent>? _subscription;
  final _pendingEvents = <EnhancedSyncEvent>[];
  Timer? _debounceTimer;
  bool _processing = false;

  EnhancedSyncRouter({
    required EnhancedEventBus eventBus,
    SyncRouterConfig config = const SyncRouterConfig(),
  })  : _eventBus = eventBus,
        _config = config;

  void registerAdapter(SyncTargetAdapter adapter) {
    _adapters[adapter.type] = adapter;
  }

  void unregisterAdapter(SyncTargetType type) {
    _adapters.remove(type);
  }

  List<SyncTargetAdapter> get enabledAdapters =>
      _adapters.values.where((a) => a.isEnabled && a.isAvailable).toList();

  void start() {
    _subscription = _eventBus.stream.listen(_handleEvent);
  }

  void _handleEvent(EnhancedSyncEvent event) {
    _pendingEvents.add(event);

    if (event.priority == SyncPriority.critical) {
      _flush();
      return;
    }

    _debounceTimer?.cancel();
    _debounceTimer = Timer(_config.debounceWindow, _flush);

    if (_pendingEvents.length >= _config.maxBatchSize) {
      _flush();
    }
  }

  Future<void> _flush() async {
    if (_processing || _pendingEvents.isEmpty) return;

    _processing = true;
    _debounceTimer?.cancel();

    final batch = List<EnhancedSyncEvent>.from(_pendingEvents);
    _pendingEvents.clear();

    batch.sort((a, b) => a.priority.index.compareTo(b.priority.index));

    final adapters = enabledAdapters;
    if (adapters.isEmpty) {
      _processing = false;
      return;
    }

    try {
      switch (_config.strategy) {
        case RoutingStrategy.all:
          await _routeToAll(batch, adapters);
          break;
        case RoutingStrategy.primaryFirst:
          await _routePrimaryFirst(batch, adapters);
          break;
        case RoutingStrategy.roundRobin:
          await _routeRoundRobin(batch, adapters);
          break;
        case RoutingStrategy.priority:
          await _routeByPriority(batch, adapters);
          break;
      }

      for (final event in batch) {
        await _eventBus.acknowledge(event.id);
      }
    } finally {
      _processing = false;
    }
  }

  Future<void> _routeToAll(
    List<EnhancedSyncEvent> events,
    List<SyncTargetAdapter> adapters,
  ) async {
    if (_config.enableParallel) {
      await Future.wait(
        adapters.map((adapter) => _pushWithRetry(adapter, events)),
      );
    } else {
      for (final adapter in adapters) {
        await _pushWithRetry(adapter, events);
      }
    }
  }

  Future<void> _routePrimaryFirst(
    List<EnhancedSyncEvent> events,
    List<SyncTargetAdapter> adapters,
  ) async {
    final primary = adapters.firstWhere(
      (a) => a.type == SyncTargetType.appwrite,
      orElse: () => adapters.first,
    );

    final result = await _pushWithRetry(primary, events);
    if (result.success) {
      final others = adapters.where((a) => a != primary);
      await Future.wait(others.map((a) => _pushWithRetry(a, events)));
    }
  }

  Future<void> _routeRoundRobin(
    List<EnhancedSyncEvent> events,
    List<SyncTargetAdapter> adapters,
  ) async {
    var index = 0;
    for (final event in events) {
      final adapter = adapters[index % adapters.length];
      await _pushWithRetry(adapter, [event]);
      index++;
    }
  }

  Future<void> _routeByPriority(
    List<EnhancedSyncEvent> events,
    List<SyncTargetAdapter> adapters,
  ) async {
    final criticalEvents =
        events.where((e) => e.priority == SyncPriority.critical).toList();
    final normalEvents =
        events.where((e) => e.priority != SyncPriority.critical).toList();

    if (criticalEvents.isNotEmpty) {
      await _routeToAll(criticalEvents, adapters);
    }

    if (normalEvents.isNotEmpty) {
      final primary = adapters.first;
      await _pushWithRetry(primary, normalEvents);
    }
  }

  Future<SyncPushResult> _pushWithRetry(
    SyncTargetAdapter adapter,
    List<EnhancedSyncEvent> events,
  ) async {
    var attempts = 0;
    SyncPushResult? lastResult;

    while (attempts < _config.maxRetries) {
      try {
        lastResult = await adapter.push(events);
        if (lastResult.success) return lastResult;
      } catch (e) {
        lastResult = SyncPushResult(success: false, error: e.toString());
      }
      attempts++;
      if (attempts < _config.maxRetries) {
        await Future.delayed(Duration(seconds: attempts * 2));
      }
    }

    return lastResult ?? SyncPushResult(success: false, error: 'Max retries');
  }

  Future<void> syncNow({bool push = true, bool pull = true}) async {
    if (push && _pendingEvents.isNotEmpty) {
      await _flush();
    }

    if (pull) {
      for (final adapter in enabledAdapters) {
        await adapter.pull();
      }
    }
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _debounceTimer?.cancel();
    for (final adapter in _adapters.values) {
      await adapter.dispose();
    }
    _adapters.clear();
  }
}

// ════════════════════════════════════════════════════════════════════════════
// 5. CONCRETE ADAPTERS - التنفيذ المحدد لكل هدف
// ════════════════════════════════════════════════════════════════════════════

// مثال: Appwrite Adapter
// class AppwriteTargetAdapter implements SyncTargetAdapter {
//   final AppwriteService _service;
//   final AppDatabase _database;
//
//   @override
//   SyncTargetType get type => SyncTargetType.appwrite;
//
//   @override
//   Future<SyncPushResult> push(List<EnhancedSyncEvent> events) async {
//     // تحويل Events إلى Appwrite documents
//     // استخدام delta sync
//     // إرجاع النتيجة
//   }
// }

// مثال: Google Drive Adapter
// class GoogleDriveTargetAdapter implements SyncTargetAdapter {
//   final GoogleDriveBackupService _backupService;
//
//   @override
//   SyncTargetType get type => SyncTargetType.googleDrive;
//
//   @override
//   Future<SyncPushResult> push(List<EnhancedSyncEvent> events) async {
//     // تجميع Events في snapshot
//     // رفع الملف إلى Drive
//   }
// }

// مثال: Local JSON Adapter
// class LocalJsonTargetAdapter implements SyncTargetAdapter {
//   @override
//   SyncTargetType get type => SyncTargetType.localJson;
//
//   @override
//   Future<SyncPushResult> push(List<EnhancedSyncEvent> events) async {
//     // كتابة backup.json محلياً
//   }
// }

// ════════════════════════════════════════════════════════════════════════════
// 6. RIVERPOD PROVIDERS - بديل Singletons
// ════════════════════════════════════════════════════════════════════════════

// final eventPersistenceProvider = Provider<EventPersistence>((ref) {
//   final db = ref.watch(databaseProvider);
//   return SqliteEventPersistence(db);
// });

// final eventBusProvider = Provider<EnhancedEventBus>((ref) {
//   final persistence = ref.watch(eventPersistenceProvider);
//   return EnhancedEventBus(persistence);
// });

// final syncRouterProvider = Provider<EnhancedSyncRouter>((ref) {
//   final eventBus = ref.watch(eventBusProvider);
//   final router = EnhancedSyncRouter(eventBus: eventBus);
//
//   // تسجيل Adapters المتاحة
//   final appwrite = ref.watch(appwriteAdapterProvider);
//   final drive = ref.watch(driveAdapterProvider);
//   final local = ref.watch(localJsonAdapterProvider);
//
//   if (appwrite != null) router.registerAdapter(appwrite);
//   if (drive != null) router.registerAdapter(drive);
//   if (local != null) router.registerAdapter(local);
//
//   router.start();
//   ref.onDispose(() => router.dispose());
//
//   return router;
// });

// ════════════════════════════════════════════════════════════════════════════
// 7. DATABASE HOOKS - ربط SQLite بـ Event Bus
// ════════════════════════════════════════════════════════════════════════════

// extension DatabaseSyncHooks on AppDatabase {
//   void setupSyncHooks(EnhancedEventBus eventBus) {
//     // مراقبة التغييرات في الجداول
//     bookings.watchAll().listen((rows) {
//       // نشر event لكل تغيير
//     });
//   }
// }
