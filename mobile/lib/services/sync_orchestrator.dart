import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'connectivity_service.dart';
import 'daos/outbox_dao.dart';
import 'local_db.dart';
import 'sync_core/circuit_breaker.dart';
import 'sync_mutex.dart';
import 'package:marina_hotel_mobile/utils/debug_log.dart';

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
    required this.duration,
    this.recordsProcessed = 0,
    this.conflicts = 0,
    this.error,
    this.metadata,
  });

  factory SyncTaskResult.success({
    required Duration duration,
    int recordsProcessed = 0,
    int conflicts = 0,
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
    required this.pendingTasks,
    required this.outboxCount,
    required this.circuitStates,
    this.lastSuccessfulSync,
    this.lastFailedSync,
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
    if (recentDurations.isEmpty) {
      return Duration.zero;
    }
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
  // ignore: prefer_constructors_over_static_methods
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
  StreamSubscription<void>? _connectivitySubscription;

  final _stateController = StreamController<OrchestratorState>.broadcast();
  final _healthController = StreamController<SyncHealth>.broadcast();
  final _metricsController = StreamController<SyncMetricsData>.broadcast();

  Stream<OrchestratorState> get stateStream => _stateController.stream;
  Stream<SyncHealth> get healthStream => _healthController.stream;
  Stream<SyncMetricsData> get metricsStream => _metricsController.stream;

  OrchestratorState get state => _state;
  SyncMetricsData get metrics => _metrics;

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
        resetTimeout: Duration(minutes: 2),
      ),
    );

    _circuitBreakers['google_drive'] = CircuitBreaker(
      name: 'google_drive',
      config: const CircuitBreakerConfig(
        failureThreshold: 3,
        timeout: Duration(minutes: 1),
        resetTimeout: Duration(minutes: 5),
      ),
    );

    await ConnectivityService.instance.initialize();

    _connectivitySubscription = ConnectivityService.instance.statusStream
        .listen((status) {
          if (status.isOnline && _state == OrchestratorState.paused) {
            _setState(OrchestratorState.idle);
            _processTasks();
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
    dlog('✅ [Orchestrator] تم التهيئة بنجاح');
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

    dlog(() => '📋 [Orchestrator] مهمة مجدولة: ${task.name} (${task.priority.name})');

    if (_state == OrchestratorState.idle) {
      unawaited(_processTasks());
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
          error: 'شروط التنفيذ غير متوفرة',
          duration: DateTime.now().difference(startTime),
        );
      }

      SyncTaskResult result;

      if (circuitBreaker != null) {
        result = await circuitBreaker.execute(
          () => task.execute().timeout(task.timeout),
        );
      } else {
        result = await task.execute().timeout(task.timeout);
      }

      final duration = DateTime.now().difference(startTime);

      if (result.success) {
        _metrics.recordSuccess(
          duration,
          result.recordsProcessed,
          result.conflicts,
        );
        dlog(() => '✅ [Orchestrator] ${task.name}: ${result.recordsProcessed} سجل في ${duration.inMilliseconds}ms');
      } else {
        _metrics.recordFailure(duration);
        dlog(() => '❌ [Orchestrator] ${task.name}: ${result.error}');
      }

      _metricsController.add(_metrics);
      await _persistMetrics();

      return result;
    } on TimeoutException {
      final duration = DateTime.now().difference(startTime);
      _metrics.recordFailure(duration);
      return SyncTaskResult.failure(
        error: 'انتهت المهلة الزمنية',
        duration: duration,
      );
    } catch (e) {
      final duration = DateTime.now().difference(startTime);
      _metrics.recordFailure(duration);
      return SyncTaskResult.failure(error: e.toString(), duration: duration);
    }
  }

  Future<void> _processTasks() async {
    if (_state != OrchestratorState.idle || _taskQueue.isEmpty) {
      return;
    }

    final acquired = await _mutex.acquire(timeout: const Duration(seconds: 5));
    if (!acquired) {
      return;
    }

    try {
      _setState(OrchestratorState.syncing);

      while (_taskQueue.isNotEmpty && ConnectivityService.instance.isOnline) {
        final task = _taskQueue.first;

        if (task.canExecute != null && !task.canExecute!()) {
          _taskQueue.removeAt(0);
          continue;
        }

        final result = await executeTask(task);

        if (result.success) {
          _taskQueue.removeAt(0);
        } else if (task.canRetry) {
          _taskQueue.removeAt(0);
          _taskQueue.add(task);
        } else {
          _taskQueue.removeAt(0);
          dlog(() => '🗑️ [Orchestrator] تم حذف المهمة بعد ${task.attempts} محاولات: ${task.name}');
        }
      }

      _setState(OrchestratorState.idle);
    } finally {
      _mutex.release();
    }
  }

  Future<SyncHealth> getHealth() async {
    final outboxCount = await _outboxDao.count(sources: const ['local']);

    return SyncHealth(
      isHealthy:
          _metrics.consecutiveFailures < 3 &&
          _circuitBreakers.values.every((cb) => cb.state != CircuitState.open),
      successRate: _metrics.successRate,
      consecutiveFailures: _metrics.consecutiveFailures,
      avgSyncDuration: _metrics.avgDuration,
      lastSuccessfulSync: _metrics.lastSuccessfulSync,
      lastFailedSync: _metrics.lastFailedSync,
      pendingTasks: _taskQueue.length,
      outboxCount: outboxCount,
      circuitStates: _circuitBreakers.map((k, v) => MapEntry(k, v.state)),
    );
  }

  Future<void> _performHealthCheck() async {
    final health = await getHealth();
    _healthController.add(health);

    if (!health.isHealthy) {
      dlog('⚠️ [Orchestrator] صحة النظام: غير صحي');

      if (_metrics.consecutiveFailures >= 5) {
        _setState(OrchestratorState.recovering);
        await _attemptRecovery();
      }
    }
  }

  Future<void> _attemptRecovery() async {
    dlog('🔧 [Orchestrator] محاولة الاسترداد...');

    for (final cb in _circuitBreakers.values) {
      if (cb.state == CircuitState.open) {
        cb.reset();
      }
    }

    _taskQueue.clear();
    _metrics.consecutiveFailures = 0;

    _setState(OrchestratorState.idle);
    dlog('✅ [Orchestrator] تم الاسترداد');
  }

  Future<List<DataIntegrityCheck>> verifyDataIntegrity() async {
    final checks = <DataIntegrityCheck>[];
    final tables = [
      'rooms',
      'bookings',
      'employees',
      'expenses',
      'payments',
      'debts',
    ];

    for (final table in tables) {
      try {
        final result = await _database
            .customSelect(
              'SELECT COUNT(*) as count FROM $table WHERE deleted_at IS NULL',
            )
            .getSingle();

        final count = result.data['count'] as int? ?? 0;

        final dataResult = await _database
            .customSelect(
              'SELECT * FROM $table WHERE deleted_at IS NULL ORDER BY local_uuid LIMIT 1000',
            )
            .get();

        final rowJsonList = dataResult.map((r) => jsonEncode(r.data)).toList();
        final checksum = await Isolate.run(() {
          final dataString = rowJsonList.join();
          return md5.convert(utf8.encode(dataString)).toString();
        });

        checks.add(
          DataIntegrityCheck(
            tableName: table,
            checksum: checksum,
            recordCount: count,
            timestamp: DateTime.now(),
          ),
        );
      } catch (e) {
        dlog(() => '⚠️ [Orchestrator] خطأ في فحص $table: $e');
      }
    }

    return checks;
  }

  Future<void> _loadPersistedMetrics() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString('sync_orchestrator_metrics');
      if (json != null) {
        final data = jsonDecode(json) as Map<String, dynamic>;
        _metrics.totalSyncs = (data['totalSyncs'] as num?)?.toInt() ?? 0;
        _metrics.successfulSyncs =
            (data['successfulSyncs'] as num?)?.toInt() ?? 0;
        _metrics.failedSyncs = (data['failedSyncs'] as num?)?.toInt() ?? 0;
        _metrics.totalRecordsProcessed =
            (data['totalRecordsProcessed'] as num?)?.toInt() ?? 0;
        _metrics.totalConflicts =
            (data['totalConflicts'] as num?)?.toInt() ?? 0;
      }
    } catch (e) {
      dlog(() => '⚠️ [Orchestrator] خطأ في تحميل المقاييس: $e');
    }
  }

  Future<void> _persistMetrics() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'sync_orchestrator_metrics',
        jsonEncode(_metrics.toJson()),
      );
    } catch (e) {
      dlog(() => '⚠️ [Orchestrator] خطأ في حفظ المقاييس: $e');
    }
  }

  void _setState(OrchestratorState newState) {
    if (_state == newState) {
      return;
    }
    _state = newState;
    _stateController.add(newState);
    dlog(() => '🔄 [Orchestrator] الحالة: ${newState.name}');
  }

  void pause() {
    if (_state == OrchestratorState.syncing ||
        _state == OrchestratorState.idle) {
      _setState(OrchestratorState.paused);
    }
  }

  void resume() {
    if (_state == OrchestratorState.paused) {
      _setState(OrchestratorState.idle);
      _processTasks();
    }
  }

  Future<void> forceSync() async {
    if (_state == OrchestratorState.syncing) {
      return;
    }
    _setState(OrchestratorState.idle);
    await _processTasks();
  }

  void dispose() {
    _setState(OrchestratorState.disposed);
    _healthCheckTimer?.cancel();
    _taskProcessorTimer?.cancel();
    _connectivitySubscription?.cancel();
    _stateController.close();
    _healthController.close();
    _metricsController.close();
    for (final cb in _circuitBreakers.values) {
      cb.dispose();
    }
    _circuitBreakers.clear();
    _taskQueue.clear();
    _instance = null;
  }
}
