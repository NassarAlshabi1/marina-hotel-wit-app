import 'package:drift/drift.dart' as d;

import '../utils/time.dart';
import 'local_db.dart';
import 'repositories/expenses_repository.dart';

/// نتيجة فحص/إصلاح روابط موظف واحد.
class EmployeeLinkRepairReport {
  int expensesRelinked = 0; // relatedId أُعيد توجيهه لهذا الموظف
  int expensesUuidBackfilled = 0; // employeeUuid كان فارغاً فُعّبئ
  int expensesRepointedAway = 0; // كانت تحمل id هذا الموظف و uuid لموظف آخر
  int withdrawalsRescued = 0; // سحوبات يتيمة أعيد إسنادها عبر مصروفها
  int orphanWithdrawalsUnrescuable = 0; // سحوبات يتيمة لا يمكن إسقاطها بأمان
  int cyclesRelinked = 0;
  int paymentsRelinked = 0;
  int carryOversRelinked = 0;
  int relationshipConflicts = 0;
  int orphanCycles = 0; // سجلات لا يمكن حسم مالكها بأمان
  final List<String> notes = [];

  bool get hasRepairs =>
      expensesRelinked > 0 ||
      expensesUuidBackfilled > 0 ||
      expensesRepointedAway > 0 ||
      withdrawalsRescued > 0 ||
      cyclesRelinked > 0 ||
      paymentsRelinked > 0 ||
      carryOversRelinked > 0;

  @override
  String toString() =>
      'expensesRelinked=$expensesRelinked, uuidBackfilled=$expensesUuidBackfilled, '
      'repointedAway=$expensesRepointedAway, withdrawalsRescued=$withdrawalsRescued, '
      'cyclesRelinked=$cyclesRelinked, paymentsRelinked=$paymentsRelinked, '
      'carryOversRelinked=$carryOversRelinked, conflicts=$relationshipConflicts, '
      'orphanWithdrawals=$orphanWithdrawalsUnrescuable, orphanCycles=$orphanCycles';
}

/// ✅ خدمة اتساق روابط الموظف — تُستدعى بعد أي تعديل ناجح على موظف.
///
/// القاعدة (طلب صاحب الفندق 2026-09-14):
/// «عند تعديل بيانات الموظف يجب تحديث جميع حقول الجدول والجداول المرتبطة
/// به بحيث لا يحدث سجلات يتيمة».
///
/// الخلل المثبت من سحابة «الاورمو محمد»:
/// مصروفاته على السحابة تحمل relatedId=6 (رقم جهاز قديم/موظف آخر) بينما
/// employeeUuid يشير إليه هو — نسخ رقمية ميتة لا تُصحَّح عند التعديل.
///
/// مصدر الحقيقة: **employeeUuid يفوز دائماً** (نفس قرار المُحوِّلات عند
/// السحب: UUID → serverId → المحلي فقط). أي تعارض بين الرقمي والـ UUID
/// يُحلّ لمصلحة الـ UUID.
///
/// الجداول المرتبطة بالموظف وأعمدة الهوية:
/// - expenses: relatedId (رقمي) + employeeUuid (نصي) → يُصلَّحان معاً
/// - salary_withdrawals: employeeUuid هو المصدر الثابت، employeeId مشتق محلياً؛
///   والـexpenseUuid لا يُستخدم للإنقاذ إلا إذا قاد إلى employeeUuid واضح.
/// - salary_cycles / salary_payments / salary_carry_over_logs: employeeUuid
///   هو المصدر المحمول، والـIDs الرقمية تُصحّح محلياً. أي تعارض بين UUIDs
///   المتعددة لا يُحسم بالتخمين ويظهر كتعارض يحتاج إصلاحاً حتمياً.
///
/// كل إصلاح يُنفَّذ عبر المسارات المعتمدة (Repository/DAO) ليرتفع
/// lastModified ويُضاف للـ outbox → يصل الإصلاح إلى السحابة والأجهزة.
///
/// ✅ (ت5-ج2 2026-10-04) تحديث سياسة الرفع — قاعدة 10.3-أ «الإصلاح
/// لا يُكتب رجوعاً إلى السحابة بشكل غير منضبط»: هذه الخدمة لا ترفع
/// إصلاحاتها بنفسها إلى outbox إطلاقاً:
/// - إصلاحات المصروفات تمر عبر المسار المعتمد (Repository/DAO) — نفس قناة
///   أي تعديل مشروع من المستخدم (ترقيم إصدار + vector clock منضبط)؛
/// - إنقاذ المسحوبات اليتيمة تحديث محلي مباشر (بلا outbox) — يحميه رفع
///   الإصدار من الطمس بمداد LWW السحابي، ولا يمس حقيقة السحابة إطلاقاً.
/// الرفع المباشر من خدمة إصلاح (payload مُبنى يدوياً خارج قنوات الإصدار)
/// كان يفسد السحابة (10.3-أ حذّر من هذا تحديداً) — أُوقف.
class EmployeeLinkConsistencyService {
  EmployeeLinkConsistencyService(this.db)
    : _expensesRepo = ExpensesRepository(db);

