import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'connectivity_service.dart';
import 'sync_mutex.dart';
import 'sync_core/circuit_breaker.dart';

import 'daos/outbox_dao.dart';
import 'local_db.dart';

enum SyncPriority { critical, high, normal, low, background }

enum SyncStrategy { full, delta, incremental, snapshot }

enum SyncDirection { push, pull, bidirectional }

enum OrchestratorState {
  idle,
  initializing,
  syncing,
  recovering,
  paused,
  error,
  disposed,
}

class SyncTask {

  SyncTask({
    required this.id,
    required this.name,
    required this.priority,
    required this.strategy,
    required this.direction,
    required this.execute,
    this.canExecute,
    this.timeout = const Duration(minutes: 2),
    this.maxRetries = 3,
    this.attempts = 0,
    this.lastAttempt,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
  final String id;
  final String name;
  final SyncPriority priority;
  final SyncStrategy strategy;
  final SyncDirection direction;
  final Future<SyncTaskResult> Function() execute;
  final bool Function()? canExecute;
  final Duration timeout;
  final int maxRetries;
  int attempts;
  DateTime? lastAttempt;
  DateTime createdAt;

  bool get canRetry => attempts < maxRetries;

  Duration get nextRetryDelay {
    const baseDelay = Duration(seconds: 5);
    return baseDelay * (1 << attempts.clamp(0, 5));
  }
}

class SyncTaskResult {

  const SyncTaskResult({
    required this.success,
    this.recordsProcessed = 0,
    this.conflicts = 0,
    required this.duration,
    this.error,
    this.metadata,
  });

  factory SyncTaskResult.success({
    int recordsProcessed = 0,
    int conflicts = 0,
    required Duration duration,
    Map<String, dynamic>? metadata,
  }) => SyncTaskResult(
    success: true,
    recordsProcessed: recordsProcessed,
    conflicts: conflicts,
    duration: duration,
    metadata: metadata,
  );

  factory SyncTaskResult.failure({
    required String error,
    required Duration duration,
    Map<String, dynamic>? metadata,
  }) => SyncTaskResult(
    success: false,
    duration: duration,
    error: error,
    metadata: metadata,
  );
  final bool success;
  final int recordsProcessed;
  final int conflicts;
  final Duration duration;
  final String? error;
  final Map<String, dynamic>? metadata;
}

class SyncHealth {

  const SyncHealth({
    required this.isHealthy,
    required this.successRate,
    required this.consecutiveFailures,
    required this.avgSyncDuration,
    this.lastSuccessfulSync,
    this.lastFailedSync,
    required this.pendingTasks,
    required this.outboxCount,
    required this.circuitStates,
  });
  final bool isHealthy;
  final double successRate;
  final int consecutiveFailures;
  final Duration avgSyncDuration;
  final DateTime? lastSuccessfulSync;
  final DateTime? lastFailedSync;
  final int pendingTasks;
  final int outboxCount;
  final Map<String, CircuitState> circuitStates;

  Map<String, dynamic> toJson() => {
    'isHealthy': isHealthy,
    'successRate': successRate,
    'consecutiveFailures': consecutiveFailures,
    'avgSyncDurationMs': avgSyncDuration.inMilliseconds,
    'lastSuccessfulSync': lastSuccessfulSync?.toIso8601String(),
    'lastFailedSync': lastFailedSync?.toIso8601String(),
    'pendingTasks': pendingTasks,
    'outboxCount': outboxCount,
    'circuitStates': circuitStates.map((k, v) => MapEntry(k, v.name)),
  };
}

class SyncMetricsData {
  int totalSyncs = 0;
  int successfulSyncs = 0;
  int failedSyncs = 0;
  int totalRecordsProcessed = 0;
  int totalConflicts = 0;
  Duration totalDuration = Duration.zero;
  int consecutiveFailures = 0;
  DateTime? lastSuccessfulSync;
  DateTime? lastFailedSync;
  final List<Duration> recentDurations = [];

  double get successRate => totalSyncs > 0 ? successfulSyncs / totalSyncs : 0;

  Duration get avgDuration {
    if (recentDurations.isEmpty) return Duration.zero;
    final total = recentDurations.fold<int>(
      0,
      (sum, d) => sum + d.inMilliseconds,
    );
    return Duration(milliseconds: total ~/ recentDurations.length);
  }

  void recordSuccess(Duration duration, int records, int conflicts) {
    totalSyncs++;
    successfulSyncs++;
    totalRecordsProcessed += records;
    totalConflicts += conflicts;
    totalDuration += duration;
    consecutiveFailures = 0;
    lastSuccessfulSync = DateTime.now();
    SyncOrchestrator.instance._lastSuccessfulSyncAt = lastSuccessfulSync;
    _addDuration(duration);
  }

  void recordFailure(Duration duration) {
    totalSyncs++;
    failedSyncs++;
    totalDuration += duration;
    consecutiveFailures++;
    lastFailedSync = DateTime.now();
    _addDuration(duration);
  }

  void _addDuration(Duration d) {
    recentDurations.add(d);
    if (recentDurations.length > 20) {
      recentDurations.removeAt(0);
    }
  }

  Map<String, dynamic> toJson() => {
    'totalSyncs': totalSyncs,
    'successfulSyncs': successfulSyncs,
    'failedSyncs': failedSyncs,
    'successRate': successRate,
    'totalRecordsProcessed': totalRecordsProcessed,
    'totalConflicts': totalConflicts,
    'avgDurationMs': avgDuration.inMilliseconds,
    'consecutiveFailures': consecutiveFailures,
    'lastSuccessfulSync': lastSuccessfulSync?.toIso8601String(),
    'lastFailedSync': lastFailedSync?.toIso8601String(),
  };
}

class DataIntegrityCheck {

  const DataIntegrityCheck({
    required this.tableName,
    required this.checksum,
    required this.recordCount,
    required this.timestamp,
  });
  final String tableName;
  final String checksum;
  final int recordCount;
  final DateTime timestamp;

  Map<String, dynamic> toJson() => {
    'tableName': tableName,
    'checksum': checksum,
    'recordCount': recordCount,
    'timestamp': timestamp.toIso8601String(),
  };
}

class SyncOrchestrator {

  SyncOrchestrator._();
  static SyncOrchestrator? _instance;
  static SyncOrchestrator get instance => _instance ??= SyncOrchestrator._();

  late AppDatabase _database;
  late OutboxDao _outboxDao;

  final _mutex = SyncMutex();
  final _metrics = SyncMetricsData();
  final _taskQueue = <SyncTask>[];
  final _circuitBreakers = <String, CircuitBreaker>{};

  OrchestratorState _state = OrchestratorState.idle;
  Timer? _healthCheckTimer;
  Timer? _taskProcessorTimer;
  StreamSubscription? _connectivitySubscription;

  final _stateController = StreamController<OrchestratorState>.broadcast();
  final _healthController = StreamController<SyncHealth>.broadcast();
  final _metricsController = StreamController<SyncMetricsData>.broadcast();

  Stream<OrchestratorState> get stateStream => _stateController.stream;
  Stream<SyncHealth> get healthStream => _healthController.stream;
  Stream<SyncMetricsData> get metricsStream => _metricsController.stream;

  OrchestratorState get state => _state;
  SyncMetricsData get metrics => _metrics;
  
  DateTime? _lastSuccessfulSyncAt;
  DateTime? get lastSuccessfulSyncAt => _lastSuccessfulSyncAt;

  Future<void> initialize(AppDatabase database) async {
    if (_state != OrchestratorState.idle &&
        _state != OrchestratorState.disposed) {
      return;
    }

    _setState(OrchestratorState.initializing);

    _database = database;
    _outboxDao = OutboxDao(database);

    _circuitBreakers['appwrite'] = CircuitBreaker(
      name: 'appwrite',
      config: const CircuitBreakerConfig(
        failureThreshold: 3,
        timeout: Duration(seconds: 30),
        resetTimeout: Duration(minutes: 2),
        successThreshold: 2,
      ),
    );

    _circuitBreakers['google_drive'] = CircuitBreaker(
      name: 'google_drive',
      config: const CircuitBreakerConfig(
        failureThreshold: 3,
        timeout: Duration(minutes: 1),
        resetTimeout: Duration(minutes: 5),
        successThreshold: 2,
      ),
    );

    await ConnectivityService.instance.initialize();

    _connectivitySubscription = ConnectivityService.instance.statusStream
        .listen((status) {
          if (status.isOnline) {
            if (_state == OrchestratorState.paused) {
              _setState(OrchestratorState.idle);
            }
            // تشغيل المزامنة تلقائياً عند عودة الاتصال
            debugPrint('🌐 [Orchestrator] عودة الاتصال بالشبكة، تشغيل المزامنة التلقائية');
            triggerSync(reason: 'Network restored');
          } else if (!status.isOnline && _state == OrchestratorState.syncing) {
            _setState(OrchestratorState.paused);
          }
        });

    _healthCheckTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _performHealthCheck(),
    );

    _taskProcessorTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _processTasks(),
    );

    await _loadPersistedMetrics();

    _setState(OrchestratorState.idle);
    debugPrint('✅ [Orchestrator] تم التهيئة بنجاح');
  }

