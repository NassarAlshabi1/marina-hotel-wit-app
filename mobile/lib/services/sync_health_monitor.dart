import 'dart:async';

import 'package:marina_hotel_mobile/utils/app_logger.dart';
import 'package:marina_hotel_mobile/utils/prefs_cache.dart';

enum SyncHealthStatus { healthy, warning, critical, error }

class SyncHealthMetrics {
  const SyncHealthMetrics({
    required this.status,
    required this.consecutiveFailures,
    required this.lastSuccessAt,
    required this.lastFailureAt,
    required this.averageSyncDuration,
    required this.conflictRate,
    required this.dataLossRisk,
    this.recommendations = const [],
  });

  final SyncHealthStatus status;
  final int consecutiveFailures;
  final DateTime? lastSuccessAt;
  final DateTime? lastFailureAt;
  final Duration averageSyncDuration;
  final double conflictRate;
  final double dataLossRisk;
  final List<String> recommendations;
}

/// مراقب صحة المزامنة - يكتشف المشاكل ويقترح حلول
class SyncHealthMonitor {

  SyncHealthMonitor._();
  static final SyncHealthMonitor instance = SyncHealthMonitor._();

  final _metricsController = StreamController<SyncHealthMetrics>.broadcast();
  Stream<SyncHealthMetrics> get metricsStream => _metricsController.stream;

  int _consecutiveFailures = 0;
  DateTime? _lastSuccessAt;
  DateTime? _lastFailureAt;
  final List<Duration> _syncDurations = [];
  final List<bool> _hadConflicts = [];

  static const int _maxFailuresBeforeWarning = 3;
  static const int _maxFailuresBeforeCritical = 5;
  static const Duration _healthCheckInterval = Duration(minutes: 5);

  Timer? _healthCheckTimer;

  Future<void> initialize() async {
    await _loadMetrics();

    _healthCheckTimer = Timer.periodic(
      _healthCheckInterval,
      (_) => _performHealthCheck(),
    );

    AppLogger.info('🏥 بدء مراقبة صحة المزامنة');
  }

  void recordSyncSuccess({
    required Duration duration,
    required bool hadConflicts,
  }) {
    _consecutiveFailures = 0;
    _lastSuccessAt = DateTime.now();

    _syncDurations.add(duration);
    if (_syncDurations.length > 20) {
      _syncDurations.removeAt(0);
    }

    _hadConflicts.add(hadConflicts);
    if (_hadConflicts.length > 20) {
      _hadConflicts.removeAt(0);
    }

    _persistMetrics();
    _emitMetrics();
  }

  void recordSyncFailure() {
    _consecutiveFailures++;
    _lastFailureAt = DateTime.now();

    _persistMetrics();
    _emitMetrics();

    AppLogger.warning('⚠️ فشل المزامنة (المحاولة $_consecutiveFailures)');
  }

  Future<void> _performHealthCheck() async {
    final metrics = await getHealthMetrics();

    if (metrics.status == SyncHealthStatus.critical) {
      AppLogger.info('🚨 حالة المزامنة حرجة!');
      AppLogger.info(
  'توصيات: ${metrics.recommendations.join(', ')}',
);
    } else if (metrics.status == SyncHealthStatus.warning) {
      AppLogger.warning('⚠️ تحذير: ${metrics.recommendations.first}');
    }

    _metricsController.add(metrics);
  }

