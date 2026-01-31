import 'package:uuid/uuid.dart';

enum SyncPriority {
  critical(0),
  high(1),
  normal(2),
  low(3);

  const SyncPriority(this.value);
  final int value;

  bool operator >(SyncPriority other) => value > other.value;
  bool operator <(SyncPriority other) => value < other.value;
  bool operator >=(SyncPriority other) => value >= other.value;
  bool operator <=(SyncPriority other) => value <= other.value;
}

enum SyncOperation {
  create,
  update,
  delete,
  restore,
  batchCreate,
  batchUpdate,
  batchDelete,
}

class EnhancedSyncEvent {
  final String id;
  final String table;
  final SyncOperation operation;
  final String entityId;
  final Map<String, dynamic>? payload;
  final Map<String, dynamic>? previousPayload;
  final SyncPriority priority;
  final DateTime timestamp;
  final DateTime? scheduledAt;
  final int retryCount;
  final int maxRetries;
  final String? correlationId;
  final String? causationId;
  final Map<String, dynamic>? metadata;
  final String source;
  final bool acknowledged;

  static const _uuid = Uuid();

  EnhancedSyncEvent({
    String? id,
    required this.table,
    required this.operation,
    required this.entityId,
    this.payload,
    this.previousPayload,
    this.priority = SyncPriority.normal,
    DateTime? timestamp,
    this.scheduledAt,
    this.retryCount = 0,
    this.maxRetries = 3,
    this.correlationId,
    this.causationId,
    this.metadata,
    this.source = 'local',
    this.acknowledged = false,
  })  : id = id ?? _uuid.v4(),
        timestamp = timestamp ?? DateTime.now();

  EnhancedSyncEvent copyWith({
    String? id,
    String? table,
    SyncOperation? operation,
    String? entityId,
    Map<String, dynamic>? payload,
    Map<String, dynamic>? previousPayload,
    SyncPriority? priority,
    DateTime? timestamp,
    DateTime? scheduledAt,
    int? retryCount,
    int? maxRetries,
    String? correlationId,
    String? causationId,
    Map<String, dynamic>? metadata,
    String? source,
    bool? acknowledged,
  }) {
    return EnhancedSyncEvent(
      id: id ?? this.id,
      table: table ?? this.table,
      operation: operation ?? this.operation,
      entityId: entityId ?? this.entityId,
      payload: payload ?? this.payload,
      previousPayload: previousPayload ?? this.previousPayload,
      priority: priority ?? this.priority,
      timestamp: timestamp ?? this.timestamp,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      retryCount: retryCount ?? this.retryCount,
      maxRetries: maxRetries ?? this.maxRetries,
      correlationId: correlationId ?? this.correlationId,
      causationId: causationId ?? this.causationId,
      metadata: metadata ?? this.metadata,
      source: source ?? this.source,
      acknowledged: acknowledged ?? this.acknowledged,
    );
  }

  EnhancedSyncEvent withRetry() {
    return copyWith(retryCount: retryCount + 1);
  }

  EnhancedSyncEvent withAcknowledged() {
    return copyWith(acknowledged: true);
  }

  bool get canRetry => retryCount < maxRetries;
  bool get isScheduled =>
      scheduledAt != null && scheduledAt!.isAfter(DateTime.now());
  bool get isCritical => priority == SyncPriority.critical;
  bool get isHighPriority => priority <= SyncPriority.high;

  Duration get retryDelay {
    final base = Duration(seconds: 2);
    return base * (1 << retryCount);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'table': table,
        'operation': operation.name,
        'entityId': entityId,
        'payload': payload,
        'previousPayload': previousPayload,
        'priority': priority.name,
        'timestamp': timestamp.toIso8601String(),
        'scheduledAt': scheduledAt?.toIso8601String(),
        'retryCount': retryCount,
        'maxRetries': maxRetries,
        'correlationId': correlationId,
        'causationId': causationId,
        'metadata': metadata,
        'source': source,
        'acknowledged': acknowledged,
      };

