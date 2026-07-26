import 'dart:async';
import 'package:flutter/foundation.dart';

/// [Deprecated] This service is being replaced by Unified Outbox Architecture.
/// All methods are now No-ops.
class SyncQueueService {
  SyncQueueService._();
  static SyncQueueService? _instance;
  // ignore: prefer_constructors_over_static_methods
  static SyncQueueService get instance => _instance ??= SyncQueueService._();

  final _queueController = StreamController<int>.broadcast();
  Stream<int> get queueCountStream => _queueController.stream;

  Future<void> initialize() async {
    debugPrint('⚠️ [SyncQueue] Service deprecated - initializing as no-op');
  }

  Future<void> addToQueue({
    required String screenId,
    required Map<String, dynamic> data,
  }) async {
    debugPrint('⚠️ [SyncQueue] addToQueue ignored (using Outbox instead)');
  }

  Future<List<SyncQueueItem>> getQueueItems() async {
    return [];
  }

  Future<void> removeFromQueue(String itemId) async {}

  Future<void> updateQueueItem(SyncQueueItem item) async {}

  Future<void> processQueue() async {}

  Future<int> getQueueCount() async => 0;

  Future<QueueStats> getStats() async =>
      const QueueStats(totalItems: 0, pendingItems: 0, processingItems: 0);

  void dispose() {
    _queueController.close();
  }
}

class SyncQueueItem {
  SyncQueueItem({
    required this.id,
    required this.screenId,
    required this.data,
    required this.createdAt,
    this.attempts = 0,
  });
  final String id;
  final String screenId;
  final Map<String, dynamic> data;
  final DateTime createdAt;
  int attempts;
}

class QueueStats {
  const QueueStats({
    required this.totalItems,
    required this.pendingItems,
    required this.processingItems,
    this.retriableItems = 0,
    this.failedItems = 0,
    this.oldestItem,
    this.lastProcessed,
  });
  final int totalItems;
  final int pendingItems;
  final int processingItems;
  final int retriableItems;
  final int failedItems;
  final DateTime? oldestItem;
  final DateTime? lastProcessed;
}
