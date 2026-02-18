import 'dart:async';
import 'package:flutter/foundation.dart';
import 'local_db.dart';

class DatabaseHealthChecker {
  DatabaseHealthChecker._();

  static final DatabaseHealthChecker instance = DatabaseHealthChecker._();

  final _healthStreamController = StreamController<DatabaseHealth>.broadcast();
  Timer? _healthCheckTimer;

  DatabaseHealth _lastHealth = DatabaseHealth.healthy();

  Stream<DatabaseHealth> get healthStream => _healthStreamController.stream;

  DatabaseHealth get currentHealth => _lastHealth;

  void startMonitoring({Duration interval = const Duration(seconds: 30)}) {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(interval, (_) => _checkHealth());
  }

  void stopMonitoring() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;
  }

  Future<void> _checkHealth() async {
    try {
      if (!DatabaseManager.isInitialized) {
        _updateHealth(DatabaseHealth.notInitialized());
        return;
      }

      final stopwatch = Stopwatch()..start();
      final db = DatabaseManager.instance;

      await db.customStatement('SELECT 1');

      stopwatch.stop();
      final responseTime = stopwatch.elapsedMilliseconds;

      if (responseTime > 1000) {
        _updateHealth(DatabaseHealth.slow(responseTime));
      } else {
        _updateHealth(DatabaseHealth.healthy(responseTime));
      }
    } catch (e) {
      debugPrint('❌ Database health check failed: $e');
      _updateHealth(DatabaseHealth.error(e.toString()));
    }
  }

  void _updateHealth(DatabaseHealth health) {
    _lastHealth = health;
    if (!_healthStreamController.isClosed) {
      _healthStreamController.add(health);
    }
  }

  Future<bool> ensureHealthy({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (!DatabaseManager.isInitialized) {
      debugPrint('⚠️ Database not initialized');
      return false;
    }

    try {
      final db = DatabaseManager.instance;
      await db.customStatement('SELECT 1').timeout(timeout);
      return true;
    } catch (e) {
      debugPrint('❌ Database health check failed: $e');
      return false;
    }
  }

  Future<T> withHealthCheck<T>(Future<T> Function() operation) async {
    if (!await ensureHealthy()) {
      throw StateError('Database is not healthy');
    }
    return await operation();
  }

  void dispose() {
    stopMonitoring();
    _healthStreamController.close();
  }
}

class DatabaseHealth {
  final DatabaseHealthStatus status;
  final int? responseTimeMs;
  final String? errorMessage;
  final DateTime timestamp;

  const DatabaseHealth._({
    required this.status,
    this.responseTimeMs,
    this.errorMessage,
    required this.timestamp,
  });

  factory DatabaseHealth.healthy([int? responseTime]) => DatabaseHealth._(
    status: DatabaseHealthStatus.healthy,
    responseTimeMs: responseTime,
    timestamp: DateTime.now(),
  );

  factory DatabaseHealth.slow(int responseTime) => DatabaseHealth._(
    status: DatabaseHealthStatus.slow,
    responseTimeMs: responseTime,
    timestamp: DateTime.now(),
  );

  factory DatabaseHealth.notInitialized() => DatabaseHealth._(
    status: DatabaseHealthStatus.notInitialized,
    timestamp: DateTime.now(),
  );

  factory DatabaseHealth.error(String message) => DatabaseHealth._(
    status: DatabaseHealthStatus.error,
    errorMessage: message,
    timestamp: DateTime.now(),
  );

  bool get isHealthy =>
      status == DatabaseHealthStatus.healthy ||
      status == DatabaseHealthStatus.slow;
}

enum DatabaseHealthStatus { healthy, slow, notInitialized, error }
