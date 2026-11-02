/// قالب PDF لتقرير المصروفات — نظام قوالب مستقل.
///
/// الشاشة تُمرّر بيانات فقط، والقالب يتولى التصميم كاملاً من نظام
/// التصميم الموحّد في lib/src/pdf/enhanced_pdf_utils.dart.
library;

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart' show PdfColor;
import 'package:pdf/widgets.dart' as pw;

import '../../../utils/salary_expense_classification.dart';
import '../enhanced_pdf_utils.dart';
import '../report_pdf_builder.dart';

/// صف مصروف واحد.
class ExpensesReportRow {
  ExpensesReportRow({
    required this.date,
    required this.amount,
    required this.type,
    required this.description,
    this.employeeName,
    this.isSalaryWithdrawal = false,
  });

  final DateTime date;
  final double amount;
  final String type;
  final String description;

  /// اسم الموظف المرتبط (للمصروفات الرواتب) أو null.
  final String? employeeName;

  /// هل الصف مأخوذ من جدول سحوبات الرواتب (سحب يتيم بدون مصروف مقابل).
  final bool isSalaryWithdrawal;
}

/// إعدادات التسميات القابلة للتخصيص (شاشة المصروفات تُستخدم بأشكال متعددة).
class ExpensesReportLabels {
  const ExpensesReportLabels({
    this.title = 'تقرير المصروفات',
    this.typeLabel = 'نوع المصروف',
    this.totalSummaryLabel = 'إجمالي المصروفات',
    this.totalRowLabel = 'الإجمالي',
  });

  final String title;
  final String typeLabel;
  final String totalSummaryLabel;
  final String totalRowLabel;
}

/// بيانات تقرير المصروفات.
class ExpensesReportData {
  ExpensesReportData({
    required this.rows,
    required this.totalAmount,
    required this.hasSalaryData,
    required this.labels,
    this.fromDate,
    this.toDate,
    this.selectedTypeLabel = 'الكل',
  });

  /// الصفوف مرتبة نهائياً — القالب لا يعيد الترتيب.
  final List<ExpensesReportRow> rows;
  final double totalAmount;

  /// هل توجد بيانات رواتب (لإظهار عمود الموظف وملخص السحوبات تلقائياً).
  final bool hasSalaryData;
  final ExpensesReportLabels labels;
  final DateTime? fromDate;
  final DateTime? toDate;

  /// تسمية نوع المصروف المحدد بالفلتر أو 'الكل'.
  final String selectedTypeLabel;

  /// إجمالي سحوبات الرواتب (النقد الخارج فعلاً — العقد النقدي 2026-09-14).
  double get salaryTotal => rows
      .where((r) => SalaryExpenseClassification.isCashSalaryExpense(r.type))
      .fold<double>(0, (sum, r) => sum + r.amount);

  /// إجمالي المصروفات التشغيلية (غير الرواتب).
  double get nonSalaryTotal => totalAmount - salaryTotal;
}

/// قالب تقرير المصروفات.
class ExpensesReportPdf {
  ExpensesReportPdf._();

