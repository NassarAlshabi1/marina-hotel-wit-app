/// قالب PDF لتقرير الديون — نظام قوالب مستقل.
///
/// هذا هو التقرير الوحيد المعني بالديون (المستحقات غير المسددة).
/// الشاشة تُمرّر بيانات فقط، والقالب يتولى التصميم كاملاً من نظام
/// التصميم الموحّد في lib/src/pdf/enhanced_pdf_utils.dart.
library;

import 'package:pdf/pdf.dart' show PdfColor;
import 'package:pdf/widgets.dart' as pw;

import '../enhanced_pdf_utils.dart';
import '../report_pdf_builder.dart';

/// ملخص دين نزيل واحد.
class DebtsReportGuestSummary {
  DebtsReportGuestSummary({
    required this.guestName,
    required this.totalAmount,
    required this.paidAmount,
    required this.remainingAmount,
  });

  final String guestName;
  final double totalAmount;
  final double paidAmount;
  final double remainingAmount;
}

/// صف سجل دين تفصيلي.
class DebtsReportDetailRow {
  DebtsReportDetailRow({
    required this.guestName,
    required this.recordedDate,
    required this.roomPrice,
    required this.totalAmount,
    required this.paidAmount,
    required this.remainingAmount,
    required this.reason,
    required this.isSettled,
  });

  final String guestName;

  /// تاريخ التسجيل منسّقاً (dd/MM/yyyy) أو '-'.
  final String recordedDate;

  /// سعر الغرفة لليلة الواحدة.
  final double roomPrice;
  final double totalAmount;
  final double paidAmount;
  final double remainingAmount;
  final String reason;
  final bool isSettled;
}

/// بيانات تقرير الديون.
class DebtsReportData {
  DebtsReportData({
    required this.guestSummaries,
    required this.detailRows,
    required this.totalDebt,
    required this.totalPaid,
    required this.totalRemaining,
    required this.settledCount,
    required this.unsettledCount,
    this.fromDate,
    this.toDate,
  });

  final List<DebtsReportGuestSummary> guestSummaries;
  final List<DebtsReportDetailRow> detailRows;
  final double totalDebt;
  final double totalPaid;
  final double totalRemaining;
  final int settledCount;
  final int unsettledCount;
  final DateTime? fromDate;
  final DateTime? toDate;

  int get recordCount => detailRows.length;
  int get guestCount => guestSummaries.length;
}

/// قالب تقرير الديون.
class DebtsReportPdf {
  DebtsReportPdf._();

