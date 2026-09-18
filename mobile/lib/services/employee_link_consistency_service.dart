import 'package:drift/drift.dart' as d;

import '../utils/time.dart';
import 'daos/outbox_dao.dart';
import 'local_db.dart';
import 'repositories/expenses_repository.dart';
import 'sync/payload_mapper.dart';

/// نتيجة فحص/إصلاح روابط موظف واحد.
class EmployeeLinkRepairReport {
  int expensesRelinked = 0; // relatedId أُعيد توجيهه لهذا الموظف
  int expensesUuidBackfilled = 0; // employeeUuid كان فارغاً فُعّبئ
  int expensesRepointedAway = 0; // كانت تحمل id هذا الموظف و uuid لموظف آخر
  int withdrawalsRescued = 0; // سحوبات يتيمة أعيد إسنادها عبر مصروفها
  int orphanWithdrawalsUnrescuable = 0; // سحوبات يتيمة لا يمكن إسقاطها بأمان
  int orphanCycles = 0; // دورات/ترحيلات تشير لموظف ميت (لا uuid — تقرير فقط)
  final List<String> notes = [];

  bool get hasRepairs =>
      expensesRelinked > 0 ||
      expensesUuidBackfilled > 0 ||
      expensesRepointedAway > 0 ||
      withdrawalsRescued > 0;

  @override
  String toString() =>
      'expensesRelinked=$expensesRelinked, uuidBackfilled=$expensesUuidBackfilled, '
      'repointedAway=$expensesRepointedAway, withdrawalsRescued=$withdrawalsRescued, '
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
/// - salary_withdrawals: employeeId (رقمي FK) — اليتيمة تُنقذ عبر رابط
///   expense_id ← مصروف يملكه هذا الموظف
/// - salary_cycles / salary_carry_over_logs: employeeId رقمي فقط — لا يمكن
///   إنقاذ يتيمها بأمان (لا uuid) → تُحصى في التقرير للفحص البشري فقط
///
/// كل إصلاح يُنفَّذ عبر المسارات المعتمدة (Repository/DAO) ليرتفع
/// lastModified ويُضاف للـ outbox → يصل الإصلاح إلى السحابة والأجهزة.
class EmployeeLinkConsistencyService {
  EmployeeLinkConsistencyService(this.db)
    : _expensesRepo = ExpensesRepository(db),
      _outbox = OutboxDao(db),
      _mapper = const PayloadMapper();

  final AppDatabase db;
  final ExpensesRepository _expensesRepo;
  final OutboxDao _outbox;
  final PayloadMapper _mapper;

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

    // ═══ 2) السحوبات اليتيمة (employee_id يشير لموظف غير موجود) ═══
    // أولاً: أف[id] المصروفات المملوكة لهذا الموظف (بعد إصلاحها أعلاه)
    final ownedExpenseIds =
        (await (db.select(db.expenses)
                  ..where((t) => t.relatedId.equals(employeeId))
                  ..where((t) => t.deletedAt.isNull()))
                .get())
            .map((e) => e.id)
            .toSet();

    final orphanWithdrawals = await (db.select(
      db.salaryWithdrawals,
    )..where((t) => t.deletedAt.isNull())).get();
    for (final sw in orphanWithdrawals) {
      if (aliveEmployeeIds.contains(sw.employeeId)) continue; // سليمة

      // محاولة إنقاذ عبر رابط المصروف (expense_id)
      final linkedExpenseId = sw.expenseId;
      if (linkedExpenseId != null &&
          linkedExpenseId > 0 &&
          ownedExpenseIds.contains(linkedExpenseId)) {
        final now = Time.nowEpoch();
        await (db.update(
          db.salaryWithdrawals,
        )..where((t) => t.id.equals(sw.id))).write(
          SalaryWithdrawalsCompanion(
            employeeId: d.Value(employeeId),
            updatedAt: d.Value(now),
            lastModified: d.Value(now),
            version: d.Value(sw.version + 1),
          ),
        );
        final updated = await (db.select(
          db.salaryWithdrawals,
        )..where((t) => t.id.equals(sw.id))).getSingle();
        await _outbox.merge(
          entity: 'salary_withdrawals',
          op: 'update',
          localUuid: updated.localUuid,
          serverId: updated.serverId,
          clientTs: now,
          payload: _mapper.salaryWithdrawalToRemote(
            updated,
            employeeUuid: emp.localUuid,
          ),
        );
        report.withdrawalsRescued++;
        report.notes.add(
          'withdrawal#${sw.id}: employeeId ${sw.employeeId} → $employeeId '
          '(عبر expense#$linkedExpenseId)',
        );
      } else {
        report.orphanWithdrawalsUnrescuable++;
      }
    }

    // ═══ 3) الدورات والترحيلات اليتيمة — تقرير فقط (لا uuid للإنقاذ) ═══
    final orphanCycles = await (db.select(
      db.salaryCycles,
    )..where((t) => t.employeeId.isNotIn(aliveEmployeeIds))).get();
    report.orphanCycles = orphanCycles.length;

    return report;
  }
}
