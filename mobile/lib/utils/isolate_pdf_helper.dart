/// ============================================================
/// Marina Hotel - Isolate PDF Helper
/// ============================================================
/// معالج PDF باستخدام Isolate لمنع حظر واجهة المستخدم
/// العمليات الثقيلة: تقارير PDF شهرية، إيصالات متعددة، فواتير
/// ============================================================

import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

/// نتيجة معالجة PDF
class PdfResult {
  PdfResult({
    required this.success,
    this.filePath,
    this.errorMessage,
    this.elapsedMs,
  });

  final bool success;
  final String? filePath;
  final String? errorMessage;
  final int? elapsedMs;

  bool get isSuccess => success;
}

/// وسيط المعالجة بين الـ Isolate الرئيسي و Isolate الخلفية
class _PdfIsolatePayload {
  _PdfIsolatePayload({
    required this.sendPort,
    required this.data,
    required this.reportType,
  });

  final SendPort sendPort;
  final String data; // JSON-serialized report data
  final String reportType; // نوع التقرير
}

/// معالج PDF باستخدام Isolate
class IsolatePdfHelper {
  /// إنشاء PDF في Isolate منفصل
  /// [data] بيانات التقرير (سيتم تحويلها إلى JSON)
  /// [reportType] نوع التقرير (مثل 'receipt', 'monthly_report', 'invoice')
  /// return: [PdfResult] نتيجة المعالجة
  static Future<PdfResult> generateInIsolate({
    required Map<String, dynamic> data,
    required String reportType,
  }) async {
    final startTime = DateTime.now();

    try {
      // إنشاء ReceivePort لاستقبال النتيجة من الـ Isolate
      final receivePort = ReceivePort();
      final completer = Completer<PdfResult>();

      // معالجة رسالة الـ Isolate
      receivePort.listen((message) {
        if (message is _PdfIsolatePayload) {
          // هذا هو sendPort من الـ Isolate
          // أرسل البيانات إلى الـ Isolate
          message.sendPort.send(data);
        } else if (message is Map<String, dynamic>) {
          // هذه هي النتيجة من الـ Isolate
          final result = PdfResult(
            success: message['success'] as bool? ?? false,
            filePath: message['filePath'] as String?,
            errorMessage: message['error'] as String?,
            elapsedMs: DateTime.now().difference(startTime).inMilliseconds,
          );
          receivePort.close();
          completer.complete(result);
        } else if (message is String && message.startsWith('ERROR:')) {
          final result = PdfResult(
            success: false,
            errorMessage: message.substring(6),
            elapsedMs: DateTime.now().difference(startTime).inMilliseconds,
          );
          receivePort.close();
          completer.complete(result);
        }
      });

      // إنشاء Isolate لمعالجة PDF
      await Isolate.spawn(
        _runPdfGeneration,
        receivePort.sendPort,
      );

      return await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          receivePort.close();
          return PdfResult(
            success: false,
            errorMessage: 'انتهت مهلة معالجة PDF (30 ثانية)',
            elapsedMs: DateTime.now().difference(startTime).inMilliseconds,
          );
        },
      );
    } catch (e, st) {
      debugPrint('❌ IsolatePdfHelper.generateInIsolate failed: $e\n$st');
      return PdfResult(
        success: false,
        errorMessage: e.toString(),
        elapsedMs: DateTime.now().difference(startTime).inMilliseconds,
      );
    }
  }

  /// دالة معالجة PDF داخل الـ Isolate
  static void _runPdfGeneration(SendPort sendPort) {
    // إنشاء ReceivePort لاستقبال البيانات
    final receivePort = ReceivePort();

    // إرسال sendPort إلى الـ Isolate الرئيسي
    sendPort.send(_PdfIsolatePayload(
      sendPort: receivePort.sendPort,
      reportType: '',
      data: '',
    ));

    // استقبال البيانات من الـ Isolate الرئيسي
    receivePort.listen((data) {
      try {
        if (data is Map<String, dynamic>) {
          final reportType = data['reportType'] as String? ?? 'unknown';
          final jsonData = data['data'] as Map<String, dynamic>? ?? {};

          // معالجة التقرير حسب النوع
          final result = _processReport(reportType, jsonData);

          // إرسال النتيجة إلى الـ Isolate الرئيسي
          sendPort.send(result);
        } else {
          sendPort.send({'success': false, 'error': 'بيانات غير صالحة'});
        }
      } catch (e) {
        sendPort.send({'success': false, 'error': e.toString()});
      } finally {
        receivePort.close();
      }
    });
  }

  /// معالجة التقرير حسب النوع
  static Map<String, dynamic> _processReport(
    String reportType,
    Map<String, dynamic> data,
  ) {
    switch (reportType) {
      case 'receipt':
        return _buildReceipt(data);
      case 'monthly_report':
        return _buildMonthlyReport(data);
      case 'invoice':
        return _buildInvoice(data);
      default:
        return {'success': false, 'error': 'نوع تقرير غير معروف: $reportType'};
    }
  }

  /// بناء إيصال دفع
  static Map<String, dynamic> _buildReceipt(Map<String, dynamic> data) {
    // TODO: تنفيذ بناء الإيصال باستخدام pdf package داخل الـ Isolate
    // حالياً: نعيد نجاح وهمي للاختبار
    return {
      'success': true,
      'filePath': '/tmp/receipt_${data['id'] ?? 'unknown'}.pdf',
    };
  }

  /// بناء تقرير شهري
  static Map<String, dynamic> _buildMonthlyReport(Map<String, dynamic> data) {
    // TODO: تنفيذ بناء التقرير الشهري
    return {
      'success': true,
      'filePath': '/tmp/monthly_report_${data['year']}_${data['month']}.pdf',
    };
  }

  /// بناء فاتورة
  static Map<String, dynamic> _buildInvoice(Map<String, dynamic> data) {
    // TODO: تنفيذ بناء الفاتورة
    return {
      'success': true,
      'filePath': '/tmp/invoice_${data['id'] ?? 'unknown'}.pdf',
    };
  }
}

/// استدعاء غير متزامن لإنشاء PDF في Isolate (للاستخدام في واجهة المستخدم)
/// تحميل فوري ولا يمنع الـ UI
Future<PdfResult> generatePdfAsync({
  required Map<String, dynamic> data,
  required String reportType,
}) async {
  // تشغيل في Isolate باستخدام compute
  return compute(
    _generatePdfInBackground,
    _IsolatePdfInput(data: data, reportType: reportType),
  );
}

/// مدخل الـ Isolate
class _IsolatePdfInput {
  _IsolatePdfInput({required this.data, required this.reportType});
  final Map<String, dynamic> data;
  final String reportType;
}

/// معالجة PDF في الخلفية
PdfResult _generatePdfInBackground(_IsolatePdfInput input) {
  try {
    final startTime = DateTime.now();

    // TODO: تنفيذ معالجة PDF الفعلية هنا
    // استخدام pdf package لإنشاء التقرير
    // هذا يعمل في Isolate منفصل، لا مانع من عمليات I/O

    return PdfResult(
      success: true,
      filePath: '/tmp/report_${DateTime.now().millisecondsSinceEpoch}.pdf',
      elapsedMs: DateTime.now().difference(startTime).inMilliseconds,
    );
  } catch (e) {
    return PdfResult(
      success: false,
      errorMessage: e.toString(),
    );
  }
}
