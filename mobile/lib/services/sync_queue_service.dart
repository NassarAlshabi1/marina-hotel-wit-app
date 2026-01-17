import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'connectivity_service.dart';
import 'google_drive_auto_sync_engine.dart';
import 'smart_sync_manager.dart';
import 'sync_core/unified_lock_manager.dart';

class RetryConfig {
  final Duration initialDelay;
  final Duration maxDelay;
  final double multiplier;
  final int maxAttempts;
  final bool useJitter;

  const RetryConfig({
    this.initialDelay = const Duration(seconds: 30),
    this.maxDelay = const Duration(minutes: 15),
    this.multiplier = 2.0,
    this.maxAttempts = 10,
    this.useJitter = true,
  });

  Duration calculateDelay(int attempts) {
    final exponentialDelay =
        initialDelay.inMilliseconds * pow(multiplier, attempts.clamp(0, 8));
    final cappedDelay = min(exponentialDelay.toInt(), maxDelay.inMilliseconds);

    if (useJitter) {
      final jitter = Random().nextInt((cappedDelay * 0.2).toInt());
      return Duration(milliseconds: cappedDelay + jitter);
    }

    return Duration(milliseconds: cappedDelay);
  }

  bool shouldRetry(int attempts) => attempts < maxAttempts;
}

class SyncQueueItem {
  final String id;
  final String screenId;
  final Map<String, dynamic> data;
  final DateTime createdAt;
  int attempts;
  DateTime? lastAttempt;
  String? lastError;

  SyncQueueItem({
    required this.id,
    required this.screenId,
    required this.data,
    required this.createdAt,
    this.attempts = 0,
    this.lastAttempt,
    this.lastError,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'screenId': screenId,
        'data': data,
        'createdAt': createdAt.toIso8601String(),
        'attempts': attempts,
        'lastAttempt': lastAttempt?.toIso8601String(),
        'lastError': lastError,
      };

  factory SyncQueueItem.fromJson(Map<String, dynamic> json) => SyncQueueItem(
        id: json['id'],
        screenId: json['screenId'],
        data: Map<String, dynamic>.from(json['data']),
        createdAt: DateTime.parse(json['createdAt']),
        attempts: json['attempts'] ?? 0,
        lastAttempt: json['lastAttempt'] != null
            ? DateTime.tryParse(json['lastAttempt'])
            : null,
        lastError: json['lastError'],
      );

  bool shouldRetryNow(RetryConfig config) {
    if (!config.shouldRetry(attempts)) return false;
    if (lastAttempt == null) return true;

    final nextRetryDelay = config.calculateDelay(attempts);
    final timeSinceLastAttempt = DateTime.now().difference(lastAttempt!);
    return timeSinceLastAttempt >= nextRetryDelay;
  }

  Duration? nextRetryIn(RetryConfig config) {
    if (!config.shouldRetry(attempts)) return null;
    if (lastAttempt == null) return Duration.zero;

    final nextRetryDelay = config.calculateDelay(attempts);
    final timeSinceLastAttempt = DateTime.now().difference(lastAttempt!);
    final remaining = nextRetryDelay - timeSinceLastAttempt;
    return remaining.isNegative ? Duration.zero : remaining;
  }
}

class QueueStats {
  final int totalItems;
  final int pendingItems;
  final int retriableItems;
  final int failedItems;
  final DateTime? oldestItem;
  final DateTime? lastProcessed;

  const QueueStats({
    required this.totalItems,
    required this.pendingItems,
    required this.retriableItems,
    required this.failedItems,
    this.oldestItem,
    this.lastProcessed,
  });

  Map<String, dynamic> toJson() => {
        'totalItems': totalItems,
        'pendingItems': pendingItems,
        'retriableItems': retriableItems,
        'failedItems': failedItems,
        'oldestItem': oldestItem?.toIso8601String(),
        'lastProcessed': lastProcessed?.toIso8601String(),
      };
}

class SyncQueueService {
  static SyncQueueService? _instance;
  static SyncQueueService get instance => _instance ??= SyncQueueService._();

  SyncQueueService._();

  static const String _queueKey = 'sync_queue_items_v2';
  static const String _statsKey = 'sync_queue_stats';

  final RetryConfig _retryConfig = const RetryConfig();
  Timer? _processingTimer;
  bool _isProcessing = false;
  StreamSubscription<ConnectionStatus>? _connectivitySubscription;
  StreamSubscription<AutoSyncEngineState>? _driveStateSubscription;
  bool _driveOnline = false;
  bool _initialized = false;
  DateTime? _lastProcessed;

  final _queueController = StreamController<int>.broadcast();
  final _statsController = StreamController<QueueStats>.broadcast();

  Stream<int> get queueCountStream => _queueController.stream;
  Stream<QueueStats> get statsStream => _statsController.stream;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    await ConnectivityService.instance.initialize();

