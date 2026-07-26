import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PerformanceMetrics {
  PerformanceMetrics({
    required this.operation,
    required this.duration,
    required this.recordsProcessed,
    required this.timestamp,
  });
  final String operation;
  final Duration duration;
  final int recordsProcessed;
  final DateTime timestamp;

  double get opsPerSecond => recordsProcessed / duration.inMilliseconds * 1000;
  String get durationMs => '${duration.inMilliseconds}ms';
}

class PerformanceState {
  PerformanceState({required this.metrics, required this.averageTimings, required this.isMonitoring});
  final List<PerformanceMetrics> metrics;
  final Map<String, double> averageTimings;
  final bool isMonitoring;

  PerformanceState copyWith({
    List<PerformanceMetrics>? metrics,
    Map<String, double>? averageTimings,
    bool? isMonitoring,
  }) {
    return PerformanceState(
      metrics: metrics ?? this.metrics,
      averageTimings: averageTimings ?? this.averageTimings,
      isMonitoring: isMonitoring ?? this.isMonitoring,
    );
  }
}

class PerformanceNotifier extends StateNotifier<PerformanceState> {
  PerformanceNotifier() : super(PerformanceState(metrics: [], averageTimings: {}, isMonitoring: kDebugMode));

  void recordOperation(PerformanceMetrics metric) {
    if (!state.isMonitoring) {
      return;
    }

    final newMetrics = List<PerformanceMetrics>.from(state.metrics)..add(metric);
    if (newMetrics.length > 100) {
      newMetrics.removeRange(0, newMetrics.length - 100);
    }

    final averages = _calculateAverages(newMetrics);

    state = state.copyWith(metrics: newMetrics, averageTimings: averages);

    if (metric.duration.inMilliseconds > 1000) {
      debugPrint('⚠️  Slow: ${metric.operation} = ${metric.durationMs}');
    }
  }

  Map<String, double> _calculateAverages(List<PerformanceMetrics> metrics) {
    final Map<String, List<double>> byOperation = {};
    for (final m in metrics) {
      byOperation.putIfAbsent(m.operation, () => []).add(m.duration.inMilliseconds.toDouble());
    }
    return {for (final e in byOperation.entries) e.key: e.value.reduce((a, b) => a + b) / e.value.length};
  }

  Map<String, dynamic> getReport() {
    final slowest = state.metrics.where((m) => m.duration.inMilliseconds > 500).toList()
      ..sort((a, b) => a.duration.compareTo(b.duration));

    return {
      'monitoringEnabled': state.isMonitoring,
      'totalOperations': state.metrics.length,
      'averageTimings': state.averageTimings,
      'slowestOperations': slowest
          .take(5)
          .map((m) => {'operation': m.operation, 'duration': m.durationMs, 'records': m.recordsProcessed})
          .toList(),
    };
  }

  void toggleMonitoring(bool enabled) {
    state = state.copyWith(isMonitoring: enabled);
  }

  void clearMetrics() {
    state = state.copyWith(metrics: [], averageTimings: {});
  }
}

final performanceProvider = StateNotifierProvider<PerformanceNotifier, PerformanceState>((ref) {
  return PerformanceNotifier();
});

class PerformanceTimer {
  PerformanceTimer({required this.operation, required this.notifier, this.recordsProcessed = 0}) {
    _stopwatch.start();
  }
  final String operation;
  final PerformanceNotifier notifier;
  final int recordsProcessed;
  final Stopwatch _stopwatch = Stopwatch();

  void stop() {
    _stopwatch.stop();
    notifier.recordOperation(
      PerformanceMetrics(
        operation: operation,
        duration: _stopwatch.elapsed,
        recordsProcessed: recordsProcessed,
        timestamp: DateTime.now(),
      ),
    );
  }

  static Future<T> measure<T>(
    String operation,
    PerformanceNotifier notifier,
    Future<T> Function() fn, {
    int recordsProcessed = 0,
  }) async {
    final timer = PerformanceTimer(operation: operation, notifier: notifier, recordsProcessed: recordsProcessed);
    try {
      return await fn();
    } finally {
      timer.stop();
    }
  }
}

extension PerformanceExtension on PerformanceNotifier {
  Future<T> timed<T>(String operation, Future<T> Function() fn, {int records = 0}) async {
    return PerformanceTimer.measure(operation, this, fn, recordsProcessed: records);
  }
}
