import 'local_db.dart';

class SalaryEntitlement {
  SalaryEntitlement({
    required this.employee,
    required this.hireDate,
    required this.totalMonthsWorked,
    required this.basicSalary,
    required this.totalEntitlement,
    required this.totalWithdrawals,
    required this.totalDeductions,
    required this.netEntitlement,
    required this.transactions,
  });
  final Employee employee;
  final DateTime hireDate;
  final int totalMonthsWorked;
  final double basicSalary;
  final double totalEntitlement;
  final double totalWithdrawals;
  final double totalDeductions;
  final double netEntitlement;
  final List<SalaryTransaction> transactions;
}

class SalaryTransaction {
  SalaryTransaction({
    required this.type,
    required this.amount,
    required this.date,
    this.note,
  });
  final String type;
  final double amount;
  final String date;
  final String? note;
}

class SalaryEntitlementService {
  SalaryEntitlementService(this._db);
  final AppDatabase _db;

  Future<List<SalaryEntitlement>> calculateAllEntitlements() async {
    final employees = await (_db.select(
      _db.employees,
    )..where((e) => e.status.equals('active')))
        .get();

    final entitlements = <SalaryEntitlement>[];
    for (final employee in employees) {
      final entitlement = await calculateEmployeeEntitlement(employee);
      entitlements.add(entitlement);
    }
    return entitlements;
  }

  Future<SalaryEntitlement> calculateEmployeeEntitlement(
    Employee employee,
  ) async {
    final now = DateTime.now();
    DateTime hireDate;
    try {
      hireDate = employee.hireDate.isNotEmpty
          ? DateTime.parse(employee.hireDate)
          : now;
    } catch (e) {
      hireDate = now;
    }

    final totalMonthsWorked = _calculateMonthsDifference(hireDate, now);
    final totalEntitlement = totalMonthsWorked * employee.basicSalary;

    final expenses = await (_db.select(
      _db.expenses,
    )..where((e) => e.relatedId.equals(employee.id)))
        .get();

    double totalWithdrawals = 0;
    double totalDeductions = 0;
    final transactions = <SalaryTransaction>[];

    for (final expense in expenses) {
      final type = expense.expenseType.trim();
      if (type == 'سحب راتب' || type == 'سلفة' || type == 'رواتب') {
        totalWithdrawals += expense.amount;
        transactions.add(
          SalaryTransaction(
            type: 'سحب',
            amount: expense.amount,
            date: expense.date,
            note: expense.description,
          ),
        );
      } else if (type == 'خصم راتب' || type == 'خصم' || type == 'غياب') {
        totalDeductions += expense.amount;
        transactions.add(
          SalaryTransaction(
            type: 'خصم',
            amount: expense.amount,
            date: expense.date,
            note: expense.description,
          ),
        );
      }
    }

    transactions.sort((a, b) => b.date.compareTo(a.date));
    final netEntitlement =
        totalEntitlement - totalWithdrawals - totalDeductions;

    return SalaryEntitlement(
      employee: employee,
      hireDate: hireDate,
      totalMonthsWorked: totalMonthsWorked,
      basicSalary: employee.basicSalary,
      totalEntitlement: totalEntitlement,
      totalWithdrawals: totalWithdrawals,
      totalDeductions: totalDeductions,
      netEntitlement: netEntitlement,
      transactions: transactions,
    );
  }

  int _calculateMonthsDifference(DateTime from, DateTime to) {
    int months = (to.year - from.year) * 12 + (to.month - from.month);
    if (to.day < from.day) months--;
    return months < 0 ? 0 : months;
  }

  Future<Map<String, dynamic>> getSummary() async {
    final entitlements = await calculateAllEntitlements();
    double totalEntitlements = 0,
        totalWithdrawals = 0,
        totalDeductions = 0,
        totalNet = 0;
    for (final e in entitlements) {
      totalEntitlements += e.totalEntitlement;
      totalWithdrawals += e.totalWithdrawals;
      totalDeductions += e.totalDeductions;
      totalNet += e.netEntitlement;
    }
    return {
      'count': entitlements.length,
      'totalEntitlements': totalEntitlements,
      'totalWithdrawals': totalWithdrawals,
      'totalDeductions': totalDeductions,
      'totalNet': totalNet,
      'entitlements': entitlements,
    };
  }
}
