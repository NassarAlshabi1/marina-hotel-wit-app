// ============================================================================
//  Marina Hotel — PDF Generation Benchmark
//  ============================================================================
//  يقيس أداء توليد PDF باستخدام package:pdf (يُستخدم بكثرة في التقارير).
//
//  المقاييس:
//    1. زمن تحميل خطوط عربية (Tajawal-Regular.ttf + Tajawal-Bold.ttf)
//    2. زمن بناء PDF بسيط (10 صفوف)
//    3. زمن بناء PDF متوسط (100 صف)
//    4. زمن بناء PDF كبير (500 صف)
//    5. زمن حفظ PDF كـ Uint8List (save())
//    6. مقارنة memory delta عبر أحجام مختلفة
//
//  التشغيل:
//    flutter test test/performance/pdf_generation_benchmark_test.dart \
//      --reporter=expanded
// ============================================================================

// ignore_for_file: lines_longer_than_80_chars, avoid_redundant_argument_values

import 'dart:io' show File, ProcessInfo;
import 'dart:typed_data' show ByteData, Uint8List;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;

/// يحمّل خط Tajawal من ملف مباشرة (يتجنب rootBundle الذي قد يفشل في tests).
Future<pw.Font> _loadFont(String path) async {
  final bytes = await File(path).readAsBytes();
  return pw.Font.ttf(ByteData.sublistView(bytes));
}

