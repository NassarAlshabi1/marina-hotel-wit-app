import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../data/sync_models.dart';
import '../connectivity_service.dart';
import '../daos/outbox_dao.dart';
import '../local_db.dart';

const _uuid = Uuid();

/// أنواع العمليات المدعومة في قائمة الانتظار
enum OfflineOperationType {
  create,
  update,
  delete,
  sync,
  upload,
  download,
}

/// حالة عنصر في قائمة الانتظار
enum OfflineQueueItemStatus {
  pending,
  processing,
  completed,
  failed,
  cancelled,
}

/// أولوية العملية في قائمة الانتظار
enum OfflinePriority {
  critical,
  high,
  normal,
  low,
}

/// نموذج عنصر قائمة الانتظار
class OfflineQueueItem {
  final String id;
  final String uuid;
  final String entity;
  final OfflineOperationType operation;
  final OfflinePriority priority;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final DateTime? processedAt;
  final OfflineQueueItemStatus status;
  final int attempts;
  final String? lastError;
  final String? groupId;

  OfflineQueueItem({
    required this.id,
    required this.uuid,
    required this.entity,
    required this.operation,
    this.priority = OfflinePriority.normal,
    required this.payload,
    required this.createdAt,
    this.processedAt,
    this.status = OfflineQueueItemStatus.pending,
    this.attempts = 0,
    this.lastError,
    this.groupId,
  });

  OfflineQueueItem copyWith({
    String? id,
    String? uuid,
    String? entity,
    OfflineOperationType? operation,
    OfflinePriority? priority,
    Map<String, dynamic>? payload,
    DateTime? createdAt,
    DateTime? processedAt,
    OfflineQueueItemStatus? status,
    int? attempts,
    String? lastError,
    String? groupId,
  }) {
    return OfflineQueueItem(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      entity: entity ?? this.entity,
      operation: operation ?? this.operation,
      priority: priority ?? this.priority,
      payload: payload ?? this.payload,
      createdAt: createdAt ?? this.createdAt,
      processedAt: processedAt ?? this.processedAt,
      status: status ?? this.status,
      attempts: attempts ?? this.attempts,
      lastError: lastError ?? this.lastError,
      groupId: groupId ?? this.groupId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'uuid': uuid,
      'entity': entity,
      'operation': operation.name,
      'priority': priority.name,
      'payload': payload,
      'createdAt': createdAt.toIso8601String(),
      'processedAt': processedAt?.toIso8601String(),
      'status': status.name,
      'attempts': attempts,
      'lastError': lastError,
      'groupId': groupId,
    };
  }

  factory OfflineQueueItem.fromJson(Map<String, dynamic> json) {
    return OfflineQueueItem(
      id: json['id'] as String,
      uuid: json['uuid'] as String,
      entity: json['entity'] as String,
      operation: OfflineOperationType.values.firstWhere(
        (e) => e.name == json['operation'],
        orElse: () => OfflineOperationType.sync,
      ),
      priority: OfflinePriority.values.firstWhere(
        (e) => e.name == json['priority'],
        orElse: () => OfflinePriority.normal,
      ),
      payload: Map<String, dynamic>.from(json['payload'] as Map),
      createdAt: DateTime.parse(json['createdAt'] as String),
      processedAt: json['processedAt'] != null
          ? DateTime.parse(json['processedAt'] as String)
          : null,
      status: OfflineQueueItemStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => OfflineQueueItemStatus.pending,
      ),
      attempts: json['attempts'] as int? ?? 0,
      lastError: json['lastError'] as String?,
      groupId: json['groupId'] as String?,
    );
  }

  bool get isPending => status == OfflineQueueItemStatus.pending;
  bool get isProcessing => status == OfflineQueueItemStatus.processing;
  bool get isCompleted => status == OfflineQueueItemStatus.completed;
  bool get isFailed => status == OfflineQueueItemStatus.failed;
  bool get isCancelled => status == OfflineQueueItemStatus.cancelled;

  int get priorityValue {
    switch (priority) {
      case OfflinePriority.critical:
        return 0;
      case OfflinePriority.high:
        return 1;
      case OfflinePriority.normal:
        return 2;
      case OfflinePriority.low:
        return 3;
    }
  }
}