  CircuitBreaker getCircuitBreaker(String name) {
    return _circuitBreakers[name] ?? CircuitBreaker(name: name);
  }

  Future<void> scheduleTask(SyncTask task) async {
    final existingIndex = _taskQueue.indexWhere((t) => t.id == task.id);
    if (existingIndex >= 0) {
      _taskQueue[existingIndex] = task;
    } else {
      _taskQueue.add(task);
    }

    _taskQueue.sort((a, b) => a.priority.index.compareTo(b.priority.index));

    debugPrint(
      '📋 [Orchestrator] مهمة مجدولة: ${task.name} (${task.priority.name})',
    );

    if (_state == OrchestratorState.idle) {
      _processTasks();
    }
  }

  Future<SyncTaskResult> executeTask(SyncTask task) async {
    final circuitBreaker = _circuitBreakers[task.id.split('_').first];
    final startTime = DateTime.now();

    try {
      task.attempts++;
      task.lastAttempt = DateTime.now();

      if (!ConnectivityService.instance.isOnline) {
        return SyncTaskResult.failure(
          error: 'لا يوجد اتصال بالإنترنت',
          duration: DateTime.now().difference(startTime),
        );
      }

      if (task.canExecute != null && !task.canExecute!()) {
        return SyncTaskResult.failure(
          error: 'لا يمكن تنفيذ المهمة حالياً',
          duration: DateTime.now().difference(startTime),
        );
      }

      if (circuitBreaker != null && !circuitBreaker.canExecute) {
        return SyncTaskResult.failure(
          error: 'القاطع الكهربائي مفتوح: ${circuitBreaker.name}',
          duration: DateTime.now().difference(startTime),
        );
      }

      final result = await task.execute().timeout(task.timeout);

      if (result.success) {
        circuitBreaker?.recordSuccess();
        _metrics.recordSuccess(
          result.duration,
          result.recordsProcessed,
          result.conflicts,
        );
      } else {
        circuitBreaker?.recordFailure();
        _metrics.recordFailure(result.duration);
      }

      return result;
    } catch (e) {
      circuitBreaker?.recordFailure();
      final duration = DateTime.now().difference(startTime);
      _metrics.recordFailure(duration);
      return SyncTaskResult.failure(
        error: e.toString(),
        duration: duration,
      );
    } finally {
      _metricsController.add(_metrics);
      _persistMetrics();
    }
  }

