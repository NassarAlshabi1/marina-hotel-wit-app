// test/services/salary_expense_link_test.dart
//
// ✅ قفل سلوك «اختيار رواتب من القائمة المنسدلة» في شاشة المصروفات.
//
// المسار الفعلي في expenses_list.dart:
//   expensesRepo.create/update(...)  ثم  salaryWithdrawalsRepo.saveFromExpense(...)
//   — أو deleteByExpenseId عند التحويل من راتب إلى نوع آخر.
//
// المتطلبات الثلاثة المُراد تثبيتها هنا:
//   1) الربط    : expenses.withdrawal_uuid ⇄ salary_withdrawals(expense_uuid, expense_id)
//   2) الموظف   : employee_uuid يتبع تغيير الموظف في التعديل (لا يبقى قديماً)
//   3) الطابع   : last_modified_epoch يطابق last_modified بالثوانٍ

import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/repositories/salary_withdrawals_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late SalaryWithdrawalsRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = SalaryWithdrawalsRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> insertEmployee(String uuid, {String name = 'موظف'}) {
    return db
        .into(db.employees)
        .insert(
          EmployeesCompanion(
            localUuid: d.Value(uuid),
            name: d.Value(name),
            position: const d.Value('موظف'),
            status: const d.Value('active'),
            basicSalary: const d.Value(5000.0),
            createdAt: const d.Value(0),
            updatedAt: const d.Value(0),
            lastModified: const d.Value(0),
            createdAtEpoch: const d.Value(0),
            lastModifiedEpoch: const d.Value(0),
            version: const d.Value(1),
            origin: const d.Value('local'),
            vectorClock: const d.Value('{}'),
          ),
        );
  }

  Future<int> insertExpense(String uuid) {
    return db
        .into(db.expenses)
        .insert(
          ExpensesCompanion(
            localUuid: d.Value(uuid),
            expenseType: const d.Value('رواتب'),
            description: const d.Value(''),
            amount: const d.Value(1000),
            date: const d.Value('2026-10-08'),
            hotelDayKey: const d.Value('2026-10-08'),
            createdAt: const d.Value(1000),
            updatedAt: const d.Value(1000),
            lastModified: const d.Value(1000),
            createdAtEpoch: const d.Value(1000),
            lastModifiedEpoch: const d.Value(1000),
          ),
        );
  }

  test('الإنشاء: ربط كامل + الموظف + الطابع بالثوانٍ', () async {
    final empA = await insertEmployee('emp-a');
    final expenseId = await insertExpense('exp-uuid-1');

    await repo.saveFromExpense(
      expenseId: expenseId,
      employeeId: empA,
      action: 'سحب راتب',
      amount: 1000,
      date: '2026-10-08',
      hotelDayKey: '2026-10-08',
    );

    final withdrawals = await repo.listActive();
    expect(withdrawals.length, 1);
    final w = withdrawals.first;

    // 1) الربط في الاتجاهين
    expect(w.expenseUuid, 'exp-uuid-1');
    expect(w.expenseId, expenseId);
    final exp = await (db.select(
      db.expenses,
    )..where((t) => t.id.equals(expenseId))).getSingle();
    expect(exp.withdrawalUuid, w.localUuid);

    // 2) الموظف الصحيح
    expect(w.employeeId, empA);
    expect(w.employeeUuid, 'emp-a');

    // 3) الطابع: الحقلان متساويان وبالثوانٍ
    expect(w.lastModifiedEpoch, w.lastModified);
    expect(w.lastModified, greaterThan(1000000000));
  });

  test('التعديل: تغيير الموظف يحدّث employee_uuid ولا يتركه قديماً', () async {
    final empA = await insertEmployee('emp-a', name: 'أ');
    final empB = await insertEmployee('emp-b', name: 'ب');
    final expenseId = await insertExpense('exp-uuid-2');

    await repo.saveFromExpense(
      expenseId: expenseId,
      employeeId: empA,
      action: 'سحب راتب',
      amount: 1000,
      date: '2026-10-08',
    );

    // تعديل بنفس المصروف مع موظف آخر — نفس ما تفعله شاشة المصروفات
    await repo.saveFromExpense(
      expenseId: expenseId,
      employeeId: empB,
      action: 'سحب راتب',
      amount: 1500,
      date: '2026-10-08',
    );

    final rows = await repo.listActive();
    expect(rows.length, 1, reason: 'يجب ألا يتكرر السجل');
    expect(rows.first.employeeId, empB);
    expect(
      rows.first.employeeUuid,
      'emp-b',
      reason:
          'employee_uuid يجب أن يتبع الموظف الجديد — غيره يجعل '
          'السحب منسوباً لموظف قديم على بقية الأجهزة',
    );
  });

  test('التعديل: last_modified_epoch يُحدَّث مع last_modified', () async {
    final empA = await insertEmployee('emp-a');
    final expenseId = await insertExpense('exp-uuid-3');

    await repo.saveFromExpense(
      expenseId: expenseId,
      employeeId: empA,
      action: 'سحب راتب',
      amount: 1000,
      date: '2026-10-08',
    );
    // ⚠️ d.Time.nowEpoch() بالثانية — «تأخير 20ms ثم قارن» لا يثبت شيئاً
    // لأن الحقلين قد لا يتبادران. البديل الحاسم: نزرع أختاماً قديمة
    // قابلة للتمييز (1000) ثم نتحقق أن الحدث كسرها في الحقلين معاً.
    final created = (await repo.listActive()).first;
    await (db.update(
      db.salaryWithdrawals,
    )..where((t) => t.id.equals(created.id))).write(
      SalaryWithdrawalsCompanion(
        lastModified: const d.Value(1000),
        lastModifiedEpoch: const d.Value(1000),
        version: d.Value(created.version),
      ),
    );

    await repo.saveFromExpense(
      expenseId: expenseId,
      employeeId: empA,
      action: 'سحب راتب',
      amount: 2000,
      date: '2026-10-08',
    );

    final after = (await repo.listActive()).first;
    expect(
      after.lastModified,
      greaterThan(1000),
      reason: 'التعديل يجب أن يُحدّث الطابع ثمّانياً',
    );
    expect(
      after.lastModifiedEpoch,
      after.lastModified,
      reason:
          'last_modified و last_modified_epoch يجب أن يُرسَلان معاً — '
          'ترك أحدهما يجعلهما يتناقضان في كل تعديل',
    );
    expect(after.version, created.version + 1, reason: 'التعديل يرفع الإصدار');
  });

  test('الحذف ثم إعادة الإنشاء: إعادة البطاقة بلا StateError', () async {
    final empA = await insertEmployee('emp-a');
    final expenseId = await insertExpense('exp-uuid-4');

    await repo.saveFromExpense(
      expenseId: expenseId,
      employeeId: empA,
      action: 'سحب راتب',
      amount: 1000,
      date: '2026-10-08',
    );
    final firstUuid = (await repo.listActive()).first.localUuid;

    // تحويل المصروف إلى نوع غير راتب — الشاشة تستدعي deleteByExpenseId
    await repo.deleteByExpenseId(expenseId);
    expect(await repo.listActive(), isEmpty);

    // ثم إعادة اختيار «رواتب» لاحقاً
    await repo.saveFromExpense(
      expenseId: expenseId,
      employeeId: empA,
      action: 'سحب راتب',
      amount: 1000,
      date: '2026-10-08',
    );

    final rows = await repo.listActive();
    expect(rows.length, 1, reason: 'يُنشأ سجل جديد بعد الحذف الناعم');
    expect(rows.first.localUuid, isNot(firstUuid));

    final exp = await (db.select(
      db.expenses,
    )..where((t) => t.id.equals(expenseId))).getSingle();
    expect(
      exp.withdrawalUuid,
      rows.first.localUuid,
      reason: 'الربط يجب أن يُحدَّث إلى السجل الجديد لا يبقى على القديم',
    );
  });
}
