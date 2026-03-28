import 'local_db.dart';

/// نتيجة حساب استحقاق الموظف
class SalaryEntitlement {
  SalaryEntitlement({
    required this.employee,
    required this.employeeName,
    required this.hireDate,
    required this.daysWorked,
    required this.totalMonthsWorked,
    required this.basicSalary,
    required this.dailyRate,
    required this.totalEntitlement,
    required this.totalWithdrawals,
    required this.totalDeductions,
    required this.totalPaid,
    required this.netEntitlement,
    required this.transactions,
  });

  final Employee employee;
  final String employeeName;
  final DateTime hireDate;
  final int daysWorked;
  final int totalMonthsWorked;
  final double basicSalary;
  final double dailyRate;
  final double totalEntitlement;      // إجمالي المستحق
  final double totalWithdrawals;      // إجمالي المسحوبات
  final double totalDeductions;       // إجمالي الخصومات
  final double totalPaid;             // إجمالي المدفوع (مسحوبات + خصومات)
  final double netEntitlement;        // المتبقي
  final List<SalaryTransaction> transactions;

  /// نسبة الاستحقاق من الراتب الشهري
  double get currentMonthProgress {
    final now = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    return now.day / daysInMonth;
  }
}

/// معاملة راتب واحدة
class SalaryTransaction {
  SalaryTransaction({
    required this.id,
    required this.type,
    required this.action,
    required this.amount,
    required this.date,
    this.note,
    this.expenseId,
  });

  final int id;
  final String type;      // 'سحب' أو 'خصم'
  final String action;    // الإجراء الفعلي
  final double amount;
  final String date;
  final String? note;
  final int? expenseId;
}

/// خدمة حساب استحقاقات الموظفين
class SalaryEntitlementService {
  SalaryEntitlementService(this._db);
  final AppDatabase _db;

  /// حساب استحقاق موظف واحد
  /// 
  /// المعادلة:
  /// - الراتب اليومي = الراتب الأساسي / 30
  /// - الأيام العمل = من تاريخ التعيين حتى اليوم
  /// - المستحق = الراتب اليومي × الأيام
  /// - المتبقي = المستحق - (المسحوبات + الخصومات)
  Future<SalaryEntitlement> calculateEmployeeEntitlement(
    Employee employee,
  ) async {
    final now = DateTime.now();
    
    // تاريخ التعيين
    DateTime hireDate;
    try {
      hireDate = employee.hireDate.isNotEmpty
          ? DateTime.parse(employee.hireDate)
          : now;
    } catch (e) {
      hireDate = now;
    }

    // حساب الأيام والشهور
    final daysWorked = now.difference(hireDate).inDays;
    final totalMonthsWorked = _calculateMonthsDifference(hireDate, now);

    // الراتب اليومي (على أساس 30 يوم)
    final dailyRate = employee.basicSalary / 30;
    
    // إجمالي المستحق
    final totalEntitlement = dailyRate * daysWorked;

    // جلب المسحوبات من salary_withdrawals
    final withdrawals = await (_db.select(_db.salaryWithdrawals)
          ..where((t) => t.employeeId.equals(employee.id)))
        .get();

    double totalWithdrawals = 0;
    double totalDeductions = 0;
    final transactions = <SalaryTransaction>[];

    for (final w in withdrawals) {
      final action = w.action.trim();
      final amount = w.amount;

      // تصنيف المعاملة
      bool isWithdrawal = _isWithdrawalAction(action);
      bool isDeduction = _isDeductionAction(action);

      if (isWithdrawal) {
        totalWithdrawals += amount;
        transactions.add(SalaryTransaction(
          id: w.id,
          type: 'سحب',
          action: action,
          amount: amount,
          date: w.date,
          note: w.note,
          expenseId: w.expenseId,
        ));
      } else if (isDeduction) {
        totalDeductions += amount;
        transactions.add(SalaryTransaction(
          id: w.id,
          type: 'خصم',
          action: action,
          amount: amount,
          date: w.date,
          note: w.note,
          expenseId: w.expenseId,
        ));
      } else {
        // افتراضياً: سحب
        totalWithdrawals += amount;
        transactions.add(SalaryTransaction(
          id: w.id,
          type: 'سحب',
          action: action,
          amount: amount,
          date: w.date,
          note: w.note,
          expenseId: w.expenseId,
        ));
      }
    }

    // ترتيب المعاملات حسب التاريخ (الأحدث أولاً)
    transactions.sort((a, b) => b.date.compareTo(a.date));

    // المجموع المدفوع والمتبقي
    final totalPaid = totalWithdrawals + totalDeductions;
    final netEntitlement = totalEntitlement - totalPaid;

    return SalaryEntitlement(
      employee: employee,
      employeeName: employee.name,
      hireDate: hireDate,
      daysWorked: daysWorked,
      totalMonthsWorked: totalMonthsWorked,
      basicSalary: employee.basicSalary,
      dailyRate: dailyRate,
      totalEntitlement: totalEntitlement,
      totalWithdrawals: totalWithdrawals,
      totalDeductions: totalDeductions,
      totalPaid: totalPaid,
      netEntitlement: netEntitlement,
      transactions: transactions,
    );
  }

