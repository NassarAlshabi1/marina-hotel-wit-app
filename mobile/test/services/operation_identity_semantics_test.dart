// ignore_for_file: lines_longer_than_80_chars
import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:marina_hotel_mobile/services/appwrite_service.dart';
import 'package:marina_hotel_mobile/services/appwrite_sync_manager.dart';
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

    test('تعديل السحب الأول 100→150: ثلاث عمليات فقط والمجموع 450 '
        'وهوية المرآة لا تتغير', () async {
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
    });

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
      expect(active.map((w) => w.expenseUuid).toSet(), {
        'exp-id-B',
        'exp-id-C',
      });
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

  group('سيناريوهات عميقة — مسار الكتابة بالهوية', () {
    late AppDatabase db;
    late SalaryWithdrawalsRepository withdrawalsRepo;
    late ExpensesRepository expensesRepo;
    late int empId;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      withdrawalsRepo = SalaryWithdrawalsRepository(db);
      expensesRepo = ExpensesRepository(db);
      empId = await createEmployee(db);
    });

    tearDown(() async {
      await db.close();
    });

    Future<int> createMirrorRaw(
      double amount, {
      required String localUuid,
      String? expenseUuid,
      int? expenseId,
      int updatedAt = 1000,
      String reason = '',
    }) {
      return db
          .into(db.salaryWithdrawals)
          .insert(
            SalaryWithdrawalsCompanion(
              employeeId: d.Value(empId),
              amount: d.Value(amount),
              withdrawDate: d.Value(day),
              withdrawalType: const d.Value('سحب راتب'),
              reason: d.Value(reason.isEmpty ? 'exp_1' : reason),
              expenseId: expenseId == null
                  ? const d.Value.absent()
                  : d.Value(expenseId),
              expenseUuid: expenseUuid == null
                  ? const d.Value.absent()
                  : d.Value(expenseUuid),
              hotelDayKey: d.Value(day),
              localUuid: d.Value(localUuid),
              createdAt: d.Value(updatedAt),
              updatedAt: d.Value(updatedAt),
              lastModified: d.Value(updatedAt),
            ),
          );
    }

    test('إنشاء مزدوج لنفس الهوية عبر الأجهزة: تُعتمد الأحدث وتُحذف النسخة '
        'الأخرى — العملية تُحتسب مرة واحدة', () async {
      final expId = await createExpense(db, empId, 100, localUuid: 'dup-1');
      // ✅ (migration 69 — D1 0013) الفهرس الفريد الجزئي يمنع نشوء هذه
      // الحالة على قاعدة نظيفة — وهو الغرض من القيد نفسه. الاختبار هنا
      // يغطي منطق الدفاع التراثي في saveFromIdentityDuplicates: قاعدة
      // قديمة سبقت القيد (ترقية مؤجلة بسبب تكرارات قائمة) — لذا يُسقط
      // الفهرس مؤقتاً لمحاكاة تلك الحالة، وتبقى كل التأكيدات كما هي.
      await db.customStatement(
        'DROP INDEX IF EXISTS idx_salary_withdrawals_active_expense',
      );
      // نسختان لنفس العملية (تصادم إنشاء من جهازين) — الأحدث تحديثاً 2000.
      await createMirrorRaw(
        100,
        localUuid: 'dup-old',
        expenseUuid: 'dup-1',
        updatedAt: 1000,
      );
      await createMirrorRaw(
        100,
        localUuid: 'dup-new',
        expenseUuid: 'dup-1',
        updatedAt: 2000,
      );

      await expensesRepo.update(expId, amount: 150);
      await withdrawalsRepo.saveFromExpense(
        expenseId: expId,
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
      expect(active, hasLength(1), reason: 'عملية واحدة بممثل وحيد');
      expect(active.first.localUuid, 'dup-new', reason: 'الأحدث معتمدة');
      expect(active.first.amount, 150);

      final deletedStmt = db.select(db.salaryWithdrawals)
        ..where((t) => t.localUuid.equals('dup-old') & t.deletedAt.isNotNull());
      expect(await deletedStmt.get(), hasLength(1));
      expect(await reportCashTotal(db), 150);
    });

    test('التبنّي لا يختطف مرآة مرتبطة بالهوية بمصروف آخر قائم حتى مع '
        'تطابق الموظف واليوم والمبلغ', () async {
      final e1 = await createExpense(db, empId, 100, localUuid: 'own-1');
      final e2 = await createExpense(db, empId, 100, localUuid: 'own-2');
      // مرآة المصروف الأول — مرتبطة بهويته.
      await withdrawalsRepo.saveFromExpense(
        expenseId: e1,
        employeeId: empId,
        action: 'سحب راتب',
        amount: 100,
        date: day,
        hotelDayKey: day,
      );

      // المصروف الثاني بلا مرآة — تعديل/حفظ يجب ألا يختطف مرآة الأول.
      await withdrawalsRepo.saveFromExpense(
        expenseId: e2,
        employeeId: empId,
        action: 'سحب راتب',
        amount: 100,
        date: day,
        hotelDayKey: day,
      );

      final activeStmt = db.select(db.salaryWithdrawals)
        ..where((t) => t.deletedAt.isNull());
      final active = await activeStmt.get();
      expect(active, hasLength(2), reason: 'عمليتان مستقلتان');
      expect(active.map((w) => w.expenseUuid).toSet(), {'own-1', 'own-2'});
      expect(await reportCashTotal(db), 200);
    });

    test(
      'إعادة تعيين الموظف: الهوية تحسم — نفس المرآة تُحدَّث ولا تُنشأ ثانية',
      () async {
        // موظف ثانٍ.
        final emp2 = await db
            .into(db.employees)
            .insert(
              const EmployeesCompanion(
                name: d.Value('موظف ثانٍ'),
                basicSalary: d.Value(1000),
                status: d.Value('active'),
                hireDate: d.Value('2026-01-01'),
                localUuid: d.Value('emp-2-identity'),
                createdAt: d.Value(1000),
                updatedAt: d.Value(1000),
                lastModified: d.Value(1000),
              ),
            );

        final expId = await createExpense(db, empId, 100, localUuid: 're-1');
        await withdrawalsRepo.saveFromExpense(
          expenseId: expId,
          employeeId: empId,
          action: 'سحب راتب',
          amount: 100,
          date: day,
          hotelDayKey: day,
        );
        final beforeStmt = db.select(db.salaryWithdrawals)
          ..where((t) => t.expenseUuid.equals('re-1'));
        final before = await beforeStmt.getSingle();

        // إعادة تعيين المصروف للموظف الثاني مع تعديل المبلغ.
        await expensesRepo.update(
          expId,
          amount: 120,
          relatedId: emp2,
          employeeUuid: 'emp-2-identity',
        );
        await withdrawalsRepo.saveFromExpense(
          expenseId: expId,
          employeeId: emp2,
          action: 'سحب راتب',
          amount: 120,
          date: day,
          hotelDayKey: day,
          previousAmount: 100,
          previousEmployeeId: empId,
        );

        final activeStmt = db.select(db.salaryWithdrawals)
          ..where((t) => t.deletedAt.isNull());
        final active = await activeStmt.get();
        expect(active, hasLength(1), reason: 'لا مرآة ثانية عند الإعادة');
        expect(active.first.localUuid, before.localUuid);
        expect(active.first.amount, 120);
        expect(active.first.employeeId, emp2);
        expect(active.first.employeeUuid, 'emp-2-identity');
      },
    );

    test(
      'ختم عكسي فاسد نحو مرآة مصروف آخر: لا اختطاف في التعديل ولا في الحذف',
      () async {
        final expB = await createExpense(db, empId, 100, localUuid: 'hb-b');
        // مرآة المصروف B — شرعية ومرتبطة بهويته.
        await withdrawalsRepo.saveFromExpense(
          expenseId: expB,
          employeeId: empId,
          action: 'سحب راتب',
          amount: 100,
          date: day,
          hotelDayKey: day,
        );
        final mbStmt = db.select(db.salaryWithdrawals)
          ..where((t) => t.expenseUuid.equals('hb-b'));
        final mb = await mbStmt.getSingle();

        // المصروف A مختوم فاسداً بمرآة B.
        final expA = await createExpense(
          db,
          empId,
          200,
          localUuid: 'hb-a',
          withdrawalUuid: mb.localUuid,
        );

        // تعديل A — يجب ألا يختطف مرآة B.
        await expensesRepo.update(expA, amount: 250);
        await withdrawalsRepo.saveFromExpense(
          expenseId: expA,
          employeeId: empId,
          action: 'سحب راتب',
          amount: 250,
          date: day,
          hotelDayKey: day,
          previousAmount: 200,
          previousEmployeeId: empId,
        );

        final activeStmt = db.select(db.salaryWithdrawals)
          ..where((t) => t.deletedAt.isNull());
        final active = await activeStmt.get();
        expect(active, hasLength(2));
        final mbAfter = await mbStmt.getSingle();
        expect(mbAfter.localUuid, mb.localUuid);
        expect(mbAfter.amount, 100, reason: 'مرآة B لم تُمَسّ');
        final maStmt = db.select(db.salaryWithdrawals)
          ..where((t) => t.expenseUuid.equals('hb-a'));
        final ma = await maStmt.getSingle();
        expect(ma.amount, 250);

        // الختم على A أُصلح ليشير لمرآته الفعلية.
        final expARowStmt = db.select(db.expenses)
          ..where((t) => t.id.equals(expA));
        final expARow = await expARowStmt.getSingle();
        expect(expARow.withdrawalUuid, ma.localUuid);

        // حذف A — مرآة B تبقى حية.
        await expensesRepo.delete(expA);
        await withdrawalsRepo.deleteByExpenseId(
          expA,
          employeeId: empId,
          employeeUuid: 'emp-uuid-identity',
        );
        final survivorsStmt = db.select(db.salaryWithdrawals)
          ..where((t) => t.deletedAt.isNull());
        final survivors = await survivorsStmt.get();
        expect(survivors, hasLength(1));
        expect(survivors.first.localUuid, mb.localUuid);
      },
    );

    test(
      'سحبان مباشران متطابقان (نفس الموظف/اليوم/المبلغ) = عمليتان',
      () async {
        await withdrawalsRepo.createFromExpense(
          expenseId: 0,
          employeeId: empId,
          reason: 'direct_withdrawal_emp-uuid-identity',
          amount: 100,
          date: day,
          hotelDayKey: day,
          withdrawalType: 'سحب راتب',
        );
        await withdrawalsRepo.createFromExpense(
          expenseId: 0,
          employeeId: empId,
          reason: 'direct_withdrawal_emp-uuid-identity',
          amount: 100,
          date: day,
          hotelDayKey: day,
          withdrawalType: 'سحب راتب',
        );

        final activeStmt = db.select(db.salaryWithdrawals)
          ..where((t) => t.deletedAt.isNull());
        final active = await activeStmt.get();
        expect(active, hasLength(2), reason: 'الإضافة الجديدة مستقلة دائماً');
        expect(active.map((w) => w.localUuid).toSet(), hasLength(2));
        // السحوبات المباشرة نقد خرج فعلاً — تُحتسب كلها.
        expect(await reportCashTotal(db), 200);
      },
    );

    test('توافق خلفي: مرآة تراثية بلا هوية تُحسم بالمستوى 3 '
        '(موظف + مبلغ + يوم)', () async {
      final expId = await createExpense(db, empId, 100, localUuid: 'leg-1');
      // مرآة تراثية: بلا expenseUuid وبرابط رقمي أجنبي.
      await createMirrorRaw(
        100,
        localUuid: 'legacy-m',
        expenseId: 99999,
        reason: 'exp_99999',
      );

      final expenseStmt = db.select(db.expenses)
        ..where((t) => t.id.equals(expId));
      final expense = await expenseStmt.getSingle();

      final isMirror = SalaryMirrorMatcher.isMirrorOfReadExpense(
        expenseId: 99999,
        reason: 'exp_99999',
        amount: 100,
        hotelDayKey: day,
        withdrawDate: day,
        employeeId: empId,
        expenses: candidatesOf([expense]),
      );
      expect(isMirror, isTrue, reason: 'المستوى 3 يبقى شبكة الأمان');
      // التقرير: المصروف مرة واحدة والمرآة التراثية مخفية.
      expect(await reportCashTotal(db), 100);
    });
  });

  group('إصلاح الأختام العكسية — _relinkExpenseWithdrawalUuids', () {
    // ⚠️ AppwriteSyncManager singleton على مستوى العملية — قاعدة بيانات
    // واحدة مشتركة لكل اختبارات هذه المجموعة، مع تنظيف الجداول بين
    // كل اختبار وآخر.
    late AppDatabase db;
    late AppwriteSyncManager manager;
    late int empId;

    setUpAll(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      manager = AppwriteSyncManager(
        appwriteService: AppwriteService(),
        database: db,
      );
      empId = await createEmployee(db);
    });

    tearDownAll(() async {
      await db.close();
    });

    setUp(() async {
      await db.customStatement('DELETE FROM salary_withdrawals');
      await db.customStatement('DELETE FROM expenses');
      await db.customStatement('DELETE FROM outbox');
    });

    Future<int> rawMirror(
      String localUuid,
      String expenseUuid, {
      bool deleted = false,
    }) {
      return db
          .into(db.salaryWithdrawals)
          .insert(
            SalaryWithdrawalsCompanion(
              employeeId: d.Value(empId),
              amount: const d.Value(100),
              withdrawDate: d.Value(day),
              withdrawalType: const d.Value('سحب راتب'),
              reason: const d.Value('exp_1'),
              expenseUuid: d.Value(expenseUuid),
              hotelDayKey: d.Value(day),
              localUuid: d.Value(localUuid),
              deletedAt: deleted ? const d.Value(5000) : const d.Value(null),
              createdAt: const d.Value(1000),
              updatedAt: const d.Value(1000),
              lastModified: const d.Value(1000),
            ),
          );
    }

    Future<Expense> expenseByUuid(String uuid) async {
      final stmt = db.select(db.expenses)
        ..where((t) => t.localUuid.equals(uuid));
      return stmt.getSingle();
    }

    test('الختم الذاتي الفاسد يُرمَّم إلى هوية المرآة الفعلية', () async {
      await createExpense(
        db,
        empId,
        100,
        localUuid: 'rl-1',
        withdrawalUuid: 'rl-1', // فاسد: ذاتي
      );
      await rawMirror('sw-rl-1', 'rl-1');

      final fixed = await manager.relinkExpenseWithdrawalUuidsForTesting();
      expect(fixed, 1);
      final expense = await expenseByUuid('rl-1');
      expect(expense.withdrawalUuid, 'sw-rl-1');

      // ✅ المزامنة تنقل الإصلاح كتحديث للعملية نفسها (وليس إضافة جديدة).
      final outboxStmt = db.select(db.outbox)
        ..where(
          (t) =>
              t.entity.equals('expenses') &
              t.localUuid.equals('rl-1') &
              t.op.equals('update'),
        );
      expect(await outboxStmt.get(), hasLength(1));
    });

    test('الختم المفقود يُعبَّأ من هوية المرآة', () async {
      await createExpense(db, empId, 100, localUuid: 'rl-2');
      await rawMirror('sw-rl-2', 'rl-2');

      final fixed = await manager.relinkExpenseWithdrawalUuidsForTesting();
      expect(fixed, 1);
      final expense = await expenseByUuid('rl-2');
      expect(expense.withdrawalUuid, 'sw-rl-2');
    });

    test('الختم الصحيح لا يُمَسّ ولا يُجدول دفع', () async {
      await createExpense(
        db,
        empId,
        100,
        localUuid: 'rl-3',
        withdrawalUuid: 'sw-rl-3',
      );
      await rawMirror('sw-rl-3', 'rl-3');

      final fixed = await manager.relinkExpenseWithdrawalUuidsForTesting();
      expect(fixed, 0);
      final expense = await expenseByUuid('rl-3');
      expect(expense.withdrawalUuid, 'sw-rl-3');
      final outboxStmt = db.select(db.outbox)
        ..where((t) => t.localUuid.equals('rl-3'));
      expect(await outboxStmt.get(), isEmpty);
    });

    test('مصروف بلا مرآة لا يُمَسّ مهما كان ختمه', () async {
      await createExpense(db, empId, 100, localUuid: 'rl-4');
      final fixed = await manager.relinkExpenseWithdrawalUuidsForTesting();
      expect(fixed, 0);
      final expense = await expenseByUuid('rl-4');
      expect(expense.withdrawalUuid, isNull);
    });

    test('ختم يشير لمرآة محذوفة يُرمَّم نحو المرآة النشطة', () async {
      await createExpense(
        db,
        empId,
        100,
        localUuid: 'rl-5',
        withdrawalUuid: 'sw-dead',
      );
      await rawMirror('sw-dead', 'rl-5', deleted: true);
      await rawMirror('sw-live', 'rl-5');

      final fixed = await manager.relinkExpenseWithdrawalUuidsForTesting();
      expect(fixed, 1);
      final expense = await expenseByUuid('rl-5');
      expect(expense.withdrawalUuid, 'sw-live');
    });
  });
}