  Future<SyncHealthMetrics> getHealthMetrics() async {
    SyncHealthStatus status;
    final recommendations = <String>[];

    if (_consecutiveFailures >= _maxFailuresBeforeCritical) {
      status = SyncHealthStatus.critical;
      recommendations.add(
        'فشل المزامنة $_consecutiveFailures مرات متتالية - تحقق من الاتصال',
      );
      recommendations.add('جرب إعادة تسجيل الدخول في Google Drive');
    } else if (_consecutiveFailures >= _maxFailuresBeforeWarning) {
      status = SyncHealthStatus.warning;
      recommendations.add('فشل المزامنة عدة مرات - تحقق من الاتصال');
    } else if (_lastSuccessAt == null) {
      status = SyncHealthStatus.warning;
      recommendations.add('لم تتم أي مزامنة ناجحة بعد');
    } else {
      final timeSinceSuccess = DateTime.now().difference(_lastSuccessAt!);
      if (timeSinceSuccess.inHours > 24) {
        status = SyncHealthStatus.warning;
        recommendations.add(
          'آخر مزامنة ناجحة منذ ${timeSinceSuccess.inHours} ساعة',
        );
      } else {
        status = SyncHealthStatus.healthy;
      }
    }

    final avgDuration = _syncDurations.isEmpty
        ? Duration.zero
        : Duration(
            milliseconds:
                _syncDurations
                    .map((d) => d.inMilliseconds)
                    .reduce((a, b) => a + b) ~/
                _syncDurations.length,
          );

    final conflictRate = _hadConflicts.isEmpty
        ? 0.0
        : _hadConflicts.where((c) => c).length / _hadConflicts.length;

    if (conflictRate > 0.3) {
      if (!recommendations.contains('معدل تعارضات مرتفع')) {
        recommendations.add(
          'معدل تعارضات مرتفع (${(conflictRate * 100).toStringAsFixed(0)}%) - راجع أولويات الأجهزة',
        );
      }
    }

    final dataLossRisk = _calculateDataLossRisk();
    if (dataLossRisk > 0.5) {
      recommendations.add(
        'خطر فقدان بيانات مرتفع - راجع استراتيجية حل التعارضات',
      );
    }

    return SyncHealthMetrics(
      status: status,
      consecutiveFailures: _consecutiveFailures,
      lastSuccessAt: _lastSuccessAt,
      lastFailureAt: _lastFailureAt,
      averageSyncDuration: avgDuration,
      conflictRate: conflictRate,
      dataLossRisk: dataLossRisk,
      recommendations: recommendations,
    );
  }

  double _calculateDataLossRisk() {
    if (_consecutiveFailures >= 5) {
      return 0.8;
    }
    if (_consecutiveFailures >= 3) {
      return 0.5;
    }

    final timeSinceSuccess = _lastSuccessAt == null
        ? const Duration(days: 365)
        : DateTime.now().difference(_lastSuccessAt!);

    if (timeSinceSuccess.inHours > 48) {
      return 0.7;
    }
    if (timeSinceSuccess.inHours > 24) {
      return 0.4;
    }

    return 0.1;
  }

  Future<void> _loadMetrics() async {
    final prefs = getSharedPrefs();
    _consecutiveFailures = prefs.getInt('sync_health_failures') ?? 0;

    final successStr = prefs.getString('sync_health_last_success');
    if (successStr != null) {
      _lastSuccessAt = DateTime.tryParse(successStr);
    }

    final failureStr = prefs.getString('sync_health_last_failure');
    if (failureStr != null) {
      _lastFailureAt = DateTime.tryParse(failureStr);
    }
  }

  Future<void> _persistMetrics() async {
    final prefs = getSharedPrefs();
    await prefs.setInt('sync_health_failures', _consecutiveFailures);

    if (_lastSuccessAt != null) {
      await prefs.setString(
        'sync_health_last_success',
        _lastSuccessAt!.toIso8601String(),
      );
    }

    if (_lastFailureAt != null) {
      await prefs.setString(
        'sync_health_last_failure',
        _lastFailureAt!.toIso8601String(),
      );
    }
  }

  void _emitMetrics() {
    getHealthMetrics().then((metrics) {
      if (!_metricsController.isClosed) {
        _metricsController.add(metrics);
      }
    });
  }

  void dispose() {
    _healthCheckTimer?.cancel();
    _metricsController.close();
  }
}