  factory EnhancedSyncEvent.fromJson(Map<String, dynamic> json) {
    return EnhancedSyncEvent(
      id: json['id'] as String,
      table: json['table'] as String,
      operation: SyncOperation.values.byName(json['operation'] as String),
      entityId: json['entityId'] as String,
      payload: json['payload'] as Map<String, dynamic>?,
      previousPayload: json['previousPayload'] as Map<String, dynamic>?,
      priority: SyncPriority.values.byName(json['priority'] as String),
      timestamp: DateTime.parse(json['timestamp'] as String),
      scheduledAt: json['scheduledAt'] != null
          ? DateTime.parse(json['scheduledAt'] as String)
          : null,
      retryCount: json['retryCount'] as int? ?? 0,
      maxRetries: json['maxRetries'] as int? ?? 3,
      correlationId: json['correlationId'] as String?,
      causationId: json['causationId'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
      source: json['source'] as String? ?? 'local',
      acknowledged: json['acknowledged'] as bool? ?? false,
    );
  }

  factory EnhancedSyncEvent.create({
    required String table,
    required String entityId,
    required Map<String, dynamic> payload,
    SyncPriority priority = SyncPriority.normal,
    String? correlationId,
    Map<String, dynamic>? metadata,
  }) {
    return EnhancedSyncEvent(
      table: table,
      operation: SyncOperation.create,
      entityId: entityId,
      payload: payload,
      priority: priority,
      correlationId: correlationId,
      metadata: metadata,
    );
  }

  factory EnhancedSyncEvent.update({
    required String table,
    required String entityId,
    required Map<String, dynamic> payload,
    Map<String, dynamic>? previousPayload,
    SyncPriority priority = SyncPriority.normal,
    String? correlationId,
    Map<String, dynamic>? metadata,
  }) {
    return EnhancedSyncEvent(
      table: table,
      operation: SyncOperation.update,
      entityId: entityId,
      payload: payload,
      previousPayload: previousPayload,
      priority: priority,
      correlationId: correlationId,
      metadata: metadata,
    );
  }

  factory EnhancedSyncEvent.delete({
    required String table,
    required String entityId,
    Map<String, dynamic>? previousPayload,
    SyncPriority priority = SyncPriority.normal,
    String? correlationId,
    Map<String, dynamic>? metadata,
  }) {
    return EnhancedSyncEvent(
      table: table,
      operation: SyncOperation.delete,
      entityId: entityId,
      previousPayload: previousPayload,
      priority: priority,
      correlationId: correlationId,
      metadata: metadata,
    );
  }

  @override
  String toString() =>
      'SyncEvent($operation $table:$entityId, priority: ${priority.name}, retry: $retryCount)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EnhancedSyncEvent &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class SyncEventBatch {
  final String id;
  final List<EnhancedSyncEvent> events;
  final DateTime createdAt;
  final String? correlationId;

  static const _uuid = Uuid();

  SyncEventBatch({
    String? id,
    required this.events,
    DateTime? createdAt,
    this.correlationId,
  })  : id = id ?? _uuid.v4(),
        createdAt = createdAt ?? DateTime.now();

  int get size => events.length;
  bool get isEmpty => events.isEmpty;
  bool get isNotEmpty => events.isNotEmpty;

  SyncPriority get highestPriority {
    if (events.isEmpty) return SyncPriority.low;
    return events.map((e) => e.priority).reduce((a, b) => a < b ? a : b);
  }

  Map<String, List<EnhancedSyncEvent>> groupByTable() {
    final map = <String, List<EnhancedSyncEvent>>{};
    for (final event in events) {
      map.putIfAbsent(event.table, () => []).add(event);
    }
    return map;
  }

  Map<SyncOperation, List<EnhancedSyncEvent>> groupByOperation() {
    final map = <SyncOperation, List<EnhancedSyncEvent>>{};
    for (final event in events) {
      map.putIfAbsent(event.operation, () => []).add(event);
    }
    return map;
  }
}
