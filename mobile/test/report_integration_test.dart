import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../lib/screens/reports/report_data_calculator.dart';
import '../lib/screens/reports/report_export_service.dart';
import '../lib/screens/reports/report_pdf_generator.dart';
import '../lib/services/local_db.dart';

class MockAppDatabase extends Mock implements AppDatabase {}

void main() {
  group('Report Integration Tests', () {
    late ReportDataCalculator calculator;
    late ReportPdfGenerator pdfGenerator;
    late ReportExportService exportService;
    late MockAppDatabase mockDatabase;

    setUp(() {
      mockDatabase = MockAppDatabase();

      calculator = ReportDataCalculator(database: mockDatabase);
      pdfGenerator = ReportPdfGenerator();
      exportService = ReportExportService(
        dataCalculator: calculator,
        pdfGenerator: pdfGenerator,
      );
    });

    test('All services initialize correctly', () {
      expect(calculator, isNotNull);
      expect(pdfGenerator, isNotNull);
      expect(exportService, isNotNull);
      expect(exportService.dataCalculator, calculator);
      expect(exportService.pdfGenerator, pdfGenerator);
    });

    test('Report data formatting utilities work', () {
      final now = DateTime(2026, 9, 10);

      final dayLabel = calculator.getGroupLabel(now, 'day');
      expect(dayLabel, contains('2026-09-10'));

      final monthLabel = calculator.getGroupLabel(now, 'month');
      expect(monthLabel, contains('2026'));

      final arabicDay = calculator.getArabicDayName(now);
      expect(arabicDay, isNotEmpty);
    });

    test('Income and expense entries can be grouped', () {
      // Test data setup
      final entries = [
        IncomeEntry(
          date: DateTime(2026, 9, 1),
          dateStr: '2026-09-01',
          totalAmount: 1000,
          paymentMethod: 'cash',
          count: 5,
        ),
        IncomeEntry(
          date: DateTime(2026, 9, 2),
          dateStr: '2026-09-02',
          totalAmount: 1500,
          paymentMethod: 'card',
          count: 3,
        ),
      ];

      expect(entries, hasLength(2));
      expect(entries[0].date.isBefore(entries[1].date), true);
    });
  });

  group('Report Data Calculation', () {
    late ReportDataCalculator calculator;
    late MockAppDatabase mockDatabase;

    setUp(() {
      mockDatabase = MockAppDatabase();
      calculator = ReportDataCalculator(database: mockDatabase);
    });

    test('ReportData contains all required statistics', () {
      final data = ReportData(
        incomeEntries: [],
        expenseEntries: [],
        incomeTotal: 5000,
        expenseTotal: 1000,
        salaryTotal: 1500,
        net: 2500,
        bookingsCount: 20,
        activeBookingsCount: 15,
        checkoutBookingsCount: 5,
        totalDebtsCount: 8,
        unsettledDebtsCount: 3,
        unsettledDebtsAmount: 450,
        activeEmployeesCount: 8,
        terminatedEmployeesCount: 2,
        unsettledDebtsInPeriodCount: 2,
        unsettledDebtsInPeriodAmount: 300,
      );

      expect(data.incomeTotal, 5000);
      expect(data.expenseTotal, 1000);
      expect(data.salaryTotal, 1500);
      expect(data.net, 2500);
      expect(data.bookingsCount, 20);
      expect(data.activeBookingsCount, 15);
      expect(data.unsettledDebtsCount, 3);
    });

    test('Report data entries are mutable for aggregation', () {
      final income = IncomeEntry(
        date: DateTime.now(),
        dateStr: '2026-09-10',
        totalAmount: 100,
        paymentMethod: 'cash',
        count: 1,
      );

      income.totalAmount = 200;
      income.count = 2;

      expect(income.totalAmount, 200);
      expect(income.count, 2);
    });

    test('Expense entries track by category', () {
      final expenses = [
        ExpenseEntry(category: 'utilities', totalAmount: 500, count: 3),
        ExpenseEntry(category: 'supplies', totalAmount: 250, count: 2),
        ExpenseEntry(category: 'maintenance', totalAmount: 750, count: 1),
      ];

      final total = expenses.fold<double>(
        0,
        (sum, e) => sum + e.totalAmount,
      );
      expect(total, 1500);
    });
  });

  group('Report Export Workflow', () {
    late ReportDataCalculator calculator;
    late ReportPdfGenerator pdfGenerator;
    late ReportExportService exportService;
    late MockAppDatabase mockDatabase;

    setUp(() {
      mockDatabase = MockAppDatabase();

      calculator = ReportDataCalculator(database: mockDatabase);
      pdfGenerator = ReportPdfGenerator();
      exportService = ReportExportService(
        dataCalculator: calculator,
        pdfGenerator: pdfGenerator,
      );
    });

    test('CSV export includes all data sections', () {
      final data = ReportData(
        incomeEntries: [
          IncomeEntry(
            date: DateTime(2026, 9, 1),
            dateStr: '2026-09-01',
            totalAmount: 1000,
            paymentMethod: 'cash',
            count: 5,
          ),
        ],
        expenseEntries: [
          ExpenseEntry(category: 'utilities', totalAmount: 200, count: 1),
        ],
        incomeTotal: 1000,
        expenseTotal: 200,
        salaryTotal: 300,
        net: 500,
        bookingsCount: 10,
        activeBookingsCount: 8,
        checkoutBookingsCount: 2,
        totalDebtsCount: 5,
        unsettledDebtsCount: 2,
        unsettledDebtsAmount: 100,
        activeEmployeesCount: 5,
        terminatedEmployeesCount: 1,
        unsettledDebtsInPeriodCount: 1,
        unsettledDebtsInPeriodAmount: 50,
      );

      final csv = exportService.buildCsvContent(
        data,
        DateTime(2026, 9, 1),
        DateTime(2026, 9, 30),
      );

      // Check all major sections are present
      expect(csv, contains('الملخص'));
      expect(csv, contains('بيانات الدخل'));
      expect(csv, contains('بيانات المصروفات'));
      expect(csv, contains('الإحصائيات'));

      // Check specific data appears
      expect(csv, contains('cash'));
      expect(csv, contains('utilities'));
      expect(csv, contains('إجمالي الحجوزات'));
    });

    test('CSV formatting preserves Arabic text', () {
      final data = ReportData(
        incomeEntries: [],
        expenseEntries: [],
        incomeTotal: 0,
        expenseTotal: 0,
        salaryTotal: 0,
        net: 0,
        bookingsCount: 0,
        activeBookingsCount: 0,
        checkoutBookingsCount: 0,
        totalDebtsCount: 0,
        unsettledDebtsCount: 0,
        unsettledDebtsAmount: 0,
        activeEmployeesCount: 0,
        terminatedEmployeesCount: 0,
        unsettledDebtsInPeriodCount: 0,
        unsettledDebtsInPeriodAmount: 0,
      );

      final csv = exportService.buildCsvContent(
        data,
        DateTime(2026, 9, 1),
        DateTime(2026, 9, 30),
      );

      // All Arabic text should be preserved
      expect(csv, contains('تقرير'));
      expect(csv, contains('ملخص'));
      expect(csv, contains('دخل'));
    });

    test('Filename generation follows pattern', () {
      final filename = exportService.getFilename(suffix: 'csv');

      expect(filename, startsWith('report_'));
      expect(filename, endsWith('.csv'));
      expect(filename.length, greaterThan('report_.csv'.length));
    });

    test('Currency formatting is consistent', () {
      final formatted1 = exportService.formatCurrency(1000);
      final formatted2 = exportService.formatCurrency(1000);

      expect(formatted1, formatted2);
      expect(formatted1, contains('ر.ي'));
    });
  });

  group('Date Range Handling', () {
    late ReportDataCalculator calculator;
    late MockAppDatabase mockDatabase;

    setUp(() {
      mockDatabase = MockAppDatabase();
      calculator = ReportDataCalculator(database: mockDatabase);
    });

    test('Group labels respect date boundaries', () {
      final start = DateTime(2026, 9, 1);
      final mid = DateTime(2026, 9, 15);
      final end = DateTime(2026, 9, 30);

      final label1 = calculator.getGroupLabel(start, 'day');
      final label2 = calculator.getGroupLabel(mid, 'day');
      final label3 = calculator.getGroupLabel(end, 'day');

      expect(label1, isNotEmpty);
      expect(label2, isNotEmpty);
      expect(label3, isNotEmpty);
      expect(label1, isNot(equals(label2)));
    });

    test('Arabic day names are consistent', () {
      final monday1 = DateTime(2026, 9, 7); // Monday
      final monday2 = DateTime(2026, 9, 14); // Monday

      final name1 = calculator.getArabicDayName(monday1);
      final name2 = calculator.getArabicDayName(monday2);

      expect(name1, name2); // Same day of week = same name
    });
  });
}
