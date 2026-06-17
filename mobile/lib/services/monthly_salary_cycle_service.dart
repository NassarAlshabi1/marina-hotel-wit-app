// lib/services/monthly_salary_cycle_service.dart
import 'dart:convert';

import 'package:drift/drift.dart' as d;
import 'package:flutter/foundation.dart';

import 'local_db.dart';
import 'utils/id.dart';
import 'utils/status_utils.dart';
import 'utils/time.dart';

/// ═══════════════════════════════════════════════════════════════
/// نظام احتساب الاستحقاق الشهري للموظفين
/// ═══════════════════════════════════════════════════════════════
///
/// آلية احتساب الشهر:
/// تعتمد على تاريخ التوظيف لكل موظف، وليس بداية الشهر الميلادي.
///
/// مثال: موظف توظف في 11-06-2026
///   الدورة 1: 11-06-2026 → 10-07-2026
///   الدورة 2: 11-07-2026 → 10-08-2026
///   ...وهكذا
///
/// معادلة المتبقي:
///   المتبقي = الراتب الأساسي - السلف - المسحوبات - الخصومات - المرحّل من سابق
///
/// تجاوز الراتب:
///   إذا المتبقي < 0 → الموظف مدين بالمبلغ → يُرحّل للشهر التالي
///
/// الترحيل التلقائي:
///   عند بدء دورة جديدة، يُخصم المبلغ المرحّل من استحقاقها
///   ويُسجّل في salary_carry_over_logs
///

/// نموذج دورة الراتب الشهرية
class MonthlySalaryCycle {
  MonthlySalaryCycle({
    required this.employee,
    required this.cycleStart,
    required this.cycleEnd,
    required this.basicSalary,
    required this.totalWithdrawals,
    required this.totalDeductions,
    required this.totalAdvances,
    required this.carriedOverFromPrevious,
    required this.transactions,
    required this.carryOverLogs,
  });

  final Employee employee;
  final DateTime cycleStart;
  final DateTime cycleEnd;
  final double basicSalary;
  final double totalWithdrawals;
  final double totalDeductions;
  final double totalAdvances;
  final double carriedOverFromPrevious;
  final List<SalaryCycleTransaction> transactions;
  final List<SalaryCarryOverLog> carryOverLogs;

  /// إجمالي المبالغ المسحوبة = مسحوبات + خصومات + سلف + مرحّل
  double get totalDeductionsAndWithdrawals =>
      totalWithdrawals + totalDeductions + totalAdvances + carriedOverFromPrevious;

  /// المتبقي = الراتب - إجمالي المسحوب
  double get remainingBalance => basicSalary - totalDeductionsAndWithdrawals;

  /// هل تجاوز الموظف راتبه؟
  bool get hasExceeded => remainingBalance < 0;

  /// المبلغ المرحّل للشهر التالي (إذا تجاوز)
  double get carryOverToNext => hasExceeded ? remainingBalance.abs() : 0.0;

  /// المبلغ المتاح للسحب
  double get availableToWithdraw =>
      remainingBalance > 0 ? remainingBalance : 0.0;

  /// مفتاح الدورة للعرض
  String get cycleKey =>
      '${cycleStart.day}/${cycleStart.month}/${cycleStart.year} → '
      '${cycleEnd.day}/${cycleEnd.month}/${cycleEnd.year}';

  /// اسم الشهر
  String get monthLabel {
    const months = [
      '', 'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
      'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
    ];
    return '${months[cycleStart.month]} ${cycleStart.year}';
  }
}

/// معاملة ضمن دورة راتب
class SalaryCycleTransaction {
  SalaryCycleTransaction({
    required this.type,
    required this.amount,
    required this.date,
    this.note,
    this.category,
    this.isCarryOver = false,
  });

  final String type;
  final double amount;
  final String date;
  final String? note;
  final String? category;
  final bool isCarryOver;
}

/// خدمة حساب دورات الرواتب الشهرية مع الترحيل التلقائي
class MonthlySalaryCycleService {
  MonthlySalaryCycleService(this._db);
  final AppDatabase _db;

