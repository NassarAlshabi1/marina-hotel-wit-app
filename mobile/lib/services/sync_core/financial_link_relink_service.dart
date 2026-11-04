import 'package:drift/drift.dart' as d;

import '../adapters/id_resolver.dart';
import '../local_db.dart';
import '../salary_expense_classifier.dart';

/// نتيجة إعادة اشتقاق الأرقام المحلية من UUID (§5.1/§9.1/§9.2).
class FinancialRelinkReport {
  int expensesRelatedIdFixed = 0;
  int withdrawalsEmployeeIdFixed = 0;
  int withdrawalsExpenseIdFixed = 0;
  int cyclesEmployeeIdFixed = 0;
  int paymentsCycleIdFixed = 0;
  int carryOversEmployeeIdFixed = 0;

  /// سجلات راتبية بـ employeeUuid لا يطابق موظفاً محلياً — تُترك كما هي
  /// بلا تخمين (§4.2/§5.2) وتُعرض في تقرير السلامة (§11).
  int unresolvedEmployeeRefs = 0;

  /// مسحوبات بـ expenseUuid لا يطابق مصروفاً محلياً — expense_id يُترك
  /// كما ورد ولا يُستنتج من رقم بعيد (§4.2).
  int unresolvedExpenseRefs = 0;

  final List<String> notes = [];

  bool get hasRepairs =>
      expensesRelatedIdFixed > 0 ||
      withdrawalsEmployeeIdFixed > 0 ||
      withdrawalsExpenseIdFixed > 0 ||
      cyclesEmployeeIdFixed > 0 ||
      paymentsCycleIdFixed > 0 ||
      carryOversEmployeeIdFixed > 0;

  @override
  String toString() =>
      'expenses.relatedId=$expensesRelatedIdFixed, '
      'withdrawals.employeeId=$withdrawalsEmployeeIdFixed, '
      'withdrawals.expenseId=$withdrawalsExpenseIdFixed, '
      'cycles.employeeId=$cyclesEmployeeIdFixed, '
      'payments.cycleId=$paymentsCycleIdFixed, '
      'carryOvers.employeeId=$carryOversEmployeeIdFixed, '
      'unresolvedEmployees=$unresolvedEmployeeRefs, '
      'unresolvedExpenses=$unresolvedExpenseRefs';
}

/// ✅ «وثيقة الربط والمزامنة Appwrite الموحدة» — تنفيذ الـ relink المالي:
///
/// - §5.1 (LocalLinkResolver): «توحيد كل إعادة ربط local IDs … لا يكتب
///   أي Repository أو Adapter هذه الأرقام من payload بعيد مباشرة».
/// - §9.1 (JSON محلي): «بعد import، ينفذ relink محلياً بلا outbox/
///   version bump» — «لا يسقط حقول الربط عند import».
/// - §9.2 (Google Drive): «Full restore: يعيد اشتقاق employeeId/
///   relatedId/expenseId من UUID … لا يكتفي بإعادة ربط payments/debts؛
///   يشمل expenses وsalary_withdrawals وsalary_cycles وsalary_payments
///   وsalary_carry_over_logs».
/// - §10.2 (حماية البيانات): «Backfill وrelink المحلي: بلا outbox، بلا
///   version increment، بلا lastModified تغيير».
///
/// القاعدة الاتجاهية الثابتة: **UUID → رقم محلي** فقط. لا يُشتق UUID من
/// رقم، ولا يُستخدم رقم بعيد fallback (§4.2/§5.2). الصيغ الثلاث للـ UUID
/// تُجرَّب مثل IdResolver (كما هو / بالشرطات / بدون — بقايا Drive القديم).
///
/// يُستدعى بعد: استعادة JSON، استعادة SQLite، استعادة Drive الكاملة
/// (وبعد أي pull/restore يغيّر الترقيم المحلي). لا يُستدعى داخل مسارات
/// المزامنة الدورية — فهي تُعيد الاشتقاق بنفسها عند التطبيق.
class FinancialLinkRelinkService {
  FinancialLinkRelinkService(this.db);

  final AppDatabase db;

