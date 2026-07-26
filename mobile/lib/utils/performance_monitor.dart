// ============================================================================
//  Marina Hotel — Performance Monitor (Lightweight Runtime Metrics)
//  ============================================================
//  بديل خفيف لـ flutter_performance_optimizer بدون أي dependency خارجي.
//  يُفعَّل فقط في kDebugMode — لا يصل لـ production APK.
//
//  الميزات:
//  - FPS tracker عبر SchedulerBinding.addTimingsCallback
//  - Rebuild counter عبر Element.rebuild hook
//  - Memory trend عبر dart:io Process
//  - Performance score (0-100) عبر 7 محاور
//  - Custom event tracking (stopwatch-based)
//  - Export تقرير كـ JSON للـ CI
//
//  الاستخدام:
//    1. في main(): PerformanceMonitor.instance.start()
//    2. قبل عملية حرجة: PerformanceMonitor.instance.startTrace('my_op')
//    3. بعدها: PerformanceMonitor.instance.endTrace('my_op')
//    4. للحصول على التقرير: PerformanceMonitor.instance.exportReport()
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, Platform, ProcessInfo;

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show FrameTiming, SchedulerBinding;

/// نوع التحذير الأدائي
enum PerfWarningType {
  lowFps,
  highRebuildCount,
  memoryGrowth,
  jankFrame,
  deepWidgetTree,
  excessiveSetState,
}

/// شدة التحذير
enum PerfSeverity { info, warning, critical }

/// تحذير أدائي
class PerfWarning {
  PerfWarning({
    required this.type,
    required this.message,
    required this.severity,
    required this.timestamp,
    this.suggestion,
    this.metadata = const {},
  });
  final PerfWarningType type;
  final String message;
  final PerfSeverity severity;
  final DateTime timestamp;
  final String? suggestion;
  final Map<String, dynamic> metadata;

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'message': message,
    'severity': severity.name,
    'timestamp': timestamp.toIso8601String(),
    'suggestion': suggestion,
    'metadata': metadata,
  };
}

/// تتبُّع عملية معينة (custom trace)
class PerfTrace {
  PerfTrace(this.name) : startedAt = DateTime.now();
  final String name;
  final DateTime startedAt;
  DateTime? endedAt;
  Map<String, dynamic>? metadata;

  int get elapsedMs =>
      (endedAt ?? DateTime.now()).difference(startedAt).inMilliseconds;

  Map<String, dynamic> toJson() => {
    'name': name,
    'startedAt': startedAt.toIso8601String(),
    'endedAt': endedAt?.toIso8601String(),
    'elapsedMs': elapsedMs,
    if (metadata != null) 'metadata': metadata,
  };
}

/// إعدادات المراقبة
class PerfConfig {
  const PerfConfig({
    this.enabled = true,
    this.fpsWarningThreshold = 45,
    this.frameJankThresholdMs = 16,
    this.rebuildWarningCount = 60,
    this.memoryGrowthThresholdMB = 50,
    this.maxWidgetDepth = 30,
    this.collectFrameTimings = true,
    this.collectMemory = true,
    this.collectTraces = true,
    this.dashboardEnabled = false, // افتراضياً معطَّل — يُفعَّل يدوياً
  });
  final bool enabled;
  final int fpsWarningThreshold;
  final int frameJankThresholdMs;
  final int rebuildWarningCount;
  final int memoryGrowthThresholdMB;
  final int maxWidgetDepth;
  final bool collectFrameTimings;
  final bool collectMemory;
  final bool collectTraces;
  final bool dashboardEnabled;
}

/// ════════════════════════════════════════════════════════════════════
///  Performance Monitor — Singleton خفيف بدون dependencies
/// ════════════════════════════════════════════════════════════════════
class PerformanceMonitor {
  PerformanceMonitor._internal();
  static final PerformanceMonitor instance = PerformanceMonitor._internal();

  // ═══════════════════════════════════════════════════════════════════
  //  الحالة
  // ═══════════════════════════════════════════════════════════════════
  PerfConfig _config = const PerfConfig();
  bool _started = false;

