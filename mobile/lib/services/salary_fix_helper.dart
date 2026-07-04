import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/expense_reason_matcher.dart';
import 'crashlytics_service.dart';
import 'local_db.dart';
import 'repositories/expenses_repository.dart';
import 'sync/payload_mapper.dart';

/// ✅ مساعد لإصلاح مصروفات الرواتب القديمة (يُشغَّل مرة واحدة فقط).
///
/// السيناريو الذي يُعالجه هذا الإصلاح:
/// مصروفات رواتب أُنشئت قبل التوصية 1 (commit 0d631a67) لها:
///   - `employeeUuid = null` (لم يكن يُكتب إلا وقت الرفع)
///   - `relatedId` قد يكون null أو يشير لموظف غير موجود (autoIncrement محلي
///     يختلف بين الأجهزة)
///
/// بعد التحديث، تظهر هذه المصروفات غير مربوطة بموظفها، فيبدو المستخدم
/// وكأنه "فقد سحبيات الرواتب القديمة".
///
/// الحل: استخدام `salary_withdrawals` كمصدر عكسي موثوق:
///   1. يبحث عن مصروفات الرواتب اليتيمة (UUID فارغ + relatedId غير صالح)
///   2. يجد السحب المرتبط عبر `expense_id` (أو `reason` كـ fallback قديم)
///   3. يأخذ `employeeId` من السحب → يحل الموظف → يملأ `employeeUuid` + `relatedId`
///   4. التحديث يتم عبر `ExpensesRepository.update` الذي يحدّث `updatedAt`/
///      `lastModified`/`version` تلقائياً ويُضيف للـ outbox للرفع التلقائي
///
/// آمن: لا يحذف أي شيء، فقط يُحدّث الروابط المفقودة. يستخدم SharedPreferences
/// flag لضمان عدم التكرار.
class SalaryFixHelper {
  SalaryFixHelper(this._db);

  final AppDatabase _db;
  static const String _fixDoneKey = 'salary_fix_v1_done';