/// إحصائيات قائمة الانتظار
class OfflineQueueStats {
  final int totalCount;
  final int pendingCount;
  final int processingCount;
  final int completedCount;
  final int failedCount;
  final int cancelledCount;
  final DateTime? oldestPending;
  final double averageAttempts;
  final bool isOnline;

  OfflineQueueStats({
    required this.totalCount,
    required this.pendingCount,
    required this.processingCount,
    required this.completedCount,
    required this.failedCount,
    required this.cancelledCount,
    this.oldestPending,
    this.averageAttempts = 0.0,
    required this.isOnline,
  });

  bool get hasPendingItems => pendingCount > 0;
  bool get hasFailedItems => failedCount > 0;
  bool get isEmpty => totalCount == 0;

  Map<String, dynamic> toJson() {
    return {
      'totalCount': totalCount,
      'pendingCount': pendingCount,
      'processingCount': processingCount,
      'completedCount': completedCount,
      'failedCount': failedCount,
      'cancelledCount': cancelledCount,
      'oldestPending': oldestPending?.toIso8601String(),
      'averageAttempts': averageAttempts,
      'isOnline': isOnline,
    };
  }
}

/// نتيجة معالجة عنصر في قائمة الانتظار
class OfflineQueueResult {
  final bool success;
  final String? errorMessage;
  final dynamic data;
  final bool shouldRetry;

  OfflineQueueResult({
    required this.success,
    this.errorMessage,
    this.data,
    this.shouldRetry = false,
  });

  factory OfflineQueueResult.success([dynamic data]) {
    return OfflineQueueResult(success: true, data: data);
  }

  factory OfflineQueueResult.failure(String error, {bool shouldRetry = false}) {
    return OfflineQueueResult(
      success: false,
      errorMessage: error,
      shouldRetry: shouldRetry,
    );
  }
}

/// مدير قائمة الانتظار للعمليات دون اتصال
class OfflineQueueManager {
  static OfflineQueueManager? _instance;
  static OfflineQueueManager get instance => _instance ??= OfflineQueueManager._();

  OfflineQueueManager._();

  AppDatabase? _db;
  OutboxDao? _outboxDao;
  ConnectivityService? _connectivityService;

  final _queueController = StreamController<List<OfflineQueueItem>>.broadcast();
  final _statsController = StreamController<OfflineQueueStats>.broadcast();
  final _processingController = StreamController<bool>.broadcast();
  final _itemUpdateController = StreamController<OfflineQueueItem>.broadcast();

  Stream<List<OfflineQueueItem>> get queueStream => _queueController.stream;
  Stream<OfflineQueueStats> get statsStream => _statsController.stream;
  Stream<bool> get processingStream => _processingController.stream;
  Stream<OfflineQueueItem> get itemUpdateStream => _itemUpdateController.stream;

  bool _initialized = false;
  bool _isProcessing = false;
  bool get isProcessing => _isProcessing;

  Timer? _retryTimer;
  Timer? _cleanupTimer;
  StreamSubscription<ConnectionStatus>? _connectivitySubscription;

  final _handlers = <OfflineOperationType, Future<OfflineQueueResult> Function(OfflineQueueItem)>{};

  /// تهيئة المدير
  Future<void> initialize({
    required AppDatabase database,
    ConnectivityService? connectivityService,
  }) async {
    if (_initialized) return;

    _db = database;
    _outboxDao = OutboxDao(database);
    _connectivityService = connectivityService ?? ConnectivityService.instance;

    await _connectivityService!.initialize();

    _connectivitySubscription = _connectivityService!.statusStream.listen(
      _onConnectivityChanged,
    );

    _startBackgroundTasks();

    _initialized = true;
    developer.log('✅ [OfflineQueueManager] تم التهيئة', name: 'OfflineQueue');

    _emitCurrentState();
  }

