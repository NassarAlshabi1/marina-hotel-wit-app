import 'package:drift/drift.dart' as d;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_logger.dart';
import '../utils/expense_reason_matcher.dart';
import 'local_db.dart';
import 'repositories/expenses_repository.dart';
import 'sync/payload_mapper.dart';

/// ✅ مساعد لإصلاح مصروفات الرواتب القديمة (مرة واحدة فقط).
///
/// المشكلة: مصروفات رواتب أُنشئت قبل التوصية 1 (commit 0d631a67) لها
/// `employeeUuid = null` وربما `relatedId` غير صالح (autoIncrement محلي
/// يختلف بين الأجهزة). بعد التحديث، تبدو هذه المصروفات غير مربوطة
/// بموظفها، فيبدو المستخدم وكأنه "فقد سحبيات الرواتب القديمة".
///
/// الحل: يستخدم جدول `salary_withdrawals` كرابط عكسي موثوق:
/// 1. يبحث عن مصروفات الرواتب اليتيمة (UUID فارغ + relatedId غير صالح)
/// 2. يجد السحب المرتبط عبر `expense_id` (أو `reason` كـ fallback قديم)
/// 3. يأخذ `employeeId` من السحب → يحل الموظف → يملأ `employeeUuid` + `relatedId`
/// 4. يُحدّث `updatedAt` عبر `ExpensesRepository.update()` الذي يُضيف للـ outbox
///    تلقائياً، فيُرفع للسحاب في المزامنة التالية (حقول camelCase).
///
/// آمن: لا يحذف أي شيء، فقط يُحدّث الروابط المفقودة. يُكمّل التوصية 6.
class SalaryFixHelper {
  SalaryFixHelper(this._db);
  final AppDatabase _db;

  /// مفتاح SharedPreferences لضمان تنفيذ الإصلاح مرة واحدة فقط.
  static const String _fixDoneKey = 'salary_fix_v1_done';

