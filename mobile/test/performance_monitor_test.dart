// ============================================================================
//  PerformanceMonitor — Unit Tests
// ============================================================================
//  اختبارات مراقب الأداء (lib/utils/performance_monitor.dart):
//    - PerfWarning.toJson — بنية التصدير
//    - PerfTrace — elapsedMs و toJson قبل/بعد الإنهاء
//    - PerfConfig — القيم الافتراضية والتخصيص
//    - دورة الحياة: start/stop، الحارس ضد التشغيل المزدوج،
//      disabled config لا يبدأ، stop قبل start آمن
//    - التتبعات: startTrace/endTrace/measure/measureSync — النتائج،
//      سلامة finally عند الاستثناء، endTrace لاسم غير موجود
//    - recordRebuild: العدّادات وتحذير الكثافة فوق العتبة
//    - exportReport: بنية التقرير الكاملة
//    - performanceScore == 100 قبل البدء
//
//  ملاحظة عزل: PerformanceMonitor singleton — كل اختبار يستخدم أسماء
//  فريدة ويعتمد على الفروقات (deltas) لا القيم المطلقة، وstop() في
//  tearDown يضمن عدم بقاء مؤقتات نشطة (pending timers).
// ============================================================================

library marina_hotel_mobile.test.performance_monitor_test;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/utils/performance_monitor.dart';