  /// يعيد اشتقاق كل الأرقام المحلية المشتقة من UUID في الجداول المالية.
  ///
  /// داخل transaction واحدة؛ يكتب فقط الأعمدة الرقمية المشتقة — لا يمس
  /// lastModified/version/deviceId ولا يضيف للـ outbox (§10.2).
  Future<FinancialRelinkReport> relinkAll() async {
    final report = FinancialRelinkReport();

    // خرائط الحل في الذاكرة — الجداول صغيرة (موظفون بعشرات، مصروفات
    // بآلاف). الصيغ الثلاث بترتيب أولوية putIfAbsent (الأدق أولاً).
    final employeesByUuid = await _buildUuidIndex(
      rowsFuture: db.select(db.employees).get(),
      uuid: (Employee e) => e.localUuid,
      id: (Employee e) => e.id,
    );
    final expensesByUuid = await _buildUuidIndex(
      rowsFuture: db.select(db.expenses).get(),
      uuid: (Expense e) => e.localUuid,
      id: (Expense e) => e.id,
    );
    final cyclesByUuid = await _buildUuidIndex(
      rowsFuture: db.select(db.salaryCycles).get(),
      uuid: (SalaryCycle c) => c.localUuid,
      id: (SalaryCycle c) => c.id,
    );

    await db.transaction(() async {
      await _relinkExpenses(report, employeesByUuid);
      await _relinkWithdrawals(report, employeesByUuid, expensesByUuid);
      await _relinkCycles(report, employeesByUuid);
      await _relinkPayments(report, cyclesByUuid);
      await _relinkCarryOvers(report, employeesByUuid);
    });

    return report;
  }

  // ───────────────────────── خرائط UUID ─────────────────────────

  Future<_UuidLookup> _buildUuidIndex<T>({
    required Future<List<T>> rowsFuture,
    required String? Function(T) uuid,
    required int Function(T) id,
  }) async {
    final map = <String, int>{};
    final normalized = <String, int>{};
    final stripped = <String, int>{};
    for (final row in await rowsFuture) {
      final u = (uuid(row) ?? '').trim().toLowerCase();
      if (u.isEmpty) continue;
      final rowId = id(row);
      map.putIfAbsent(u, () => rowId);
      final norm = IdResolver.normalizeUuid(u);
      normalized.putIfAbsent(norm, () => rowId);
      final strip = IdResolver.stripDashes(u);
      if (strip.length == 32) stripped.putIfAbsent(strip, () => rowId);
    }
    return _UuidLookup(map, normalized, stripped);
  }

  int? _resolve(_UuidLookup index, String? rawUuid) {
    final u = (rawUuid ?? '').trim().toLowerCase();
    if (u.isEmpty) return null;
    return index.exact[u] ??
        index.normalized[IdResolver.normalizeUuid(u)] ??
        index.stripped[IdResolver.stripDashes(u)];
  }

  // ───────────────────────── الجداول ─────────────────────────

  /// expenses.relatedId ← employees.id — لمصروفات عائلة الرواتب فقط
  /// (نفس نطاق إعادة الاشتقاق في مسار السحب: المصروف المرتبط بموظف).
  Future<void> _relinkExpenses(
    FinancialRelinkReport report,
    _UuidLookup employees,
  ) async {
    final rows = await db.select(db.expenses).get();
    for (final e in rows) {
      final type = e.expenseType.trim();
      if (!SalaryExpenseClassifier.isSalaryRelated(type)) continue;
      final empId = _resolve(employees, e.employeeUuid);
      if (empId == null) {
        if (e.employeeUuid?.trim().isNotEmpty == true) {
          report.unresolvedEmployeeRefs++;
        }
        continue;
      }
      if (e.relatedId != empId) {
        await (db.update(db.expenses)..where((t) => t.id.equals(e.id))).write(
          ExpensesCompanion(relatedId: d.Value(empId)),
        );
        report.expensesRelatedIdFixed++;
      }
    }
  }

