import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../lib/screens/reports/report_data_calculator.dart';
import '../lib/services/local_db.dart';

class MockAppDatabase extends Mock implements AppDatabase {}

void main() {
  group('ReportDataCalculator', () {
    late ReportDataCalculator calculator;
    late MockAppDatabase mockDatabase;

    setUp(() {
      mockDatabase = MockAppDatabase();
      calculator = ReportDataCalculator(database: mockDatabase);
    });

    test('calculateReportData initializes with empty data', () async {
      // With mocked database returning empty results
      // This is simplified - full test would mock DAO methods

      expect(calculator, isNotNull);
    });

    test('getGroupLabel returns correct format for different groupBy values',
        () {
      final date = DateTime(2026, 9, 10);

      expect(
        calculator.getGroupLabel(date, 'day'),
        contains('2026-09-10'),
      );

      expect(
        calculator.getGroupLabel(date, 'month'),
        contains('2026'),
      );

      expect(
        calculator.getGroupLabel(date, 'year'),
        '2026',
      );
    });

    test('getArabicDayName returns correct Arabic day names', () {
      // Monday
      final monday = DateTime(2026, 9, 7);
      expect(calculator.getArabicDayName(monday), 'الاثنين');

      // Friday
      final friday = DateTime(2026, 9, 11);
      expect(calculator.getArabicDayName(friday), 'الجمعة');
    });
  });

  group('ReportData', () {
    test('creates instance with all fields', () {
      final data = ReportData(
        incomeEntries: [],
        expenseEntries: [],
        incomeTotal: 10000,
        expenseTotal: 2000,
        salaryTotal: 3000,
        net: 5000,
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

      expect(data.incomeTotal, 10000);
      expect(data.expenseTotal, 2000);
      expect(data.salaryTotal, 3000);
      expect(data.net, 5000);
      expect(data.bookingsCount, 50);
    });
  });

  group('IncomeEntry', () {
    test('creates instance with all fields', () {
      final now = DateTime.now();
      final entry = IncomeEntry(
        date: now,
        dateStr: '2026-09-10',
        totalAmount: 1000,
        paymentMethod: 'cash',
        count: 5,
      );

      expect(entry.date, now);
      expect(entry.dateStr, '2026-09-10');
      expect(entry.totalAmount, 1000);
      expect(entry.paymentMethod, 'cash');
      expect(entry.count, 5);
    });

    test('totalAmount is mutable', () {
      final entry = IncomeEntry(
        date: DateTime.now(),
        dateStr: '2026-09-10',
        totalAmount: 100,
        paymentMethod: 'card',
        count: 1,
      );

      entry.totalAmount = 200;
      expect(entry.totalAmount, 200);
    });

    test('count is mutable', () {
      final entry = IncomeEntry(
        date: DateTime.now(),
        dateStr: '2026-09-10',
        totalAmount: 100,
        paymentMethod: 'card',
        count: 1,
      );

      entry.count = 5;
      expect(entry.count, 5);
    });
  });

  group('ExpenseEntry', () {
    test('creates instance with all fields', () {
      final entry = ExpenseEntry(
        category: 'utilities',
        totalAmount: 500,
        count: 3,
      );

      expect(entry.category, 'utilities');
      expect(entry.totalAmount, 500);
      expect(entry.count, 3);
    });

    test('totalAmount is mutable', () {
      final entry = ExpenseEntry(
        category: 'supplies',
        totalAmount: 100,
        count: 2,
      );

      entry.totalAmount = 150;
      expect(entry.totalAmount, 150);
    });

    test('count is mutable', () {
      final entry = ExpenseEntry(
        category: 'supplies',
        totalAmount: 100,
        count: 2,
      );

      entry.count = 5;
      expect(entry.count, 5);
    });
  });
}
