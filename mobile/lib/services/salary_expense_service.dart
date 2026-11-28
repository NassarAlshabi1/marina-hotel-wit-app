// lib/services/salary_expense_service.dart
//
// ✅ (2026-11-05 — وثيقة الربط والمزامنة الموحدة §6.1) SalaryExpenseService
// المسار الوحيد لإنشاء/تعديل/حذف مصروف من عائلة الرواتب (وإعادة إسناده).
//
// العقد الذري (§6.1/§1.3-7): «كل عملية محلية تمس مصروفاً ومرآته تتم في
// transaction واحدة»:
// - حفظ المصروف + إنشاء/تحديث المرآة في معاملة واحدة — فشل إنشاء المرآة
//   يلغي حفظ المصروف (§13: «فشل إنشاء المرآة يلغي حفظ المصروف»).
// - تثبيت employeeUuid في الطرفين (المصروف والمرآة) وقت الكتابة نفسها.
// - تثبيت expenseUuid في المرآة (رابط الهوية الدائم §1.1/§6.1).
// - تحديث outbox للسجلين داخل المعاملة (المستودعات تدمجه عبر OutboxDao).
// - منع إنشاء مرآة ثانية نشطة للمصروف نفسه (حارس ux_salary_withdrawals_
//   expense_uuid_active + منطق الهوية في saveFromExpense).
// - الإشعارات وتحديث UI بعد نجاح commit فقط — لا شيء هنا يلمس UI.
//
// ربط الموظف UUID-first (§5.1): لا يكتب هذا الخدمة أي رقم محلي من
// payload بعيد؛ يُحل الموظف من employeeUuid إلى employees.id داخل
// المعاملة، وإذا لم يُحل فشلت العملية كاملة بلا أي كتابة (§5.2).
import 'package:drift/drift.dart' as d;

import '../utils/debug_log.dart';
import 'local_db.dart';
import 'repositories/expenses_repository.dart';
import 'repositories/salary_withdrawals_repository.dart';
import 'salary_expense_classifier.dart';

/// مسودة عملية راتبية — تُبنى من الشاشة بعد التحقق من المدخلات.
class SalaryExpenseDraft {
  const SalaryExpenseDraft({
    required this.expenseType,
    required this.amount,
    required this.date,
    required this.hotelDayKey,
    required this.description,
    required this.isSalaryFamily,
    this.existing,
    this.employeeUuid,
    this.cashRepaymentOnly = false,
  });

  /// المصروف عند التعديل (null = إنشاء جديد). يحمل القيم **قبل** التغيير.
  final Expense? existing;

  /// نوع المصروف النهائي (بعد اشتقاق الشاشة من نوع العملية).
  final String expenseType;

  /// مبلغ موجب دائماً — الإشارة الموقّعة تُشتق داخل الخدمة من النوع
  /// (خصم/تسديد → سالب، سحب/سلفة → موجب).
  final double amount;

  /// yyyy-MM-dd — يُطبّع داخل المستودعات.
  final String date;

  /// مفتاح اليوم الفندقي المطابق للتاريخ المختار.
  final String hotelDayKey;
  final String description;

  /// هل النوع النهائي من عائلة الرواتب؟ (false عند التحويل لغير راتب)
  final bool isSalaryFamily;

  /// هوية الموظف الدائمة — إلزامية لكل عملية راتب (§3.2/§6.1).
  final String? employeeUuid;

  /// تسديد سلفة نقدياً (§6.2): مرآة سالبة مباشرة **بلا مصروف** —
  /// يخفّض رصيد السلف فقط ولا يمس خرج الصندوق.
  final bool cashRepaymentOnly;
}

/// نتيجة حفظ ذري ناجح — يُقرأ بعد commit فقط.
class SalaryExpenseSaveResult {
  const SalaryExpenseSaveResult({
    required this.expenseId,
    required this.expenseLocalUuid,
    required this.mirrorId,
    required this.mirrorLocalUuid,
    required this.createdExpense,
    required this.deletedMirror,
    required this.cashRepayment,
  });

  /// null للتسديد النقدي (لا مصروف).
  final int? expenseId;
  final String expenseLocalUuid;
  final int? mirrorId;
  final String mirrorLocalUuid;