  /// حساب استحقاقات جميع الموظفين النشطين
  Future<List<SalaryEntitlement>> calculateAllEntitlements() async {
    final employees = await (_db.select(_db.employees)
          ..where((e) => e.status.equals('active')))
        .get();

    final entitlements = <SalaryEntitlement>[];
    for (final employee in employees) {
      final entitlement = await calculateEmployeeEntitlement(employee);
      entitlements.add(entitlement);
    }

    // ترتيب حسب المتبقي (الأعلى أولاً)
    entitlements.sort((a, b) => b.netEntitlement.compareTo(a.netEntitlement));

    return entitlements;
  }

  /// ملخص عام لجميع الموظفين
  Future<Map<String, dynamic>> getSummary() async {
    final entitlements = await calculateAllEntitlements();

    double totalEntitlements = 0;
    double totalWithdrawals = 0;
    double totalDeductions = 0;
    double totalPaid = 0;
    double totalNet = 0;

    for (final e in entitlements) {
      totalEntitlements += e.totalEntitlement;
      totalWithdrawals += e.totalWithdrawals;
      totalDeductions += e.totalDeductions;
      totalPaid += e.totalPaid;
      totalNet += e.netEntitlement;
    }

    return {
      'employeeCount': entitlements.length,
      'totalEntitlements': totalEntitlements,
      'totalWithdrawals': totalWithdrawals,
      'totalDeductions': totalDeductions,
      'totalPaid': totalPaid,
      'totalNet': totalNet,
      'entitlements': entitlements,
      'generatedAt': DateTime.now().toIso8601String(),
    };
  }

  /// حساب استحقاق موظف واحد حسب الـ ID
  Future<SalaryEntitlement?> calculateById(int employeeId) async {
    final employee = await (_db.select(_db.employees)
          ..where((t) => t.id.equals(employeeId)))
        .getSingleOrNull();

    if (employee == null) return null;
    return calculateEmployeeEntitlement(employee);
  }

  /// حساب فرق الشهور بين تاريخين
  int _calculateMonthsDifference(DateTime from, DateTime to) {
    int months = (to.year - from.year) * 12 + (to.month - from.month);
    if (to.day < from.day) months--;
    return months < 0 ? 0 : months;
  }

  /// تحديد ما إذا كان الإجراء سحب
  bool _isWithdrawalAction(String action) {
    const withdrawalActions = [
      'سحب من الراتب',
      'سحب راتب',
      'سلفة',
      'سلفة راتب',
      'مقابل مالي',
      'مساعدة مالية',
    ];
    return withdrawalActions.any((a) => action.contains(a) || a.contains(action));
  }

  /// تحديد ما إذا كان الإجراء خصم
  bool _isDeductionAction(String action) {
    const deductionActions = [
      'خصم من الراتب',
      'خصم راتب',
      'خصم',
      'غياب',
      'تأخير',
      'جزاء',
      'عقوبة',
    ];
    return deductionActions.any((a) => action.contains(a) || a.contains(action));
  }
}
