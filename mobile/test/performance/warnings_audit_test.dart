// ignore_for_file: lines_longer_than_80_chars, avoid_print

/// يُشغّل benchmark_test.dart ثم يطبع تقرير الـ warnings التفصيلي
/// من PerformanceMonitor لفحص الأنواع والمصادر.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/utils/performance_monitor.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    PerformanceMonitor.instance.start();
  });

  tearDownAll(() async {
    final report = PerformanceMonitor.instance.exportReport();
    final warningsSection = report['warnings'] as Map<String, dynamic>;
    final totalWarnings = warningsSection['total'] as int? ?? 0;
    final criticalWarnings = warningsSection['critical'] as int? ?? 0;
    final warningSeverity = warningsSection['warning'] as int? ?? 0;
    final recentWarnings = warningsSection['recent'] as List<dynamic>? ?? [];

    print('\n═══════════════════════════════════════════════════════════');
    print('  📋 ملخص الـ warnings');
    print('═══════════════════════════════════════════════════════════');
    print('  إجمالي الـ warnings: $totalWarnings');
    print('  • critical: $criticalWarnings');
    print('  • warning: $warningSeverity');
    print('');

    if (recentWarnings.isEmpty) {
      print('  لا توجد recent warnings (آخر 10).');
    } else {
      print('  📄 آخر ${recentWarnings.length} warnings (recent):');
      for (var i = 0; i < recentWarnings.length; i++) {
        final m = recentWarnings[i] as Map<String, dynamic>;
        print('  ${i + 1}. [${m['severity']}] ${m['type']}');
        print('     message: ${m['message']}');
        if (m['suggestion'] != null) {
          print('     suggestion: ${m['suggestion']}');
        }
      }
    }
    print('═══════════════════════════════════════════════════════════\n');

    // حفظ التقرير الكامل في ملف
    final jsonStr = PerformanceMonitor.instance.exportReportJson();
    final outFile = File('/home/z/my-project/scripts/perf_report.json');
    await outFile.writeAsString(jsonStr);
    print('💾 تم حفظ التقرير الكامل في: ${outFile.path}');

    PerformanceMonitor.instance.stop();
  });

  test('جمع warnings', () async {
    // محاكاة benchmark_test.dart الأصلي — هذان هما المصدران للـ 50 warnings
    for (var i = 0; i < 70; i++) {
      PerformanceMonitor.instance.recordRebuild('ExcessiveWidget');
    }
    for (var i = 0; i < 100; i++) {
      PerformanceMonitor.instance.recordRebuild('StreamTestWidget');
    }
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(true, isTrue);
  });
}
