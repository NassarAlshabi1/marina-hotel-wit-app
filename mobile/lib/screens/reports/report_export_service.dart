/// Export services for income/expense reports (PDF, CSV, print).
///
/// Extracted from income_expense_report_screen.dart (2,944 LOC)
/// Handles PDF export, CSV export, and printing

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import 'report_data_calculator.dart';
import 'report_pdf_generator.dart';

/// Export service for reports
class ReportExportService {
  ReportExportService({
    required this.dataCalculator,
    required this.pdfGenerator,
  });

  final ReportDataCalculator dataCalculator;
  final ReportPdfGenerator pdfGenerator;

  final _dateFormat = DateFormat('yyyy-MM-dd');
  final _currencyFormat = NumberFormat('#,##0', 'en_US');

  /// Export report to PDF file
  Future<File?> exportToPdf({
    required ReportData data,
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    try {
      final pdf = await pdfGenerator.buildPdfDocument(
        data: data,
        fromDate: fromDate,
        toDate: toDate,
      );

      final fileName = getFilename(suffix: 'pdf');
      final file = await _saveFile(fileName, await pdf.save());

      return file;
    } catch (e) {
      debugPrint('❌ PDF export error: $e');
      return null;
    }
  }

  /// Export report to CSV file
  Future<File?> exportToCsv({
    required ReportData data,
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    try {
      final csv = buildCsvContent(data, fromDate, toDate);
      final fileName = getFilename(suffix: 'csv');
      final file = await _saveFile(fileName, utf8.encode(csv));

      return file;
    } catch (e) {
      debugPrint('❌ CSV export error: $e');
      return null;
    }
  }

  /// Print report
  Future<void> printReport({
    required ReportData data,
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    try {
      final pdf = await pdfGenerator.buildPdfDocument(
        data: data,
        fromDate: fromDate,
        toDate: toDate,
      );

      await Printing.layoutPdf(
        onLayout: (_) async => pdf.save(),
      );
    } catch (e) {
      debugPrint('❌ Print error: $e');
    }
  }

  /// Share report file
  Future<void> shareReport(File file) async {
    try {
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'تقرير الدخل والمصروفات',
      );
    } catch (e) {
      debugPrint('❌ Share error: $e');
    }
  }

  /// Build CSV content
  String buildCsvContent(
    ReportData data,
    DateTime fromDate,
    DateTime toDate,
  ) {
    final lines = <String>[];

    // Header
    lines.add('تقرير الدخل والمصروفات');
    lines.add(
      '${_dateFormat.format(fromDate)} إلى ${_dateFormat.format(toDate)}',
    );
    lines.add('');

    // Summary
    lines.add('الملخص');
    lines.add('إجمالي الدخل,${formatCurrency(data.incomeTotal)}');
    lines.add('إجمالي المصروفات,${formatCurrency(data.expenseTotal)}');
    lines.add('إجمالي الرواتب,${formatCurrency(data.salaryTotal)}');
    lines.add('الصافي,${formatCurrency(data.net)}');
    lines.add('');

    // Income entries
    lines.add('بيانات الدخل');
    lines.add('التاريخ,طريقة الدفع,المبلغ,العدد');
    for (final entry in data.incomeEntries) {
      lines.add(
        '${entry.dateStr},${entry.paymentMethod},${formatCurrency(entry.totalAmount)},${entry.count}',
      );
    }
    lines.add('');

    // Expense entries
    lines.add('بيانات المصروفات');
    lines.add('الفئة,المبلغ,العدد');
    for (final entry in data.expenseEntries) {
      lines.add(
        '${entry.category},${formatCurrency(entry.totalAmount)},${entry.count}',
      );
    }
    lines.add('');

    // Statistics
    lines.add('الإحصائيات');
    lines.add('إجمالي الحجوزات,${data.bookingsCount}');
    lines.add('حجوزات نشطة,${data.activeBookingsCount}');
    lines.add('حجوزات المغادرة,${data.checkoutBookingsCount}');
    lines.add('إجمالي الديون,${data.totalDebtsCount}');
    lines.add(
      'الديون غير المسددة,${data.unsettledDebtsCount} (${formatCurrency(data.unsettledDebtsAmount)})',
    );
    lines.add('الموظفون النشطون,${data.activeEmployeesCount}');
    lines.add('الموظفون المنتهون,${data.terminatedEmployeesCount}');

    return lines.join('\n');
  }

  /// Get filename for export
  String getFilename({String suffix = ''}) {
    final now = DateTime.now();
    final timestamp = _dateFormat.format(now);
    final ext = suffix.isEmpty ? 'pdf' : suffix;
    return 'report_$timestamp.$ext';
  }

  /// Save file to local storage
  Future<File> _saveFile(String fileName, List<int> bytes) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$fileName');
    return file.writeAsBytes(bytes);
  }

  /// Format currency for CSV
  String formatCurrency(double amount) {
    return '${_currencyFormat.format(amount)} ر.ي';
  }
}