  /// استدعاء هذه الدالة بعد اكتمال السحب الأول من Appwrite.
  ///
  /// تتحقق من العلم، وإن لم يكن موجوداً، تنفذ الإصلاح. تنتظر حتى يكتمل
  /// سحب الموظفين (تتحقق من وجود موظف واحد على الأقل) لتجنب الإصلاح
  /// المبكر على جهاز جديد فارغ.
  Future<void> runOnceAfterFirstPull() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_fixDoneKey) ?? false) {
        // سبق تنفيذه — لا حاجة للتكرار.
        return;
      }

      // تأكد من وجود بيانات (موظفين) للتأكد من اكتمال السحب الأول.
      // على جهاز جديد فارغ، نؤجل الإصلاح حتى يكتمل السحب.
      final hasEmployees = await (_db.select(_db.employees)
            ..where((e) => e.deletedAt.isNull())
            ..limit(1))
          .get();
      if (hasEmployees.isEmpty) {
        debugPrint(
          '🔧 [SalaryFixHelper] No employees found yet — deferring fix '
          'until next sync (will retry).',
        );
        return; // سيُعاد المحاولة في المرة القادمة (flag لم يُضبط بعد)
      }

      debugPrint('🔧 [SalaryFixHelper] Starting one-time salary fix...');

      // 1. إصلاح البيانات المحلية (يُحدّث updatedAt/lastModified + outbox)
      final fixedCount = await _fixOrphanSalaryExpenses();

      if (fixedCount > 0) {
        debugPrint(
          '🔧 [SalaryFixHelper] Fixed $fixedCount orphan salary expenses. '
          'Changes will be pushed to Appwrite on next sync (via outbox).',
        );
      } else {
        debugPrint(
          '🔧 [SalaryFixHelper] No broken salary expenses found.',
        );
      }

      // 2. ضبط الـ flag (حتى لو لم يجد شيئاً — المهم أن الإصلاح تم تشغيله)
      await prefs.setBool(_fixDoneKey, true);
      debugPrint('🔧 [SalaryFixHelper] One-time fix marked as done.');
    } catch (e, st) {
      debugPrint('⚠️ [SalaryFixHelper] Fix failed: $e');
      // لا نضبط الـ flag عند الفشل — يُعاد المحاولة في التشغيل التالي.
      try {
        await CrashlyticsService.instance.recordUnexpectedError(
          error: e,
          stackTrace: st,
          context: 'salary_fix_helper',
        );
      } catch (_) {
        // Crashlytics قد لا يكون جاهزاً — تجاهل.
      }
    }
  }

  /// إصلاح المصروفات التالفة وإرجاع عدد المصروفات التي تم إصلاحها.
  ///
  /// يستخدم `ExpensesRepository.update` (وليس customUpdate المباشر) لضمان:
  ///   - تحديث `updatedAt` و `lastModified` بـ epoch حالي
  ///   - زيادة `version`
  ///   - إضافة السجل للـ outbox للرفع التلقائي في المزامنة التالية
  Future<int> _fixOrphanSalaryExpenses() async {
    var fixedCount = 0;

    // ابحث عن مصروفات الرواتب اليتيمة.
    // نُجري فحص نوع الراتب في Dart عبر PayloadMapper.isSalaryExpenseType
    // لأن الكلمات المفتاحية عربية متعددة ولا تُترجم بسهولة إلى LIKE.
    final candidates = await _db.customSelect(
      'SELECT id, expense_type, related_id, employee_uuid '
      'FROM expenses '
      'WHERE deleted_at IS NULL '
      "AND (employee_uuid IS NULL OR employee_uuid = '') "
      'AND (related_id IS NULL OR related_id NOT IN '
      '    (SELECT id FROM employees WHERE deleted_at IS NULL))',
      readsFrom: {_db.expenses, _db.employees},
    ).get();

    final orphans = candidates.where((row) {
      final expenseType = row.read<String>('expense_type');
      return PayloadMapper.isSalaryExpenseType(expenseType);
    }).toList();

    if (orphans.isEmpty) {
      return 0;
    }

    debugPrint(
      '🔧 [SalaryFixHelper] Found ${orphans.length} orphan salary expenses '
      'needing repair.',
    );

    // جهّز repository لاستخدام updateById (يُحدّث updatedAt + outbox).
    // ExpensesRepository ينشئ dao و outbox تلقائياً في constructor.
    final repo = ExpensesRepository(_db);

    for (final row in orphans) {
      final expenseId = row.read<int>('id');
      final existingUuid = row.read<String?>('employee_uuid');

      int? resolvedEmployeeId;
      String? resolvedEmployeeUuid;

      // المحاولة 1: عبر employeeUuid (إن وُجد)
      if (existingUuid != null && existingUuid.isNotEmpty) {
        final employee = await (_db.select(_db.employees)
              ..where((e) => e.localUuid.equals(existingUuid))
              ..where((e) => e.deletedAt.isNull())
              ..limit(1))
            .getSingleOrNull();
        if (employee != null) {
          resolvedEmployeeId = employee.id;
          resolvedEmployeeUuid = employee.localUuid;
        }
      }

      // المحاولة 2: عبر salary_withdrawals (المصدر الموثوق)
      if (resolvedEmployeeId == null) {
        int? employeeIdFromWithdrawal;

        // 2أ. بحث عبر expense_id (العمود المُعلَن في Drift)
        try {
          final swRow = await (_db.select(_db.salaryWithdrawals)
                ..where((t) => t.expenseId.equals(expenseId))
                ..where((t) => t.deletedAt.isNull())
                ..limit(1))
              .getSingleOrNull();
          if (swRow != null) {
            employeeIdFromWithdrawal = swRow.employeeId;
          }
        } catch (_) {
          // العمود expense_id قد لا يكون موجوداً في DBs القديمة جداً.
        }

        // 2ب. fallback: بحث عبر reason (للسجلات القديمة جداً قبل migration 40)
        // نستخدم customSelect لأن Drift's GeneratedColumn.reason لا يدعم
        // .like مباشرة في الـ query builder.
        if (employeeIdFromWithdrawal == null) {
          final swRows = await _db.customSelect(
            'SELECT id, employee_id, reason FROM salary_withdrawals '
            'WHERE deleted_at IS NULL AND reason LIKE ?',
            variables: [drift.Variable.withString('%exp_$expenseId%')],
            readsFrom: {_db.salaryWithdrawals},
          ).get();
          for (final sw in swRows) {
            final reason = sw.read<String?>('reason');
            if (reason != null && matchesExpenseRef(reason, expenseId)) {
              employeeIdFromWithdrawal = sw.read<int>('employee_id');
              break;
            }
          }
        }

        if (employeeIdFromWithdrawal != null) {
          final employee = await (_db.select(_db.employees)
                ..where((e) => e.id.equals(employeeIdFromWithdrawal!))
                ..where((e) => e.deletedAt.isNull())
                ..limit(1))
              .getSingleOrNull();
          if (employee != null) {
            resolvedEmployeeId = employee.id;
            resolvedEmployeeUuid = employee.localUuid;
          }
        }
      }

      if (resolvedEmployeeId == null || resolvedEmployeeUuid == null) {
        debugPrint(
          '  ⚠️ Expense #$expenseId: could not resolve employee — leaving as is.',
        );
        continue;
      }

      // 3. حدّث المصروف عبر repository (يُحدّث updatedAt/lastModified + outbox).
      //    نمرّر employeeUuid كـ '' لنتمكن من تعيينه (لأن null يعني "لا تغيير"
      //    في update() — راجع expenses_repository.dart:186-190).
      //    لكننا نريد تعيين قيمة فعلية، فنمرّرها مباشرة.
      try {
        await repo.update(
          expenseId,
          relatedId: resolvedEmployeeId,
          employeeUuid: resolvedEmployeeUuid,
        );
        fixedCount++;
        final uuidPreview = resolvedEmployeeUuid.length >= 8
            ? resolvedEmployeeUuid.substring(0, 8)
            : resolvedEmployeeUuid;
        debugPrint(
          '  ✅ Fixed expense #$expenseId → employee #$resolvedEmployeeId '
          '(uuid: $uuidPreview...)',
        );
      } catch (e) {
        debugPrint('  ❌ Failed to update expense #$expenseId: $e');
      }
    }

    return fixedCount;
  }
}