    _connectivitySubscription =
        ConnectivityService.instance.statusStream.listen((status) {
      if (status.isOnline) {
        debugPrint('🌐 [SyncQueue] الإنترنت متصل - معالجة الطابور...');
        processQueue();
      }
    });

    _setupDriveStateListener();
    _startSmartTimer();
    await processQueue();

    debugPrint(
        '✅ [SyncQueue] تم تهيئة خدمة طابور المزامنة مع Exponential Backoff');
  }

  void _startSmartTimer() {
    _processingTimer?.cancel();
    _processingTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      final items = await getQueueItems();
      final retriable =
          items.where((item) => item.shouldRetryNow(_retryConfig)).toList();

      if (retriable.isNotEmpty) {
        debugPrint(
            '⏰ [SyncQueue] ${retriable.length} عنصر جاهز لإعادة المحاولة');
        processQueue();
      }
    });
  }

  Future<void> addToQueue({
    required String screenId,
    required Map<String, dynamic> data,
  }) async {
    final item = SyncQueueItem(
      id: '${screenId}_${DateTime.now().millisecondsSinceEpoch}',
      screenId: screenId,
      data: data,
      createdAt: DateTime.now(),
    );

    final prefs = await SharedPreferences.getInstance();
    final queueJson = prefs.getStringList(_queueKey) ?? [];
    queueJson.add(jsonEncode(item.toJson()));
    await prefs.setStringList(_queueKey, queueJson);

    _emitQueueCount();
    _emitStats();
    debugPrint('📥 [SyncQueue] تمت إضافة عنصر من $screenId للطابور');
  }

  Future<List<SyncQueueItem>> getQueueItems() async {
    final prefs = await SharedPreferences.getInstance();
    final queueJson = prefs.getStringList(_queueKey) ?? [];
    return queueJson
        .map((json) {
          try {
            return SyncQueueItem.fromJson(jsonDecode(json));
          } catch (e) {
            debugPrint('⚠️ [SyncQueue] خطأ في قراءة عنصر: $e');
            return null;
          }
        })
        .whereType<SyncQueueItem>()
        .toList();
  }

  Future<void> removeFromQueue(String itemId) async {
    final prefs = await SharedPreferences.getInstance();
    final queueJson = prefs.getStringList(_queueKey) ?? [];
    queueJson.removeWhere((json) {
      try {
        final item = jsonDecode(json);
        return item['id'] == itemId;
      } catch (_) {
        return true;
      }
    });
    await prefs.setStringList(_queueKey, queueJson);
    _emitQueueCount();
    _emitStats();
  }

  Future<void> updateQueueItem(SyncQueueItem item) async {
    final prefs = await SharedPreferences.getInstance();
    final queueJson = prefs.getStringList(_queueKey) ?? [];
    final index = queueJson.indexWhere((json) {
      try {
        final parsed = jsonDecode(json);
        return parsed['id'] == item.id;
      } catch (_) {
        return false;
      }
    });
    if (index != -1) {
      queueJson[index] = jsonEncode(item.toJson());
      await prefs.setStringList(_queueKey, queueJson);
    }
    _emitStats();
  }

  Future<void> processQueue() async {
    final lockResult = await UnifiedLockManager.instance.acquire(
      category: LockCategory.queueProcessing,
      holder: 'SyncQueueService.processQueue',
      priority: LockPriority.normal,
    );

    if (!lockResult.acquired) {
      debugPrint(
          '❌ [SyncQueue] فشل الحصول على القفل: ${lockResult.failureReason}');
      return;
    }

    if (_isProcessing) {
      UnifiedLockManager.instance.release(
        category: LockCategory.queueProcessing,
        holder: 'SyncQueueService.processQueue',
      );
      return;
    }

    _isProcessing = true;

    try {
      if (!ConnectivityService.instance.isOnline) {
        debugPrint('📴 [SyncQueue] لا يوجد اتصال - تأجيل المعالجة');
        return;
      }

      final driveOnline = await _ensureDriveOnline();
      if (!driveOnline) {
        debugPrint('🔒 [SyncQueue] Google Drive غير جاهز - الانتظار');
        return;
      }

      final items = await getQueueItems();
      final retriableItems =
          items.where((item) => item.shouldRetryNow(_retryConfig)).toList();

      if (retriableItems.isEmpty) {
        final pendingCount = items
            .where((item) => _retryConfig.shouldRetry(item.attempts))
            .length;
        if (pendingCount > 0) {
          final nextRetry = items
              .map((item) => item.nextRetryIn(_retryConfig))
              .whereType<Duration>()
              .reduce((a, b) => a < b ? a : b);
          debugPrint(
              '⏳ [SyncQueue] $pendingCount عنصر في الانتظار، التالي بعد ${nextRetry.inSeconds}s');
        }
        return;
      }

      debugPrint('🔄 [SyncQueue] معالجة ${retriableItems.length} عنصر...');

      try {
        final success = await SmartSyncManager.instance.pushLocalChanges();

        if (success) {
          for (final item in retriableItems) {
            await removeFromQueue(item.id);
          }
          _lastProcessed = DateTime.now();
          debugPrint(
              '✅ [SyncQueue] تم رفع ${retriableItems.length} عنصر بنجاح');
        } else {
          await _handleFailure(retriableItems, 'Sync returned false');
        }
      } catch (e) {
        await _handleFailure(retriableItems, e.toString());
      }
    } finally {
      _isProcessing = false;
      // إصلاح: await على release لضمان إطلاق القفل قبل إرسال التحديثات
      await UnifiedLockManager.instance.release(
        category: LockCategory.queueProcessing,
        holder: 'SyncQueueService.processQueue',
      );
      _emitQueueCount();
      _emitStats();
    }
  }

  Future<void> _handleFailure(List<SyncQueueItem> items, String error) async {
    for (final item in items) {
      item.attempts++;
      item.lastAttempt = DateTime.now();
      item.lastError = error;
      await updateQueueItem(item);

      final nextDelay = _retryConfig.calculateDelay(item.attempts);
      if (_retryConfig.shouldRetry(item.attempts)) {
        debugPrint(
            '⚠️ [SyncQueue] ${item.id}: محاولة ${item.attempts}، التالية بعد ${nextDelay.inSeconds}s');
      } else {
        debugPrint(
            '❌ [SyncQueue] ${item.id}: تجاوز الحد الأقصى للمحاولات (${item.attempts})');
      }
    }
  }

  Future<int> getQueueCount() async {
    final items = await getQueueItems();
    return items.length;
  }

  Future<QueueStats> getStats() async {
    final items = await getQueueItems();
    final now = DateTime.now();

    final pendingItems =
        items.where((item) => _retryConfig.shouldRetry(item.attempts)).length;
    final retriableItems =
        items.where((item) => item.shouldRetryNow(_retryConfig)).length;
    final failedItems =
        items.where((item) => !_retryConfig.shouldRetry(item.attempts)).length;
    final oldestItem = items.isNotEmpty
        ? items.map((e) => e.createdAt).reduce((a, b) => a.isBefore(b) ? a : b)
        : null;

    return QueueStats(
      totalItems: items.length,
      pendingItems: pendingItems,
      retriableItems: retriableItems,
      failedItems: failedItems,
      oldestItem: oldestItem,
      lastProcessed: _lastProcessed,
    );
  }

  Future<void> clearFailedItems() async {
    final items = await getQueueItems();
    final failedIds = items
        .where((item) => !_retryConfig.shouldRetry(item.attempts))
        .map((item) => item.id)
        .toList();

    for (final id in failedIds) {
      await removeFromQueue(id);
    }

    debugPrint('🗑️ [SyncQueue] تم حذف ${failedIds.length} عنصر فاشل');
  }

  Future<void> retryAllFailed() async {
    final items = await getQueueItems();
    for (final item in items) {
      if (!_retryConfig.shouldRetry(item.attempts)) {
        item.attempts = 0;
        item.lastAttempt = null;
        item.lastError = null;
        await updateQueueItem(item);
      }
    }
    debugPrint('🔄 [SyncQueue] تم إعادة تعيين جميع العناصر الفاشلة');
    processQueue();
  }

  void _emitQueueCount() async {
    final count = await getQueueCount();
    _queueController.add(count);
  }

  void _emitStats() async {
    final stats = await getStats();
    _statsController.add(stats);
  }

  Future<bool> _ensureDriveOnline() async {
    if (_driveOnline) return true;

    final engine = AutoSyncEngine.instance;
    if (_isDriveStateOnline(engine.currentState)) {
      _driveOnline = true;
      return true;
    }

    if (!SmartSyncManager.instance.isDriveSignedIn) {
      debugPrint('🔓 [SyncQueue] Google Drive غير مسجل الدخول');
      return false;
    }

    return true;
  }

  void _setupDriveStateListener() {
    _driveStateSubscription?.cancel();
    final engine = AutoSyncEngine.instance;
    _driveOnline = _isDriveStateOnline(engine.currentState);
    _driveStateSubscription = engine.stateStream.listen((state) {
      final online = _isDriveStateOnline(state);
      if (online && !_driveOnline) {
        _driveOnline = true;
        debugPrint('🌐 [SyncQueue] Google Drive متصل');
        processQueue();
      } else if (!online && _driveOnline) {
        _driveOnline = false;
        debugPrint('📴 [SyncQueue] Google Drive غير متصل');
      } else {
        _driveOnline = online;
      }
    });
  }

  bool _isDriveStateOnline(AutoSyncEngineState state) {
    return state.isSignedIn && state.hasNetworkConnection;
  }

  void dispose() {
    _processingTimer?.cancel();
    _processingTimer = null;
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _driveStateSubscription?.cancel();
    _driveStateSubscription = null;
    _queueController.close();
    _statsController.close();
    _initialized = false;
    _instance = null;
  }
}