  /// حساب الدورة الشهرية الحالية للموظف
  Future<MonthlySalaryCycle> calculateCurrentCycle(Employee employee) async {
    final now = DateTime.now();
    final hireDate = _parseDate(employee.hireDate) ?? now;

    final cycleStart = _getCycleStart(hireDate, now);
    final cycleEnd = _getCycleEnd(cycleStart);

    // احسب الترحيل من الدورات السابقة
    final carriedOver = await _calculateAccumulatedCarryOver(employee, hireDate, cycleStart);

    // جلب معاملات الدورة
    final cycleTxns = await _getCycleTransactions(employee, cycleStart, cycleEnd);

    // جلب سجلات الترحيل المرتبطة بهذه الدورة
    final carryOverLogs = await _getCarryOverLogsForCycle(employee.id, cycleStart, cycleEnd);

    return MonthlySalaryCycle(
      employee: employee,
      cycleStart: cycleStart,
      cycleEnd: cycleEnd,
      basicSalary: employee.basicSalary,
      totalWithdrawals: cycleTxns.withdrawals,
      totalDeductions: cycleTxns.deductions,
      totalAdvances: cycleTxns.advances,
      carriedOverFromPrevious: carriedOver,
      transactions: cycleTxns.transactions,
      carryOverLogs: carryOverLogs,
    );
  }

  /// حساب كل الدورات الشهرية للموظف
  Future<List<MonthlySalaryCycle>> calculateAllCycles(Employee employee) async {
    final now = DateTime.now();
    final hireDate = _parseDate(employee.hireDate) ?? now;

    final cycles = <MonthlySalaryCycle>[];
    var cycleStart = _getCycleStart(hireDate, hireDate);
    var carriedOver = 0.0;

    while (cycleStart.isBefore(now) || cycleStart.isAtSameMomentAs(now)) {
      final cycleEnd = _getCycleEnd(cycleStart);
      final txns = await _getCycleTransactions(employee, cycleStart, cycleEnd);
      final carryOverLogs = await _getCarryOverLogsForCycle(employee.id, cycleStart, cycleEnd);

      // إضافة معاملة الترحيل للعرض
      final displayTransactions = List<SalaryCycleTransaction>.from(txns.transactions);
      if (carriedOver > 0) {
        displayTransactions.insert(0, SalaryCycleTransaction(
          type: 'ترحيل',
          amount: carriedOver,
          date: _formatDate(cycleStart),
          note: 'مبلغ مرحّل من الدورة السابقة لتجاوز السحب',
          category: 'ترحيل',
          isCarryOver: true,
        ));
      }

      final cycle = MonthlySalaryCycle(
        employee: employee,
        cycleStart: cycleStart,
        cycleEnd: cycleEnd,
        basicSalary: employee.basicSalary,
        totalWithdrawals: txns.withdrawals,
        totalDeductions: txns.deductions,
        totalAdvances: txns.advances,
        carriedOverFromPrevious: carriedOver,
        transactions: displayTransactions,
        carryOverLogs: carryOverLogs,
      );

      // حساب الترحيل للشهر التالي
      carriedOver = cycle.carryOverToNext;

      cycles.add(cycle);

      // الانتقال للدورة التالية
      final nextStart = cycleEnd.add(const Duration(days: 1));
      if (nextStart.isAfter(now)) break;
      cycleStart = nextStart;
    }

    return cycles.reversed.toList();
  }

  /// ═══════════════════════════════════════════════════════════
  /// الترحيل التلقائي — ينشئ سجل ترحيل عند تجاوز الراتب
  /// ═══════════════════════════════════════════════════════════

  /// فحص وإنشاء ترحيل تلقائي للموظف إذا تجاوز راتبه في الدورة السابقة.
  ///
  /// تُستدعى عند:
  /// - بدء دورة جديدة (عند فتح شاشة الرواتب)
  /// - يدوياً من زر "فحص الترحيل"
  Future<void> processAutoCarryOver(Employee employee) async {
    final now = DateTime.now();
    final hireDate = _parseDate(employee.hireDate) ?? now;
    final currentCycleStart = _getCycleStart(hireDate, now);

    // الدورة السابقة
    final previousCycleEnd = currentCycleStart.subtract(const Duration(days: 1));
    final previousCycleStart = _getCycleStart(hireDate, previousCycleEnd);

    if (previousCycleStart.isBefore(hireDate)) return; // لا توجد دورة سابقة

    // احسب التراكمي من كل الدورات السابقة
    final carriedOver = await _calculateAccumulatedCarryOver(
      employee, hireDate, currentCycleStart,
    );

    if (carriedOver <= 0) return; // لا يوجد تجاوز

    // تحقق من عدم وجود سجل ترحيل سابق لهذه الدورة (منع التكرار)
    final existing = await _checkExistingCarryOver(
      employee.id, previousCycleStart, currentCycleStart,
    );
    if (existing) return; // سبق ترحيله — منع التكرار

    // إنشاء سجل الترحيل
    final currentCycleEnd = _getCycleEnd(currentCycleStart);
    final reason = 'تم ترحيل مبلغ ${carriedOver.toStringAsFixed(0)} ريال '
        'إلى دورة الراتب التالية '
        'بسبب تجاوز إجمالي السحوبات والخصومات للراتب '
        'في دورة ${_formatDate(previousCycleStart)} إلى ${_formatDate(previousCycleEnd)}.';

    await _createCarryOverLog(
      employeeId: employee.id,
      amount: carriedOver,
      previousCycleStart: previousCycleStart,
      previousCycleEnd: previousCycleEnd,
      newCycleStart: currentCycleStart,
      newCycleEnd: currentCycleEnd,
      reason: reason,
    );

    debugPrint('📝 تم إنشاء ترحيل تلقائي: $carriedOver للموظف ${employee.name}');
  }

