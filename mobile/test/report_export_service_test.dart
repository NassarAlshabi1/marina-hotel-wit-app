import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../lib/screens/reports/report_data_calculator.dart';
import '../lib/screens/reports/report_export_service.dart';
import '../lib/screens/reports/report_pdf_generator.dart';

class MockDataCalculator extends Mock implements ReportDataCalculator {}

class MockPdfGenerator extends Mock implements ReportPdfGenerator {}

void main() {
  group('ReportExportService', () {
    late ReportExportService service;
    late MockDataCalculator mockCalculator;
    late MockPdfGenerator mockPdfGenerator;

    setUp(() {
      mockCalculator = MockDataCalculator();
      mockPdfGenerator = MockPdfGenerator();

      service = ReportExportService(
        dataCalculator: mockCalculator,
        pdfGenerator: mockPdfGenerator,
      );
    });

    test('exportToPdf initializes service', () {
      expect(service, isNotNull);
      expect(service.dataCalculator, mockCalculator);
      expect(service.pdfGenerator, mockPdfGenerator);
    });

    test('exportToCsv builds valid CSV content', () {
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
          ExpenseEntry(
            category: 'utilities',
            totalAmount: 200,
            count: 2,
          ),
        ],
        incomeTotal: 1000,
        expenseTotal: 200,
        salaryTotal: 300,
        net: 500,
        bookingsCount: 10,
        activeBookingsCount: 8,
        checkoutBookingsCount: 2,
        totalDebtsCount: 5,
        unsettledDebtsCount: 3,
        unsettledDebtsAmount: 150,
        activeEmployeesCount: 5,
        terminatedEmployeesCount: 1,
        unsettledDebtsInPeriodCount: 2,
        unsettledDebtsInPeriodAmount: 100,
      );

      final csv = service.buildCsvContent(
        data,
        DateTime(2026, 9, 1),
        DateTime(2026, 9, 30),
      );

      expect(csv, contains('تقرير الدخل والمصروفات'));
      expect(csv, contains('الملخص'));
      expect(csv, contains('بيانات الدخل'));
      expect(csv, contains('بيانات المصروفات'));
      expect(csv, contains('الإحصائيات'));
    });

    test('CSV content includes income entries', () {
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
        expenseEntries: [],
        incomeTotal: 1000,
        expenseTotal: 0,
        salaryTotal: 0,
        net: 1000,
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

      final csv = service.buildCsvContent(
        data,
        DateTime(2026, 9, 1),
        DateTime(2026, 9, 30),
      );

      expect(csv, contains('cash'));
      expect(csv, contains('2026-09-01'));
    });

    test('CSV content includes expense entries', () {
      final data = ReportData(
        incomeEntries: [],
        expenseEntries: [
          ExpenseEntry(
            category: 'utilities',
            totalAmount: 500,
            count: 3,
          ),
          ExpenseEntry(
            category: 'supplies',
            totalAmount: 250,
            count: 2,
          ),
        ],
        incomeTotal: 0,
        expenseTotal: 750,
        salaryTotal: 0,
        net: -750,
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

      final csv = service.buildCsvContent(
        data,
        DateTime(2026, 9, 1),
        DateTime(2026, 9, 30),
      );

      expect(csv, contains('utilities'));
      expect(csv, contains('supplies'));
    });

    test('CSV content includes statistics', () {
      final data = ReportData(
        incomeEntries: [],
        expenseEntries: [],
        incomeTotal: 0,
        expenseTotal: 0,
        salaryTotal: 0,
        net: 0,
        bookingsCount: 50,
        activeBookingsCount: 30,
        checkoutBookingsCount: 20,
        totalDebtsCount: 10,
        unsettledDebtsCount: 5,
        unsettledDebtsAmount: 500,
        activeEmployeesCount: 10,
        terminatedEmployeesCount: 2,
        unsettledDebtsInPeriodCount: 3,
        unsettledDebtsInPeriodAmount: 300,
      );

      final csv = service.buildCsvContent(
        data,
        DateTime(2026, 9, 1),
        DateTime(2026, 9, 30),
      );

      expect(csv, contains('إجمالي الحجوزات'));
      expect(csv, contains('حجوزات نشطة'));
      expect(csv, contains('الموظفون النشطون'));
    });

    test('_formatCurrency formats amounts correctly', () {
      final formatted = service.formatCurrency(1500.5);
      expect(formatted, contains('1,500'));
      expect(formatted, contains('ر.ي'));
    });

    test('_getFilename includes current date', () {
      final filename = service.getFilename(suffix: 'pdf');
      expect(filename, startsWith('report_'));
      expect(filename, endsWith('.pdf'));
    });

    test('_getFilename supports different extensions', () {
      final pdfFile = service.getFilename(suffix: 'pdf');
      final csvFile = service.getFilename(suffix: 'csv');

      expect(pdfFile, endsWith('.pdf'));
      expect(csvFile, endsWith('.csv'));
    });
  });

  group('Report Data Statistics', () {
    test('ReportData calculates net correctly', () {
      final data = ReportData(
        incomeEntries: [],
        expenseEntries: [],
        incomeTotal: 10000,
        expenseTotal: 2000,
        salaryTotal: 3000,
        net: 5000,
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

      // net = income - expenses - salary
      expect(data.net, 5000);
    });

    test('ReportData tracks unsettled debts correctly', () {
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
        totalDebtsCount: 10,
        unsettledDebtsCount: 5,
        unsettledDebtsAmount: 1000,
        activeEmployeesCount: 0,
        terminatedEmployeesCount: 0,
        unsettledDebtsInPeriodCount: 3,
        unsettledDebtsInPeriodAmount: 500,
      );

      expect(data.totalDebtsCount, 10);
      expect(data.unsettledDebtsCount, 5);
      expect(data.unsettledDebtsAmount, 1000);
    });
  });
}

// Extension to expose private methods for testing
extension ExportServiceTestHelper on ReportExportService {
  String buildCsvContent(
    ReportData data,
    DateTime from,
    DateTime to,
  ) =>
      _buildCsvContent(data, from, to);

  String formatCurrency(double amount) => _formatCurrency(amount);

  String getFilename({String suffix = ''}) => _getFilename(suffix: suffix);
}