  /// مشاركة تقرير الديون.
  static Future<void> share(DebtsReportData data) async {
    final fromLabel = data.fromDate != null ? _fmt(data.fromDate!) : 'غير محدد';
    final toLabel = data.toDate != null ? _fmt(data.toDate!) : 'غير محدد';

    String fmt(double v) => EnhancedPdfUtils.formatNumber(v);

    await ReportPdfBuilder.buildAndShare(
      ReportPdfConfig(
        title: 'تقرير الديون',
        fromDate: data.fromDate,
        toDate: data.toDate,
        buildContent: (fonts) {
          final stats = pw.Row(
            children: [
              pw.Expanded(
                child: EnhancedPdfUtils.buildStatisticsBox(
                  title: 'إجمالي الديون',
                  value: fmt(data.totalDebt),
                  subtitle: '${data.guestCount} نزيل',
                  fonts: fonts,
                  color: PdfColors.danger,
                ),
              ),
              pw.SizedBox(width: 6),
              pw.Expanded(
                child: EnhancedPdfUtils.buildStatisticsBox(
                  title: 'المدفوع',
                  value: fmt(data.totalPaid),
                  subtitle: data.totalDebt > 0
                      ? '${(data.totalPaid / data.totalDebt * 100).toStringAsFixed(0)}%'
                      : '0%',
                  fonts: fonts,
                  color: PdfColors.success,
                ),
              ),
              pw.SizedBox(width: 6),
              pw.Expanded(
                child: EnhancedPdfUtils.buildStatisticsBox(
                  title: 'المتبقي',
                  value: fmt(data.totalRemaining),
                  subtitle: '${data.unsettledCount} غير مسدد',
                  fonts: fonts,
                  color: PdfColors.warning,
                ),
              ),
            ],
          );

          final metaInfoCard = EnhancedPdfUtils.buildInfoCard(
            title: 'تفاصيل التقرير',
            fonts: fonts,
            content: [
              EnhancedPdfUtils.buildKeyValueRow(
                fonts: fonts,
                label: 'التقرير',
                value: 'الديون',
              ),
              EnhancedPdfUtils.buildKeyValueRow(
                fonts: fonts,
                label: 'الفترة',
                value: 'من $fromLabel إلى $toLabel',
              ),
              EnhancedPdfUtils.buildKeyValueRow(
                fonts: fonts,
                label: 'عدد السجلات',
                value: data.recordCount.toString(),
              ),
              EnhancedPdfUtils.buildKeyValueRow(
                fonts: fonts,
                label: 'عدد النزلاء',
                value: data.guestCount.toString(),
              ),
              EnhancedPdfUtils.buildKeyValueRow(
                fonts: fonts,
                label: 'مسدد',
                value: '${data.settledCount} سجل',
              ),
              EnhancedPdfUtils.buildKeyValueRow(
                fonts: fonts,
                label: 'غير مسدد',
                value: '${data.unsettledCount} سجل',
              ),
            ],
          );

          final guestHeaders = [
            'النزيل',
            'إجمالي الدين',
            'المدفوع',
            'المتبقي',
          ];
          final guestColWidths = [140.0, 100.0, 100.0, 100.0];
          final guestData = data.guestSummaries
              .map(
                (guest) => [
                  guest.guestName,
                  fmt(guest.totalAmount),
                  fmt(guest.paidAmount),
                  fmt(guest.remainingAmount),
                ],
              )
              .toList();

          final guestSummaryCard = EnhancedPdfUtils.buildInfoCard(
            title: 'ملخص حسب النزلاء',
            fonts: fonts,
            content: [
              if (guestData.isEmpty)
                pw.Text(
                  'لا توجد بيانات',
                  style: pw.TextStyle(font: fonts.regular, fontSize: 11),
                )
              else
                EnhancedPdfUtils.buildProfessionalTable(
                  headers: guestHeaders,
                  data: guestData,
                  fonts: fonts,
                  columnFlex: guestColWidths,
                ),
            ],
          );

          final totalsCard = _buildTotalsCard(fonts, data, fmt);

          final detailHeaders = [
            '#',
            'النزيل',
            'التسجيل',
            'سعر الغرفة',
            'الإجمالي',
            'المدفوع',
            'المتبقي',
            'السبب',
            'الحالة',
          ];
          final detailColWidths = [
            25.0,
            80.0,
            60.0,
            55.0,
            60.0,
            60.0,
            60.0,
            75.0,
            55.0,
          ];
          final detailData = <List<String>>[];
          for (var i = 0; i < data.detailRows.length; i++) {
            final row = data.detailRows[i];
            detailData.add([
              (i + 1).toString(),
              row.guestName,
              row.recordedDate,
              fmt(row.roomPrice),
              fmt(row.totalAmount),
              fmt(row.paidAmount),
              fmt(row.remainingAmount),
              if (row.reason.isNotEmpty) row.reason else '-',
              if (row.isSettled) 'مسدد' else 'غير مسدد',
            ]);
          }
          // صف الإجمالي
          detailData.add([
            '',
            'الإجمالي',
            '',
            '',
            fmt(data.totalDebt),
            fmt(data.totalPaid),
            fmt(data.totalRemaining),
            '',
            '',
          ]);

          return [
            pw.SizedBox(height: 12),
            stats,
            pw.SizedBox(height: 12),
            metaInfoCard,
            pw.SizedBox(height: 12),
            guestSummaryCard,
            pw.SizedBox(height: 12),
            totalsCard,
            pw.SizedBox(height: 16),
            pw.Text(
              'تفاصيل السجلات',
              style: pw.TextStyle(font: fonts.bold, fontSize: 14),
            ),
            pw.SizedBox(height: 8),
            ...EnhancedPdfUtils.buildChunkedTable(
              headers: detailHeaders,
              data: detailData,
              fonts: fonts,
              columnFlex: detailColWidths,
            ),
          ];
        },
        fileName: ReportPdfBuilder.generateFileName('تقرير الديون'),
      ),
    );
  }

  /// بطاقة الإجماليات الثلاثة (ديون/مدفوع/متبقي).
  static pw.Widget _buildTotalsCard(
    ArabicPdfFonts fonts,
    DebtsReportData data,
    String Function(double) fmt,
  ) {
    pw.Widget buildTotalLine(String title, String value, PdfColor color) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 4),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(
                font: fonts.bold,
                fontSize: 12,
                color: color,
              ),
            ),
            pw.Text(
              value,
              style: pw.TextStyle(
                font: fonts.bold,
                fontSize: 13,
                color: color,
              ),
            ),
          ],
        ),
      );
    }

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: PdfColors.backgroundLight,
        border: pw.Border.all(color: PdfColors.primary, width: 0.5),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Column(
        children: [
          buildTotalLine(
            'إجمالي الديون',
            fmt(data.totalDebt),
            PdfColors.danger,
          ),
          pw.Divider(color: PdfColors.textLight),
          buildTotalLine(
            'المدفوع',
            fmt(data.totalPaid),
            PdfColors.success,
          ),
          pw.Divider(color: PdfColors.textLight),
          buildTotalLine(
            'المتبقي',
            fmt(data.totalRemaining),
            PdfColors.warning,
          ),
        ],
      ),
    );
  }

  static String _fmt(DateTime d) => EnhancedPdfUtils.formatDateShort(d);
}