  // مقاييس FPS — نحتفظ بالـ FrameTiming + timestamp مسجّل يدوياً
  // لأن FrameTiming.timestamp قد لا يكون public في كل إصدارات Flutter
  final List<_FrameSample> _recentFrames = [];
  static const int _maxFrameSamples = 120; // ~2 ثانية @ 60fps
  int _totalFrames = 0;
  int _jankFrames = 0;
  DateTime? _firstFrameTime;

  // مقاييس الذاكرة
  final List<_MemorySample> _memorySamples = [];
  static const int _maxMemorySamples = 60; // ~1 دقيقة @ 1Hz
  Timer? _memoryTimer;

  // التتبُّعات النشطة
  final Map<String, PerfTrace> _activeTraces = {};
  final List<PerfTrace> _completedTraces = [];

  // التحذيرات
  final List<PerfWarning> _warnings = [];

  // العدّاد العام لإعادة البناء (يُحدَّث من PerformanceInspector)
  final Map<String, int> _rebuildCounts = {};
  int _totalRebuilds = 0;

  // Callbacks
  final _warningController = StreamController<PerfWarning>.broadcast();
  Stream<PerfWarning> get warningStream => _warningController.stream;

  // ═══════════════════════════════════════════════════════════════════
  //  التشغيل
  // ═══════════════════════════════════════════════════════════════════

  /// يبدأ المراقبة — يُستدعى مرة واحدة في main() قبل runApp
  void start({PerfConfig? config}) {
    if (!kDebugMode) {
      debugPrint('PerformanceMonitor: معطَّل في release mode');
      return;
    }
    if (_started) return;

    _config = config ?? _config;
    if (!_config.enabled) return;

    _started = true;

    if (_config.collectFrameTimings) {
      SchedulerBinding.instance.addTimingsCallback(_onFrameTiming);
    }

    if (_config.collectMemory && !kIsWeb) {
      _memoryTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _sampleMemory(),
      );
    }