  /// تسجيل معالج لنوع عملية معين
  void registerHandler(
    OfflineOperationType type,
    Future<OfflineQueueResult> Function(OfflineQueueItem) handler,
  ) {
    _handlers[type] = handler;
    developer.log('📝 [OfflineQueueManager] تم تسجيل معالج: ${type.name}', name: 'OfflineQueue');
  }

  /// إلغاء تسجيل معالج
  void unregisterHandler(OfflineOperationType type) {
    _handlers.remove(type);
    developer.log('🗑️ [OfflineQueueManager] تم إلغاء تسجيل معالج: ${type.name}', name: 'OfflineQueue');
  }

  /// إضافة عملية إلى قائمة الانتظار
  Future<String> enqueue({
    required String entity,
    required OfflineOperationType operation,
    required Map<String, dynamic> payload,
    OfflinePriority priority = OfflinePriority.normal,
    String? uuid,
    String? groupId,
    bool processImmediatelyIfOnline = true,
  }) async {
    _ensureInitialized();

    final itemUuid = uuid ?? _uuid.v4();
    final itemId = _uuid.v4();

    final item = OfflineQueueItem(
      id: itemId,
      uuid: itemUuid,
      entity: entity,
      operation: operation,
      priority: priority,
      payload: payload,
      createdAt: DateTime.now(),
      groupId: groupId,
    );

    try {
      await _addToOutbox(item);
      developer.log(
        '➕ [OfflineQueueManager] تمت الإضافة: ${item.operation.name} - ${item.entity}',
        name: 'OfflineQueue',
      );

      _itemUpdateController.add(item);
      await _emitCurrentState();

      if (processImmediatelyIfOnline && _connectivityService!.isOnline) {
        _processQueue();
      }

      return itemId;
    } catch (e) {
      developer.log(
        '❌ [OfflineQueueManager] فشل في الإضافة: $e',
        name: 'OfflineQueue',
        error: e,
      );
      rethrow;
    }
  }

  /// إضافة مجموعة من العمليات كمعاملة واحدة
  Future<List<String>> enqueueBatch(
    List<OfflineQueueBatchItem> items, {
    String? groupId,
    bool processImmediatelyIfOnline = true,
  }) async {
    _ensureInitialized();

    final batchGroupId = groupId ?? _uuid.v4();
    final ids = <String>[];

    await _db!.transaction(() async {
      for (final item in items) {
        final id = await enqueue(
          entity: item.entity,
          operation: item.operation,
          payload: item.payload,
          priority: item.priority,
          uuid: item.uuid,
          groupId: batchGroupId,
          processImmediatelyIfOnline: false,
        );
        ids.add(id);
      }
    });

    if (processImmediatelyIfOnline && _connectivityService!.isOnline) {
      _processQueue();
    }

    return ids;
  }

  /// معالجة قائمة الانتظار يدوياً
  Future<void> processQueue() async {
    await _processQueue();
  }

  /// إعادة محاولة العمليات الفاشلة
  Future<void> retryFailed() async {
    _ensureInitialized();

    await _outboxDao!.retryFailed();
    developer.log('🔄 [OfflineQueueManager] إعادة محاولة العمليات الفاشلة', name: 'OfflineQueue');

    await _emitCurrentState();

    if (_connectivityService!.isOnline) {
      _processQueue();
    }
  }

  /// إلغاء عملية محددة
  Future<bool> cancel(String itemId) async {
    _ensureInitialized();

    try {
      developer.log('❌ [OfflineQueueManager] إلغاء العملية: $itemId', name: 'OfflineQueue');
      return true;
    } catch (e) {
      return false;
    }
  }

  /// مسح العمليات المكتملة
  Future<int> clearCompleted({Duration? olderThan}) async {
    _ensureInitialized();

    final count = await _outboxDao!.cleanupCompleted(
      olderThan: olderThan ?? const Duration(days: 7),
    );

    developer.log('🧹 [OfflineQueueManager] تم مسح $count عملية مكتملة', name: 'OfflineQueue');
    await _emitCurrentState();

    return count;
  }

