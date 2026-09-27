/// قالب PDF لتقرير مدفوعات النزلاء — نظام قوالب مستقل.
///
/// الشاشة تُمرّر بيانات فقط (صفوف المدفوعات والإجماليات)، والقالب يتولى
/// التصميم كاملاً من نظام التصميم الموحّد في lib/src/pdf/enhanced_pdf_utils.dart.
library;

import 'package:pdf/widgets.dart' as pw;

import '../enhanced_pdf_utils.dart';
import '../report_pdf_builder.dart';

/// صف دفعة واحدة داخل تقرير المدفوعات.
class PaymentsReportRow {
  PaymentsReportRow({
    required this.paymentDate,
    required this.amount,
    required this.roomNumber,
    required this.payerName,
    required this.bookingCode,
    required this.paymentMethod,
  });

  /// تاريخ الدفعة (يُنسَّق داخل القالب على سطرين: تاريخ/وقت).
  final DateTime paymentDate;
  final double amount;
  final String roomNumber;
  final String payerName;

  /// رقم الحجز منسّقاً (مثال: 000123) أو 'غير متوفر'.
  final String bookingCode;

  /// طريقة الدفع بعد الترجمة للعربية (نقداً/بطاقة/تحويل/شيك).
  final String paymentMethod;
}

/// بيانات تقرير المدفوعات.
class PaymentsReportData {
  PaymentsReportData({
    required this.rows,
    required this.totalRoomPaid,
    required this.totalOtherPaid,
    required this.totalRemaining,
    required this.totalDue,
    this.fromDate,
    this.toDate,
    this.roomFilterLabel,
  });

  /// الصفوف مرتبة ترتيباً نهائياً (الأحدث أولاً) — القالب لا يعيد الترتيب.
  final List<PaymentsReportRow> rows;
  final DateTime? fromDate;
  final DateTime? toDate;

  /// مدفوعات الغرف (revenueType = room).
  final double totalRoomPaid;

  /// مدفوعات أخرى (أنواع إيراد غير الغرف).
  final double totalOtherPaid;

  /// إجمالي الأرصدة المتبقية على الحجوزات ذات الدفعات.
  final double totalRemaining;

  /// إجمالي المستحق على النزلاء (يظهر فقط عندما > 0).
  final double totalDue;

  /// تسمية فلتر الغرفة إن وُجد (تظهر في سطر الرأس الإضافي).
  final String? roomFilterLabel;
}

/// قالب تقرير مدفوعات النزلاء.
class PaymentsReportPdf {
  PaymentsReportPdf._();

  /// مشاركة تقرير مدفوعات النزلاء.
  static Future<void> share(PaymentsReportData data) async {
    final selectedRoomLabel = data.roomFilterLabel ?? '';

    final dataRows = [
      for (final row in data.rows)
        [
          row.bookingCode,
          row.payerName,
          row.roomNumber,
          row.paymentMethod,
          _formatPdfPaymentDate(row.paymentDate),
          EnhancedPdfUtils.formatNumber(row.amount),
        ],
    ];

    await ReportPdfBuilder.buildAndShare(
      ReportPdfConfig(
        title: 'مدفوعات النزلاء',
        fromDate: data.fromDate,
        toDate: data.toDate,
        compactHeader: true,
        extraHeaderLine: selectedRoomLabel.isNotEmpty
            ? 'الغرفة: $selectedRoomLabel'
            : null,
        buildContent: (fonts) => [
          pw.SizedBox(height: 8),
          pw.Text(
            'تفاصيل المدفوعات',
            style: PdfTextStyles.sectionTitle(fonts),
          ),
          pw.SizedBox(height: 6),
          ...EnhancedPdfUtils.buildChunkedTable(
            headers: _headers,
            data: dataRows,
            fonts: fonts,
            columnFlex: _columnFlex,
            alignments: _alignments,
          ),
          _buildCompactTotalsCard(fonts, data),
        ],
        fileName: ReportPdfBuilder.generateFileName('مدفوعات النزلاء'),
      ),
    );
  }

  static const List<String> _headers = [
    'رقم الحجز',
    'اسم النزيل',
    'الغرفة',
    'طريقة الدفع',
    'التاريخ',
    'المبلغ',
  ];

  /// توزيع FlexColumnWidth مناسب لحجم 12 عريض في ورقة A4.
  static const List<double> _columnFlex = [
    1.20, // رقم الحجز
    2.20, // اسم النزيل
    0.85, // الغرفة
    1.20, // طريقة الدفع
    1.30, // التاريخ
    1.25, // المبلغ
  ];

  static const List<pw.TextAlign> _alignments = [
    pw.TextAlign.center, // رقم الحجز
    pw.TextAlign.right, // اسم النزيل
    pw.TextAlign.center, // الغرفة
    pw.TextAlign.center, // طريقة الدفع
    pw.TextAlign.center, // التاريخ
    pw.TextAlign.center, // المبلغ
  ];

  /// تاريخ مختصر لخلايا جدول PDF: dd/MM/yyyy ثم HH:mm على سطرين.
  static String _formatPdfPaymentDate(DateTime value) {
    final date =
        '${value.day.toString().padLeft(2, '0')}/'
        '${value.month.toString().padLeft(2, '0')}/'
        '${value.year}';
    final time =
        '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
    return '$date\n$time';
  }

  /// بطاقة إجماليات مضغوطة لصفحة A4 — من نظام التصميم الموحّد.
  static pw.Widget _buildCompactTotalsCard(
    ArabicPdfFonts fonts,
    PaymentsReportData data,
  ) {
    final remainingColor = data.totalRemaining > 0
        ? PdfColors.danger
        : PdfColors.success;

    return pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.only(top: 10),
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: pw.BoxDecoration(
        color: PdfColors.cardBackground,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        border: pw.Border.all(color: PdfColors.border, width: 0.5),
      ),
      child: pw.Column(
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Row(
                children: [
                  pw.Text(
                    'إجمالي المدفوعات: ',
                    style: pw.TextStyle(
                      font: fonts.bold,
                      fontSize: 10.5,
                      color: PdfColors.textDark,
                    ),
                  ),
                  pw.Text(
                    EnhancedPdfUtils.formatNumber(
                      data.totalRoomPaid + data.totalOtherPaid,
                    ),
                    style: pw.TextStyle(
                      font: fonts.bold,
                      fontSize: 13,
                      color: PdfColors.secondary,
                    ),
                  ),
                ],
              ),
              pw.Row(
                children: [
                  pw.Text(
                    'المبلغ المتبقي: ',
                    style: pw.TextStyle(
                      font: fonts.bold,
                      fontSize: 10.5,
                      color: PdfColors.textDark,
                    ),
                  ),
                  pw.Text(
                    EnhancedPdfUtils.formatNumber(data.totalRemaining),
                    style: pw.TextStyle(
                      font: fonts.bold,
                      fontSize: 13,
                      color: remainingColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (data.totalDue > 0) ...[
            pw.SizedBox(height: 4),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.Text(
                  'إجمالي المستحق على النزلاء: ',
                  style: pw.TextStyle(
                    font: fonts.bold,
                    fontSize: 10.5,
                    color: PdfColors.textDark,
                  ),
                ),
                pw.Text(
                  EnhancedPdfUtils.formatNumber(data.totalDue),
                  style: pw.TextStyle(
                    font: fonts.bold,
                    fontSize: 13,
                    color: PdfColors.info,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
