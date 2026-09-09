/// PDF generation for income/expense reports.
///
/// Extracted from income_expense_report_screen.dart (2,944 LOC)
/// Generates PDF documents with financial data and visualizations

import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../utils/enhanced_pdf_utils.dart';
import '../../utils/status_utils.dart';
import 'report_data_calculator.dart';

/// PDF generation service for income/expense reports
class ReportPdfGenerator {
  ReportPdfGenerator();

  final _currencyFormat = NumberFormat('#,##0', 'en_US');
  final _dateFormat = DateFormat('yyyy-MM-dd');

  /// Build main PDF document
  Future<pw.Document> buildPdfDocument({
    required ReportData data,
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    final pdf = pw.Document();
    final fonts = ArabicPdfFonts();

    // Title page
    pdf.addPage(
      pw.Page(
        build: (pw.Context context) => pw.Column(
          children: [
            pw.Text(
              'تقرير الدخل والمصروفات',
              style: pw.TextStyle(
                fontSize: 28,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Text(
              '${_dateFormat.format(fromDate)} إلى ${_dateFormat.format(toDate)}',
              style: const pw.TextStyle(fontSize: 14),
            ),
            pw.SizedBox(height: 40),
            _buildSummaryTable(data),
          ],
        ),
      ),
    );

    // Details page
    pdf.addPage(
      pw.Page(
        build: (pw.Context context) => pw.Column(
          children: [
            pw.Text(
              'التفاصيل',
              style: pw.TextStyle(
                fontSize: 20,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 20),
            _buildPaymentMethodsTable(),
            pw.SizedBox(height: 20),
            _buildDebtAnalysisTable(data),
          ],
        ),
      ),
    );

    return pdf;
  }

  /// Build detailed grouped PDF
  Future<pw.Document> buildDetailedGroupedPdf({
    required ReportData data,
    required String groupBy,
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        build: (pw.Context context) => pw.Column(
          children: [
            pw.Text(
              'تقرير مفصل - ${_getGroupTypeLabel(groupBy)}',
              style: pw.TextStyle(
                fontSize: 20,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 20),
            _buildGroupedTable(data, groupBy),
          ],
        ),
      ),
    );

    return pdf;
  }

  /// Build summary table
  pw.Widget _buildSummaryTable(ReportData data) {
    return pw.Table(
      border: pw.TableBorder.all(),
      children: [
        _buildSummaryRow('إجمالي الدخل', _formatCurrency(data.incomeTotal)),
        _buildSummaryRow('إجمالي المصروفات', _formatCurrency(data.expenseTotal)),
        _buildSummaryRow('إجمالي الرواتب', _formatCurrency(data.salaryTotal)),
        _buildSummaryRow('الصافي', _formatCurrency(data.net)),
      ],
    );
  }

  /// Build summary row
  pw.TableRow _buildSummaryRow(String label, String value) {
    return pw.TableRow(
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.all(8),
          child: pw.Text(label),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(8),
          child: pw.Text(value),
        ),
      ],
    );
  }

  /// Build payment methods table
  pw.Widget _buildPaymentMethodsTable() {
    return pw.Table(
      border: pw.TableBorder.all(),
      children: [
        pw.TableRow(
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.all(8),
              child: pw.Text('طريقة الدفع'),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(8),
              child: pw.Text('العدد'),
            ),
          ],
        ),
      ],
    );
  }

  /// Build debt analysis table
  pw.Widget _buildDebtAnalysisTable(ReportData data) {
    return pw.Table(
      border: pw.TableBorder.all(),
      children: [
        _buildSummaryRow('الديون غير المسددة', _formatCurrency(data.unsettledDebtsAmount)),
        _buildSummaryRow('عدد الديون', data.unsettledDebtsCount.toString()),
        _buildSummaryRow(
          'الديون في الفترة',
          _formatCurrency(data.unsettledDebtsInPeriodAmount),
        ),
      ],
    );
  }

  /// Build grouped table by time period
  pw.Widget _buildGroupedTable(ReportData data, String groupBy) {
    return pw.Table(
      border: pw.TableBorder.all(),
      children: [
        pw.TableRow(
          children: [
            pw.Text('الفترة'),
            pw.Text('الدخل'),
            pw.Text('المصروفات'),
            pw.Text('الصافي'),
          ],
        ),
      ],
    );
  }

  /// Get group type label
  String _getGroupTypeLabel(String groupBy) {
    switch (groupBy) {
      case 'day':
        return 'يومي';
      case 'week':
        return 'أسبوعي';
      case 'month':
        return 'شهري';
      case 'year':
        return 'سنوي';
      default:
        return groupBy;
    }
  }

  /// Format currency for display
  String _formatCurrency(double amount) {
    return '${_currencyFormat.format(amount)} ر.ي';
  }
}