  final AppDatabase db;
  final ExpensesRepository _expensesRepo;

  /// يفحص ويُصلح كل السجلات المرتبطة بالموظف [employeeId].
  /// آمن للاستدعاء المتكرر: الصف السليم لا يُمسّ إطلاقاً (صفر ضوضاء outbox).
  Future<EmployeeLinkRepairReport> repairLinksForEmployee(
    int employeeId,
  ) async {
    final report = EmployeeLinkRepairReport();

    final emp = await (db.select(
      db.employees,
    )..where((t) => t.id.equals(employeeId))).getSingleOrNull();
    if (emp == null) {
      report.notes.add('employee#$employeeId غير موجود — لا إصلاح');
      return report;
    }

    // خريطة هوية كل الموظفين (بما فيهم المنتهيون — الهوية لا تتأثر بالحالة)
    final allEmployees = await db.select(db.employees).get();
    final employeeByUuid = {for (final e in allEmployees) e.localUuid: e};
    final employeeById = {for (final e in allEmployees) e.id: e};
    final aliveEmployeeIds = allEmployees.map((e) => e.id).toSet();

    // ═══ 1) المصروفات — الروابط المزدوجة (رقمي + uuid) ═══
    final expenseRows =
        await (db.select(db.expenses)
              ..where(
                (t) =>
                    t.relatedId.equals(employeeId) |
                    t.employeeUuid.equals(emp.localUuid),
              )
              ..where((t) => t.deletedAt.isNull()))
            .get();

    for (final exp in expenseRows) {
      final uuid = exp.employeeUuid?.trim() ?? '';

      // ── أ) uuid لموظف آخر موجود → الرقمي يُعاد توجيهه لهذا الموظف
      // (uuid يفوز) — يمنع احتساب صرف موظف ضمن استحقاق موظف آخر.
      if (uuid.isNotEmpty && uuid != emp.localUuid) {
        final owner = employeeByUuid[uuid];
        if (owner != null && exp.relatedId != owner.id) {
          await _expensesRepo.update(
            exp.id,
            relatedId: owner.id,
            employeeUuid: uuid,
          );
          report.expensesRepointedAway++;
          report.notes.add(
            'expense#${exp.id}: relatedId ${exp.relatedId} → ${owner.id} (uuid يفوز)',
          );
        }
        continue;
      }

      // ── ب) ينتمي لهذا الموظف (بالـ uuid أو الرقمي) — يُوحَّد الطرفان
      final needsNumericFix = exp.relatedId != employeeId;
      final needsUuidBackfill = uuid.isEmpty;
      if (!needsNumericFix && !needsUuidBackfill) continue; // سليم — لا مسّ

      await _expensesRepo.update(
        exp.id,
        relatedId: needsNumericFix ? employeeId : null,
        employeeUuid: needsUuidBackfill ? emp.localUuid : null,
      );
      if (needsNumericFix) report.expensesRelinked++;
      if (needsUuidBackfill) report.expensesUuidBackfilled++;
      report.notes.add(
        'expense#${exp.id}: '
        '${needsNumericFix ? 'relatedId ${exp.relatedId} → $employeeId؛ ' : ''}'
        '${needsUuidBackfill ? 'employeeUuid عُبّئ' : ''}',
      );
    }

    // ═══ 2) السحوبات — employeeUuid هو المصدر الثابت، employeeId مشتق محلياً ═══
    final allWithdrawals = await (db.select(db.salaryWithdrawals)
          ..where((t) => t.deletedAt.isNull()))
        .get();
    for (final sw in allWithdrawals) {
      final uuid = sw.employeeUuid?.trim() ?? '';
      if (uuid.isNotEmpty) {
        final owner = employeeByUuid[uuid];
        if (owner == null) {
          report.orphanWithdrawalsUnrescuable++;
          report.notes.add(
            'withdrawal#${sw.id}: employeeUuid=$uuid غير موجود — لم يُخمن المالك',
          );
          continue;
        }
        if (sw.employeeId != owner.id) {
          final now = Time.nowEpoch();
          await (db.update(db.salaryWithdrawals)
                ..where((t) => t.id.equals(sw.id)))
              .write(
                SalaryWithdrawalsCompanion(
                  employeeId: d.Value(owner.id),
                  updatedAt: d.Value(now),
                  lastModified: d.Value(now),
                  version: d.Value(sw.version + 1),
                ),
              );
          report.withdrawalsRescued++;
          report.notes.add(
            'withdrawal#${sw.id}: employeeId ${sw.employeeId} → ${owner.id} وفق employeeUuid',
          );
        }
        continue;
      }

      // No UUID: only rescue when the already-linked expense itself carries a
      // valid employeeUuid. Never infer from amount/date/name alone.
      final expenseUuid = sw.expenseUuid?.trim() ?? '';
      if (expenseUuid.isNotEmpty) {
        final exp = await (db.select(db.expenses)
              ..where((e) => e.localUuid.equals(expenseUuid))
              ..limit(1))
            .getSingleOrNull();
        final expOwner = exp == null
            ? null
            : employeeByUuid[exp.employeeUuid?.trim() ?? ''];
        if (expOwner != null) {
          final now = Time.nowEpoch();
          await (db.update(db.salaryWithdrawals)
                ..where((t) => t.id.equals(sw.id)))
              .write(
                SalaryWithdrawalsCompanion(
                  employeeId: d.Value(expOwner.id),
                  employeeUuid: d.Value(expOwner.localUuid),
                  updatedAt: d.Value(now),
                  lastModified: d.Value(now),
                  version: d.Value(sw.version + 1),
                ),
              );
          report.withdrawalsRescued++;
          report.notes.add(
            'withdrawal#${sw.id}: employeeUuid أُعيد بناؤه من expenseUuid=$expenseUuid',
          );
          continue;
        }
      }

      // Legacy rescue: a raw expense_id is acceptable only when the
      // referenced expense independently proves ownership of this employee.
      // Amount/date/reason alone are never sufficient evidence.
      if (sw.expenseId != null && sw.expenseId! > 0) {
        final exp = await (db.select(db.expenses)
              ..where((e) => e.id.equals(sw.expenseId!))
              ..limit(1))
            .getSingleOrNull();
        final provenOwner = exp != null &&
            (exp.employeeUuid == emp.localUuid || exp.relatedId == employeeId);
        if (provenOwner) {
          final now = Time.nowEpoch();
          await (db.update(db.salaryWithdrawals)
                ..where((t) => t.id.equals(sw.id)))
              .write(
                SalaryWithdrawalsCompanion(
                  employeeId: d.Value(employeeId),
                  employeeUuid: d.Value(emp.localUuid),
                  updatedAt: d.Value(now),
                  lastModified: d.Value(now),
                  version: d.Value(sw.version + 1),
                ),
              );
          report.withdrawalsRescued++;
          report.notes.add(
            'withdrawal#${sw.id}: employeeId أُعيد بناؤه من expenseId=${sw.expenseId} ذي ملكية مثبتة',
          );
          continue;
        }
      }

      // If no identity proof exists, leave the row untouched.
      if (!aliveEmployeeIds.contains(sw.employeeId)) {
        report.orphanWithdrawalsUnrescuable++;
      }
    }

    // ═══ 3) دورات الرواتب — UUID يحدد الموظف، والرقمي مشتق محلياً ═══
    final cycles = await (db.select(db.salaryCycles)
          ..where((t) => t.deletedAt.isNull()))
        .get();
    for (final cycle in cycles) {
      final uuid = cycle.employeeUuid?.trim() ?? '';
      if (uuid.isEmpty) {
        final owner = employeeById[cycle.employeeId];
        if (owner == null) {
          report.orphanCycles++;
          continue;
        }
        await (db.update(db.salaryCycles)..where((t) => t.id.equals(cycle.id)))
            .write(SalaryCyclesCompanion(employeeUuid: d.Value(owner.localUuid)));
        report.cyclesRelinked++;
        continue;
      }
      final owner = employeeByUuid[uuid];
      if (owner == null) {
        report.orphanCycles++;
        report.notes.add(
          'salary_cycle#${cycle.id}: employeeUuid=$uuid غير موجود — لم يُخمن المالك',
        );
        continue;
      }
      if (cycle.employeeId != owner.id) {
        await (db.update(db.salaryCycles)..where((t) => t.id.equals(cycle.id)))
            .write(SalaryCyclesCompanion(employeeId: d.Value(owner.id)));
        report.cyclesRelinked++;
      }
    }

    // ═══ 4) دفعات الرواتب — يجب أن تتفق هوية الدفعة مع هوية دورتها ═══
    final payments = await (db.select(db.salaryPayments)
          ..where((t) => t.deletedAt.isNull()))
        .get();
    for (final payment in payments) {
      final cycle = await (db.select(db.salaryCycles)
            ..where((c) => c.id.equals(payment.cycleId))
            ..limit(1))
          .getSingleOrNull();
      if (cycle == null) {
        report.relationshipConflicts++;
        report.notes.add(
          'salary_payment#${payment.id}: cycleId=${payment.cycleId} غير موجود — لم يُخمن',
        );
        continue;
      }
      final cycleUuid = cycle.employeeUuid?.trim() ?? '';
      final paymentUuid = payment.employeeUuid?.trim() ?? '';
      if (cycleUuid.isNotEmpty && paymentUuid.isNotEmpty && cycleUuid != paymentUuid) {
        // Two authoritative UUID claims disagree. Do not choose one silently.
        report.relationshipConflicts++;
        report.notes.add(
          'salary_payment#${payment.id}: تعارض employeeUuid بين الدفعة والدورة — لم يُخمن',
        );
        continue;
      }
      final ownerUuid = cycleUuid.isNotEmpty ? cycleUuid : paymentUuid;
      if (ownerUuid.isEmpty) continue;
      final owner = employeeByUuid[ownerUuid];
      if (owner == null) {
        report.relationshipConflicts++;
        continue;
      }
      if (payment.employeeUuid != owner.localUuid) {
        await (db.update(db.salaryPayments)..where((t) => t.id.equals(payment.id)))
            .write(SalaryPaymentsCompanion(employeeUuid: d.Value(owner.localUuid)));
        report.paymentsRelinked++;
      }
    }

    // ═══ 5) سجلات الترحيل — employeeUuid هو المرجع المحمول ═══
    final carryOvers = await (db.select(db.salaryCarryOverLogs)
          ..where((t) => t.deletedAt.isNull()))
        .get();
    for (final log in carryOvers) {
      final uuid = log.employeeUuid?.trim() ?? '';
      if (uuid.isEmpty) {
        final owner = employeeById[log.employeeId];
        if (owner == null) {
          report.orphanCycles++;
          continue;
        }
        await (db.update(db.salaryCarryOverLogs)
              ..where((t) => t.id.equals(log.id)))
            .write(SalaryCarryOverLogsCompanion(employeeUuid: d.Value(owner.localUuid)));
        report.carryOversRelinked++;
        continue;
      }
      final owner = employeeByUuid[uuid];
      if (owner == null) {
        report.orphanCycles++;
        continue;
      }
      if (log.employeeId != owner.id) {
        await (db.update(db.salaryCarryOverLogs)
              ..where((t) => t.id.equals(log.id)))
            .write(SalaryCarryOverLogsCompanion(employeeId: d.Value(owner.id)));
        report.carryOversRelinked++;
      }
    }

    return report;
  }
}