void main() {
  // إعدادات بلا مؤقتات ولا مستمعات إطارات — عزل كامل عن الزمن الحقيقي
  const testConfig = PerfConfig(
    collectMemory: false,
    collectFrameTimings: false,
  );

  tearDown(() {
    // أمان مزدوج: لا مؤقتات معلقة بعد أي اختبار
    PerformanceMonitor.instance.stop();
  });

  group('PerfConfig', () {
    test('القيم الافتراضية معقولة', () {
      const config = PerfConfig();

      expect(config.enabled, isTrue);
      expect(config.fpsWarningThreshold, 45);
      expect(config.frameJankThresholdMs, 16);
      expect(config.rebuildWarningCount, 60);
      expect(config.memoryGrowthThresholdMB, 50);
      expect(config.collectFrameTimings, isTrue);
      expect(config.collectMemory, isTrue);
      expect(config.dashboardEnabled, isFalse);
    });
  });

  group('PerfWarning.toJson', () {
    test('يُصدِّر كل الحقول بالأسماء الصحيحة', () {
      final timestamp = DateTime(2026, 9, 24, 10);
      final warning = PerfWarning(
        type: PerfWarningType.lowFps,
        message: 'انخفض FPS',
        severity: PerfSeverity.critical,
        timestamp: timestamp,
        suggestion: 'قلّل الإعادة البناء',
        metadata: {'fps': 30},
      );
      final json = warning.toJson();

      expect(json['type'], 'lowFps');
      expect(json['message'], 'انخفض FPS');
      expect(json['severity'], 'critical');
      expect(json['timestamp'], timestamp.toIso8601String());
      expect(json['suggestion'], 'قلّل الإعادة البناء');
      expect(json['metadata'], {'fps': 30});
    });

    test('suggestion اختياري ويبقى null بدون قيمة', () {
      final warning = PerfWarning(
        type: PerfWarningType.jankFrame,
        message: 'إطار بطيء',
        severity: PerfSeverity.warning,
        timestamp: DateTime(2026, 1, 1),
      );

      expect(warning.toJson()['suggestion'], isNull);
    });
  });

  group('PerfTrace', () {
    test('endedAt null قبل الإنهاء وelapsedMs غير سالب', () {
      final trace = PerfTrace('op');

      expect(trace.endedAt, isNull);
      expect(trace.elapsedMs, greaterThanOrEqualTo(0));
      expect(trace.toJson()['endedAt'], isNull);
    });

    test('بعد الإنهاء: endedAt مضبوط وtoJson يشمل المدة والـ metadata', () {
      final trace = PerfTrace('db-query')..metadata = {'table': 'rooms'};
      trace.endedAt = trace.startedAt.add(const Duration(milliseconds: 42));

      expect(trace.elapsedMs, 42);
      final json = trace.toJson();

      expect(json['name'], 'db-query');
      expect(json['elapsedMs'], 42);
      expect(json['endedAt'], isNotNull);
      expect(json['metadata'], {'table': 'rooms'});
    });
  });

  group('PerformanceMonitor — دورة الحياة', () {
    test('performanceScore = 100 قبل البدء', () {
      PerformanceMonitor.instance.stop();

      expect(PerformanceMonitor.instance.performanceScore, 100);
    });

    test('start ثم stop يعملان بلا مؤقتات معلقة', () {
      final monitor = PerformanceMonitor.instance;

      monitor.start(config: testConfig);
      expect(monitor.exportReport()['started'], isTrue);

      monitor.stop();
      expect(monitor.exportReport()['started'], isFalse);
    });

    test('start مع enabled=false لا يبدأ المراقبة', () {
      final monitor = PerformanceMonitor.instance;

      monitor.start(config: const PerfConfig(enabled: false));

      expect(monitor.exportReport()['started'], isFalse);
    });

    test('stop قبل start آمن (no-op)', () {
      final monitor = PerformanceMonitor.instance;

      monitor.stop();

      expect(monitor.exportReport()['started'], isFalse);
    });
  });

  group('PerformanceMonitor — التتبعات', () {
    test('startTrace/endTrace يُسجلان تتبعاً مكتملًا', () {
      final monitor = PerformanceMonitor.instance;
      final before = monitor.exportReport()['traces']['completed'] as int;

      final started = monitor.startTrace('unit-trace-ok');
      final ended = monitor.endTrace('unit-trace-ok');

      expect(identical(started, ended), isTrue);
      final after = monitor.exportReport()['traces']['completed'] as int;
      expect(after, before + 1);
    });

    test('endTrace لاسم غير موجود يُرجع null ولا يُسجل شيئاً', () {
      final monitor = PerformanceMonitor.instance;
      final before = monitor.exportReport()['traces']['completed'] as int;

      expect(monitor.endTrace('unit-trace-ghost'), isNull);
      expect(
        monitor.exportReport()['traces']['completed'] as int,
        before,
      );
    });

    test(
      'measure يُرجع قيمة الـ action ويُنهي التتبع حتى مع الاستثناء',
      () async {
        final monitor = PerformanceMonitor.instance;
        final before = monitor.exportReport()['traces']['completed'] as int;

        final result = await monitor.measure('unit-measure-ok', () async => 7);

        expect(result, 7);
        expect(
          monitor.exportReport()['traces']['completed'] as int,
          before + 1,
        );

        // الاستثناء: finally يضمن إنهاء التتبع + الاستثناء ينتشر كما هو
        await expectLater(
          monitor.measure('unit-measure-throw', () async {
            throw StateError('boom');
          }),
          throwsStateError,
        );
        expect(
          monitor.exportReport()['traces']['completed'] as int,
          before + 2,
        );
      },
    );

    test('measureSync يُرجع القيمة ويُنهي التتبع', () {
      final monitor = PerformanceMonitor.instance;
      final before = monitor.exportReport()['traces']['completed'] as int;

      final result = monitor.measureSync('unit-measure-sync', () => 'ناتج');

      expect(result, 'ناتج');
      expect(
        monitor.exportReport()['traces']['completed'] as int,
        before + 1,
      );
    });
  });

  group('PerformanceMonitor — recordRebuild', () {
    test('يعدّ لكل widget ويجمع الإجمالي', () {
      final monitor = PerformanceMonitor.instance;
      const widget = 'RebuildCounterWidget#unit-1';
      final uniqueBefore = monitor.rebuildCounts.length;
      final totalBefore = monitor.totalRebuilds;

      monitor
        ..recordRebuild(widget)
        ..recordRebuild(widget)
        ..recordRebuild(widget);

      expect(monitor.rebuildCounts[widget], 3);
      expect(monitor.rebuildCounts.length, uniqueBefore + 1);
      expect(monitor.totalRebuilds, totalBefore + 3);
    });

    test('rebuildCounts غير قابل للتعديل من الخارج', () {
      final monitor = PerformanceMonitor.instance;

      expect(
        () => monitor.rebuildCounts['hack'] = 1,
        throwsUnsupportedError,
      );
    });

    test('يُطلق تحذير highRebuildCount فوق العتبة المخصصة', () async {
      final monitor = PerformanceMonitor.instance;
      monitor.start(
        config: const PerfConfig(
          collectMemory: false,
          collectFrameTimings: false,
          rebuildWarningCount: 2,
        ),
      );

      final received = <PerfWarning>[];
      final sub = monitor.warningStream.listen(received.add);
      const widget = 'HotWidget#unit-2';

      for (var i = 0; i < 4; i++) {
        monitor.recordRebuild(widget);
      }
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      final highRebuild = received
          .where((w) => w.type == PerfWarningType.highRebuildCount)
          .toList();
      expect(highRebuild, isNotEmpty);
      expect(highRebuild.first.metadata['widgetName'], widget);
      expect(highRebuild.first.metadata['count'], greaterThan(2));
      expect(highRebuild.first.severity, PerfSeverity.warning);
    });
  });

  group('PerformanceMonitor — exportReport', () {
    test('بنية التقرير الكاملة بمفاتيح الأقسام السبعة', () {
      final report = PerformanceMonitor.instance.exportReport();

      expect(report.containsKey('timestamp'), isTrue);
      expect(report.containsKey('platform'), isTrue);
      expect(report['started'], isA<bool>());
      expect(report['fps'], isA<Map<dynamic, dynamic>>());
      expect(report['memory'], isA<Map<dynamic, dynamic>>());
      expect(report['rebuilds'], isA<Map<dynamic, dynamic>>());
      expect(report['traces'], isA<Map<dynamic, dynamic>>());
      expect(report['warnings'], isA<Map<dynamic, dynamic>>());
      expect(report['score'], isA<int>());
    });

    test('exportReportJson يُنتج JSON نصياً صالحاً', () {
      final json = PerformanceMonitor.instance.exportReportJson();

      expect(json, contains('"score"'));
      expect(json, contains('"started"'));
    });
  });
}