  /// إنشاء سجل ترحيل في قاعدة البيانات
  Future<void> _createCarryOverLog({
    required int employeeId,
    required double amount,
    required DateTime previousCycleStart,
    required DateTime previousCycleEnd,
    required DateTime newCycleStart,
    required DateTime newCycleEnd,
    required String reason,
  }) async {
    final now = Time.nowEpoch();
    final uuid = IdGen.uuid();

    await _db.into(_db.salaryCarryOverLogs).insert(
      SalaryCarryOverLogsCompanion.insert(
        employeeId: employeeId,
        amount: amount,
        previousCycleStart: _formatDate(previousCycleStart),
        previousCycleEnd: _formatDate(previousCycleEnd),
        newCycleStart: _formatDate(newCycleStart),
        newCycleEnd: _formatDate(newCycleEnd),
        reason: reason,
        carriedAt: now,
        localUuid: uuid,
        createdAt: now,
        updatedAt: now,
        lastModified: now,
      ),
    );
  }

  /// التحقق من وجود سجل ترحيل سابق لمنع التكرار
  Future<bool> _checkExistingCarryOver(
    int employeeId,
    DateTime previousCycleStart,
    DateTime newCycleStart,
  ) async {
    final prevStartStr = _formatDate(previousCycleStart);
    final newStartStr = _formatDate(newCycleStart);

    final result = await (_db.select(_db.salaryCarryOverLogs)
          ..where((t) => t.employeeId.equals(employeeId))
          ..where((t) => t.previousCycleStart.equals(prevStartStr))
          ..where((t) => t.newCycleStart.equals(newStartStr))
          ..where((t) => t.deletedAt.isNull())
          ..limit(1))
        .get();

    return result.isNotEmpty;
  }

  /// جلب سجلات الترحيل لدورة معينة
  Future<List<SalaryCarryOverLog>> _getCarryOverLogsForCycle(
    int employeeId,
    DateTime cycleStart,
    DateTime cycleEnd,
  ) async {
    final startStr = _formatDate(cycleStart);
    final endStr = _formatDate(cycleEnd);

    return (_db.select(_db.salaryCarryOverLogs)
          ..where((t) => t.employeeId.equals(employeeId))
          ..where((t) => t.deletedAt.isNull())
          ..where((t) => t.newCycleStart.equals(startStr) | t.previousCycleStart.equals(startStr))
          ..orderBy([(t) => d.OrderingTerm.desc(t.carriedAt)]))
        .get();
  }

