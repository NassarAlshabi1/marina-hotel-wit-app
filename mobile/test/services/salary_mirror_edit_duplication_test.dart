// ignore_for_file: lines_longer_than_80_chars
import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/repositories/expenses_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/salary_withdrawals_repository.dart';
import 'package:marina_hotel_mobile/services/salary_expense_classifier.dart';
import 'package:marina_hotel_mobile/services/salary_mirror_matcher.dart';

/// ✅ اختبارات إصلاح تكرار التقرير عند تعديل مبلغ مصروف/مصروف راتب
/// (شكوى 2026-09-25: «عند تعديل مبلغ مصروفات أو مصروفات الرواتب يتكرر
/// عند عرض التقرير»).
///
/// السبب الجذري المُشخَّص:
/// - رابط مرآة الراتب (salary_withdrawals.expense_id / reason=exp_N)
///   يحمل معرّف autoincrement **محلياً لجهاز الإنشاء** — غير محمول عبر
///   الأجهزة (يُرفع ويُكتب كما هو من Appwrite).
/// - عند تعديل المبلغ من جهاز آخر (أو بعد مزامنة): البحث في
///   saveFromExpense لا يجد المرآة → يُنشئ مرآة جديدة وتبقى القديمة
///   نشطة بالمبلغ القديم.
/// - فلتر التقارير (SalaryMirrorMatcher) كان يخفي التكرار عبر المستوى 3
///   (موظف + نقدي + **مبلغ** + يوم) — تعديل المبلغ يكسره → المرآة
///   القديمة تُعَد «سحبة يتيمة» → المبلغ يظهر مرتين.
///
/// الإصلاح المُختبر هنا (طبقتان):
/// 1. الكتابة: saveFromExpense يتبنّى المرآة اليتيمة (الطريقة 3) عبر
///    (الموظف + المبلغ القديم الموقّع + اليوم) — المعامل الجديد
///    previousAmount — بدل إنشاء مرآة ثانية.
/// 2. القراءة: SalaryMirrorMatcher المستوى 4 — مرآة تحمل علامة رابط
///    أجنبياً + مصروف وحيد لنفس الموظف/اليوم من نفس العائلة → مرآة
///    بغض النظر عن المبلغ (شبكة أمان للبيانات المزدوجة القائمة).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const day = '2026-09-25';

  /// إنشاء موظف واحد — كل السيناريوهات على نفس الموظف.
  Future<int> createEmployee(AppDatabase db) {
    return db
        .into(db.employees)
        .insert(
          const EmployeesCompanion(
            name: d.Value('موظف التحرير'),
            basicSalary: d.Value(1000),
            status: d.Value('active'),
            hireDate: d.Value('2026-01-01'),
            localUuid: d.Value('emp-uuid-edit'),
            createdAt: d.Value(1000),
            updatedAt: d.Value(1000),
            lastModified: d.Value(1000),
          ),
        );
  }

  /// مصروف راتب «مُسحوب من جهاز آخر»: معرف محلي جديد، serverId فارغ.
  Future<int> createPulledSalaryExpense(
    AppDatabase db,
    int employeeId,
    double amount, {
    String type = 'سحب راتب',
    String date = day,
    String uuidSuffix = '',
    String? localUuid,
  }) {
    return db
        .into(db.expenses)
        .insert(
          ExpensesCompanion(
            expenseType: d.Value(type),
            relatedId: d.Value(employeeId),
            employeeUuid: const d.Value('emp-uuid-edit'),
            amount: d.Value(amount),
            date: d.Value(date),
            hotelDayKey: d.Value(date),
            description: const d.Value('راتب شهر ٩'),
            localUuid: d.Value(
              localUuid ?? 'exp-pulled-$type-$amount-$date$uuidSuffix',
            ),
            createdAt: const d.Value(1000),
            updatedAt: const d.Value(1000),
            lastModified: const d.Value(1000),
          ),
        );
  }

  /// مرآة راتب من جهاز المصدر: رابطها يحمل معرّف جهاز المصدر (أجنبي).
  Future<int> createForeignMirrorWithdrawal(
    AppDatabase db,
    int employeeId,
    double amount, {
    int foreignExpenseId = 962,
    String date = day,
    String withdrawalType = 'سحب راتب',
    String? expenseUuid,
    String? localUuid,
  }) {
    return db
        .into(db.salaryWithdrawals)
        .insert(
          SalaryWithdrawalsCompanion(
            employeeId: d.Value(employeeId),
            amount: d.Value(amount),
            withdrawDate: d.Value(date),
            withdrawalType: d.Value(withdrawalType),
            reason: d.Value('exp_$foreignExpenseId'),
            expenseId: d.Value(foreignExpenseId),
            hotelDayKey: d.Value(date),
            localUuid: d.Value(
              localUuid ?? 'sw-foreign-$foreignExpenseId-$amount-$date',
            ),
            if (expenseUuid != null) expenseUuid: d.Value(expenseUuid),
            createdAt: const d.Value(1000),
            updatedAt: const d.Value(1000),
            lastModified: d.Value(1000),
          ),
        );
  }

  /// مرشحو المطابقة كما تبنيهم التقارير من المصروفات المقروءة.
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
          ),
        )
        .toList(growable: false);
  }

  /// منطق تجميع التقرير النقدي (نفس قواعد expenses_report_screen):
  /// المصروفات غير الخصمية + السحوبات اليتيمة الموجبة غير الخصمية.
  Future<double> reportCashTotal(AppDatabase db, int employeeId) async {
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

  group('المستوى 4 (قراءة): مرآة برابط أجنبي بعد تعديل المبلغ', () {
    test('المرآة القديمة (المبلغ القديم) لا تُعَد يتيمة بعد تعديل المصروف', () {
      // المصروف بعد التعديل: 150 (كان 100) — والمرآة القديمة 100 برابط أجنبي.
      const candidate = MirrorExpenseCandidate(
        id: 7,
        serverId: null,
        expenseType: 'سحب راتب',
        amount: 150,
        date: day,
        hotelDayKey: day,
        relatedId: 9,
      );
      final isMirror = SalaryMirrorMatcher.isMirrorOfReadExpense(
        expenseId: 962,
        reason: 'exp_962',
        amount: 100,
        hotelDayKey: day,
        withdrawDate: day,
        employeeId: 9,
        expenses: [candidate],
      );
      expect(
        isMirror,
        isTrue,
        reason: 'رابط أجنبي + مصروف نقدي وحيد لنفس اليوم',
      );
    });

    test('مصروفان نقديان لنفس الموظف/اليوم → غموض → ليست مرآة', () {
      const c1 = MirrorExpenseCandidate(
        id: 7,
        serverId: null,
        expenseType: 'سحب راتب',
        amount: 150,
        date: day,
        hotelDayKey: day,
        relatedId: 9,
      );
      const c2 = MirrorExpenseCandidate(
        id: 8,
        serverId: null,
        expenseType: 'سحب راتب',
        amount: 250,
        date: day,
        hotelDayKey: day,
        relatedId: 9,
      );
      final isMirror = SalaryMirrorMatcher.isMirrorOfReadExpense(
        expenseId: 962,
        reason: 'exp_962',
        amount: 100,
        hotelDayKey: day,
        withdrawDate: day,
        employeeId: 9,
        expenses: [c1, c2],
      );
      expect(isMirror, isFalse, reason: 'لا نخمّن أي مصروف عند وجود اثنين');
    });

    test('سحبة مباشرة (direct_withdrawal_) محمية رغم التفرد', () {
      const candidate = MirrorExpenseCandidate(
        id: 7,
        serverId: null,
        expenseType: 'سحب راتب',
        amount: 150,
        date: day,
        hotelDayKey: day,
        relatedId: 9,
      );
      final isMirror = SalaryMirrorMatcher.isMirrorOfReadExpense(
        expenseId: null,
        reason: 'direct_withdrawal_emp-uuid-9',
        amount: 100,
        hotelDayKey: day,
        withdrawDate: day,
        employeeId: 9,
        expenses: [candidate],
      );
      expect(isMirror, isFalse, reason: 'الحارس يسبق كل المستويات');
    });

    test('مرآة خصم سالبة برابط أجنبي + مصروف خصم وحيد → مرآة', () {
      const candidate = MirrorExpenseCandidate(
        id: 7,
        serverId: null,
        expenseType: 'خصم من الراتب',
        amount: 150,
        date: day,
        hotelDayKey: day,
        relatedId: 9,
      );
      final isMirror = SalaryMirrorMatcher.isMirrorOfReadExpense(
        expenseId: 962,
        reason: 'exp_962',
        amount: -100,
        hotelDayKey: day,
        withdrawDate: day,
        employeeId: 9,
        expenses: [candidate],
      );
      expect(isMirror, isTrue, reason: 'عائلة الخصوم للمرايا السالبة');
    });

    test('مرآة بلا علامة رابط (نص حر) تظل خاضعة للمستوى 3 وحده', () {
      const candidate = MirrorExpenseCandidate(
        id: 7,
        serverId: null,
        expenseType: 'سحب راتب',
        amount: 150,
        date: day,
        hotelDayKey: day,
        relatedId: 9,
      );
      final isMirror = SalaryMirrorMatcher.isMirrorOfReadExpense(
        expenseId: null,
        reason: 'سحبة يدوية قديمة',
        amount: 100,
        hotelDayKey: day,
        withdrawDate: day,
        employeeId: 9,
        expenses: [candidate],
      );
      expect(isMirror, isFalse, reason: 'بلا علامة مرآة لا يُفعَّل المستوى 4');
    });
  });

  group('التبنّي (كتابة): saveFromExpense يتبنّى المرآة اليتيمة', () {
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
      'تعديل المبلغ 100→150 على جهاز ثانٍ: مرآة واحدة فقط بمبلغ 150 ورباط صحيح',
      () async {
        final empId = await createEmployee(db);

        // المصروف كما وصل من جهاز المصدر (id محلي جديد على هذا الجهاز).
        final expenseId = await createPulledSalaryExpense(db, empId, 100);
        // المرآة القديمة برابط جهاز المصدر (أجنبي عن هذا الجهاز).
        await createForeignMirrorWithdrawal(db, empId, 100);

        // تعديل المبلغ على هذا الجهاز — كما تفعل شاشة expenses_list.
        await expensesRepo.update(expenseId, amount: 150);
        await withdrawalsRepo.saveFromExpense(
          expenseId: expenseId,
          employeeId: empId,
          action: 'سحب راتب',
          amount: 150,
          date: day,
          hotelDayKey: day,
          previousAmount: 100,
        );

        final activeStmt = db.select(db.salaryWithdrawals)
          ..where((t) => t.deletedAt.isNull());
        final active = await activeStmt.get();
        expect(active, hasLength(1), reason: 'التبنّي بدل الإنشاء المكرر');
        expect(active.first.amount, 150, reason: 'مبلغ المرآة = المبلغ الجديد');
        expect(active.first.expenseId, expenseId, reason: 'الرابط أصبح محلياً');
        expect(active.first.reason, 'exp_$expenseId');

        // التقرير النقدي: 150 مرة واحدة فقط (لا 150+100).
        expect(await reportCashTotal(db, empId), 150);
      },
    );

    test(
      'تعديل خصم 100→150 (مرآة سالبة): التبنّي يعمل بعائلة الخصوم',
      () async {
        final empId = await createEmployee(db);
        final expenseId = await createPulledSalaryExpense(
          db,
          empId,
          100,
          type: 'خصم من الراتب',
        );
        await createForeignMirrorWithdrawal(
          db,
          empId,
          -100,
          withdrawalType: 'خصم من الراتب',
        );

        await expensesRepo.update(expenseId, amount: 150);
        await withdrawalsRepo.saveFromExpense(
          expenseId: expenseId,
          employeeId: empId,
          action: 'خصم من الراتب',
          amount: -150,
          date: day,
          hotelDayKey: day,
          previousAmount: -100,
        );

        final activeStmt = db.select(db.salaryWithdrawals)
          ..where((t) => t.deletedAt.isNull());
        final active = await activeStmt.get();
        expect(active, hasLength(1));
        expect(active.first.amount, -150);
        expect(active.first.expenseId, expenseId);
      },
    );

    test('لا مرآة سابقة (إنشاء جديد): يُنشئ مرآة واحدة — توافق خلفي', () async {
      final empId = await createEmployee(db);
      final expenseId = await createPulledSalaryExpense(db, empId, 300);

      await withdrawalsRepo.saveFromExpense(
        expenseId: expenseId,
        employeeId: empId,
        action: 'سحب راتب',
        amount: 300,
        date: day,
        hotelDayKey: day,
      );

      final activeStmt = db.select(db.salaryWithdrawals)
        ..where((t) => t.deletedAt.isNull());
      final active = await activeStmt.get();
      expect(active, hasLength(1));
      expect(active.first.amount, 300);
      expect(active.first.expenseId, expenseId);
      expect(await reportCashTotal(db, empId), 300);
    });

    test('التبنّي لا يختطف مرآة مصروف محلي آخر قائم', () async {
      final empId = await createEmployee(db);

      // مصروفان: الحالي (id=1) ومصروف آخر قائم (id=2) من نفس الموظف/اليوم.
      final currentExpenseId = await createPulledSalaryExpense(
        db,
        empId,
        100,
        uuidSuffix: '-current',
      );
      final otherExpenseId = await createPulledSalaryExpense(
        db,
        empId,
        100,
        uuidSuffix: '-other',
      );

      // مرآة مرتبطة (برابطها المحلي الصحيح) بالمصروف الآخر id=2.
      await db
          .into(db.salaryWithdrawals)
          .insert(
            SalaryWithdrawalsCompanion(
              employeeId: d.Value(empId),
              amount: const d.Value(100),
              withdrawDate: const d.Value(day),
              withdrawalType: const d.Value('سحب راتب'),
              reason: d.Value('exp_$otherExpenseId'),
              expenseId: d.Value(otherExpenseId),
              hotelDayKey: const d.Value(day),
              localUuid: const d.Value('sw-owned-by-other'),
              createdAt: const d.Value(1000),
              updatedAt: const d.Value(1000),
              lastModified: const d.Value(1000),
            ),
          );

      await expensesRepo.update(currentExpenseId, amount: 150);
      await withdrawalsRepo.saveFromExpense(
        expenseId: currentExpenseId,
        employeeId: empId,
        action: 'سحب راتب',
        amount: 150,
        date: day,
        hotelDayKey: day,
        previousAmount: 100,
      );

      // مرآة المصروف الآخر بقيت كما هي (لم تُختطف).
      final owned = await (db.select(
        db.salaryWithdrawals,
      )..where((t) => t.localUuid.equals('sw-owned-by-other'))).getSingle();
      expect(owned.expenseId, otherExpenseId, reason: 'لم تُتبنّى مرآة الآخر');
      expect(owned.amount, 100);

      // ومرآة جديدة أُنشئت للمصروف الحالي.
      final activeStmt = db.select(db.salaryWithdrawals)
        ..where((t) => t.deletedAt.isNull());
      final active = await activeStmt.get();
      expect(active, hasLength(2));
    });

    test('سيناريو المستخدم كاملاً: تعديل مبلغ راتب على الجهاز الثاني '
        '→ التقرير لا يكرر', () async {
      final empId = await createEmployee(db);

      // المصروف الأصلي 100 وصل للمزامنة + مرآته القديمة 100 (رابط أجنبي).
      final expenseId = await createPulledSalaryExpense(db, empId, 100);
      await createForeignMirrorWithdrawal(db, empId, 100);

      // التقرير قبل التعديل: 100 مرة واحدة (المستوى 3 يطابق المبلغ).
      expect(await reportCashTotal(db, empId), 100);

      // تعديل المبلغ إلى 150 (كما في شاشة المصروفات).
      await expensesRepo.update(expenseId, amount: 150);
      await withdrawalsRepo.saveFromExpense(
        expenseId: expenseId,
        employeeId: empId,
        action: 'سحب راتب',
        amount: 150,
        date: day,
        hotelDayKey: day,
        previousAmount: 100,
      );

      // التقرير بعد التعديل: 150 مرة واحدة فقط.
      // (قبل الإصلاح: 150 من المصروف + 100 من المرآة اليتيمة = 250).
      expect(await reportCashTotal(db, empId), 150);
    });

    test(
      'شبكة الأمان للقراءة: حتى بلا تبنّي (تحديث مباشر للDB) لا يتكرر',
      () async {
        final empId = await createEmployee(db);
        final expenseId = await createPulledSalaryExpense(db, empId, 100);
        await createForeignMirrorWithdrawal(db, empId, 100);

        // تعديل مباشر في قاعدة البيانات بلا تمرير saveFromExpense
        // (يحاكي تحديثاً وصل من المزامنة فقط بلا إعادة ربط).
        await (db.update(db.expenses)..where((t) => t.id.equals(expenseId)))
            .write(const ExpensesCompanion(amount: d.Value(150)));

        // المستوى 4 يخفي المرآة القديمة → 150 مرة واحدة.
        expect(await reportCashTotal(db, empId), 150);
      },
    );
  });

  group('ختم الرابط العكسي migration 68 (مراجعة kilo PR#610)', () {
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

    Future<Expense> expenseById(int id) =>
        (db.select(db.expenses)..where((e) => e.id.equals(id))).getSingle();

    Future<SalaryWithdrawal> mirrorByLocalUuid(String uuid) =>
        (db.select(
          db.salaryWithdrawals,
        )..where((t) => t.localUuid.equals(uuid))).getSingle();

    Future<List<OutboxData>> expensesOutboxEntries() {
      return (db.select(
        db.outbox,
      )..where((t) => t.entity.equals('expenses'))).get();
    }

    test(
      'مسار الإنشاء: المصروف يختم بـ uuid السحبة الجديدة (لا رابط ذاتي) + outbox',
      () async {
        final empId = await createEmployee(db);
        final expenseId = await createPulledSalaryExpense(
          db,
          empId,
          300,
          localUuid: 'exp-create-stamp',
        );

        await withdrawalsRepo.saveFromExpense(
          expenseId: expenseId,
          employeeId: empId,
          action: 'سحب راتب',
          amount: 300,
          date: day,
          hotelDayKey: day,
        );

        final mirror = await (db.select(
          db.salaryWithdrawals,
        )..where((t) => t.deletedAt.isNull())).getSingle();
        final exp = await expenseById(expenseId);

        // الختم العكسي = uuid السحبة — وليس uuid المصروف ذاته (رابط ذاتي).
        expect(
          exp.withdrawalUuid,
          mirror.localUuid,
          reason: 'المصروف يشير إلى مرآته بالهوية الدائمة',
        );
        expect(
          exp.withdrawalUuid,
          isNot('exp-create-stamp'),
          reason: 'رابط ذاتي مرجعي = عطل kilo السابق',
        );
        expect(mirror.expenseUuid, 'exp-create-stamp');

        // الختم ينتشر للسحابة: عنصر outbox للمصروف exists.
        final entries = await expensesOutboxEntries();
        expect(
          entries.where((e) => e.localUuid == 'exp-create-stamp'),
          isNotEmpty,
          reason: 'بلا outbox لا يصل الختم للسحابة أبداً',
        );
      },
    );

    test(
      'مسار التحديث (تبنّي أجنبي): المصروف يختم بـ uuid المرآة المتبنّاة + outbox',
      () async {
        final empId = await createEmployee(db);
        final expenseId = await createPulledSalaryExpense(
          db,
          empId,
          100,
          localUuid: 'exp-update-stamp',
        );
        await createForeignMirrorWithdrawal(
          db,
          empId,
          100,
          localUuid: 'sw-stamp-target',
        );

        await expensesRepo.update(expenseId, amount: 150);
        await withdrawalsRepo.saveFromExpense(
          expenseId: expenseId,
          employeeId: empId,
          action: 'سحب راتب',
          amount: 150,
          date: day,
          hotelDayKey: day,
          previousAmount: 100,
        );

        final mirror = await mirrorByLocalUuid('sw-stamp-target');
        final exp = await expenseById(expenseId);
        expect(mirror.amount, 150, reason: 'التبنّي يحدث المرآة في مكانها');
        expect(
          exp.withdrawalUuid,
          'sw-stamp-target',
          reason: 'uuid السحبة المتبنّاة — لا رابط ذاتي',
        );
        final entries = await expensesOutboxEntries();
        expect(
          entries.where((e) => e.localUuid == 'exp-update-stamp'),
          isNotEmpty,
        );
      },
    );

    test(
      'عقد المستخدم 100+100+200: الهوية تحسم المتساويات — لا تقاطع هويات',
      () async {
        final empId = await createEmployee(db);

        // ثلاث عمليات: سحبتان متساوتان (100+100) وثالثة (200) — نفس اليوم.
        final exp1 = await createPulledSalaryExpense(
          db,
          empId,
          100,
          localUuid: 'exp-eq-1',
        );
        final exp2 = await createPulledSalaryExpense(
          db,
          empId,
          100,
          localUuid: 'exp-eq-2',
        );
        final exp3 = await createPulledSalaryExpense(
          db,
          empId,
          200,
          localUuid: 'exp-eq-3',
        );

        // المرايا بروابط أجنبية + هوية expense_uuid صحيحة لكل منها.
        // mirror2 تُدرج أولاً — الترتيب القديم (أول مرشح) كان سيختارها
        // اعتباطياً فيتقاطع الهويّتان.
        await createForeignMirrorWithdrawal(
          db,
          empId,
          100,
          foreignExpenseId: 962,
          expenseUuid: 'exp-eq-2',
          localUuid: 'sw-eq-2',
        );
        await createForeignMirrorWithdrawal(
          db,
          empId,
          100,
          foreignExpenseId: 961,
          expenseUuid: 'exp-eq-1',
          localUuid: 'sw-eq-1',
        );
        await createForeignMirrorWithdrawal(
          db,
          empId,
          200,
          foreignExpenseId: 963,
          expenseUuid: 'exp-eq-3',
          localUuid: 'sw-eq-3',
        );

        // تعديل السحبة الأولى 100 → 150 (مثال المستخدم حرفياً).
        await expensesRepo.update(exp1, amount: 150);
        await withdrawalsRepo.saveFromExpense(
          expenseId: exp1,
          employeeId: empId,
          action: 'سحب راتب',
          amount: 150,
          date: day,
          hotelDayKey: day,
          previousAmount: 100,
        );

        // ثلاث عمليات فقط — كل برابطها الصحيح.
        final active =
            await (db.select(
              db.salaryWithdrawals,
            )..where((t) => t.deletedAt.isNull())).get();
        expect(active, hasLength(3), reason: 'التعديل ليس مصروفاً جديداً');

        final m1 = await mirrorByLocalUuid('sw-eq-1');
        final m2 = await mirrorByLocalUuid('sw-eq-2');
        final m3 = await mirrorByLocalUuid('sw-eq-3');

        // الهوية أولوية: كل مرآة لصاحبتها — حتى تساوي المبالغ.
        expect(m1.amount, 150, reason: 'مرآة المصروف الأول تحدّثت في مكانها');
        expect(m1.expenseUuid, 'exp-eq-1');
        expect(m1.expenseId, exp1);
        expect(m2.amount, 100, reason: 'مرآة الثانية لم تُلمس');
        expect(m2.expenseUuid, 'exp-eq-2');
        expect(m2.expenseId, 962);
        expect(m3.amount, 200);
        expect(m3.expenseUuid, 'exp-eq-3');

        // الروابط العكسية سليمة وغير متقاطعة.
        expect((await expenseById(exp1)).withdrawalUuid, 'sw-eq-1');
        expect((await expenseById(exp2)).withdrawalUuid, isNull);
        expect((await expenseById(exp3)).withdrawalUuid, isNull);
        expect(exp2, isNot(exp1));

        // التقرير: 150 + 100 + 200 = 450 — ثلاث عمليات لا أربع.
        expect(await reportCashTotal(db, empId), 450);
      },
    );

    test(
      'حارس غموض التبنّي: مرشحان بلا هوية (توارث قديم) — لا اختطاف ولا تخمين',
      () async {
        final empId = await createEmployee(db);

        final exp1 = await createPulledSalaryExpense(
          db,
          empId,
          100,
          localUuid: 'exp-amb-1',
        );
        // مرآتان قديمتان بلا expense_uuid (ما قبل migration 68) — متساويتان.
        await createForeignMirrorWithdrawal(
          db,
          empId,
          100,
          foreignExpenseId: 961,
          localUuid: 'sw-amb-1',
        );
        await createForeignMirrorWithdrawal(
          db,
          empId,
          100,
          foreignExpenseId: 962,
          localUuid: 'sw-amb-2',
        );

        await expensesRepo.update(exp1, amount: 150);
        await withdrawalsRepo.saveFromExpense(
          expenseId: exp1,
          employeeId: empId,
          action: 'سحب راتب',
          amount: 150,
          date: day,
          hotelDayKey: day,
          previousAmount: 100,
        );

        // المرآتان القديمتان بلا هوية لم تُختطف أي منهما.
        final legacy1 = await mirrorByLocalUuid('sw-amb-1');
        final legacy2 = await mirrorByLocalUuid('sw-amb-2');
        expect(legacy1.expenseId, 961);
        expect(legacy1.amount, 100);
        expect(legacy2.expenseId, 962);
        expect(legacy2.amount, 100);

        // والتعديل أنشأ مرآة جديدة خاصة بالمصروف المعدّل.
        final active =
            await (db.select(
              db.salaryWithdrawals,
            )..where((t) => t.deletedAt.isNull())).get();
        expect(active, hasLength(3));
        final created = active.where((w) => w.amount == 150).single;
        expect(created.expenseId, exp1);
        expect(created.expenseUuid, 'exp-amb-1');
        expect((await expenseById(exp1)).withdrawalUuid, created.localUuid);
      },
    );
  });
}
