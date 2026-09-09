/// Data calculations and aggregations for income/expense reports.
///
/// Extracted from income_expense_report_screen.dart (2,944 LOC)
/// Handles data fetching, calculations, grouping, and filtering

import 'package:intl/intl.dart';

import '../../services/daos/bookings_dao.dart';
import '../../services/daos/debts_dao.dart';
import '../../services/daos/employees_dao.dart';
import '../../services/daos/expenses_dao.dart';
import '../../services/daos/outbox_dao.dart';
import '../../services/daos/payments_dao.dart';
import '../../services/local_db.dart';

/// Data calculation service for income/expense reports
class ReportDataCalculator {
  ReportDataCalculator({
    required this.database,
  });

  final AppDatabase database;

  /// Fetch and calculate report data for date range
  Future<ReportData> calculateReportData({
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    final outboxDao = OutboxDao(database);
    final paymentsDao = PaymentsDao(database, outboxDao);
    final expensesDao = ExpensesDao(database, outboxDao);
    final bookingsDao = BookingsDao(database, outboxDao);
    final debtsDao = DebtsDao(database);
    final employeesDao = EmployeesDao(database, outboxDao);

    // Fetch data for period
    final payments = await paymentsDao.getPaymentsInRange(fromDate, toDate);
    final expenses = await expensesDao.getExpensesInRange(fromDate, toDate);
    final bookings = await bookingsDao.allBookings();
    final debts = await debtsDao.allDebts();
    final employees = await employeesDao.allEmployees();

    // Calculate totals
    double incomeTotal = 0;
    double expenseTotal = 0;
    double salaryTotal = 0;

    for (final payment in payments) {
      incomeTotal += payment.amount ?? 0;
    }

    for (final expense in expenses) {
      if (expense.expenseType == 'salary') {
        salaryTotal += expense.amount ?? 0;
      } else {
        expenseTotal += expense.amount ?? 0;
      }
    }

    final net = incomeTotal - expenseTotal - salaryTotal;

    // Count statistics
    final activeBookings = bookings.where((b) => b.status == 'active').length;
    final checkoutBookings = bookings.where((b) => b.status == 'checkout').length;
    final unsettledDebts = debts.where((d) => d.status != 'settled').length;
    double unsettledAmount = 0;
    for (final debt in debts.where((d) => d.status != 'settled')) {
      unsettledAmount += debt.amount ?? 0;
    }

    final unsettledInPeriod = debts.where(
      (d) => d.status != 'settled' &&
          _isInRange(d.dateCreated, fromDate, toDate),
    ).length;
    double unsettledInPeriodAmount = 0;
    for (final debt in debts.where(
      (d) => d.status != 'settled' &&
          _isInRange(d.dateCreated, fromDate, toDate),
    )) {
      unsettledInPeriodAmount += debt.amount ?? 0;
    }

    final activeEmployees = employees.where((e) => e.status == 'active').length;
    final terminatedEmployees = employees.where((e) => e.status == 'terminated').length;

    return ReportData(
      incomeEntries: _groupIncomeEntries(payments),
      expenseEntries: _groupExpenseEntries(expenses),
      incomeTotal: incomeTotal,
      expenseTotal: expenseTotal,
      salaryTotal: salaryTotal,
      net: net,
      bookingsCount: bookings.length,
      activeBookingsCount: activeBookings,
      checkoutBookingsCount: checkoutBookings,
      totalDebtsCount: debts.length,
      unsettledDebtsCount: unsettledDebts,
      unsettledDebtsAmount: unsettledAmount,
      activeEmployeesCount: activeEmployees,
      terminatedEmployeesCount: terminatedEmployees,
      unsettledDebtsInPeriodCount: unsettledInPeriod,
      unsettledDebtsInPeriodAmount: unsettledInPeriodAmount,
    );
  }

  /// Group income entries by date
  List<IncomeEntry> _groupIncomeEntries(List<dynamic> payments) {
    final grouped = <String, IncomeEntry>{};

    for (final payment in payments) {
      final dateStr = _formatDate(payment.paymentDate ?? DateTime.now());
      final key = dateStr;

      if (!grouped.containsKey(key)) {
        grouped[key] = IncomeEntry(
          date: payment.paymentDate ?? DateTime.now(),
          dateStr: dateStr,
          totalAmount: 0,
          paymentMethod: payment.paymentMethod ?? 'unknown',
          count: 0,
        );
      }

      grouped[key]!.totalAmount += payment.amount ?? 0;
      grouped[key]!.count += 1;
    }

    return grouped.values.toList()..sort((a, b) => b.date.compareTo(a.date));
  }

  /// Group expense entries by category
  List<ExpenseEntry> _groupExpenseEntries(List<dynamic> expenses) {
    final grouped = <String, ExpenseEntry>{};

    for (final expense in expenses) {
      final category = expense.expenseType ?? 'other';

      if (!grouped.containsKey(category)) {
        grouped[category] = ExpenseEntry(
          category: category,
          totalAmount: 0,
          count: 0,
        );
      }

      grouped[category]!.totalAmount += expense.amount ?? 0;
      grouped[category]!.count += 1;
    }

    return grouped.values.toList();
  }

  /// Format date for display
  String _formatDate(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  /// Check if date is in range
  bool _isInRange(DateTime? date, DateTime from, DateTime to) {
    if (date == null) return false;
    return date.isAfter(from) && date.isBefore(to);
  }

  /// Get group label for grouping strategy
  String getGroupLabel(DateTime date, String groupBy) {
    final dateFormat = DateFormat('yyyy-MM-dd');
    switch (groupBy) {
      case 'day':
        return dateFormat.format(date);
      case 'week':
        return 'Week of ${dateFormat.format(date)}';
      case 'month':
        return DateFormat('MMMM yyyy').format(date);
      case 'year':
        return DateFormat('yyyy').format(date);
      default:
        return dateFormat.format(date);
    }
  }

  /// Get Arabic day name
  String getArabicDayName(DateTime date) {
    const names = ['الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];
    return names[date.weekday % 7];
  }
}

/// Report data model
class ReportData {
  ReportData({
    required this.incomeEntries,
    required this.expenseEntries,
    required this.incomeTotal,
    required this.expenseTotal,
    required this.salaryTotal,
    required this.net,
    required this.bookingsCount,
    required this.activeBookingsCount,
    required this.checkoutBookingsCount,
    required this.totalDebtsCount,
    required this.unsettledDebtsCount,
    required this.unsettledDebtsAmount,
    required this.activeEmployeesCount,
    required this.terminatedEmployeesCount,
    required this.unsettledDebtsInPeriodCount,
    required this.unsettledDebtsInPeriodAmount,
  });

  final List<IncomeEntry> incomeEntries;
  final List<ExpenseEntry> expenseEntries;
  final double incomeTotal;
  final double expenseTotal;
  final double salaryTotal;
  final double net;
  final int bookingsCount;
  final int activeBookingsCount;
  final int checkoutBookingsCount;
  final int totalDebtsCount;
  final int unsettledDebtsCount;
  final double unsettledDebtsAmount;
  final int activeEmployeesCount;
  final int terminatedEmployeesCount;
  final int unsettledDebtsInPeriodCount;
  final double unsettledDebtsInPeriodAmount;
}

/// Income entry model
class IncomeEntry {
  IncomeEntry({
    required this.date,
    required this.dateStr,
    required this.totalAmount,
    required this.paymentMethod,
    required this.count,
  });

  final DateTime date;
  final String dateStr;
  double totalAmount;
  final String paymentMethod;
  int count;
}

/// Expense entry model
class ExpenseEntry {
  ExpenseEntry({
    required this.category,
    required this.totalAmount,
    required this.count,
  });

  final String category;
  double totalAmount;
  int count;
}
