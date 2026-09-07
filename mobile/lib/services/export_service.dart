// lib/services/export_service.dart
// خدمة تصدير البيانات — Excel + PDF + مشاركة
//
// تُصدّر البيانات إلى:
// - XLSX: كشوف الرواتب والمصروفات (3 أوراق: ملخص، رواتب، مصروفات)
// - PDF: فواتير النزلاء (عبر EnhancedPdfUtils الموجود)
// - مشاركة: عبر share_plus
//
// الاستخدام:
// ```dart
// // تصدير الرواتب والمصروفات
// final file = await ExportService.instance.exportSalaryAndExpenses(
//   month: '2026-07',
//   salaries: salaryList,
//   expenses: expenseList,
// );
//
// // مشاركة الملف
// await ExportService.instance.shareFile(file);
// ```

import 'dart:io';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// نموذج بيانات سحب راتب للتصدير
class SalaryExportData {
  const SalaryExportData({
    required this.date,
    required this.employeeName,
    required this.role,
    required this.type,
    required this.amount,
  });

  final DateTime date;
  final String employeeName;
  final String role;
  final String type;
  final double amount;
}

/// نموذج بيانات مصروف للتصدير
class ExpenseExportData {
  const ExpenseExportData({
    required this.date,
    required this.type,
    required this.description,
    required this.amount,
  });

  final DateTime date;
  final String type;
  final String description;
  final double amount;
}

/// نموذج بيانات فاتورة للتصدير
class InvoiceExportData {
  const InvoiceExportData({
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.guestName,
    required this.guestPhone,
    required this.guestId,
    required this.roomNumber,
    required this.checkinDate,
    required this.checkoutDate,
    required this.nights,
    required this.roomRate,
    required this.items,
    required this.paymentMethod,
    required this.receivedBy,
  });

  final String invoiceNumber;
  final DateTime invoiceDate;
  final String guestName;
  final String guestPhone;
  final String guestId;
  final String roomNumber;
  final DateTime checkinDate;
  final DateTime checkoutDate;
  final int nights;
  final double roomRate;
  final List<InvoiceItem> items;
  final String paymentMethod;
  final String receivedBy;

  double get total => items.fold(0.0, (sum, item) => sum + item.total);
}

class InvoiceItem {
  const InvoiceItem({
    required this.description,
    required this.qty,
    required this.unitPrice,
    required this.total,
  });

  final String description;
  final int qty;
  final double unitPrice;
  final double total;
}

/// خدمة تصدير البيانات
class ExportService {
  factory ExportService() => _instance;
  ExportService._internal();
  static final ExportService _instance = ExportService._internal();
  static ExportService get instance => _instance;

  // ═══════════════════════════════════════════════════════════════
  //  XLSX Export — الرواتب والمصروفات
  // ═══════════════════════════════════════════════════════════════

  /// تصدير كشوف الرواتب والمصروفات إلى ملف Excel
  ///
  /// يُنشئ ملف XLSX بـ 3 أوراق:
  /// 1. ملخص — إجمالي الرواتب + المصروفات + الصافي
  /// 2. الرواتب — تفاصيل كل سحب راتب
  /// 3. المصروفات — تفاصيل كل مصروف
  Future<File> exportSalaryAndExpenses({
    required String month,
    required List<SalaryExportData> salaries,
    required List<ExpenseExportData> expenses,
  }) async {
    final excel = Excel.createExcel();

    // ─── Sheet 1: ملخص (Summary) ───
    final summarySheet = excel['ملخص'];
    summarySheet.isRTL = true;

    // Title
    summarySheet.cell(CellIndex.indexByString('A1'))
      ..value = TextCellValue('فندق مارينا — تقرير شهر $month')
      ..cellStyle = CellStyle(
        bold: true,
        fontSize: 16,
        fontColorHex: ExcelColor.fromHexString('FFB46B00'),
        horizontalAlign: HorizontalAlign.Center,
      );

    // Merge title row
    summarySheet.merge(
      CellIndex.indexByString('A1'),
      CellIndex.indexByString('D1'),
    );

    // Headers
    final headers = ['البند', 'العدد', 'المبلغ الإجمالي (ريال)', 'ملاحظات'];
    for (var i = 0; i < headers.length; i++) {
      final cell = summarySheet.cell(
        CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 3),
      );
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = CellStyle(
        bold: true,
        fontSize: 11,
        fontColorHex: ExcelColor.fromHexString('FFFFFFFF'),
        backgroundColorHex: ExcelColor.fromHexString('FF1B3A5C'),
        horizontalAlign: HorizontalAlign.Center,
      );
    }

