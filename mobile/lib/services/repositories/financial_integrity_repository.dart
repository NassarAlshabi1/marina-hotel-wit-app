import 'package:drift/drift.dart' as d;

import '../adapters/id_resolver.dart';
import '../local_db.dart';
import '../salary_expense_classifier.dart';

/// صف تقرير السلامة العام (§11) — قراءة فقط، لا حذف ولا تصحيح تلقائي.
class FinancialIntegrityReport {
  const FinancialIntegrityReport({
    required this.salaryExpensesWithoutMirror,
    required this.activeMirrorsWithoutExpense,
    required this.withdrawalsWithoutEmployeeUuid,
    required this.unknownEmployeeUuidRefs,
    required this.employeeIdMismatches,
    required this.relatedIdMismatches,
    required this.expenseIdMismatches,
    required this.duplicateActiveMirrors,
    required this.pendingLinks,
    required this.stuckOutbox,
    required this.localTotalsByEmployee,
  });

  /// مصروفات رواتب نشطة بلا مرآة (§11-1)
  final List<String> salaryExpensesWithoutMirror;

  /// مرايا نشطة بلا مصروف (§11-2)
  final List<String> activeMirrorsWithoutExpense;

  /// مسحوبات بلا employeeUuid (§11-3)
  final List<String> withdrawalsWithoutEmployeeUuid;

  /// employeeUuid لا يطابق موظفاً (§11-4)
  final List<String> unknownEmployeeUuidRefs;

  /// اختلاف الأرقام المشتقة عمّا يحله UUID (§11-5/6/7)
  final List<String> employeeIdMismatches;
  final List<String> relatedIdMismatches;
  final List<String> expenseIdMismatches;

  /// أكثر من مرآة نشطة لنفس expenseUuid (§11-8)
  final List<String> duplicateActiveMirrors;

  /// pending links وعدد محاولاتها وأسبابها (§11-9)
  final List<String> pendingLinks;

  /// outbox المتعثر وسبب عدم الرفع (§11-10)
  final List<String> stuckOutbox;

  /// مقارنة counts ومجموع المبالغ حسب employeeUuid — الجانب المحلي
  /// (المقارنة السحابية عبر سكربت منفصل مدقق — §10.7).
  final Map<String, LocalEmployeeTotals> localTotalsByEmployee;

  bool get isClean =>
      salaryExpensesWithoutMirror.isEmpty &&
      activeMirrorsWithoutExpense.isEmpty &&
      withdrawalsWithoutEmployeeUuid.isEmpty &&
      unknownEmployeeUuidRefs.isEmpty &&
      employeeIdMismatches.isEmpty &&
      relatedIdMismatches.isEmpty &&
      expenseIdMismatches.isEmpty &&
      duplicateActiveMirrors.isEmpty &&
      pendingLinks.isEmpty &&
      stuckOutbox.isEmpty;
}

/// إجماليات محلية لكل موظف — للمعاينة مقابل السحابة (§11-10).
class LocalEmployeeTotals {
  const LocalEmployeeTotals({
    required this.employeeUuid,
    required this.expenseCount,
    required this.expenseAmount,
    required this.withdrawalCount,
    required this.withdrawalAmount,
  });

  final String employeeUuid;
  final int expenseCount;
  final double expenseAmount;
  final int withdrawalCount;
  final double withdrawalAmount;
}

/// ✅ «وثيقة الربط والمزامنة Appwrite الموحدة» — §11 تقرير سلامة دائم
/// (قراءة فقط) + §16.4-F السجلات غير المرتبطة.
///
/// «لا يقوم التقرير بأي حذف أو تصحيح تلقائي؛ يعرض الأدلة ويتيح إصلاحاً
/// صريحاً ومدققاً». كل الفحوص UUID-first عبر LocalLinkResolver semantics
/// (صيغ UUID الثلاث)، ولا يستخدم reason='exp_N' أو amount/date للربط.
class FinancialIntegrityRepository {
  FinancialIntegrityRepository(this._db);