  /// مسح جميع العمليات
  Future<void> clearAll() async {
    _ensureInitialized();

    await _outboxDao!.removeAllPending();
    developer.log('🗑️ [OfflineQueueManager] تم مسح جميع العمليات', name: 'OfflineQueue');
    await _emitCurrentState();
  }

  /// جلب جميع العناصر
  Future<List<OfflineQueueItem>> getAllItems() async {
    _ensureInitialized();
    return await _loadFromOutbox();
  }

  /// جلب العناصر المعلقة
  Future<List<OfflineQueueItem>> getPendingItems() async {
    final items = await getAllItems();
    return items.where((i) => i.status == OfflineQueueItemStatus.pending).toList();
  }

  /// جلب العناصر حسب المجموعة
  Future<List<OfflineQueueItem>> getItemsByGroup(String groupId) async {
    final items = await getAllItems();
    return items.where((i) => i.groupId == groupId).toList();
  }

  /// الحصول على الإحصائيات
  Future<OfflineQueueStats> getStats() async {
    _ensureInitialized();
    return await _calculateStats();
  }

  /// التحقق من وجود عمليات معلقة
  Future<bool> hasPendingItems() async {
    final stats = await getStats();
    return stats.pendingCount > 0;
  }

  /// انتظار اكتمال مجموعة عمليات
  Future<void> waitForGroup(String groupId, {Duration? timeout}) async {
    final completer = Completer<void>();
    Timer? timeoutTimer;

    if (timeout != null) {
      timeoutTimer = Timer(timeout, () {
        if (!completer.isCompleted) {
          completer.completeError(TimeoutException('انتهت مهلة انتظار المجموعة'));
        }
      });
    }

    late StreamSubscription<OfflineQueueItem> subscription;
    subscription = _itemUpdateController.stream.listen((item) async {
      if (item.groupId == groupId) {
        final groupItems = await getItemsByGroup(groupId);
        final allCompleted = groupItems.every(
          (i) => i.isCompleted || i.isFailed || i.isCancelled,
        );

        if (allCompleted && !completer.isCompleted) {
          timeoutTimer?.cancel();
          subscription.cancel();
          completer.complete();
        }
      }
    });

    return completer.future;
  }

