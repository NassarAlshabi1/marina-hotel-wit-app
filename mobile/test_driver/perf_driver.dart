// ============================================================================
//  Marina Hotel — Performance Driver
//  يستخدمه flutter drive لتشغيل integration tests + جمع Timeline
//  الاستخدام:
//    flutter drive \
//      --driver=test_driver/perf_driver.dart \
//      --target=integration_test/app_test.dart \
//      --profile \
//      -d chrome
// ============================================================================

import 'dart:async';
import 'dart:convert' show JsonEncoder;
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart' as driver;
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() {
  return integrationDriver(
    responseDataCallback: (data) async {
      if (data != null) {
        final outputDir = Directory('build/performance');
        if (!outputDir.existsSync()) {
          outputDir.createSync(recursive: true);
        }

        const encoder = JsonEncoder.withIndent('  ');

        for (final entry in data.entries) {
          final key = entry.key;
          final value = entry.value;

          if (value is Map<String, dynamic>) {
            try {
              final timeline = driver.Timeline.fromJson(value);
              final summary = driver.TimelineSummary.summarize(timeline);
              final summaryMap = summary.summaryJson;

              // حفظ الـ summary
              final summaryFile = File('${outputDir.path}/${key}_summary.json');
              await summaryFile.writeAsString(encoder.convert(summaryMap));
              print('✅ Saved: ${summaryFile.path}');

              // طباعة ملخص سريع
              print('');
              print('═══════════════════════════════════════════════════════════');
              print('  📊 Timeline Summary: $key');
              print('═══════════════════════════════════════════════════════════');
              print('  Frame count:              ${summaryMap['frame_count'] ?? 'N/A'}');
              print('  Avg frame build time:     ${summaryMap['average_frame_build_time_millis'] ?? 'N/A'} ms');
              print('  Worst frame build time:   ${summaryMap['worst_frame_build_time_millis'] ?? 'N/A'} ms');
              print('  Avg raster time:          ${summaryMap['average_frame_rasterizer_time_millis'] ?? 'N/A'} ms');
              print('  Worst raster time:        ${summaryMap['worst_frame_rasterizer_time_millis'] ?? 'N/A'} ms');
              print('  Missed build budget:      ${summaryMap['missed_frame_build_budget_count'] ?? 'N/A'}');
              print('  Missed raster budget:     ${summaryMap['missed_frame_rasterizer_budget_count'] ?? 'N/A'}');
              print('═══════════════════════════════════════════════════════════');
              print('');
            } catch (e) {
              print('⚠️ Failed to parse timeline for $key: $e');
              final rawFile = File('${outputDir.path}/${key}_raw.json');
              await rawFile.writeAsString(encoder.convert(value));
            }
          } else {
            final dataFile = File('${outputDir.path}/${key}_data.json');
            await dataFile.writeAsString(value.toString());
            print('✅ Saved: ${dataFile.path}');
          }
        }
      }
    },
  );
}