  final AppDatabase _db;

  /// يبني التقرير الكامل. [rowLimit] حد عرض لكل قسم (العدد الكامل يُذكر).
  Future<FinancialIntegrityReport> build({int rowLimit = 50}) async {
    final employees = await (_db.select(
      _db.employees,
    )..where((e) => e.deletedAt.isNull())).get();
    final expenses = await (_db.select(
      _db.expenses,
    )..where((e) => e.deletedAt.isNull())).get();
    final withdrawals = await (_db.select(
      _db.salaryWithdrawals,
    )..where((w) => w.deletedAt.isNull())).get();
    final cycles = await (_db.select(
      _db.salaryCycles,
    )..where((c) => c.deletedAt.isNull())).get();
    final payments = await (_db.select(
      _db.salaryPayments,
    )..where((p) => p.deletedAt.isNull())).get();
    final carryOvers = await (_db.select(
      _db.salaryCarryOverLogs,
    )..where((c) => c.deletedAt.isNull())).get();

    // خرائط UUID → صف (صيغ UUID الثلاث مثل IdResolver).
    final employeeIdsByUuid = _UuidIndex(
      employees.map((e) => (e.localUuid, e.id)),
    );
    final expenseIdsByUuid = _UuidIndex(
      expenses.map((e) => (e.localUuid, e.id)),
    );

    // ── 1) مصروفات رواتب نشطة بلا مرآة ──
    final activeMirrorByExpenseUuid = <String, List<SalaryWithdrawal>>{};
    for (final w in withdrawals) {
      final eu = (w.expenseUuid ?? '').trim();
      if (eu.isEmpty) continue;
      activeMirrorByExpenseUuid.putIfAbsent(eu, () => []).add(w);
    }
    final salaryExpensesWithoutMirror = <String>[];
    for (final e in expenses) {
      if (!SalaryExpenseClassifier.isSalaryRelated(e.expenseType.trim())) {
        continue;
      }
      final group = activeMirrorByExpenseUuid[e.localUuid.trim()];
      if (group == null || group.isEmpty) {
        salaryExpensesWithoutMirror.add(_expenseLabel(e));
      }
    }

    // ── 2) مرايا نشطة بلا مصروف ──
    final activeMirrorsWithoutExpense = <String>[];
    final duplicateActiveMirrors = <String>[];
    for (final entry in activeMirrorByExpenseUuid.entries) {
      final expenseId = expenseIdsByUuid.anyId(entry.key);
      if (expenseId == null) {
        for (final w in entry.value) {
          activeMirrorsWithoutExpense.add(_withdrawalLabel(w));
        }
      }
      if (entry.value.length > 1) {
        duplicateActiveMirrors.add(
          'expenseUuid=${entry.key} — ${entry.value.length} مرايا نشطة '
          '(${entry.value.map((w) => w.localUuid).take(3).join(', ')})',
        );
      }
    }

    // ── 3) مسحوبات بلا employeeUuid ──
    final withdrawalsWithoutEmployeeUuid = withdrawals
        .where((w) => (w.employeeUuid ?? '').trim().isEmpty)
        .map(_withdrawalLabel)
        .toList();

    // ── 4) employeeUuid لا يطابق موظفاً + 5/6/7) اختلاف الأرقام المشتقة ──
    final unknownEmployeeUuidRefs = <String>[];
    final employeeIdMismatches = <String>[];
    final relatedIdMismatches = <String>[];
    final expenseIdMismatches = <String>[];

    void checkEmployeeRef({
      required String table,
      required String localUuid,
      required String? employeeUuid,
      required int? employeeId,
    }) {
      final uuid = (employeeUuid ?? '').trim();
      if (uuid.isEmpty) return;
      final resolved = employeeIdsByUuid.anyId(uuid);
      if (resolved == null) {
        unknownEmployeeUuidRefs.add('$table/$localUuid — $uuid');
        return;
      }
      if (employeeId != null && employeeId != resolved) {
        employeeIdMismatches.add(
          '$table/$localUuid — employeeId=$employeeId بينما يحله UUID إلى '
          'employees.id=$resolved',
        );
      }
    }

    for (final e in expenses) {
      if (!SalaryExpenseClassifier.isSalaryRelated(e.expenseType.trim())) {
        continue;
      }
      final uuid = (e.employeeUuid ?? '').trim();
      if (uuid.isEmpty) continue;
      final resolved = employeeIdsByUuid.anyId(uuid);
      if (resolved == null) {
        unknownEmployeeUuidRefs.add('expenses/${e.localUuid} — $uuid');
      } else if (e.relatedId != null && e.relatedId != resolved) {
        relatedIdMismatches.add(
          'expenses/${e.localUuid} — relatedId=${e.relatedId} بينما يحله '
          'UUID إلى employees.id=$resolved',
        );
      }
    }
    for (final w in withdrawals) {
      checkEmployeeRef(
        table: 'salary_withdrawals',
        localUuid: w.localUuid,
        employeeUuid: w.employeeUuid,
        employeeId: w.employeeId,
      );
      final eu = (w.expenseUuid ?? '').trim();
      if (eu.isNotEmpty) {
        final resolvedExpense = expenseIdsByUuid.anyId(eu);
        // expenseUuid بلا مصروف محلي — مغطى في قسم المرايا اليتيمة
        // (§11-2) ولا نُضاعفه هنا.
        if (resolvedExpense != null &&
            w.expenseId != null &&
            w.expenseId != resolvedExpense) {
          expenseIdMismatches.add(
            'salary_withdrawals/${w.localUuid} — expenseId=${w.expenseId} '
            'بينما يحله expenseUuid إلى expenses.id=$resolvedExpense',
          );
        }
      }
    }
    for (final c in cycles) {
      checkEmployeeRef(
        table: 'salary_cycles',
        localUuid: c.localUuid,
        employeeUuid: c.employeeUuid,
        employeeId: c.employeeId,
      );
    }
    for (final p in payments) {
      // ملاحظة مخطط: salary_payments لا يحمل employeeId — الموظف عبر
      // employeeUuid (عرضي) والدورة عبر cycleId/cycleUuid. نفحص فقط
      // أن employeeUuid يحلّ لموظف (بدون مقارنة رقمية).
      checkEmployeeRef(
        table: 'salary_payments',
        localUuid: p.localUuid,
        employeeUuid: p.employeeUuid,
        employeeId: null,
      );
    }
    for (final c in carryOvers) {
      checkEmployeeRef(
        table: 'salary_carry_over_logs',
        localUuid: c.localUuid,
        employeeUuid: c.employeeUuid,
        employeeId: c.employeeId,
      );
    }

    // ── 9) pending links (§4.1/§8.1) ──
    final pendingLinks = <String>[];
    final pendingRows = await _db.select(_db.pendingLinks).get();
    for (final r in pendingRows) {
      pendingLinks.add(
        '${r.entity}/${r.localUuid} — محاولات=${r.attempts} — '
        'أب=${r.parentEntity}/${r.parentUuid ?? '—'} — '
        'سبب: ${r.reason}'
        '${r.resolvedAt != null ? ' (حُلّ)' : ' (معلّق)'}',
      );
    }

    // ── 10) outbox المتعثر ──
    final stuckOutbox = <String>[];
    final stuckRows =
        await (_db.select(_db.outbox)
              ..where(
                (t) => t.processingStatus.isIn(const ['failed', 'processing']),
              )
              ..orderBy([
                (t) => d.OrderingTerm(
                  expression: t.attempts,
                  mode: d.OrderingMode.desc,
                ),
              ])
              ..limit(rowLimit))
            .get();
    for (final r in stuckRows) {
      stuckOutbox.add(
        '${r.entity}/${r.localUuid} op=${r.op} — محاولات=${r.attempts} '
        '— حالة=${r.processingStatus} — سبب: ${r.lastError ?? '—'}',
      );
    }

    // ── الإجماليات المحلية لكل موظف (جانب المقارنة المحلي — §11-10) ──
    final totals = <String, _Accumulator>{};
    _Accumulator acc(String uuid) =>
        totals.putIfAbsent(uuid, () => _Accumulator());
    for (final e in expenses) {
      final uuid = (e.employeeUuid ?? '').trim();
      if (uuid.isEmpty) continue;
      final a = acc(uuid);
      a.expenseCount++;
      a.expenseAmount += e.amount;
    }
    for (final w in withdrawals) {
      final uuid = (w.employeeUuid ?? '').trim();
      if (uuid.isEmpty) continue;
      final a = acc(uuid);
      a.withdrawalCount++;
      a.withdrawalAmount += w.amount;
    }
    final localTotals = <String, LocalEmployeeTotals>{
      for (final entry in totals.entries)
        entry.key: LocalEmployeeTotals(
          employeeUuid: entry.key,
          expenseCount: entry.value.expenseCount,
          expenseAmount: entry.value.expenseAmount,
          withdrawalCount: entry.value.withdrawalCount,
          withdrawalAmount: entry.value.withdrawalAmount,
        ),
    };

    return FinancialIntegrityReport(
      salaryExpensesWithoutMirror: salaryExpensesWithoutMirror,
      activeMirrorsWithoutExpense: activeMirrorsWithoutExpense,
      withdrawalsWithoutEmployeeUuid: withdrawalsWithoutEmployeeUuid,
      unknownEmployeeUuidRefs: unknownEmployeeUuidRefs,
      employeeIdMismatches: employeeIdMismatches,
      relatedIdMismatches: relatedIdMismatches,
      expenseIdMismatches: expenseIdMismatches,
      duplicateActiveMirrors: duplicateActiveMirrors,
      pendingLinks: pendingLinks,
      stuckOutbox: stuckOutbox,
      localTotalsByEmployee: localTotals,
    );
  }
}