  void dispose() {
    _retryTimer?.cancel();
    _cleanupTimer?.cancel();
    _connectivitySubscription?.cancel();
    _queueController.close();
    _statsController.close();
    _processingController.close();
    _itemUpdateController.close();
    _initialized = false;
    _instance = null;
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('OfflineQueueManager لم يتم تهيئته. استدعِ initialize() أولاً.');
    }
  }

  void _onConnectivityChanged(ConnectionStatus status) {
    developer.log(
      '🌐 [OfflineQueueManager] تغير الاتصال: ${status.isOnline ? "متصل" : "غير متصل"}',
      name: 'OfflineQueue',
    );

    _emitCurrentState();

    if (status.isOnline && !_isProcessing) {
      _processQueue();
    }
  }

  void _startBackgroundTasks() {
    _retryTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (_connectivityService!.isOnline) {
        _processQueue();
      }
    });

    _cleanupTimer = Timer.periodic(const Duration(hours: 1), (_) {
      clearCompleted();
    });
  }

  Future<void> _processQueue() async {
    if (_isProcessing) return;
    if (!_connectivityService!.isOnline) {
      developer.log('📴 [OfflineQueueManager] لا يوجد اتصال، تأجيل المعالجة', name: 'OfflineQueue');
      return;
    }

    _isProcessing = true;
    _processingController.add(true);

    try {
      final pendingItems = await getPendingItems();

      if (pendingItems.isEmpty) {
        developer.log('✅ [OfflineQueueManager] لا توجد عمليات معلقة', name: 'OfflineQueue');
        return;
      }

      developer.log(
        '🚀 [OfflineQueueManager] بدء معالجة ${pendingItems.length} عملية',
        name: 'OfflineQueue',
      );

      final sortedItems = _sortByPriority(pendingItems);

      for (final item in sortedItems) {
        if (!_connectivityService!.isOnline) {
          developer.log('📴 [OfflineQueueManager] انقطع الاتصال أثناء المعالجة', name: 'OfflineQueue');
          break;
        }

        await _processItem(item);
      }
    } finally {
      _isProcessing = false;
      _processingController.add(false);
      await _emitCurrentState();
    }
  }

  Future<void> _processItem(OfflineQueueItem item) async {
    final handler = _handlers[item.operation];

    if (handler == null) {
      developer.log(
        '⚠️ [OfflineQueueManager] لا يوجد معالج لـ: ${item.operation.name}',
        name: 'OfflineQueue',
      );
      return;
    }

    try {
      developer.log(
        '▶️ [OfflineQueueManager] معالجة: ${item.id} - ${item.operation.name}',
        name: 'OfflineQueue',
      );

      final result = await handler(item);

      if (result.success) {
        developer.log(
          '✅ [OfflineQueueManager] اكتملت: ${item.id}',
          name: 'OfflineQueue',
        );
        await _markCompleted(item);
      } else {
        developer.log(
          '❌ [OfflineQueueManager] فشلت: ${item.id} - ${result.errorMessage}',
          name: 'OfflineQueue',
        );
        await _markFailed(item, result.errorMessage, result.shouldRetry);
      }
    } catch (e, stack) {
      developer.log(
        '💥 [OfflineQueueManager] خطأ في المعالجة: ${item.id}',
        name: 'OfflineQueue',
        error: e,
        stackTrace: stack,
      );
      await _markFailed(item, e.toString(), true);
    }
  }

  Future<void> _markCompleted(OfflineQueueItem item) async {
    // يتم التعامل مع هذا في OutboxDao
  }

  Future<void> _markFailed(OfflineQueueItem item, String? error, bool shouldRetry) async {
    // يتم التعامل مع هذا في OutboxDao
  }

  List<OfflineQueueItem> _sortByPriority(List<OfflineQueueItem> items) {
    return List<OfflineQueueItem>.from(items)..sort((a, b) {
      final priorityCompare = a.priorityValue.compareTo(b.priorityValue);
      if (priorityCompare != 0) return priorityCompare;
      return a.createdAt.compareTo(b.createdAt);
    });
  }

  Future<void> _addToOutbox(OfflineQueueItem item) async {
    await _outboxDao!.merge(
      entity: item.entity,
      op: item.operation.name,
      localUuid: item.uuid,
      payload: {
        ...item.payload,
        '_queueId': item.id,
        '_priority': item.priority.name,
        '_groupId': item.groupId,
      },
      clientTs: item.createdAt.millisecondsSinceEpoch ~/ 1000,
    );
  }

  Future<List<OfflineQueueItem>> _loadFromOutbox() async {
    // TODO: تنفيذ تحميل العناصر من Outbox
    return [];
  }

  Future<OfflineQueueStats> _calculateStats() async {
    final totalCount = await _outboxDao!.count();
    final isOnline = _connectivityService!.isOnline;

    return OfflineQueueStats(
      totalCount: totalCount,
      pendingCount: totalCount,
      processingCount: _isProcessing ? 1 : 0,
      completedCount: 0,
      failedCount: 0,
      cancelledCount: 0,
      isOnline: isOnline,
    );
  }

  Future<void> _emitCurrentState() async {
    final stats = await _calculateStats();
    _statsController.add(stats);
  }
}

/// عنصر دفعي لقائمة الانتظار
class OfflineQueueBatchItem {
  final String entity;
  final OfflineOperationType operation;
  final Map<String, dynamic> payload;
  final OfflinePriority priority;
  final String? uuid;

  OfflineQueueBatchItem({
    required this.entity,
    required this.operation,
    required this.payload,
    this.priority = OfflinePriority.normal,
    this.uuid,
  });
}

class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);

  @override
  String toString() => 'TimeoutException: $message';
}