    debugPrint(
      '🚀 PerformanceMonitor بدأ التشغيل (FPS: ${_config.fpsWarningThreshold}Hz threshold, '
      'memory: ${_config.memoryGrowthThresholdMB}MB threshold)',
    );
  }

  /// يُوقِف المراقبة ويُصدِر الموارد
  void stop() {
    if (!_started) return;
    _memoryTimer?.cancel();
    _memoryTimer = null;
    if (_config.collectFrameTimings) {
      SchedulerBinding.instance.removeTimingsCallback(_onFrameTiming);
    }
    _started = false;
    debugPrint('🛑 PerformanceMonitor توقَّف');
  }

  // ═══════════════════════════════════════════════════════════════════
  //  مقاييس FPS
  // ═══════════════════════════════════════════════════════════════════
  void _onFrameTiming(List<FrameTiming> timings) {
    final now = DateTime.now();
    _firstFrameTime ??= now;
    for (final t in timings) {
      _recentFrames.add(_FrameSample(timing: t, timestamp: now));
      _totalFrames++;

      final buildMs = t.buildDuration.inMilliseconds;
      final rasterMs = t.rasterDuration.inMilliseconds;
      final totalMs = buildMs + rasterMs;

      if (totalMs > _config.frameJankThresholdMs) {
        _jankFrames++;
        if (totalMs > _config.frameJankThresholdMs * 3) {
          _emitWarning(
            PerfWarningType.jankFrame,
            'إطار بطيء: ${totalMs}ms (build=$buildMs, raster=$rasterMs)',
            PerfSeverity.critical,
            suggestion:
                'استخدم RepaintBoundary أو أزل العمليات الثقيلة من build()',
            metadata: {
              'buildMs': buildMs,
              'rasterMs': rasterMs,
              'totalMs': totalMs,
            },
          );
        }
      }
    }
    if (_recentFrames.length > _maxFrameSamples) {
      _recentFrames.removeRange(0, _recentFrames.length - _maxFrameSamples);
    }
  }

  /// FPS الحالي (متوسط آخر 60 إطار)
  double get currentFps {
    if (_recentFrames.length < 2) return 0;
    final first = _recentFrames.first.timestamp;
    final last = _recentFrames.last.timestamp;
    final elapsed = last.difference(first);
    if (elapsed.inMicroseconds == 0) return 0;
    return (_recentFrames.length - 1) * 1000000 / elapsed.inMicroseconds;
  }

  /// متوسط زمن الإطار (build + raster) بالملي ثانية
  double get averageFrameTimeMs {
    if (_recentFrames.isEmpty) return 0;
    var sum = 0.0;
    for (final sample in _recentFrames) {
      final t = sample.timing;
      sum += t.buildDuration.inMilliseconds + t.rasterDuration.inMilliseconds;
    }
    return sum / _recentFrames.length;
  }

  // ═══════════════════════════════════════════════════════════════════
  //  مقاييس الذاكرة
  // ═══════════════════════════════════════════════════════════════════
  void _sampleMemory() {
    if (kIsWeb) return;
    try {
      final currentRss = ProcessInfo.currentRss;
      final maxRss = ProcessInfo.maxRss;
      _memorySamples.add(
        _MemorySample(
          timestamp: DateTime.now(),
          currentRssBytes: currentRss,
          maxRssBytes: maxRss,
        ),
      );
      if (_memorySamples.length > _maxMemorySamples) {
        _memorySamples.removeRange(
          0,
          _memorySamples.length - _maxMemorySamples,
        );
      }

      // كشف نمو الذاكرة المشبوه
      if (_memorySamples.length >= 30) {
        final firstHalf = _memorySamples.sublist(0, 15);
        final secondHalf = _memorySamples.sublist(15);
        final avgFirst = _avg(firstHalf.map((s) => s.currentRssBytes));
        final avgSecond = _avg(secondHalf.map((s) => s.currentRssBytes));
        final growthMB = (avgSecond - avgFirst) / (1024 * 1024);
        if (growthMB > _config.memoryGrowthThresholdMB) {
          _emitWarning(
            PerfWarningType.memoryGrowth,
            'نمو الذاكرة: +${growthMB.toStringAsFixed(1)}MB خلال 30 ثانية',
            PerfSeverity.warning,
            suggestion:
                'تحقَّق من controllers/streams غير مُغلقة. استخدم MemoryTracker.trackDisposable()',
            metadata: {
              'growthMB': growthMB,
              'currentRssMB': currentRss / (1024 * 1024),
            },
          );
        }
      }
    } catch (_) {}
  }

  double get currentMemoryMB => _memorySamples.isEmpty
      ? 0
      : _memorySamples.last.currentRssBytes / (1024 * 1024);

  double get peakMemoryMB => _memorySamples.isEmpty
      ? 0
      : _memorySamples
                .map((s) => s.maxRssBytes)
                .reduce((a, b) => a > b ? a : b) /
            (1024 * 1024);

  // ═══════════════════════════════════════════════════════════════════
  //  التتبُّعات (Custom Traces)
  // ═══════════════════════════════════════════════════════════════════

  /// يبدأ تتبُّع عملية معينة — يُعيد معرّف العملية
  PerfTrace startTrace(String name, {Map<String, dynamic>? metadata}) {
    final trace = PerfTrace(name);
    if (metadata != null) trace.metadata = metadata;
    _activeTraces[name] = trace;
    return trace;
  }

  /// يُنهي تتبُّع عملية ويُسجِّلها
  PerfTrace? endTrace(String name, {Map<String, dynamic>? metadata}) {
    final trace = _activeTraces.remove(name);
    if (trace == null) return null;
    trace.endedAt = DateTime.now();
    if (metadata != null) {
      trace.metadata = {...?trace.metadata, ...metadata};
    }
    _completedTraces.add(trace);
    // احتفظ بآخر 100 تتبُّع فقط
    if (_completedTraces.length > 100) {
      _completedTraces.removeRange(0, _completedTraces.length - 100);
    }
    debugPrint('⏱️ [$name] ${trace.elapsedMs}ms');
    return trace;
  }

  /// ينفِّذ دالة ويقيس زمنها
  Future<T> measure<T>(String name, Future<T> Function() action) async {
    startTrace(name);
    try {
      final result = await action();
      return result;
    } finally {
      endTrace(name);
    }
  }

  /// نسخة متزامنة من measure
  T measureSync<T>(String name, T Function() action) {
    startTrace(name);
    try {
      return action();
    } finally {
      endTrace(name);
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  //  تتبُّع إعادة بناء الـ Widgets (عبر PerformanceInspector)
  // ═══════════════════════════════════════════════════════════════════
  void recordRebuild(String widgetName) {
    _rebuildCounts[widgetName] = (_rebuildCounts[widgetName] ?? 0) + 1;
    _totalRebuilds++;

    final count = _rebuildCounts[widgetName]!;
    if (count > _config.rebuildWarningCount) {
      _emitWarning(
        PerfWarningType.highRebuildCount,
        'الـ widget "$widgetName" أُعيد بناؤه $count مرة',
        PerfSeverity.warning,
        suggestion:
            'استخدم const constructor أو ValueListenableBuilder أو .select() في Riverpod',
        metadata: {'widgetName': widgetName, 'count': count},
      );
    }
  }

  Map<String, int> get rebuildCounts => Map.unmodifiable(_rebuildCounts);
  int get totalRebuilds => _totalRebuilds;

  // ═══════════════════════════════════════════════════════════════════
  //  التحذيرات
  // ═══════════════════════════════════════════════════════════════════
  void _emitWarning(
    PerfWarningType type,
    String message,
    PerfSeverity severity, {
    String? suggestion,
    Map<String, dynamic>? metadata,
  }) {
    final warning = PerfWarning(
      type: type,
      message: message,
      severity: severity,
      timestamp: DateTime.now(),
      suggestion: suggestion,
      metadata: metadata ?? {},
    );
    _warnings.add(warning);
    if (_warnings.length > 200) {
      _warnings.removeRange(0, _warnings.length - 200);
    }
    _warningController.add(warning);

    final icon = severity == PerfSeverity.critical ? '🔴' : '🟡';
    debugPrint('$icon [PerfWarning] $message');
    if (suggestion != null) debugPrint('   💡 $suggestion');
  }

  List<PerfWarning> get warnings => List.unmodifiable(_warnings);

  // ═══════════════════════════════════════════════════════════════════
  //  درجة الأداء (Performance Score 0-100)
  // ═══════════════════════════════════════════════════════════════════
  /// درجة شاملة من 0-100 عبر 7 محاور:
  /// FPS, frame time, jank ratio, memory stability, rebuild density,
  /// warning count, trace latency
  int get performanceScore {
    if (!_started) return 100;
    var score = 100;

    // 1. FPS (25 نقطة)
    final fps = currentFps;
    if (fps < _config.fpsWarningThreshold) {
      score -= 25;
    } else if (fps < 55) {
      score -= 10;
    } else if (fps < 58) {
      score -= 5;
    }

    // 2. زمن الإطار (15 نقطة)
    final avgFrameTime = averageFrameTimeMs;
    if (avgFrameTime > 32) {
      score -= 15;
    } else if (avgFrameTime > 20) {
      score -= 8;
    } else if (avgFrameTime > 16) {
      score -= 4;
    }

    // 3. نسبة الـ jank (15 نقطة)
    if (_totalFrames > 10) {
      final jankRatio = _jankFrames / _totalFrames;
      if (jankRatio > 0.20) {
        score -= 15;
      } else if (jankRatio > 0.10) {
        score -= 8;
      } else if (jankRatio > 0.05) {
        score -= 4;
      }
    }

    // 4. استقرار الذاكرة (15 نقطة)
    if (_memorySamples.length >= 30) {
      final growthMB =
          currentMemoryMB -
          (_memorySamples.first.currentRssBytes / (1024 * 1024));
      if (growthMB > _config.memoryGrowthThresholdMB) {
        score -= 15;
      } else if (growthMB > _config.memoryGrowthThresholdMB / 2) {
        score -= 8;
      }
    }

    // 5. كثافة إعادة البناء (10 نقطة)
    if (_totalRebuilds > 500) {
      score -= 10;
    } else if (_totalRebuilds > 200) {
      score -= 5;
    }

    // 6. عدد التحذيرات (10 نقطة)
    final criticalCount = _warnings
        .where((w) => w.severity == PerfSeverity.critical)
        .length;
    final warningCount = _warnings
        .where((w) => w.severity == PerfSeverity.warning)
        .length;
    score -= criticalCount * 5;
    score -= warningCount * 2;

    // 7. متوسط زمن التتبُّعات (10 نقاط)
    if (_completedTraces.isNotEmpty) {
      final avgTraceMs =
          _completedTraces.map((t) => t.elapsedMs).reduce((a, b) => a + b) /
          _completedTraces.length;
      if (avgTraceMs > 500) {
        score -= 10;
      } else if (avgTraceMs > 200) {
        score -= 5;
      }
    }

    return score.clamp(0, 100);
  }

  // ═══════════════════════════════════════════════════════════════════
  //  تصدير التقرير
  // ═══════════════════════════════════════════════════════════════════

  /// يُصدِّر كل المقاييس كـ JSON (للـ CI أو التحليل)
  Map<String, dynamic> exportReport() {
    return {
      'timestamp': DateTime.now().toIso8601String(),
      'platform': kIsWeb ? 'web' : Platform.operatingSystem,
      'started': _started,
      'fps': {
        'current': currentFps.toStringAsFixed(1),
        'averageFrameTimeMs': averageFrameTimeMs.toStringAsFixed(2),
        'totalFrames': _totalFrames,
        'jankFrames': _jankFrames,
        'jankRatio': _totalFrames > 0
            ? (_jankFrames / _totalFrames).toStringAsFixed(3)
            : '0',
      },
      'memory': {
        'currentMB': currentMemoryMB.toStringAsFixed(1),
        'peakMB': peakMemoryMB.toStringAsFixed(1),
        'samples': _memorySamples.length,
      },
      'rebuilds': {
        'total': _totalRebuilds,
        'uniqueWidgets': _rebuildCounts.length,
        'topWidgets': _topRebuiltWidgets(5),
      },
      'traces': {
        'completed': _completedTraces.length,
        'active': _activeTraces.length,
        'slowest': _slowestTraces(5),
      },
      'warnings': {
        'total': _warnings.length,
        'critical': _warnings
            .where((w) => w.severity == PerfSeverity.critical)
            .length,
        'warning': _warnings
            .where((w) => w.severity == PerfSeverity.warning)
            .length,
        'recent': _warnings.reversed.take(10).map((w) => w.toJson()).toList(),
      },
      'score': performanceScore,
    };
  }

  /// يُصدِّر التقرير كـ JSON string
  String exportReportJson() {
    return const JsonEncoder.withIndent('  ').convert(exportReport());
  }

  /// يحفظ التقرير في ملف (للـ CI artifact)
  Future<void> saveReportToFile(String path) async {
    final file = await File(path).writeAsString(exportReportJson());
    debugPrint('📊 Performance report saved to: ${file.path}');
  }

  /// يطبع ملخصاً في console
  void printSummary() {
    final report = exportReport();
    debugPrint('');
    debugPrint('═══════════════════════════════════════════════════════════');
    debugPrint('  📊 Marina Hotel — Performance Summary');
    debugPrint('═══════════════════════════════════════════════════════════');
    debugPrint('  Score:        ${report['score']}/100');
    debugPrint('  FPS:          ${(report['fps'] as Map)['current']}');
    debugPrint(
      '  Frame time:   ${(report['fps'] as Map)['averageFrameTimeMs']}ms avg',
    );
    debugPrint(
      '  Jank:         ${(report['fps'] as Map)['jankFrames']}/${(report['fps'] as Map)['totalFrames']} frames',
    );
    debugPrint(
      '  Memory:       ${(report['memory'] as Map)['currentMB']}MB current, '
      '${(report['memory'] as Map)['peakMB']}MB peak',
    );
    debugPrint(
      '  Rebuilds:     ${(report['rebuilds'] as Map)['total']} total '
      '(${(report['rebuilds'] as Map)['uniqueWidgets']} unique widgets)',
    );
    debugPrint(
      '  Warnings:     ${(report['warnings'] as Map)['critical']} critical, '
      '${(report['warnings'] as Map)['warning']} warnings',
    );
    debugPrint('═══════════════════════════════════════════════════════════');
    debugPrint('');
  }

  List<Map<String, dynamic>> _topRebuiltWidgets(int limit) {
    final sorted = _rebuildCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted
        .take(limit)
        .map((e) => {'widget': e.key, 'count': e.value})
        .toList();
  }

  List<Map<String, dynamic>> _slowestTraces(int limit) {
    final sorted = _completedTraces.toList()
      ..sort((a, b) => b.elapsedMs.compareTo(a.elapsedMs));
    return sorted.take(limit).map((t) => t.toJson()).toList();
  }

  double _avg(Iterable<int> values) {
    if (values.isEmpty) return 0;
    return values.reduce((a, b) => a + b) / values.length;
  }

  /// يُعيد ضبط كل المقاييس (مفيد لإعادة القياس بين الاختبارات)
  void reset() {
    _recentFrames.clear();
    _totalFrames = 0;
    _jankFrames = 0;
    _memorySamples.clear();
    _activeTraces.clear();
    _completedTraces.clear();
    _warnings.clear();
    _rebuildCounts.clear();
    _totalRebuilds = 0;
    debugPrint('🔄 PerformanceMonitor تمت إعادة ضبطه');
  }
}

/// ════════════════════════════════════════════════════════════════════
///  PerformanceInspector — Widget لالتفاف widgets محددة لقياس rebuild
/// ════════════════════════════════════════════════════════════════════
class PerformanceInspector extends StatelessWidget {
  const PerformanceInspector({
    required this.name,
    required this.child,
    super.key,
    this.showBadge = false,
    this.onRebuild,
  });
  final String name;
  final Widget child;
  final bool showBadge;
  final void Function(int count)? onRebuild;

  @override
  Widget build(BuildContext context) {
    if (kDebugMode) {
      PerformanceMonitor.instance.recordRebuild(name);
      onRebuild?.call(PerformanceMonitor.instance.rebuildCounts[name] ?? 1);
    }
    if (!showBadge) return child;
    // إذا showBadge=true، نُغلف الـ child بـ Stack يُظهر عدّاد صغير
    return Stack(
      children: [
        child,
        Positioned(
          top: 2,
          right: 2,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${PerformanceMonitor.instance.rebuildCounts[name] ?? 0}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// ════════════════════════════════════════════════════════════════════
///  MemoryTracker — تتبُّع disposables لكشف memory leaks
/// ════════════════════════════════════════════════════════════════════
class MemoryTracker {
  MemoryTracker._internal();
  static final MemoryTracker instance = MemoryTracker._internal();

  final Map<String, DateTime> _tracked = {};

  void trackDisposable(String id) {
    _tracked[id] = DateTime.now();
  }

  void markDisposed(String id) {
    _tracked.remove(id);
  }

  /// يُعيد الـ disposables غير المُغلقة (potential leaks)
  Map<String, Duration> get undisposed => _tracked.map(
    (id, time) => MapEntry(id, DateTime.now().difference(time)),
  );

  /// يطبع تقرير الـ leaks
  void printLeaks() {
    if (_tracked.isEmpty) {
      debugPrint('✅ MemoryTracker: لا توجد disposables غير مُغلقة');
      return;
    }
    debugPrint('⚠️ MemoryTracker: ${_tracked.length} disposables غير مُغلقة:');
    for (final entry in _tracked.entries) {
      debugPrint(
        '   • ${entry.key}: ${entry.value.difference(DateTime.now()).abs().inSeconds}s',
      );
    }
  }
}

/// عينة ذاكرة في نقطة زمنية
class _MemorySample {
  _MemorySample({
    required this.timestamp,
    required this.currentRssBytes,
    required this.maxRssBytes,
  });
  final DateTime timestamp;
  final int currentRssBytes;
  final int maxRssBytes;
}

/// عينة إطار مع timestamp مسجَّل يدوياً
/// (لأن FrameTiming.timestamp قد لا يكون public في كل إصدارات Flutter)
class _FrameSample {
  _FrameSample({required this.timing, required this.timestamp});
  final FrameTiming timing;
  final DateTime timestamp;
}