  /// استدعاء هذه الدالة بعد اكتمال السحب الأول من Appwrite.
  ///
  /// تتحقق من:
  /// 1. SharedPreferences flag — إن كان true، تتخطى (سبق التنفيذ).
  /// 2. وجود موظفين محلياً — إن لم يوجدوا، تؤجّل (السحب لم يكتمل بعد).
  ///
  /// عند النجاح:
  /// - تُصلح المصروفات اليتيمة محلياً (مع outbox merge للرفع التلقائي).
  /// - تُضبط الـ flag حتى لا تتكرر.
  ///
  /// لا ترفع استثناءات — أخطاء الإصلاح لا توقف المزامنة.
  Future<void> runOnceAfterFirstPull() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_fixDoneKey) ?? false) {
        // سبق تنفيذه — لا حاجة للتكرار.
        return;
      }

      // تأكد من وجود بيانات (موظفين) للتأكد من اكتمال السحب الأول.
      // بدون هذا الفحص، قد نُصلح مصروفات قبل وصول موظفيها.
      final employeesCount = await _db.employees.count().getSingle();
      if (employeesCount == 0) {
        AppLogger.info('Salary fix deferred — no employees synced yet (waiting for first pull).', tag: 'SALARY_FIX');
        return; // سيُعاد المحاولة في المرة القادمة (نفس الدالة).
      }

      AppLogger.info('Starting one-time salary fix (first run after pull)...', tag: 'SALARY_FIX');

      // 1. إصلاح البيانات المحلية (يُضيف للـ outbox تلقائياً عبر repo.update).
      final fixedCount = await _fixOrphanSalaryExpenses();

      if (fixedCount > 0) {
        AppLogger.info(
          '✅ Salary fix completed — $fixedCount orphan expenses re-linked. '
          'Changes queued in outbox for next sync.',
          tag: 'SALARY_FIX',
        );
        // ملاحظة: لا نستدعي sync() هنا لأن الاستدعاء يأتي من داخل
        // AppwriteSyncManager.pull() — ستُرفع التغييرات في الـ sync التالي
        // تلقائياً عبر outbox. استدعاء sync() هنا قد يسبب recursive lock.
      } else {
        AppLogger.info('No orphan salary expenses found. Marking fix as done.', tag: 'SALARY_FIX');
      }

      // 2. ضبط الـ flag (حتى لو لم يجد شيئاً — لا حاجة للتكرار).
      await prefs.setBool(_fixDoneKey, true);
    } catch (e, st) {
      AppLogger.error('❌ Salary fix failed — will retry on next sync.', error: e, stackTrace: st, tag: 'SALARY_FIX');
      // لا نضبط الـ flag عند الفشل — يُعاد المحاولة في المرة القادمة.
    }
  }

  /// إصلاح المصروفات اليتيمة محلياً وإرجاع عدد المصروفات المُصلَحة.
  ///
  /// يستخدم `ExpensesRepository.update()` (وليس customUpdate خام) لضمان:
  /// - تحديث `updatedAt` تلقائياً.
  /// - إضافة العملية للـ outbox (للرفع التلقائي للسحاب).
  /// - توافق الحقول مع camelCase في Appwrite Cloud.
  Future<int> _fixOrphanSalaryExpenses() async {
    return fixOrphanSalaryExpensesForTest();
  }

  /// دالة الإصلاح الفعلية (مُعرَّضة للاختبار).
  ///
  /// تبحث عن مصروفات الرواتب اليتيمة وتُعيد ربطها عبر:
  /// 1. employeeUuid (إن وُجد وصالح)
  /// 2. salary_withdrawals كرابط عكسي (عبر expense_id ثم reason)
  ///
  /// تُرجع عدد المصروفات المُصلَحة. لا تحذف شيئاً — آمنة للاختبار.
  Future<int> fixOrphanSalaryExpensesForTest() async {
    var fixedCount = 0;
    final repo = ExpensesRepository(_db);

    // 1. ابحث عن مصروفات الرواتب اليتيمة.
    //    نُجري فحص نوع الراتب في Dart عبر PayloadMapper.isSalaryExpenseType
    //    لأن الكلمات المفتاحية عربية متعددة (رواتب / سحب راتب / خصم راتب…)
    //    ولا تُترجم بسهولة إلى LIKE في SQL.
    //
    //    شرط "اليتيم": relatedId غير صالح (NULL أو يشير لموظف غير موجود/محذوف)
    //    — بصرف النظر عن حالة employeeUuid (قد يكون فارغاً أو موجوداً لكن
    //      relatedId لم يُحَل بعد). هذا يغطّي:
    //      * المصروفات القديمة جداً (UUID فارغ + relatedId غير صالح)
    //      * المصروفات التي لها UUID لكن relatedId لم يُحَل (نادر لكن ممكن)
    final candidates = await _db
        .customSelect(
          'SELECT id, expense_type, related_id, employee_uuid '
          'FROM expenses '
          'WHERE deleted_at IS NULL '
          'AND (related_id IS NULL OR related_id NOT IN '
          '    (SELECT id FROM employees WHERE deleted_at IS NULL))',
          readsFrom: {_db.expenses, _db.employees},
        )
        .get();

    final orphans = candidates.where((row) {
      final expenseType = row.read<String>('expense_type');
      return PayloadMapper.isSalaryExpenseType(expenseType);
    }).toList();

    if (orphans.isEmpty) {
      return 0;
    }

    AppLogger.info('🔍 Found ${orphans.length} orphan salary expenses to repair.', tag: 'SALARY_FIX');

    for (final row in orphans) {
      final expenseId = row.read<int>('id');
      final existingEmployeeUuid = row.read<String?>('employee_uuid');

      // المحاولة 1: عبر employeeUuid الموجود (إن وُجد ولم يُحَل بعد).
      if (existingEmployeeUuid != null && existingEmployeeUuid.isNotEmpty) {
        final employee =
            await (_db.select(_db.employees)
                  ..where((e) => e.localUuid.equals(existingEmployeeUuid))
                  ..where((e) => e.deletedAt.isNull())
                  ..limit(1))
                .getSingleOrNull();

        if (employee != null) {
          // employeeUuid موجود وصالح → فقط عيّن relatedId.
          // تحديث عبر repo يضمن outbox merge + updatedAt.
          await repo.update(expenseId, relatedId: employee.id, employeeUuid: employee.localUuid);
          fixedCount++;
          AppLogger.debug(
            '  ✅ Expense #$expenseId fixed via employeeUuid '
            '→ employee #${employee.id}',
            tag: 'SALARY_FIX',
          );
          continue;
        }
      }

      // المحاولة 2: عبر salary_withdrawals (المصدر الموثوق للبيانات التاريخية).
      // ابحث عن السحب المرتبط عبر expense_id أولاً.
      int? employeeIdFromWithdrawal;
      try {
        final swRow = await _db
            .customSelect(
              'SELECT employee_id FROM salary_withdrawals '
              'WHERE expense_id = ? AND deleted_at IS NULL LIMIT 1',
              variables: [d.Variable.withInt(expenseId)],
              readsFrom: {_db.salaryWithdrawals},
            )
            .getSingleOrNull();
        if (swRow != null) {
          employeeIdFromWithdrawal = swRow.read<int>('employee_id');
        }
      } catch (_) {
        // العمود expense_id قد لا يكون موجوداً في DBs القديمة جداً
        // (أُضيف في migration 40) — ننتقل للـ fallback.
      }

      // 2ب. fallback: ابحث عبر reason (للسجلات القديمة جداً قبل migration 40).
      if (employeeIdFromWithdrawal == null) {
        final swByReason = await _db
            .customSelect(
              'SELECT employee_id, reason FROM salary_withdrawals '
              'WHERE deleted_at IS NULL AND reason LIKE ?',
              variables: [d.Variable.withString('%exp_$expenseId%')],
              readsFrom: {_db.salaryWithdrawals},
            )
            .get();

        for (final sw in swByReason) {
          final reason = sw.read<String?>('reason');
          if (reason != null && matchesExpenseRef(reason, expenseId)) {
            employeeIdFromWithdrawal = sw.read<int>('employee_id');
            break;
          }
        }
      }

      if (employeeIdFromWithdrawal == null) {
        AppLogger.warning('  ⚠️ Expense #$expenseId: no salary_withdrawal found, leaving as is.', tag: 'SALARY_FIX');
        continue;
      }

      // تحقق من وجود الموظف واحصل على localUuid.
      final employee =
          await (_db.select(_db.employees)
                ..where((e) => e.id.equals(employeeIdFromWithdrawal!))
                ..where((e) => e.deletedAt.isNull())
                ..limit(1))
              .getSingleOrNull();

      if (employee == null) {
        AppLogger.warning(
          '  ⚠️ Expense #$expenseId: employee #$employeeIdFromWithdrawal '
          'not found (deleted?), leaving as is.',
          tag: 'SALARY_FIX',
        );
        continue;
      }

      // أعد ربط المصروف (relatedId + employeeUuid معاً).
      // تحديث عبر repo يضمن outbox merge + updatedAt للرفع للسحاب.
      await repo.update(expenseId, relatedId: employee.id, employeeUuid: employee.localUuid);
      fixedCount++;
      final uuidPreview = employee.localUuid.length >= 8 ? employee.localUuid.substring(0, 8) : employee.localUuid;
      AppLogger.debug(
        '  ✅ Expense #$expenseId fixed via salary_withdrawal '
        '→ employee #${employee.id} (uuid: $uuidPreview...)',
        tag: 'SALARY_FIX',
      );
    }

    return fixedCount;
  }

  /// دالة يدوية لإعادة ضبط الـ flag (للاختبار أو إعادة التشغيل).
  /// تُتيح إعادة تنفيذ الإصلاح في المرة القادمة.
  static Future<void> resetFlag() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_fixDoneKey);
    debugPrint('🔧 Salary fix flag reset — will run again on next sync.');
  }
}