    // Calculate totals
    final totalSalaries = salaries.fold<double>(0, (sum, s) => sum + s.amount);
    final totalExpenses = expenses.fold<double>(0, (sum, e) => sum + e.amount);
    final grandTotal = totalSalaries + totalExpenses;

    // Summary data
    final summaryRows = [
      (
        'سحوبات الرواتب',
        salaries.length,
        totalSalaries,
        'يشمل الرواتب + السلف + الخصومات',
      ),
      (
        'المصروفات التشغيلية',
        expenses.length,
        totalExpenses,
        'ديزل + صيانة + فواتير + مستلزمات',
      ),
      (
        'إجمالي المصروفات',
        salaries.length + expenses.length,
        grandTotal,
        'إجمالي ما صُرف هذا الشهر',
      ),
    ];

    for (var i = 0; i < summaryRows.length; i++) {
      final row = summaryRows[i];
      final rowIndex = 4 + i;
      final isTotal = i == 2;

      summarySheet.cell(
          CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex),
        )
        ..value = TextCellValue(row.$1)
        ..cellStyle = CellStyle(
          bold: true,
          fontSize: 10,
          backgroundColorHex: isTotal
              ? ExcelColor.fromHexString('FFF0F0F0')
              : ExcelColor.fromHexString('FFFFF8E7'),
        );

