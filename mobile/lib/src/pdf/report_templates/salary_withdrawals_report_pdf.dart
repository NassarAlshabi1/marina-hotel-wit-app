/// قالب PDF لتقرير سحبيات الرواتب — نظام قوالب مستقل.
///
/// الشاشة تُمرّر بيانات فقط، والقالب يتولى التصميم كاملاً من نظام
/// التصميم الموحّد في lib/src/pdf/enhanced_pdf_utils.dart.
library;

import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;

import '../enhanced_pdf_utils.dart';
import '../report_pdf_builder.dart';

/// صف سحبة راتب واحدة.
class SalaryWithdrawalsReportRow {
  SalaryWithdrawalsReportRow({
    required this.date,
    required this.amount,
    required this.withdrawalType,
    required this.displayReason,
    required this.description,
    this.employeeName,
  });

  final DateTime date;
  final double amount;

  /// نوع السحبة (سحب راتب / خصم من الراتب / ...) أو 'سحب' إن فارغاً.
  final String withdrawalType;

  /// سبب السحبة بعد التنظيف (استبعاد روابط exp_XX الداخلية) أو '-'.
  final String displayReason;
  final String description;

  /// اسم الموظف — يظهر فقط عندما لا يوجد فلتر موظف.
  final String? employeeName;
}

/// بيانات تقرير سحبيات الرواتب.
class SalaryWithdrawalsReportData {
  SalaryWithdrawalsReportData({
    required this.rows,
    this.fromDate,
    this.toDate,
    this.selectedEmployeeName,
  });

  /// الصفوف مرتبة نهائياً (الأحدث أولاً) — القالب لا يعيد الترتيب.
  final List<SalaryWithdrawalsReportRow> rows;
  final DateTime? fromDate;
  final DateTime? toDate;

  /// اسم الموظف المفلتر (null أو '' = الكل — يُضاف عمود الموظف تلقائياً).
  final String? selectedEmployeeName;

  double get totalAmount => rows.fold<double>(0, (sum, r) => sum + r.amount);
  bool get showEmployeeColumn =>
      selectedEmployeeName == null || selectedEmployeeName!.isEmpty;
}

/// قالب تقرير سحبيات الرواتب.
class SalaryWithdrawalsReportPdf {
  SalaryWithdrawalsReportPdf._();

  /// مشاركة تقرير سحبيات الرواتب.
  static Future<void> share(SalaryWithdrawalsReportData data) async {
    final fromLabel = data.fromDate != null
        ? DateFormat('yyyy-MM-dd').format(data.fromDate!)
        : 'غير محدد';
    final toLabel = data.toDate != null
        ? DateFormat('yyyy-MM-dd').format(data.toDate!)
        : 'غير محدد';
    final selectedEmpName = data.selectedEmployeeName;

    final headers = data.showEmployeeColumn
        ? <String>['التاريخ', 'المبلغ', 'النوع', 'السبب', 'الملاحظات', 'الموظف']
        : <String>['التاريخ', 'المبلغ', 'النوع', 'السبب', 'الملاحظات'];

    final dataRows = <List<String>>[];
    for (final row in data.rows) {
      final cells = <String>[
        DateFormat('yyyy/MM/dd').format(row.date),
        EnhancedPdfUtils.formatNumber(row.amount),
        if (row.withdrawalType.isNotEmpty) row.withdrawalType else 'سحب',
        row.displayReason,
        if (row.description.isNotEmpty) row.description else '-',
      ];
      if (data.showEmployeeColumn) {
        cells.add(row.employeeName ?? 'غير محدد');
      }
      dataRows.add(cells);
    }

    final emptyCells = List.filled(headers.length, '');
    dataRows.add([
      'الإجمالي',
      EnhancedPdfUtils.formatNumber(data.totalAmount),
      ...emptyCells.sublist(2),
    ]);

    await ReportPdfBuilder.buildAndShare(
      ReportPdfConfig(
        title: 'تقرير سحبيات الرواتب',
        fromDate: data.fromDate,
        toDate: data.toDate,
        buildContent: (fonts) {
          return [
            pw.SizedBox(height: 16),
            EnhancedPdfUtils.buildInfoCard(
              title: 'تقرير سحبيات الرواتب',
              fonts: fonts,
              content: [
                EnhancedPdfUtils.buildKeyValueRow(
                  fonts: fonts,
                  label: 'الفترة',
                  value: 'من $fromLabel إلى $toLabel',
                ),
                EnhancedPdfUtils.buildKeyValueRow(
                  fonts: fonts,
                  label: 'الموظف',
                  value: (selectedEmpName == null || selectedEmpName.isEmpty)
                      ? 'الكل'
                      : selectedEmpName,
                ),
                EnhancedPdfUtils.buildKeyValueRow(
                  fonts: fonts,
                  label: 'عدد السجلات',
                  value: data.rows.length.toString(),
                ),
              ],
            ),
            pw.SizedBox(height: 12),
            ...EnhancedPdfUtils.buildChunkedTable(
              headers: headers,
              data: dataRows,
              fonts: fonts,
            ),
          ];
        },
        fileName: ReportPdfBuilder.generateFileName(
          selectedEmpName != null && selectedEmpName.isNotEmpty
              ? 'سحبيات راتب $selectedEmpName'
              : 'تقرير سحبيات الرواتب',
        ),
      ),
    );
  }
}