  final bool createdExpense;

  /// true عند تحويل مصروف راتبي قديم إلى غير راتبي (حُذفت مرآته).
  final bool deletedMirror;
  final bool cashRepayment;
}

/// خدمة المصروفات الراتببة الذرية — §6.1.
class SalaryExpenseService {
  SalaryExpenseService(
    this._db, {
    required ExpensesRepository expensesRepo,
    required SalaryWithdrawalsRepository salaryRepo,
  }) : _expensesRepo = expensesRepo,
       _salaryRepo = salaryRepo;

  final AppDatabase _db;
  final ExpensesRepository _expensesRepo;
  final SalaryWithdrawalsRepository _salaryRepo;

  /// حفظ ذري (إنشاء أو تعديل) لمصروف راتبي ومرآته — §6.1.
  ///
  /// - [draft.cashRepaymentOnly] → تسديد نقدي: مرآة سالبة بلا مصروف (§6.2).
  /// - إنشاء: مصروف + مرآة في معاملة واحدة.
  /// - تعديل مصروف راتبي: تحديث المصروف + تحديث/تبنّي المرآة بتمرير
  ///   المبلغ/الموظف السابقين (هوية العملية لا الاستدلال).
  /// - تعديل وتحويل النوع لغير الراتب: مسح employeeUuid من المصروف +
  ///   حذف مرآته في المعاملة نفسها (لا مرآة يتيمة).
  Future<SalaryExpenseSaveResult> saveSalaryExpense(
    SalaryExpenseDraft draft,
  ) async {
    final existing = draft.existing;
    final amount = draft.amount;
    if (amount <= 0) {
      throw ArgumentError('مبلغ العملية الراتببة يجب أن يكون موجباً');
    }
    if (draft.cashRepaymentOnly && existing != null) {
      throw ArgumentError('التسديد النقدي عملية إنشاء فقط (بلا مصروف)');
    }

    // ── حل الموظف من UUID داخل المعاملة (§5.1) — قبل أي كتابة ──
    Employee? resolvedEmployee;
    if (draft.isSalaryFamily || draft.cashRepaymentOnly) {
      final uuid = (draft.employeeUuid ?? '').trim();
      if (uuid.isEmpty) {
        throw StateError(
          'employeeUuid إلزامي لكل عملية راتب (§6.1) — أُوقف الحفظ.',
        );
      }
      resolvedEmployee = await (_db.select(
        _db.employees,
      )..where((e) => e.localUuid.equals(uuid))).getSingleOrNull();
      if (resolvedEmployee == null) {
        throw StateError(
          'تعذر حل الموظف بواسطة employeeUuid؛ أُوقف الحفظ لمنع ربط '
          'المصروف بموظف خاطئ (§5.2).',
        );
      }
    }

    // ── المعاملة الذرية: مصروف + مرآة + outbox معاً (§6.1/§1.3-7) ──
    return _db.transaction(() async {
      // 1) تسديد سلفة نقدياً: بلا مصروف — مرآة سالبة مباشرة (§6.2).
      if (draft.cashRepaymentOnly) {
        final mirrorId = await _salaryRepo.createDirect(
          employeeId: resolvedEmployee!.id,
          amount: -amount,
          date: draft.date,
          reason: 'تسديد سلفة نقدي',
          withdrawalType: 'تسديد سلفة',
          description: draft.description.isEmpty
              ? 'تسديد سلفة نقدي'
              : draft.description,
          hotelDayKey: draft.hotelDayKey,
        );
        final mirror = await (_db.select(
          _db.salaryWithdrawals,
        )..where((w) => w.id.equals(mirrorId))).getSingle();
        return SalaryExpenseSaveResult(
          expenseId: null,
          expenseLocalUuid: '',
          mirrorId: mirrorId,
          mirrorLocalUuid: mirror.localUuid,
          createdExpense: false,
          deletedMirror: false,
          cashRepayment: true,
        );
      }

      final wasSalary = existing != null
          ? SalaryExpenseClassifier.isSalaryRelated(existing.expenseType)
          : false;

      // 2) المصروف — إنشاء أو تحديث.
      int expenseId;
      String expenseUuid;
      if (existing == null) {
        expenseId = await _expensesRepo.create(
          expenseType: draft.expenseType,
          relatedId: draft.isSalaryFamily ? resolvedEmployee!.id : null,
          description: draft.description,
          amount: amount,
          date: draft.date,
          hotelDayKey: draft.hotelDayKey,
          employeeUuid: draft.isSalaryFamily ? resolvedEmployee!.localUuid : '',
        );
        final row = await (_db.select(
          _db.expenses,
        )..where((e) => e.id.equals(expenseId))).getSingle();
        expenseUuid = row.localUuid;
      } else {
        await _expensesRepo.update(
          existing.id,
          expenseType: draft.expenseType,
          relatedId: draft.isSalaryFamily ? resolvedEmployee!.id : null,
          description: draft.description,
          amount: amount,
          date: draft.date,
          hotelDayKey: draft.hotelDayKey,
          // فارغ = مسح الرابط عند التحويل لغير الراتب (يمنع رابطاً يتيماً).
          employeeUuid: draft.isSalaryFamily ? resolvedEmployee!.localUuid : '',
        );
        expenseId = existing.id;
        final row = await (_db.select(
          _db.expenses,
        )..where((e) => e.id.equals(expenseId))).getSingle();
        expenseUuid = row.localUuid;
      }

      // 3) المرآة — إنشاء/تحديث/حذف حسب العائلة.
      if (!draft.isSalaryFamily) {
        if (wasSalary) {
          // تحويل مصروف راتبي قديم إلى غير راتبي: حذف مرآته في المعاملة
          // نفسها (§6.3) — بتمرير موظف المصروف القديم كي لا تُمسّ مرآة
          // أجنبية تصادم الرقم (R3).
          await _salaryRepo.deleteByExpenseId(
            expenseId,
            // existing غير null هنا (wasSalary مشتق من existing != null)
            // والتحليل السكاني يعرف ذلك — بلا حاجة لـ '!'.
            employeeId: existing.relatedId,
            employeeUuid: existing.employeeUuid,
          );
        }
        return SalaryExpenseSaveResult(
          expenseId: expenseId,
          expenseLocalUuid: expenseUuid,
          mirrorId: null,
          mirrorLocalUuid: '',
          createdExpense: existing == null,
          deletedMirror: wasSalary,
          cashRepayment: false,
        );
      }

      // المبلغ الموقّع: سالب للخصم وتسديد السلفة (سداد لا سحب) — §6.1.
      final signedAmount =
          SalaryExpenseClassifier.isSalaryDeduction(draft.expenseType) ||
              SalaryExpenseClassifier.isLoanRepayment(draft.expenseType)
          ? -amount
          : amount;

      // تبنّي الهوية عند التعديل: المبلغ/الموظف السابقان قبل التغيير —
      // كي تُعتمد المرآة القائمة بدل إنشاء مرآة ثانية مكررة.
      final double? previousSignedAmount;
      final int? previousEmployeeId;
      if (existing != null && wasSalary) {
        previousSignedAmount =
            SalaryExpenseClassifier.isSalaryDeduction(existing.expenseType) ||
                SalaryExpenseClassifier.isLoanRepayment(existing.expenseType)
            ? -existing.amount
            : existing.amount;
        previousEmployeeId = existing.relatedId;
      } else {
        previousSignedAmount = null;
        previousEmployeeId = null;
      }

      await _salaryRepo.saveFromExpense(
        expenseId: expenseId,
        employeeId: resolvedEmployee!.id,
        action: draft.expenseType,
        amount: signedAmount,
        date: draft.date,
        note: draft.description,
        hotelDayKey: draft.hotelDayKey,
        previousAmount: previousSignedAmount,
        previousEmployeeId: previousEmployeeId,
      );

      // المرآة بعد الحفظ — ليعيد الحساب هويتها الدائمة (expenseUuid).
      final mirror =
          await (_db.select(_db.salaryWithdrawals)..where(
                (w) => w.expenseUuid.equals(expenseUuid) & w.deletedAt.isNull(),
              ))
              .get();
      final activeMirror = mirror.isEmpty
          ? await (_db.select(_db.salaryWithdrawals)..where(
                  (w) => w.expenseId.equals(expenseId) & w.deletedAt.isNull(),
                ))
                .getSingleOrNull()
          : mirror.first;

      dlog(
        () =>
            '✅ SalaryExpenseService: حفظ ذري مكتمل '
            'expense=$expenseId($expenseUuid) '
            'mirror=${activeMirror?.id}(${activeMirror?.localUuid}) '
            'cash=false',
      );

      return SalaryExpenseSaveResult(
        expenseId: expenseId,
        expenseLocalUuid: expenseUuid,
        mirrorId: activeMirror?.id,
        mirrorLocalUuid: activeMirror?.localUuid ?? '',
        createdExpense: existing == null,
        deletedMirror: false,
        cashRepayment: false,
      );
    });
  }