      summarySheet.cell(
          CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIndex),
        )
        ..value = IntCellValue(row.$2)
        ..cellStyle = CellStyle(
          fontSize: 10,
          backgroundColorHex: isTotal
              ? ExcelColor.fromHexString('FFF0F0F0')
              : ExcelColor.fromHexString('FFFFF8E7'),
        );

      summarySheet.cell(
          CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIndex),
        )
        ..value = DoubleCellValue(row.$3)
        ..cellStyle = CellStyle(
          bold: isTotal,
          fontSize: isTotal ? 11 : 10,
          fontColorHex: isTotal
              ? ExcelColor.fromHexString('FFB46B00')
              : ExcelColor.fromHexString('FF333333'),
          backgroundColorHex: isTotal
              ? ExcelColor.fromHexString('FFF0F0F0')
              : ExcelColor.fromHexString('FFFFF8E7'),
          horizontalAlign: HorizontalAlign.Right,
        );

      summarySheet.cell(
          CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIndex),
        )
        ..value = TextCellValue(row.$4)
        ..cellStyle = CellStyle(
          fontSize: 9,
          fontColorHex: ExcelColor.fromHexString('FF666666'),
          backgroundColorHex: isTotal
              ? ExcelColor.fromHexString('FFF0F0F0')
              : ExcelColor.fromHexString('FFFFF8E7'),
        );
    }

    // ─── Sheet 2: الرواتب (Salaries) ───
    final salarySheet = excel['الرواتب'];
    salarySheet.isRTL = true;

    // Title
    salarySheet.cell(CellIndex.indexByString('A1'))
      ..value = TextCellValue('كشف الرواتب — $month')
      ..cellStyle = CellStyle(
        bold: true,
        fontSize: 14,
        fontColorHex: ExcelColor.fromHexString('FFB46B00'),
        horizontalAlign: HorizontalAlign.Center,
      );
    salarySheet.merge(
      CellIndex.indexByString('A1'),
      CellIndex.indexByString('F1'),
    );

    // Headers
    final salaryHeaders = [
      '#',
      'التاريخ',
      'الموظف',
      'الوظيفة',
      'النوع',
      'المبلغ (ريال)',
    ];
    for (var i = 0; i < salaryHeaders.length; i++) {
      final cell = salarySheet.cell(
        CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 2),
      );
      cell.value = TextCellValue(salaryHeaders[i]);
      cell.cellStyle = CellStyle(
        bold: true,
        fontSize: 11,
        fontColorHex: ExcelColor.fromHexString('FFFFFFFF'),
        backgroundColorHex: ExcelColor.fromHexString('FF1B3A5C'),
        horizontalAlign: HorizontalAlign.Center,
      );
    }

    // Data
    for (var i = 0; i < salaries.length; i++) {
      final s = salaries[i];
      final rowIndex = 3 + i;
      final isNegative = s.amount < 0;
      final bgColor = isNegative
          ? ExcelColor.fromHexString('FFFFEBEE')
          : ExcelColor.fromHexString('FFFFFFFF');

      salarySheet.cell(
          CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex),
        )
        ..value = IntCellValue(i + 1)
        ..cellStyle = CellStyle(fontSize: 10, backgroundColorHex: bgColor);

      salarySheet.cell(
          CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIndex),
        )
        ..value = TextCellValue(DateFormat('yyyy-MM-dd').format(s.date))
        ..cellStyle = CellStyle(fontSize: 10, backgroundColorHex: bgColor);

      salarySheet.cell(
          CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIndex),
        )
        ..value = TextCellValue(s.employeeName)
        ..cellStyle = CellStyle(fontSize: 10, backgroundColorHex: bgColor);

      salarySheet.cell(
          CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIndex),
        )
        ..value = TextCellValue(s.role)
        ..cellStyle = CellStyle(fontSize: 10, backgroundColorHex: bgColor);

      salarySheet.cell(
          CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIndex),
        )
        ..value = TextCellValue(s.type)
        ..cellStyle = CellStyle(fontSize: 10, backgroundColorHex: bgColor);

      salarySheet.cell(
          CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: rowIndex),
        )
        ..value = DoubleCellValue(s.amount)
        ..cellStyle = CellStyle(
          fontSize: 10,
          fontColorHex: isNegative
              ? ExcelColor.fromHexString('FFC0392B')
              : ExcelColor.fromHexString('FF333333'),
          backgroundColorHex: bgColor,
          horizontalAlign: HorizontalAlign.Right,
        );
    }

    // Total row for salaries
    final salaryTotalRow = 3 + salaries.length;
    salarySheet.cell(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: salaryTotalRow),
      )
      ..value = TextCellValue('الإجمالي')
      ..cellStyle = CellStyle(
        bold: true,
        fontSize: 11,
        fontColorHex: ExcelColor.fromHexString('FFB46B00'),
        backgroundColorHex: ExcelColor.fromHexString('FFF0F0F0'),
        horizontalAlign: HorizontalAlign.Center,
      );
    for (var i = 1; i < 5; i++) {
      salarySheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: salaryTotalRow),
        CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: salaryTotalRow),
      );
    }
    salarySheet.cell(
        CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: salaryTotalRow),
      )
      ..value = DoubleCellValue(totalSalaries)
      ..cellStyle = CellStyle(
        bold: true,
        fontSize: 11,
        fontColorHex: ExcelColor.fromHexString('FFB46B00'),
        backgroundColorHex: ExcelColor.fromHexString('FFF0F0F0'),
        horizontalAlign: HorizontalAlign.Right,
      );

    // ─── Sheet 3: المصروفات (Expenses) ───
    final expenseSheet = excel['المصروفات'];
    expenseSheet.isRTL = true;

    // Title
    expenseSheet.cell(CellIndex.indexByString('A1'))
      ..value = TextCellValue('كشف المصروفات — $month')
      ..cellStyle = CellStyle(
        bold: true,
        fontSize: 14,
        fontColorHex: ExcelColor.fromHexString('FFB46B00'),
        horizontalAlign: HorizontalAlign.Center,
      );
    expenseSheet.merge(
      CellIndex.indexByString('A1'),
      CellIndex.indexByString('E1'),
    );

    // Headers
    final expenseHeaders = ['#', 'التاريخ', 'النوع', 'الوصف', 'المبلغ (ريال)'];
    for (var i = 0; i < expenseHeaders.length; i++) {
      final cell = expenseSheet.cell(
        CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 2),
      );
      cell.value = TextCellValue(expenseHeaders[i]);
      cell.cellStyle = CellStyle(
        bold: true,
        fontSize: 11,
        fontColorHex: ExcelColor.fromHexString('FFFFFFFF'),
        backgroundColorHex: ExcelColor.fromHexString('FF1B3A5C'),
        horizontalAlign: HorizontalAlign.Center,
      );
    }

    // Data
    for (var i = 0; i < expenses.length; i++) {
      final e = expenses[i];
      final rowIndex = 3 + i;

      expenseSheet.cell(
          CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex),
        )
        ..value = IntCellValue(i + 1)
        ..cellStyle = CellStyle(fontSize: 10);

      expenseSheet.cell(
          CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIndex),
        )
        ..value = TextCellValue(DateFormat('yyyy-MM-dd').format(e.date))
        ..cellStyle = CellStyle(fontSize: 10);

      expenseSheet.cell(
          CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIndex),
        )
        ..value = TextCellValue(e.type)
        ..cellStyle = CellStyle(fontSize: 10);

      expenseSheet.cell(
          CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIndex),
        )
        ..value = TextCellValue(e.description)
        ..cellStyle = CellStyle(fontSize: 10);

      expenseSheet.cell(
          CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIndex),
        )
        ..value = DoubleCellValue(e.amount)
        ..cellStyle = CellStyle(
          fontSize: 10,
          horizontalAlign: HorizontalAlign.Right,
        );
    }

    // Total row for expenses
    final expenseTotalRow = 3 + expenses.length;
    expenseSheet.cell(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: expenseTotalRow),
      )
      ..value = TextCellValue('الإجمالي')
      ..cellStyle = CellStyle(
        bold: true,
        fontSize: 11,
        fontColorHex: ExcelColor.fromHexString('FFB46B00'),
        backgroundColorHex: ExcelColor.fromHexString('FFF0F0F0'),
        horizontalAlign: HorizontalAlign.Center,
      );
    for (var i = 1; i < 4; i++) {
      expenseSheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: expenseTotalRow),
        CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: expenseTotalRow),
      );
    }
    expenseSheet.cell(
        CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: expenseTotalRow),
      )
      ..value = DoubleCellValue(totalExpenses)
      ..cellStyle = CellStyle(
        bold: true,
        fontSize: 11,
        fontColorHex: ExcelColor.fromHexString('FFB46B00'),
        backgroundColorHex: ExcelColor.fromHexString('FFF0F0F0'),
        horizontalAlign: HorizontalAlign.Right,
      );

    // Remove default Sheet1
    excel.delete('Sheet1');

    // Save file
    final bytes = excel.save();
    if (bytes == null) throw Exception('Failed to generate Excel file');

    final dir = await getApplicationDocumentsDirectory();
    final fileName = 'marina_hotel_salary_expenses_$month.xlsx';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);

    return file;
  }

  // ═══════════════════════════════════════════════════════════════
  //  File Sharing
  // ═══════════════════════════════════════════════════════════════

  /// مشاركة ملف عبر نظام المشاركة في الجهاز
  Future<void> shareFile(File file, {String? subject}) async {
    await Share.shareXFiles([
      XFile(file.path),
    ], subject: subject ?? 'Marina Hotel Export');
  }

  /// حفظ الملف في مجلد التحميلات (إن أمكن)
  Future<File?> saveToDownloads(File file, String fileName) async {
    try {
      final dir = await getExternalStorageDirectory();
      if (dir == null) return null;

      final downloadsDir = Directory('${dir.path}/Download');
      if (!downloadsDir.existsSync()) {
        await downloadsDir.create(recursive: true);
      }

      final newFile = File('${downloadsDir.path}/$fileName');
      await file.copy(newFile.path);
      return newFile;
    } catch (e) {
      return null;
    }
  }
}