class _Accumulator {
  int expenseCount = 0;
  double expenseAmount = 0;
  int withdrawalCount = 0;
  double withdrawalAmount = 0;
}

/// فهرس UUID ثلاثي الصيغ — يعيد استخدام IdResolver (§5.1) بدل التكرار.
class _UuidIndex {
  _UuidIndex(Iterable<(String, int)> rows) {
    for (final (uuid, id) in rows) {
      final u = uuid.trim().toLowerCase();
      if (u.isEmpty) continue;
      exact.putIfAbsent(u, () => id);
      normalized.putIfAbsent(IdResolver.normalizeUuid(u), () => id);
      final strip = IdResolver.stripDashes(u);
      if (strip.length == 32) stripped.putIfAbsent(strip, () => id);
    }
  }

  final Map<String, int> exact = {};
  final Map<String, int> normalized = {};
  final Map<String, int> stripped = {};

  int? anyId(String raw) {
    final u = raw.trim().toLowerCase();
    if (u.isEmpty) return null;
    return exact[u] ??
        normalized[IdResolver.normalizeUuid(u)] ??
        stripped[IdResolver.stripDashes(u)];
  }
}

String _expenseLabel(Expense e) =>
    'expenses/${e.localUuid} — ${e.expenseType} — ${e.amount.toStringAsFixed(2)} — ${e.date}';

String _withdrawalLabel(SalaryWithdrawal w) =>
    'salary_withdrawals/${w.localUuid} — ${w.withdrawalType ?? 'سحب'} — '
    '${w.amount.toStringAsFixed(2)} — ${w.withdrawDate}';