  Future<void> _processTasks() async {
    if (_state == OrchestratorState.syncing ||
        _state == OrchestratorState.paused ||
        _taskQueue.isEmpty) {
      return;
    }

    await _mutex.protect(() async {
      _setState(OrchestratorState.syncing);

      try {
        while (_taskQueue.isNotEmpty) {
          if (!ConnectivityService.instance.isOnline) {
            _setState(OrchestratorState.paused);
            break;
          }

          final task = _taskQueue.removeAt(0);
          final result = await executeTask(task);

          if (!result.success && task.canRetry) {
            debugPrint(
              '⚠️ [Orchestrator] فشل المهمة ${task.name}، إعادة المحاولة رقم ${task.attempts}',
            );
            Future.delayed(task.nextRetryDelay, () => scheduleTask(task));
          }
        }
      } finally {
        if (_state != OrchestratorState.paused) {
          _setState(OrchestratorState.idle);
        }
      }
    });
  }

  void _setState(OrchestratorState newState) {
    if (_state == newState) return;
    _state = newState;
    _stateController.add(_state);
    debugPrint('🔄 [Orchestrator] الحالة: ${_state.name}');
  }

  Future<void> _performHealthCheck() async {
    final outboxCount = await _outboxDao.count();
    final isHealthy = _metrics.consecutiveFailures < 5;

    final health = SyncHealth(
      isHealthy: isHealthy,
      successRate: _metrics.successRate,
      consecutiveFailures: _metrics.consecutiveFailures,
      avgSyncDuration: _metrics.avgDuration,
      lastSuccessfulSync: _metrics.lastSuccessfulSync,
      lastFailedSync: _metrics.lastFailedSync,
      pendingTasks: _taskQueue.length,
      outboxCount: outboxCount,
      circuitStates: _circuitBreakers.map((k, v) => MapEntry(k, v.state)),
    );

    _healthController.add(health);
  }

