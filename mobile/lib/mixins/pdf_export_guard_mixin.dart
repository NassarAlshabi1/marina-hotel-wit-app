import 'package:flutter/material.dart';

/// حماية موحّدة لعمليات تصدير/طباعة/مشاركة PDF في شاشات التقارير.
///
/// كانت شاشات التقارير تستدعي دوال تصدير PDF مباشرة (غالباً عبر
/// `unawaited(...)`) بلا `try/catch` وبلا حماية من الضغط المتكرر على الزر.
/// أي استثناء أثناء بناء المستند (فشل تحميل الخط، خطأ تخطيط، مساحة تخزين
/// ممتلئة...) كان يختفي بصمت ويُشعر المستخدم بأن التطبيق "توقف"، وكان
/// بالإمكان الضغط على زر التصدير عدة مرات فيتراكم أكثر من بناء PDF ثقيل
/// في نفس الوقت.
///
/// استخدم [runProtectedPdfExport] لتغليف أي عملية تصدير/طباعة/حفظ PDF:
/// ```dart
/// Future<void> _exportPdf() async {
///   if (_rows.isEmpty) return;
///   await runProtectedPdfExport(() async {
///     await ReportPdfBuilder.buildAndShare(config);
///   });
/// }
/// ```
mixin PdfExportGuardMixin<T extends StatefulWidget> on State<T> {
  bool _pdfExporting = false;

  /// true أثناء تنفيذ عملية تصدير/طباعة PDF — استخدمه لتعطيل زر التصدير.
  bool get isPdfExporting => _pdfExporting;

  /// ينفّذ [action] مع حماية من:
  /// - التنفيذ المتزامن المتكرر (ضغط المستخدم على الزر أكثر من مرة أثناء
  ///   بناء تقرير ثقيل).
  /// - الأخطاء غير المُعالجة (تظهر الآن كرسالة `SnackBar` بدل تجميد صامت).
  Future<void> runProtectedPdfExport(
    Future<void> Function() action, {
    String errorPrefix = 'تعذر تصدير التقرير',
  }) async {
    if (_pdfExporting) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _pdfExporting = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('$errorPrefix: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _pdfExporting = false);
      }
    }
  }
}