  /// جلب كل سجلات الترحيل لموظف (للعرض في التقارير)
  Future<List<SalaryCarryOverLog>> getAllCarryOverLogs(int employeeId) async {
    return (_db.select(_db.salaryCarryOverLogs)
          ..where((t) => t.employeeId.equals(employeeId))
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => d.OrderingTerm.desc(t.carriedAt)]))
        .get();
  }

  /// ═══════════════════════════════════════════════════════════
  /// حساب الترحيل التراكمي
  /// ═══════════════════════════════════════════════════════════

  /// احسب الترحيل المتراكم من كل الدورات السابقة حتى الدورة الحالية.
  ///
  /// يبدأ من أول دورة ويحسب المتبقي لكل دورة:
  /// المتبقي = الراتب - (مسحوبات + خصومات + سلف + ترحيل سابق)
  /// إذا المتبقي < 0 → الترحيل = |المتبقي|
  /// إذا المتبقي ≥ 0 → الترحيل = 0
  Future<double> _calculateAccumulatedCarryOver(
    Employee employee,
    DateTime hireDate,
    DateTime targetCycleStart,
  ) async {
    var cycleStart = _getCycleStart(hireDate, hireDate);
    var carryOver = 0.0;

    while (cycleStart.isBefore(targetCycleStart)) {
      final cycleEnd = _getCycleEnd(cycleStart);
      final txns = await _getCycleTransactions(employee, cycleStart, cycleEnd);

      final totalDeductions = txns.withdrawals + txns.deductions + txns.advances + carryOver;
      final remaining = employee.basicSalary - totalDeductions;

      if (remaining < 0) {
        carryOver = remaining.abs();
      } else {
        carryOver = 0.0;
      }

      cycleStart = cycleEnd.add(const Duration(days: 1));
    }

    return carryOver;
  }

  /// ═══════════════════════════════════════════════════════════
  /// جلب معاملات الدورة
  /// ═══════════════════════════════════════════════════════════

  Future<_CycleTransactions> _getCycleTransactions(
    Employee employee,
    DateTime cycleStart,
    DateTime cycleEnd,
  ) async {
    final expenses = await (_db.select(_db.expenses)
          ..where((e) => e.relatedId.equals(employee.id))
          ..where((e) => e.deletedAt.isNull()))
        .get();

    double withdrawals = 0;
    double deductions = 0;
    double advances = 0;
    final transactions = <SalaryCycleTransaction>[];

    for (final expense in expenses) {
      final expDate = _parseDate(expense.date);
      if (expDate == null) continue;

      // فلترة: فقط المعاملات ضمن هذه الدورة
      if (expDate.isBefore(cycleStart) || expDate.isAfter(cycleEnd)) continue;

      final type = expense.expenseType.trim();

      if (type == 'سحب راتب' || type == 'رواتب' || type == 'سحب من الراتب') {
        withdrawals += expense.amount;
        transactions.add(SalaryCycleTransaction(
          type: 'سحب',
          amount: expense.amount,
          date: expense.date,
          note: expense.description,
          category: 'سحب راتب',
        ));
      } else if (type == 'سلفة') {
        advances += expense.amount;
        transactions.add(SalaryCycleTransaction(
          type: 'سلفة',
          amount: expense.amount,
          date: expense.date,
          note: expense.description,
          category: 'سلفة',
        ));
      } else if (type == 'خصم من الراتب') {
        final isInstallment = expense.isAutoGenerated &&
            expense.description.contains('قسط سلفة');
        if (!isInstallment) {
          deductions += expense.amount;
          transactions.add(SalaryCycleTransaction(
            type: 'خصم',
            amount: expense.amount,
            date: expense.date,
            note: expense.description,
            category: 'خصم من الراتب',
          ));
        }
      } else if (type == 'خصم راتب' || type == 'خصم' || type == 'غياب') {
        deductions += expense.amount;
        transactions.add(SalaryCycleTransaction(
          type: 'خصم',
          amount: expense.amount,
          date: expense.date,
          note: expense.description,
          category: type,
        ));
      }
    }

    transactions.sort((a, b) => b.date.compareTo(a.date));

    return _CycleTransactions(
      withdrawals: withdrawals,
      deductions: deductions,
      advances: advances,
      transactions: transactions,
    );
  }

  /// ═══════════════════════════════════════════════════════════
  /// أدوات مساعدة
  /// ═══════════════════════════════════════════════════════════

  /// حساب بداية الدورة بناءً على تاريخ التوظيف
  DateTime _getCycleStart(DateTime hireDate, DateTime referenceDate) {
    int day = hireDate.day;
    int year = referenceDate.year;
    int month = referenceDate.month;

    // إذا كان يوم المرجع < يوم التوظيف، الدورة في الشهر السابق
    if (referenceDate.day < day) {
      month--;
      if (month < 1) {
        month = 12;
        year--;
      }
    }

    // التعامل مع أشهر لا تحتوي على اليوم المطلوب
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final actualDay = day > daysInMonth ? daysInMonth : day;

    return DateTime(year, month, actualDay);
  }

  /// حساب نهاية الدورة (يوم قبل بداية الدورة التالية)
  DateTime _getCycleEnd(DateTime cycleStart) {
    final nextCycleStart = DateTime(cycleStart.year, cycleStart.month + 1, cycleStart.day);
    return nextCycleStart.subtract(const Duration(days: 1));
  }

  DateTime? _parseDate(String dateStr) {
    if (dateStr.isEmpty) return null;
    try {
      final normalized = dateStr.contains('T')
          ? dateStr
          : dateStr.replaceFirst(' ', 'T');
      final withSeconds = normalized.length == 16
          ? '$normalized:00'
          : normalized;
      return DateTime.parse(withSeconds);
    } catch (_) {
      try {
        return DateTime.parse(dateStr.split(' ').first);
      } catch (_) {
        return null;
      }
    }
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}

/// مساعد لجمع معاملات الدورة
class _CycleTransactions {
  _CycleTransactions({
    required this.withdrawals,
    required this.deductions,
    required this.advances,
    required this.transactions,
  });

  final double withdrawals;
  final double deductions;
  final double advances;
  final List<SalaryCycleTransaction> transactions;
}