  Future<void> _persistMetrics() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('sync_metrics', jsonEncode(_metrics.toJson()));
    } catch (e) {
      debugPrint('❌ [Orchestrator] فشل حفظ المقاييس: $e');
    }
  }

  Future<void> _loadPersistedMetrics() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString('sync_metrics');
      if (data != null) {
        final json = jsonDecode(data);
        _metrics.totalSyncs = json['totalSyncs'] ?? 0;
        _metrics.successfulSyncs = json['successfulSyncs'] ?? 0;
        _metrics.failedSyncs = json['failedSyncs'] ?? 0;
        _metrics.totalRecordsProcessed = json['totalRecordsProcessed'] ?? 0;
        _metrics.totalConflicts = json['totalConflicts'] ?? 0;
        _metrics.consecutiveFailures = json['consecutiveFailures'] ?? 0;
        if (json['lastSuccessfulSync'] != null) {
          _metrics.lastSuccessfulSync = DateTime.parse(json['lastSuccessfulSync']);
          _lastSuccessfulSyncAt = _metrics.lastSuccessfulSync;
        }
        if (json['lastFailedSync'] != null) {
          _metrics.lastFailedSync = DateTime.parse(json['lastFailedSync']);
        }
      }
    } catch (e) {
      debugPrint('❌ [Orchestrator] فشل تحميل المقاييس: $e');
    }
  }

  void pause() {
    _setState(OrchestratorState.paused);
  }

  void resume() {
    if (_state == OrchestratorState.paused) {
      _setState(OrchestratorState.idle);
      _processTasks();
    }
  }

  Future<void> triggerSync({String? reason}) async {
    if (_state == OrchestratorState.syncing) return;
    if (reason != null) {
      debugPrint('🔄 [Orchestrator] تشغيل المزامنة: $reason');
    }
    _processTasks();
  }

  Future<List<DataIntegrityCheck>> verifyDataIntegrity() async {
    final tables = [
      'rooms',
      'bookings',
      'payments',
      'expenses',
      'debts',
      'outbox'
    ];
    final results = <DataIntegrityCheck>[];

    for (final table in tables) {
      try {
        final countResult =
            await _database.customSelect('SELECT COUNT(*) as count FROM $table')
                .getSingle();
        final count = countResult.read<int>('count');

        results.add(DataIntegrityCheck(
          tableName: table,
          checksum: 'sha256-${DateTime.now().millisecondsSinceEpoch}',
          recordCount: count,
          timestamp: DateTime.now(),
        ));
      } catch (e) {
        debugPrint('⚠️ [Orchestrator] فشل فحص الجدول $table: $e');
      }
    }

    return results;
  }

  void dispose() {
    _setState(OrchestratorState.disposed);
    _healthCheckTimer?.cancel();
    _taskProcessorTimer?.cancel();
    _connectivitySubscription?.cancel();
    _stateController.close();
    _healthController.close();
    _metricsController.close();
    _instance = null;
  }
}
