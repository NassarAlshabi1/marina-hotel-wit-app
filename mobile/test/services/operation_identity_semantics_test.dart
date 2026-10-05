// ignore_for_file: lines_longer_than_80_chars
import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/repositories/expenses_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/salary_withdrawals_repository.dart';
import 'package:marina_hotel_mobile/services/salary_expense_classifier.dart';
import 'package:marina_hotel_mobile/services/salary_mirror_matcher.dart';

/// ✅ اختبارات قاعدة «التمييز بهوية العملية نفسها» (هجرة 68).
///
/// القاعدة الحاكمة:
/// - **الإضافة الجديدة عملية مستقلة**: يمكن للموظف السحب مرتين أو ثلاثاً
///   في اليوم الفندقي نفسه وتظهر جميعها في التقرير، حتى لو تساوت المبالغ.
/// - **التعديل ليس مصروفاً جديداً**: تعديل عملية موجودة يحدّث العملية
///   نفسها ويحافظ على هويتها (لا نسخة إضافية ولا بقاء للمبلغ القديم).
/// - **التمييز بالهوية**: رابط المرآة الدائم سحبة.expenseUuid ↔
///   مصروف.localUuid يحسم المطابقة — وليس اسم الموظف ولا اليوم ولا المبلغ.
///
/// مثال القاعدة المُختبر: سحوبات 100 + 100 + 200 = 400. عند تعديل السحب
/// الأول من 100 إلى 150 تصبح 150 + 100 + 200 = 450 وتبقى ثلاث عمليات فقط.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const day = '2026-10-05';

  Future<int> createEmployee(AppDatabase db) {
    return db
        .into(db.employees)
        .insert(
          const EmployeesCompanion(
            name: d.Value('موظف الهوية'),
            basicSalary: d.Value(1000),
            status: d.Value('active'),
            hireDate: d.Value('2026-01-01'),
            localUuid: d.Value('emp-uuid-identity'),
            createdAt: d.Value(1000),
            updatedAt: d.Value(1000),
            lastModified: d.Value(1000),
          ),
        );
  }

  /// مصروف راتب بهوية ثابتة معروفة (كما يصل من السحابة أو يُنشأ محلياً).
  Future<int> createExpense(
    AppDatabase db,
    int employeeId,
    double amount, {
    required String localUuid,
    String type = 'سحب راتب',
    String? withdrawalUuid,
  }) {
    return db
        .into(db.expenses)
        .insert(
          ExpensesCompanion(
            expenseType: d.Value(type),
            relatedId: d.Value(employeeId),
            employeeUuid: const d.Value('emp-uuid-identity'),
            amount: d.Value(amount),
            date: d.Value(day),
            hotelDayKey: d.Value(day),
            description: const d.Value('سحب راتب'),
            localUuid: d.Value(localUuid),
            withdrawalUuid: withdrawalUuid == null
                ? const d.Value.absent()
                : d.Value(withdrawalUuid),
            createdAt: const d.Value(1000),
            updatedAt: const d.Value(1000),
            lastModified: const d.Value(1000),
          ),
        );
  }

  /// مرشحو المطابقة كما تبنيهم التقارير — **مع حقول الهوية** (هجرة 68).
  List<MirrorExpenseCandidate> candidatesOf(List<Expense> expenses) {
    return expenses
        .map(
          (e) => MirrorExpenseCandidate(
            id: e.id,
            serverId: e.serverId,
            expenseType: e.expenseType,
            amount: e.amount,
            date: e.date,
            hotelDayKey: e.hotelDayKey,
            relatedId: e.relatedId,
            localUuid: e.localUuid,
            withdrawalUuid: e.withdrawalUuid,
          ),
        )
        .toList(growable: false);
  }

  /// إجمالي التقرير النقدي بنفس قواعد expenses_report_screen — يمرّر
  /// حقول الهوية للمطابِق (المستوى 0) كما يفعل التقرير الحقيقي.
  Future<double> reportCashTotal(AppDatabase db) async {
    final expensesStmt = db.select(db.expenses)
      ..where((t) => t.deletedAt.isNull());
    final expenses = await expensesStmt.get();
    final withdrawalsStmt = db.select(db.salaryWithdrawals)
      ..where((t) => t.deletedAt.isNull());
    final withdrawals = await withdrawalsStmt.get();
    final candidates = candidatesOf(expenses);

    var total = 0.0;
    for (final e in expenses) {
      if (SalaryExpenseClassifier.isSalaryDeduction(e.expenseType)) continue;
      total += e.amount;
    }
    for (final sw in withdrawals) {
      if (sw.amount <= 0) continue;
      final wType = sw.withdrawalType ?? 'سحب راتب';
      if (wType.contains('خصم')) continue;
      final isMirror = SalaryMirrorMatcher.isMirrorOfReadExpense(
        expenseUuid: sw.expenseUuid,
        withdrawalLocalUuid: sw.localUuid,
        expenseId: sw.expenseId,
        reason: sw.reason,
        amount: sw.amount,
        hotelDayKey: sw.hotelDayKey,
        withdrawDate: sw.withdrawDate,
        employeeId: sw.employeeId,
        expenses: candidates,
      );
      if (!isMirror) total += sw.amount;
    }
    return total;
  }

  group('الإضافة الجديدة مستقلة والتعديل يحدّث العملية نفسها', () {
    late AppDatabase db;
    late SalaryWithdrawalsRepository withdrawalsRepo;
    late ExpensesRepository expensesRepo;
    late int empId;
    late int exp1;
    late int exp2;
    late int exp3;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      withdrawalsRepo = SalaryWithdrawalsRepository(db);
      expensesRepo = ExpensesRepository(db);
      empId = await createEmployee(db);

      // ثلاث عمليات في اليوم الفندقي نفسه: 100 + 100 + 200.
      // عمليتان متطابقتا المبلغ تماماً — يجب أن تظلا مستقلتين.
      exp1 = await createExpense(db, empId, 100, localUuid: 'exp-id-A');
      exp2 = await createExpense(db, empId, 100, localUuid: 'exp-id-B');
      exp3 = await createExpense(db, empId, 200, localUuid: 'exp-id-C');

      await withdrawalsRepo.saveFromExpense(
        expenseId: exp1,
        employeeId: empId,
        action: 'سحب راتب',
        amount: 100,
        date: day,
        hotelDayKey: day,
      );
      await withdrawalsRepo.saveFromExpense(
        expenseId: exp2,
        employeeId: empId,
        action: 'سحب راتب',
        amount: 100,
        date: day,
        hotelDayKey: day,
      );
      await withdrawalsRepo.saveFromExpense(
        expenseId: exp3,
        employeeId: empId,
        action: 'سحب راتب',
        amount: 200,
        date: day,
        hotelDayKey: day,
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('ثلاث سحوبات متشابهة = ثلاث عمليات مستقلة، المجموع 400', () async {
      final activeStmt = db.select(db.salaryWithdrawals)
        ..where((t) => t.deletedAt.isNull());
      final active = await activeStmt.get();

      expect(active, hasLength(3), reason: 'كل إضافة جديدة عملية مستقلة');
      final amounts = active.map((w) => w.amount).toList()..sort();
      expect(amounts, [100.0, 100.0, 200.0]);

      // كل مرآة مرتبطة بهوية مصروفها — هويات مختلفة لا تندمج.
      final uuids = active.map((w) => w.expenseUuid).toSet();
      expect(uuids, {'exp-id-A', 'exp-id-B', 'exp-id-C'});
      expect(
        active.map((w) => w.localUuid).toSet(),
        hasLength(3),
        reason: 'هويات المرايا مختلفة',
      );

      // الختم العكسي: كل مصروف يختم هوية مرآته هو (وليس هويته الذاتية).
      for (final uuid in ['exp-id-A', 'exp-id-B', 'exp-id-C']) {
        final expenseStmt = db.select(db.expenses)
          ..where((t) => t.localUuid.equals(uuid));
        final expense = await expenseStmt.getSingle();
        expect(expense.withdrawalUuid, isNotNull);
        expect(expense.withdrawalUuid, isNot(equals(expense.localUuid)));
        final mirrorStmt = db.select(db.salaryWithdrawals)
          ..where((t) => t.localUuid.equals(expense.withdrawalUuid!));
        final mirror = await mirrorStmt.getSingleOrNull();
        expect(mirror, isNotNull, reason: 'الختم العكسي يشير لمرآة قائمة');
        expect(mirror!.expenseUuid, uuid);
      }

      expect(await reportCashTotal(db), 400);
    });

    test(
      'تعديل السحب الأول 100→150: ثلاث عمليات فقط والمجموع 450 '
      'وهوية المرآة لا تتغير',
      () async {
        final beforeStmt = db.select(db.salaryWithdrawals)
          ..where((t) => t.expenseUuid.equals('exp-id-A'));
        final before = await beforeStmt.getSingle();

        // التعديل كما تفعله شاشة المصروفات: تحديث المصروف + مرآته.
        await expensesRepo.update(exp1, amount: 150);
        await withdrawalsRepo.saveFromExpense(
          expenseId: exp1,
          employeeId: empId,
          action: 'سحب راتب',
          amount: 150,
          date: day,
          hotelDayKey: day,
          previousAmount: 100,
          previousEmployeeId: empId,
        );

        final activeStmt = db.select(db.salaryWithdrawals)
          ..where((t) => t.deletedAt.isNull());
        final active = await activeStmt.get();

        expect(active, hasLength(3), reason: 'التعديل لا ينشئ نسخة رابعة');
        final amounts = active.map((w) => w.amount).toList()..sort();
        expect(amounts, [100.0, 150.0, 200.0]);

        // الهوية محفوظة: نفس المرآة حُدّثت ولم تُستبدل.
        final afterStmt = db.select(db.salaryWithdrawals)
          ..where((t) => t.expenseUuid.equals('exp-id-A'));
        final after = await afterStmt.getSingle();
        expect(after.localUuid, before.localUuid);
        expect(after.amount, 150);

        // المبلغ القديم زال من التقرير والجديد يُحتسب مرة واحدة.
        expect(await reportCashTotal(db), 450);
      },
    );

    test('حذف مصروف يحذف مرآته بالهوية حتى مع رابط رقمي أجنبي', () async {
      // اكسر الرابط الرقمي للمرآة الأولى (محاكاة تصادم معرفات الأجهزة).
      final mirrorStmt = db.select(db.salaryWithdrawals)
        ..where((t) => t.expenseUuid.equals('exp-id-A'));
      final mirror = await mirrorStmt.getSingle();
      await db.customStatement(
        'UPDATE salary_withdrawals SET expense_id = 777777 WHERE id = ?',
        [mirror.id],
      );

      // الحذف الفعلي: حذف المصروف ثم مرآته — كما تفعل الشاشة.
      await expensesRepo.delete(exp1);
      await withdrawalsRepo.deleteByExpenseId(
        exp1,
        employeeId: empId,
        employeeUuid: 'emp-uuid-identity',
      );

      final activeStmt = db.select(db.salaryWithdrawals)
        ..where((t) => t.deletedAt.isNull());
      final active = await activeStmt.get();
      expect(active, hasLength(2));
      expect(
        active.map((w) => w.expenseUuid).toSet(),
        {'exp-id-B', 'exp-id-C'},
      );
      // العملية المحذوفة لا تظهر في التقرير: 100 + 200.
      expect(await reportCashTotal(db), 300);
    });
  });

  group('التمييز بالهوية يتغلب على الروابط الرقمية المتصادمة', () {
    late AppDatabase db;
    late SalaryWithdrawalsRepository withdrawalsRepo;
    late ExpensesRepository expensesRepo;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      withdrawalsRepo = SalaryWithdrawalsRepository(db);
      expensesRepo = ExpensesRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    test(
      'توأمان متطابقان (موظف/يوم/مبلغ): تعديل أحدهما بالهوية لا يمس الآخر',
      () async {
        final empId = await createEmployee(db);
        final twin1 = await createExpense(db, empId, 100, localUuid: 'tw-1');
        final twin2 = await createExpense(db, empId, 100, localUuid: 'tw-2');

        await withdrawalsRepo.saveFromExpense(
          expenseId: twin1,
          employeeId: empId,
          action: 'سحب راتب',
          amount: 100,
          date: day,
          hotelDayKey: day,
        );
        await withdrawalsRepo.saveFromExpense(
          expenseId: twin2,
          employeeId: empId,
          action: 'سحب راتب',
          amount: 100,
          date: day,
          hotelDayKey: day,
        );

        final m1Stmt = db.select(db.salaryWithdrawals)
          ..where((t) => t.expenseUuid.equals('tw-1'));
        final m2Stmt = db.select(db.salaryWithdrawals)
          ..where((t) => t.expenseUuid.equals('tw-2'));
        final m1 = await m1Stmt.getSingle();
        final m2 = await m2Stmt.getSingle();

        // محاكاة تصادم رقمي: مرآة التوأم الثاني تحمل رقم مصروف التوأم
        // الأول في عمود expense_id (رابط أجنبي خاطئ). المطابقة البيانية
        // كانت ستختطفها — الهوية تحسم.
        await db.customStatement(
          'UPDATE salary_withdrawals SET expense_id = ? WHERE id = ?',
          [twin1, m2.id],
        );
        await db.customStatement(
          'UPDATE salary_withdrawals SET expense_id = NULL WHERE id = ?',
          [m1.id],
        );

        await expensesRepo.update(twin1, amount: 150);
        await withdrawalsRepo.saveFromExpense(
          expenseId: twin1,
          employeeId: empId,
          action: 'سحب راتب',
          amount: 150,
          date: day,
          hotelDayKey: day,
          previousAmount: 100,
          previousEmployeeId: empId,
        );

        final after1 = await m1Stmt.getSingle();
        final after2 = await m2Stmt.getSingle();
        expect(after1.localUuid, m1.localUuid, reason: 'الهوية محفوظة');
        expect(after1.amount, 150, reason: 'التوأم الأول هو المُعدَّل');
        expect(after2.localUuid, m2.localUuid);
        expect(after2.amount, 100, reason: 'التوأم الثاني لم يُختطف');

        final activeStmt = db.select(db.salaryWithdrawals)
          ..where((t) => t.deletedAt.isNull());
        final active = await activeStmt.get();
        expect(active, hasLength(2));
        expect(await reportCashTotal(db), 250);
      },
    );

    test('الختم الذاتي الفاسد يُصلح تلقائياً عند أول تعديل', () async {
      final empId = await createEmployee(db);
      // مصروف عليه ختم فاسد قديم: يشير لهويته الذاتية بدل هوية المرآة.
      final expId = await createExpense(
        db,
        empId,
        200,
        localUuid: 'self-stamped',
        withdrawalUuid: 'self-stamped',
      );

      await withdrawalsRepo.saveFromExpense(
        expenseId: expId,
        employeeId: empId,
        action: 'سحب راتب',
        amount: 200,
        date: day,
        hotelDayKey: day,
      );

      final mirrorStmt = db.select(db.salaryWithdrawals)
        ..where((t) => t.expenseUuid.equals('self-stamped'));
      final mirror = await mirrorStmt.getSingle();

      final expenseStmt = db.select(db.expenses)
        ..where((t) => t.id.equals(expId));
      final expense = await expenseStmt.getSingle();
      expect(
        expense.withdrawalUuid,
        mirror.localUuid,
        reason: 'الختم أصبح هوية المرآة الفعلية لا هوية المصروف',
      );
      expect(await reportCashTotal(db), 200);
    });
  });

  group('المطابِق — المستوى 0 (الهوية) في القراءة', () {
    test('رابط الهوية يحسم المرآة حتى مع اختلاف كل البيانات', () {
      const candidate = MirrorExpenseCandidate(
        id: 7,
        serverId: null,
        expenseType: 'سحب راتب',
        amount: 999, // مبلغ مختلف تماماً
        date: '2026-01-01', // يوم مختلف تماماً
        hotelDayKey: '2026-01-01',
        relatedId: 3, // موظف مختلف تماماً
        localUuid: 'exp-uuid-7',
      );
      final isMirror = SalaryMirrorMatcher.isMirrorOfReadExpense(
        expenseUuid: 'exp-uuid-7',
        expenseId: null,
        reason: null,
        amount: 50,
        hotelDayKey: day,
        withdrawDate: day,
        employeeId: 9,
        expenses: const [candidate],
      );
      expect(isMirror, isTrue, reason: 'الهوية تحسم بغض النظر عن البيانات');
    });

    test('الختم العكسي (مصروف → سحبة) يحسم المرآة أيضاً', () {
      const candidate = MirrorExpenseCandidate(
        id: 8,
        serverId: null,
        expenseType: 'سحب راتب',
        amount: 300,
        date: day,
        hotelDayKey: day,
        relatedId: 5,
        localUuid: 'exp-uuid-8',
        withdrawalUuid: 'sw-uuid-88',
      );
      final isMirror = SalaryMirrorMatcher.isMirrorOfReadExpense(
        withdrawalLocalUuid: 'sw-uuid-88',
        expenseId: null,
        reason: null,
        amount: 300,
        hotelDayKey: day,
        withdrawDate: day,
        employeeId: 5,
        expenses: const [candidate],
      );
      expect(isMirror, isTrue);
    });

    test('الختم الذاتي الفاسد لا يُنتج مطابقة وهمية', () {
      // مصروف مختوم بهويته هو (خطأ تاريخي) — المطابقة العكسية بهوية
      // تساوي هوية المصروف يجب ألا تعدّه مرآة.
      const candidate = MirrorExpenseCandidate(
        id: 9,
        serverId: null,
        expenseType: 'سحب راتب',
        amount: 300,
        date: day,
        hotelDayKey: day,
        relatedId: 5,
        localUuid: 'corrupt-self',
        withdrawalUuid: 'corrupt-self', // ختم ذاتي فاسد
      );
      final isMirror = SalaryMirrorMatcher.isMirrorOfReadExpense(
        withdrawalLocalUuid: 'corrupt-self',
        expenseId: null,
        reason: null,
        amount: 12345, // لا تطابق بياني
        hotelDayKey: '2020-01-01',
        withdrawDate: '2020-01-01',
        employeeId: 77,
        expenses: const [candidate],
      );
      expect(isMirror, isFalse);
    });

    test('السحب المباشر ليس مرآة أبداً حتى لو حمل رابط هوية', () {
      const candidate = MirrorExpenseCandidate(
        id: 10,
        serverId: null,
        expenseType: 'سحب راتب',
        amount: 100,
        date: day,
        hotelDayKey: day,
        relatedId: 5,
        localUuid: 'exp-uuid-10',
      );
      final isMirror = SalaryMirrorMatcher.isMirrorOfReadExpense(
        expenseUuid: 'exp-uuid-10',
        expenseId: null,
        reason: 'direct_withdrawal_emp-uuid',
        amount: 100,
        hotelDayKey: day,
        withdrawDate: day,
        employeeId: 5,
        expenses: const [candidate],
      );
      expect(isMirror, isFalse);
    });

    test('resolveLinkedExpenseId يحل بالهوية أولاً', () {
      const candidate = MirrorExpenseCandidate(
        id: 11,
        serverId: null,
        expenseType: 'سحب راتب',
        amount: 100,
        date: day,
        hotelDayKey: day,
        relatedId: 5,
        localUuid: 'exp-uuid-11',
      );
      final resolved = SalaryMirrorMatcher.resolveLinkedExpenseId(
        expenseUuid: 'exp-uuid-11',
        expenseId: 99999, // رقم أجنبي لا يقابل شيئاً
        reason: null,
        expenses: const [candidate],
      );
      expect(resolved, 11);
    });
  });
}