  /// salary_withdrawals: employeeId ← employeeUuid، expenseId ← expenseUuid.
  Future<void> _relinkWithdrawals(
    FinancialRelinkReport report,
    _UuidLookup employees,
    _UuidLookup expenses,
  ) async {
    final rows = await db.select(db.salaryWithdrawals).get();
    for (final w in rows) {
      var changed = false;
      final empId = _resolve(employees, w.employeeUuid);
      if (empId == null) {
        if (w.employeeUuid?.trim().isNotEmpty == true) {
          report.unresolvedEmployeeRefs++;
        }
      } else if (w.employeeId != empId) {
        await (db.update(db.salaryWithdrawals)
              ..where((t) => t.id.equals(w.id)))
            .write(SalaryWithdrawalsCompanion(employeeId: d.Value(empId)));
        report.withdrawalsEmployeeIdFixed++;
        changed = true;
      }

      // expenseId يُشتق فقط من expenseUuid (لا عكس، لا رقم بعيد — §4.2).
      if (w.expenseUuid?.trim().isNotEmpty == true) {
        final expId = _resolve(expenses, w.expenseUuid);
        if (expId == null) {
          report.unresolvedExpenseRefs++;
        } else if (w.expenseId != expId) {
          await (db.update(db.salaryWithdrawals)
                ..where((t) => t.id.equals(w.id)))
              .write(SalaryWithdrawalsCompanion(expenseId: d.Value(expId)));
          report.withdrawalsExpenseIdFixed++;
          changed = true;
        }
      }
      if (changed) report.notes.add('withdrawal ${w.localUuid}');
    }
  }

  /// salary_cycles.employeeId ← employeeUuid.
  Future<void> _relinkCycles(
    FinancialRelinkReport report,
    _UuidLookup employees,
  ) async {
    final rows = await db.select(db.salaryCycles).get();
    for (final c in rows) {
      final empId = _resolve(employees, c.employeeUuid);
      if (empId == null) {
        if (c.employeeUuid?.trim().isNotEmpty == true) {
          report.unresolvedEmployeeRefs++;
        }
        continue;
      }
      if (c.employeeId != empId) {
        await (db.update(db.salaryCycles)..where((t) => t.id.equals(c.id)))
            .write(SalaryCyclesCompanion(employeeId: d.Value(empId)));
        report.cyclesEmployeeIdFixed++;
      }
    }
  }

  /// salary_payments: cycleId ← cycleUuid.
  ///
  /// ملاحظة مخطط: salary_payments لا يحمل employeeId أصلاً — يرتبط
  /// بالموظف عبر employeeUuid (عرضي) وبالدورة عبر cycleId/cycleUuid.
  Future<void> _relinkPayments(
    FinancialRelinkReport report,
    _UuidLookup cycles,
  ) async {
    final rows = await db.select(db.salaryPayments).get();
    for (final p in rows) {
      if (p.cycleUuid?.trim().isNotEmpty == true) {
        final cycId = _resolve(cycles, p.cycleUuid);
        if (cycId != null && p.cycleId != cycId) {
          await (db.update(db.salaryPayments)..where((t) => t.id.equals(p.id)))
              .write(SalaryPaymentsCompanion(cycleId: d.Value(cycId)));
          report.paymentsCycleIdFixed++;
        }
      }
    }
  }

  /// salary_carry_over_logs.employeeId ← employeeUuid.
  Future<void> _relinkCarryOvers(
    FinancialRelinkReport report,
    _UuidLookup employees,
  ) async {
    final rows = await db.select(db.salaryCarryOverLogs).get();
    for (final c in rows) {
      final empId = _resolve(employees, c.employeeUuid);
      if (empId == null) {
        if (c.employeeUuid?.trim().isNotEmpty == true) {
          report.unresolvedEmployeeRefs++;
        }
        continue;
      }
      if (c.employeeId != empId) {
        await (db.update(db.salaryCarryOverLogs)
              ..where((t) => t.id.equals(c.id)))
            .write(SalaryCarryOverLogsCompanion(employeeId: d.Value(empId)));
        report.carryOversEmployeeIdFixed++;
      }
    }
  }
}

/// فهرس حل UUID ثلاثي الصيغ في الذاكرة (نفس دلالات IdResolver).
class _UuidLookup {
  _UuidLookup(this.exact, this.normalized, this.stripped);

  final Map<String, int> exact;
  final Map<String, int> normalized;
  final Map<String, int> stripped;
}