  /// حذف ذري لمصروف راتبي ومرآته — soft-delete للطرفين + outbox لكليهما
  /// في معاملة واحدة (§6.3): «حذف مصروف راتب: soft-delete للمصروف
  /// والمرآة في transaction واحدة، وإنشاء tombstones/outbox لكليهما».
  Future<void> deleteSalaryExpense(Expense expense) async {
    await _db.transaction(() async {
      // المرآة أولاً (بنفس معاملة المصروف) — فشل أي طرف يُلغي الطرفين.
      await _salaryRepo.deleteByExpenseId(
        expense.id,
        employeeId: expense.relatedId,
        employeeUuid: expense.employeeUuid,
      );
      await _expensesRepo.delete(expense.id);
      dlog(
        () =>
            '✅ SalaryExpenseService: حذف ذري مكتمل '
            'expense=${expense.id}(${expense.localUuid}) + مرآته',
      );
    });
  }

  /// إعادة إسناد مصروف راتبي لموظف آخر — §6.1 reassignEmployee:
  /// تحديث employeeUuid للمصروف والمرآة معاً في معاملة واحدة، ثم إعادة
  /// اشتقاق relatedId وemployeeId محلياً من UUID الأب الجديد (§5.1).
  Future<void> reassignEmployee({
    required String expenseUuid,
    required String employeeUuid,
  }) async {
    final eu = expenseUuid.trim();
    final nu = employeeUuid.trim();
    if (eu.isEmpty || nu.isEmpty) {
      throw ArgumentError('expenseUuid و employeeUuid إلزاميان (§6.1)');
    }

    await _db.transaction(() async {
      final expense = await (_db.select(
        _db.expenses,
      )..where((e) => e.localUuid.equals(eu))).getSingleOrNull();
      if (expense == null) {
        throw StateError('المصروف $eu غير موجود محلياً — لا إعادة إسناد');
      }
      if (!SalaryExpenseClassifier.isSalaryRelated(expense.expenseType)) {
        throw StateError('reassignEmployee لمصروفات عائلة الرواتب فقط (§6.1)');
      }
      final employee = await (_db.select(
        _db.employees,
      )..where((e) => e.localUuid.equals(nu))).getSingleOrNull();
      if (employee == null) {
        throw StateError(
          'تعذر حل الموظف الجديد بواسطة employeeUuid (§5.2) — '
          'لا إعادة إسناد بلا أب محلول',
        );
      }

      // المصروف: UUID + الرقم المحلي المشتق من الأب (cache محلي §1.1).
      await (_db.update(
        _db.expenses,
      )..where((e) => e.localUuid.equals(eu))).write(
        ExpensesCompanion(
          employeeUuid: d.Value(nu),
          relatedId: d.Value(employee.id),
        ),
      );

      // المرآة بالهوية: كل مرآة نشطة تعلن ارتباطها بهذا المصروف.
      final mirrors = await (_db.select(
        _db.salaryWithdrawals,
      )..where((w) => w.expenseUuid.equals(eu) & w.deletedAt.isNull())).get();
      for (final m in mirrors) {
        await (_db.update(
          _db.salaryWithdrawals,
        )..where((w) => w.localUuid.equals(m.localUuid))).write(
          SalaryWithdrawalsCompanion(
            employeeUuid: d.Value(nu),
            employeeId: d.Value(employee.id),
          ),
        );
      }
      dlog(
        () =>
            '✅ SalaryExpenseService: إعادة إسناد ذرية $eu → $nu '
            '(mirrors=${mirrors.length})',
      );
    });
  }
}