/// يبني PDF بعدد صفوف محدد.
Future<pw.Document> _buildPdf({
  required pw.Font regular,
  required pw.Font bold,
  required int rowCount,
  required String title,
}) async {
  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
      header: (context) => pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 8),
        decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(width: 1)),
        ),
        child: pw.Text(
          title,
          style: pw.TextStyle(font: bold, fontSize: 18),
        ),
      ),
      footer: (context) => pw.Container(
        alignment: pw.Alignment.center,
        child: pw.Text(
          'صفحة ${context.pageNumber} من ${context.pagesCount}',
          style: pw.TextStyle(font: regular, fontSize: 9),
        ),
      ),
      build: (context) => [
        pw.TableHelper.fromTextArray(
          context: context,
          data: List.generate(
            rowCount,
            (i) => ['${i + 1}', 'عنصر $i', '${(i + 1) * 10.5} ر.س', '2026-07-20'],
          ),
          cellStyle: pw.TextStyle(font: regular, fontSize: 10),
          headerStyle: pw.TextStyle(font: bold, fontSize: 11),
          cellAlignment: pw.Alignment.center,
          cellPadding: const pw.EdgeInsets.all(4),
        ),
      ],
    ),
  );
  return doc;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late pw.Font regularFont;
  late pw.Font boldFont;

  setUpAll(() async {
    // تحميل الخطوط مرة واحدة قبل كل الاختبارات (لا نُعيد تحميلها في كل test
    // لأن الـ font loading مكلف).
    regularFont = await _loadFont('assets/fonts/Tajawal-Regular.ttf');
    boldFont = await _loadFont('assets/fonts/Tajawal-Bold.ttf');
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  1. Font Loading Performance
  // ═══════════════════════════════════════════════════════════════════════════
  group('🔤 Font Loading Performance', () {
    test('تحميل Tajawal-Regular.ttf خلال < 100ms', () async {
      final stopwatch = Stopwatch()..start();
      await _loadFont('assets/fonts/Tajawal-Regular.ttf');
      stopwatch.stop();

      debugPrint('✓ Font load (Tajawal-Regular.ttf, 55KB): ${stopwatch.elapsedMilliseconds}ms');
      expect(stopwatch.elapsedMilliseconds, lessThan(100), reason: 'تحميل خط 55KB يجب أن يكون < 100ms');
    });

    test('تحميل Tajawal-Bold.ttf خلال < 100ms', () async {
      final stopwatch = Stopwatch()..start();
      await _loadFont('assets/fonts/Tajawal-Bold.ttf');
      stopwatch.stop();

      debugPrint('✓ Font load (Tajawal-Bold.ttf, 55KB): ${stopwatch.elapsedMilliseconds}ms');
      expect(stopwatch.elapsedMilliseconds, lessThan(100), reason: 'تحميل خط 55KB يجب أن يكون < 100ms');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  2. PDF Build — أحجام مختلفة
  // ═══════════════════════════════════════════════════════════════════════════
  group('📄 PDF Build Performance', () {
    test('بناء PDF بسيط (10 صفوف) خلال < 200ms', () async {
      final beforeBytes = ProcessInfo.currentRss;

      final stopwatch = Stopwatch()..start();
      await _buildPdf(
        regular: regularFont,
        bold: boldFont,
        rowCount: 10,
        title: 'تقرير بسيط',
      );
      stopwatch.stop();

      final afterBytes = ProcessInfo.currentRss;
      final deltaMB = (afterBytes - beforeBytes) / (1024 * 1024);

      debugPrint('✓ PDF build (10 rows): ${stopwatch.elapsedMilliseconds}ms, mem=+${deltaMB.toStringAsFixed(2)}MB');
      expect(stopwatch.elapsedMilliseconds, lessThan(200), reason: 'PDF بسيط يجب أن يُبنى خلال < 200ms');
    });

    test('بناء PDF متوسط (100 صف) خلال < 500ms', () async {
      final beforeBytes = ProcessInfo.currentRss;

      final stopwatch = Stopwatch()..start();
      await _buildPdf(
        regular: regularFont,
        bold: boldFont,
        rowCount: 100,
        title: 'تقرير متوسط',
      );
      stopwatch.stop();

      final afterBytes = ProcessInfo.currentRss;
      final deltaMB = (afterBytes - beforeBytes) / (1024 * 1024);

      debugPrint('✓ PDF build (100 rows): ${stopwatch.elapsedMilliseconds}ms, mem=+${deltaMB.toStringAsFixed(2)}MB');
      expect(stopwatch.elapsedMilliseconds, lessThan(500), reason: 'PDF متوسط يجب أن يُبنى خلال < 500ms');
    });

    test('بناء PDF كبير (500 صف) خلال < 2 ثانية', () async {
      final beforeBytes = ProcessInfo.currentRss;

      final stopwatch = Stopwatch()..start();
      await _buildPdf(
        regular: regularFont,
        bold: boldFont,
        rowCount: 500,
        title: 'تقرير كبير',
      );
      stopwatch.stop();

      final afterBytes = ProcessInfo.currentRss;
      final deltaMB = (afterBytes - beforeBytes) / (1024 * 1024);

      debugPrint('✓ PDF build (500 rows): ${stopwatch.elapsedMilliseconds}ms, mem=+${deltaMB.toStringAsFixed(2)}MB');
      expect(stopwatch.elapsedMilliseconds, lessThan(2000), reason: 'PDF كبير يجب أن يُبنى خلال < 2 ثانية');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  3. PDF Save — تحويل إلى Uint8List
  // ═══════════════════════════════════════════════════════════════════════════
  group('💾 PDF Save Performance', () {
    test('save PDF (100 صف) خلال < 300ms', () async {
      final doc = await _buildPdf(
        regular: regularFont,
        bold: boldFont,
        rowCount: 100,
        title: 'تقرير للحفظ',
      );

      final stopwatch = Stopwatch()..start();
      final Uint8List bytes = await doc.save();
      stopwatch.stop();

      debugPrint('✓ PDF save (100 rows): ${stopwatch.elapsedMilliseconds}ms, size=${bytes.length} bytes');
      expect(stopwatch.elapsedMilliseconds, lessThan(300), reason: 'save PDF يجب أن يكون < 300ms');
      expect(bytes.length, greaterThan(0));
    });

    test('save PDF (500 صف) خلال < 1 ثانية', () async {
      final doc = await _buildPdf(
        regular: regularFont,
        bold: boldFont,
        rowCount: 500,
        title: 'تقرير كبير للحفظ',
      );

      final stopwatch = Stopwatch()..start();
      final Uint8List bytes = await doc.save();
      stopwatch.stop();

      debugPrint('✓ PDF save (500 rows): ${stopwatch.elapsedMilliseconds}ms, size=${bytes.length} bytes');
      expect(stopwatch.elapsedMilliseconds, lessThan(1000), reason: 'save PDF كبير يجب أن يكون < 1 ثانية');
      expect(bytes.length, greaterThan(0));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  4. Scaling — مقارنة linear vs non-linear growth
  // ═══════════════════════════════════════════════════════════════════════════
  group('📈 PDF Scaling Analysis', () {
    test('مقارنة زمن البناء عبر أحجام مختلفة', () async {
      final sizes = [10, 50, 100, 200, 500];
      final times = <int, int>{};

      for (final size in sizes) {
        final stopwatch = Stopwatch()..start();
        await _buildPdf(
          regular: regularFont,
          bold: boldFont,
          rowCount: size,
          title: 'تقرير $size',
        );
        stopwatch.stop();
        times[size] = stopwatch.elapsedMilliseconds;
      }

      debugPrint('✓ PDF scaling analysis:');
      for (final size in sizes) {
        debugPrint('  $size rows: ${times[size]}ms (${(times[size]! / size).toStringAsFixed(2)}ms/row)');
      }

      // التحقق أن النمو شبه خطي (كل صف يضيف ≤ 5ms)
      for (final size in sizes) {
        final perRow = times[size]! / size;
        expect(perRow, lessThan(5), reason: '$size rows: زمن لكل صف يجب أن يكون < 5ms');
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  5. تقرير نهائي
  // ═══════════════════════════════════════════════════════════════════════════
  group('📊 PDF Benchmark Summary', () {
    test('طباعة ملخص مقاييس PDF', () {
      debugPrint('');
      debugPrint('═══════════════════════════════════════════════════════════');
      debugPrint('  📊 PDF Generation Benchmark — Summary');
      debugPrint('═══════════════════════════════════════════════════════════');
      debugPrint('  يقيس:');
      debugPrint('    • Font loading (Tajawal-Regular + Bold)');
      debugPrint('    • PDF build (10/100/500 rows)');
      debugPrint('    • PDF save (Uint8List)');
      debugPrint('    • Scaling analysis (ms/row)');
      debugPrint('  Package: pdf 3.12.0 + Tajawal fonts (Arabic RTL)');
      debugPrint('═══════════════════════════════════════════════════════════');
      expect(true, isTrue);
    });
  });
}