  /// مشاركة تقرير المصروفات.
  static Future<void> share(ExpensesReportData data) async {
    final labels = data.labels;
    final fromLabel = data.fromDate != null
        ? DateFormat('yyyy-MM-dd').format(data.fromDate!)
        : 'غير محدد';
    final toLabel = data.toDate != null
        ? DateFormat('yyyy-MM-dd').format(data.toDate!)
        : 'غير محدد';

    // عرض عمود الموظف تلقائياً عند وجود بيانات رواتب.
    final showEmployeeCol = data.hasSalaryData;

    final headers = <String>['التاريخ', 'المبلغ', 'النوع', 'الوصف'];
    if (showEmployeeCol) {
      headers.add('الموظف');
    }

    final dataRows = <List<String>>[];
    for (final row in data.rows) {
      final cells = [
        DateFormat('yyyy/MM/dd').format(row.date),
        EnhancedPdfUtils.formatNumber(row.amount),
        row.type,
        if (row.description.isNotEmpty) row.description else '-',
      ];
      if (showEmployeeCol) {
        cells.add(
          row.employeeName ?? (row.isSalaryWithdrawal ? 'غير محدد' : '-'),
        );
      }
      dataRows.add(cells);
    }

    final totalRow = [
      labels.totalRowLabel,
      EnhancedPdfUtils.formatNumber(data.totalAmount),
      '',
      '',
    ];
    if (showEmployeeCol) {
      totalRow.add('');
    }
    dataRows.add(totalRow);

    await ReportPdfBuilder.buildAndShare(
      ReportPdfConfig(
        title: labels.title,
        fromDate: data.fromDate,
        toDate: data.toDate,
        buildContent: (fonts) {
          final metaInfoCard = EnhancedPdfUtils.buildInfoCard(
            title: labels.title,
            fonts: fonts,
            content: [
              EnhancedPdfUtils.buildKeyValueRow(
                fonts: fonts,
                label: 'الفترة',
                value: 'من $fromLabel إلى $toLabel',
              ),
              EnhancedPdfUtils.buildKeyValueRow(
                fonts: fonts,
                label: labels.typeLabel,
                value: data.selectedTypeLabel,
              ),
              EnhancedPdfUtils.buildKeyValueRow(
                fonts: fonts,
                label: 'عدد السجلات',
                value: data.rows.length.toString(),
              ),
              if (data.hasSalaryData)
                EnhancedPdfUtils.buildKeyValueRow(
                  fonts: fonts,
                  label: 'يشمل',
                  value: 'مصروفات تشغيلية + سحوبات الرواتب',
                ),
            ],
          );

          return [
            pw.SizedBox(height: 16),
            metaInfoCard,
            pw.SizedBox(height: 12),
            ...EnhancedPdfUtils.buildChunkedTable(
              headers: headers,
              data: dataRows,
              fonts: fonts,
            ),
            pw.SizedBox(height: 12),
            _buildTotalsSummary(fonts, data),
          ];
        },
        fileName: ReportPdfBuilder.generateFileName(labels.title),
      ),
    );
  }

  /// بطاقة ملخص الإجماليات (إجمالي + عدد السجلات + سحوبات/تشغيلية).
  static pw.Widget _buildTotalsSummary(
    ArabicPdfFonts fonts,
    ExpensesReportData data,
  ) {
    pw.Widget summaryItem(String title, String value, PdfColor accent) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: PdfColors.cardBackground,
          border: pw.Border.all(color: accent, width: 0.7),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Column(
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(
                font: fonts.regular,
                fontSize: 11,
                color: PdfColors.textDark,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              value,
              style: pw.TextStyle(
                font: fonts.bold,
                fontSize: 16,
                color: accent,
              ),
            ),
          ],
        ),
      );
    }

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.backgroundLight,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: PdfColors.primary, width: 0.4),
      ),
      child: pw.Column(
        children: [
          pw.Row(
            children: [
              pw.Expanded(
                child: summaryItem(
                  data.labels.totalSummaryLabel,
                  EnhancedPdfUtils.formatNumber(data.totalAmount),
                  PdfColors.secondary,
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: summaryItem(
                  'عدد السجلات',
                  data.rows.length.toString(),
                  PdfColors.info,
                ),
              ),
            ],
          ),
          if (data.hasSalaryData) ...[
            pw.SizedBox(height: 8),
            pw.Row(
              children: [
                pw.Expanded(
                  child: summaryItem(
                    'سحوبات الرواتب',
                    EnhancedPdfUtils.formatNumber(data.salaryTotal),
                    PdfColors.warning,
                  ),
                ),
                pw.SizedBox(width: 8),
                pw.Expanded(
                  child: summaryItem(
                    'مصروفات تشغيلية',
                    EnhancedPdfUtils.formatNumber(data.nonSalaryTotal),
                    PdfColors.info,
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
