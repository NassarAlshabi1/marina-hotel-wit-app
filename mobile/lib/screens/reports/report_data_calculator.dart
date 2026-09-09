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
    final debtsDao = DebtsDao(database, outboxDao);
    final employeesDao = EmployeesDao(database, outboxDao);

    // Fetch data for period
    // التواريخ مخزّنة كنصوص: paymentDate بصيغة ISO الزمنية، و date للمصروفات
    // بصيغة yyyy-MM-dd — لذا تُمرّر حدود النطاق كسلاسل مقارنة معجمية صحيحة.
    final fromStr = _formatDate(fromDate);
    // حد أعلى حصري (يوم لاحق): يشمل كل دفعات toDate ذات التنسيق الزمني
    final toStr = _formatDate(toDate.add(const Duration(days: 1)));
    final payments = await paymentsDao.listForReport(from: fromStr, to: toStr);
    // تاريخ المصروف مخزّن yyyy-MM-dd بالضبط — المقارنة المباشرة كافية
    final allExpenses = await expensesDao.listFiltered(
      from: fromStr,
      to: _formatDate(toDate),
    );

    final bookings = await bookingsDao.list();
    final debts = await debtsDao.list();
    final employees = await employeesDao.list();

    // Calculate totals
    double incomeTotal = 0;
    double expenseTotal = 0;
    double salaryTotal = 0;

    for (final payment in payments) {
      incomeTotal += payment.amount;
    }

    for (final expense in allExpenses) {
      if (expense.expenseType == 'salary') {
        salaryTotal += expense.amount;
      } else {
        expenseTotal += expense.amount;
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
      (d) =>
          d.status != 'settled' &&
          _isDateInRange(d.dateRecorded, fromDate, toDate),
    ).length;
    double unsettledInPeriodAmount = 0;
    for (final debt in debts.where(
      (d) =>
          d.status != 'settled' &&
          _isDateInRange(d.dateRecorded, fromDate, toDate),
    )) {
      unsettledInPeriodAmount += debt.amount ?? 0;
    }

    final activeEmployees = employees.where((e) => e.status == 'active').length;
    final terminatedEmployees = employees.where((e) => e.status == 'terminated').length;

    return ReportData(
      incomeEntries: _groupIncomeEntries(payments),
      expenseEntries: _groupExpenseEntries(allExpenses),
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
  List<IncomeEntry> _groupIncomeEntries(List<Payment> payments) {
    final grouped = <String, IncomeEntry>{};

    for (final payment in payments) {
      final paidAt = DateTime.tryParse(payment.paymentDate) ?? DateTime.now();
      final dateStr = _formatDate(paidAt);
      final key = dateStr;

      if (!grouped.containsKey(key)) {
        grouped[key] = IncomeEntry(
          date: paidAt,
          dateStr: dateStr,
          totalAmount: 0,
          paymentMethod: payment.paymentMethod,
          count: 0,
        );
      }

      grouped[key]!.totalAmount += payment.amount;
      grouped[key]!.count += 1;
    }

    return grouped.values.toList()..sort((a, b) => b.date.compareTo(a.date));
  }

  /// Group expense entries by category
  List<ExpenseEntry> _groupExpenseEntries(List<Expense> expenses) {
    final grouped = <String, ExpenseEntry>{};

    for (final expense in expenses) {
      final category = expense.expenseType;

      if (!grouped.containsKey(category)) {
        grouped[category] = ExpenseEntry(
          category: category,
          totalAmount: 0,
          count: 0,
        );
      }

      grouped[category]!.totalAmount += expense.amount;
      grouped[category]!.count += 1;
    }

    return grouped.values.toList();
  }

  /// Format date for display
  String _formatDate(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  /// Check if date is in range (inclusive bounds).
  ///
  /// يقبل صيغ التاريخ المخزنة نصياً ('yyyy-MM-dd' أو ISO-8601)،
  /// ويعيد false للقيم الفارغة أو غير القابلة للتحليل.
  bool _isDateInRange(String? dateStr, DateTime from, DateTime to) {
    if (dateStr == null || dateStr.isEmpty) return false;
    final parsed = DateTime.tryParse(dateStr);
    if (parsed == null) return false;
    return !parsed.isBefore(from) && !parsed.isAfter(to);
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
