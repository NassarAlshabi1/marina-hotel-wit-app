import 'package:flutter/foundation.dart';
import 'local_db.dart';

class SalaryEntitlement {
  final Employee employee;
  final DateTime hireDate;
  final int totalMonthsWorked;
  final int totalDaysWorked;
  final double basicSalary;
  final double totalEntitlement;
  final double totalWithdrawals;
  final double totalDeductions;
  final double totalAbsenceDeductions;
  final double netEntitlement;
  final List<SalaryTransaction> transactions;

  SalaryEntitlement({
    required this.employee,
    required this.hireDate,
    required this.totalMonthsWorked,
    required this.totalDaysWorked,
    required this.basicSalary,
    required this.totalEntitlement,
    required this.totalWithdrawals,
    required this.totalDeductions,
    required this.totalAbsenceDeductions,
    required this.netEntitlement,
    required this.transactions,
  });
}

class SalaryTransaction {
  final String type;
  final double amount;
  final String date;
  final String? note;

  SalaryTransaction({
    required this.type,
    required this.amount,
    required this.date,
    this.note,
  });
}

class SalaryEntitlementService {
  final AppDatabase _db;

  SalaryEntitlementService(this._db);

  static const Set<String> _salaryExpenseTypes = {
    'salary',
    'salaries',
    'salary_withdrawal',
    'salary-withdrawal',
    'salary_deduction',
    'salary-deduction',
    'رواتب',
    'سحب راتب',
    'سحب من الراتب',
    'خصم راتب',
    'خصم من الراتب',
    'سلفة',
    'سلفة راتب',
  };

  static const Set<String> _deductionTypes = {
    'خصم',
    'خصم راتب',
    'خصم من الراتب',
    'salary_deduction',
    'salary-deduction',
    'deduction',
  };

  static const Set<String> _absenceTypes = {
    'غياب',
    'خصم غياب',
    'absence',
    'absence_deduction',
  };

  Future<List<SalaryEntitlement>> calculateAllEntitlements() async {
    final employees = await (_db.select(_db.employees)
          ..where((e) => e.status.equals('active')))
        .get();

    final entitlements = <SalaryEntitlement>[];

    for (final employee in employees) {
      final entitlement = await calculateEmployeeEntitlement(employee);
      entitlements.add(entitlement);
    }

    return entitlements;
  }

  Future<SalaryEntitlement> calculateEmployeeEntitlement(Employee employee) async {
    final now = DateTime.now();
    DateTime hireDate;

    try {
      hireDate = employee.hireDate.isNotEmpty
          ? DateTime.parse(employee.hireDate)
          : now;
    } catch (e) {
      hireDate = now;
    }

    final totalDaysWorked = now.difference(hireDate).inDays;
    final totalMonthsWorked = _calculateMonthsDifference(hireDate, now);

    final dailySalary = employee.basicSalary / 30;
    final totalEntitlement = totalMonthsWorked * employee.basicSalary;

    final expenses = await (_db.select(_db.expenses)
          ..where((e) => e.relatedId.equals(employee.id)))
        .get();

    double totalWithdrawals = 0;
    double totalDeductions = 0;
    double totalAbsenceDeductions = 0;
    final transactions = <SalaryTransaction>[];

    for (final expense in expenses) {
      final expenseType = expense.expenseType.toLowerCase();

      if (_salaryExpenseTypes.any((t) => expenseType.contains(t.toLowerCase()))) {
        if (_deductionTypes.any((t) => expenseType.contains(t.toLowerCase()))) {
          totalDeductions += expense.amount;
          transactions.add(SalaryTransaction(
            type: 'خصم',
            amount: expense.amount,
            date: expense.date,
            note: expense.description,
          ));
        } else if (_absenceTypes.any((t) => expenseType.contains(t.toLowerCase()))) {
          totalAbsenceDeductions += expense.amount;
          transactions.add(SalaryTransaction(
            type: 'خصم غياب',
            amount: expense.amount,
            date: expense.date,
            note: expense.description,
          ));
        } else {
          totalWithdrawals += expense.amount;
          transactions.add(SalaryTransaction(
            type: 'سحب/سلفة',
            amount: expense.amount,
            date: expense.date,
            note: expense.description,
          ));
        }
      }
    }

    final salaryPayments = await (_db.select(_db.salaryPayments)
          ..where((p) {
            final cycleQuery = _db.select(_db.salaryCycles)
              ..where((c) => c.employeeId.equals(employee.id));
            return p.cycleId.isInQuery(cycleQuery.map((c) => c.id));
          }))
        .get();

    for (final payment in salaryPayments) {
      totalWithdrawals += payment.amount;
      transactions.add(SalaryTransaction(
        type: 'دفعة راتب',
        amount: payment.amount,
        date: payment.paymentDateIso,
        note: payment.method,
      ));
    }

    transactions.sort((a, b) => b.date.compareTo(a.date));

    final netEntitlement = totalEntitlement - totalWithdrawals - totalDeductions - totalAbsenceDeductions;

    return SalaryEntitlement(
      employee: employee,
      hireDate: hireDate,
      totalMonthsWorked: totalMonthsWorked,
      totalDaysWorked: totalDaysWorked,
      basicSalary: employee.basicSalary,
      totalEntitlement: totalEntitlement,
      totalWithdrawals: totalWithdrawals,
      totalDeductions: totalDeductions,
      totalAbsenceDeductions: totalAbsenceDeductions,
      netEntitlement: netEntitlement,
      transactions: transactions,
    );
  }

  int _calculateMonthsDifference(DateTime from, DateTime to) {
    int months = (to.year - from.year) * 12 + (to.month - from.month);
    if (to.day < from.day) {
      months--;
    }
    return months < 0 ? 0 : months;
  }

  Future<Map<String, dynamic>> getSummary() async {
    final entitlements = await calculateAllEntitlements();
    
    double totalBasicSalaries = 0;
    double totalEntitlements = 0;
    double totalWithdrawals = 0;
    double totalDeductions = 0;
    double totalNetEntitlements = 0;

    for (final e in entitlements) {
      totalBasicSalaries += e.basicSalary;
      totalEntitlements += e.totalEntitlement;
      totalWithdrawals += e.totalWithdrawals;
      totalDeductions += e.totalDeductions + e.totalAbsenceDeductions;
      totalNetEntitlements += e.netEntitlement;
    }

    return {
      'employeeCount': entitlements.length,
      'totalBasicSalaries': totalBasicSalaries,
      'totalEntitlements': totalEntitlements,
      'totalWithdrawals': totalWithdrawals,
      'totalDeductions': totalDeductions,
      'totalNetEntitlements': totalNetEntitlements,
      'entitlements': entitlements,
    };
  }
}
