// ignore_for_file: lines_longer_than_80_chars
import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/salary_entitlement_service.dart';
import 'package:marina_hotel_mobile/services/salary_mirror_matcher.dart';

/// ✅ اختبارات ثغرة العد المزدوج عبر الأجهزة — حالة «الاورمو محمد» (2026-09-14).
///
/// السيناريو المُثبت من السحابة:
/// - جهاز المصدر ينشئ مصروف «سحب راتب» (id محلي 962) + سحبة مرآة reason=exp_962.
/// - المستند السحابي للمصروف لا يحمل أي معرف رقمي (id/serverId = null).
/// - على الجهاز الثاني يأخذ المصروف id محلياً جديداً → dedup بالمعرفات يفشل
///   → السحبة تُعَد مرة ثانية → استحقاق الموظف ينخفض ضعف مرايا السحوبات
///   وتنكسر المعادلة «مصروفات الرواتب = استحقاقات الموظف».
///
/// الإصلاح: SalaryMirrorMatcher — مستوى 3 (مطابقة موظف + نقدي + مبلغ + يوم)
/// ومستوى 2-ب (exp_N مقابل serverId) وحارس direct_withdrawal_.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late SalaryEntitlementService service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = SalaryEntitlementService(db);
  });

  tearDown(() async {
    await db.close();
  });

  String padded(int n) => n.toString().padLeft(2, '0');

  /// موظف براتب 1000 وتعيين منذ 12 شهراً بالضبط → استحقاق 12000 حتمي.
  Future<int> createEmployee() async {
    final now = DateTime.now();
    final hire = DateTime(now.year - 1, now.month, 1);
    final hireStr = '${hire.year}-${padded(hire.month)}-01';
    return db.into(db.employees).insert(
          EmployeesCompanion(
            name: const d.Value('موظف الجهاز الثاني'),
            basicSalary: const d.Value(1000),
            status: const d.Value('active'),
            hireDate: d.Value(hireStr),
            localUuid: const d.Value('emp-uuid-cross'),
            createdAt: const d.Value(1000),
            updatedAt: const d.Value(1000),
            lastModified: const d.Value(1000),
          ),
        );
  }

  /// مصروف مرآة مُسحوب من السحابة إلى جهاز ثانٍ:
  /// id محلي جديد (autoincrement) — بلا serverId — employeeUuid موجود.
  Future<int> createPulledMirrorExpense({
    required int employeeId,
    required double amount,
    required String date,
    String type = 'سحب راتب',
  }) {
    return db.into(db.expenses).insert(
          ExpensesCompanion(
            expenseType: d.Value(type),
            relatedId: d.Value(employeeId),
            employeeUuid: const d.Value('emp-uuid-cross'),
            amount: d.Value(amount),
            date: d.Value(date),
            hotelDayKey: d.Value(date),
            description: const d.Value('شهر ٨'),
            localUuid: d.Value('exp-pulled-uuid-$amount-$date'),
            createdAt: const d.Value(1000),
            updatedAt: const d.Value(1000),
            lastModified: const d.Value(1000),
          ),
        );
  }

  /// سحبة مرآة من جهاز المصدر: reason=exp_<id جهاز المصدر> بلا expense_id.
  Future<int> createMirrorWithdrawal({
    required int employeeId,
    required double amount,
    required String date,
    required String originReason,
  }) {
    return db.into(db.salaryWithdrawals).insert(
          SalaryWithdrawalsCompanion(
            employeeId: d.Value(employeeId),
            amount: d.Value(amount),
            withdrawDate: d.Value(date),
            withdrawalType: const d.Value('سحب راتب'),
            reason: d.Value(originReason),
            hotelDayKey: d.Value(date),
            localUuid: d.Value('sw-mirror-uuid-$amount-$date'),
            createdAt: const d.Value(1000),
            updatedAt: const d.Value(1000),
            lastModified: const d.Value(1000),
          ),
        );
  }

  group('حالة «الاورمو محمد»: سحوبات مرآة عبر الأجهزة', () {
    test('المرآة exp_962 بلا مصروف محلي 962 لا تُعَد مرتين (مطابقة بيانات)', () async {
      final empId = await createEmployee();
      final emp = await (db.select(
        db.employees,
      )..where((e) => e.id.equals(empId))).getSingle();

      // الجهاز الثاني سحب المصروف: id محلي جديد ≠ 962، serverId = null
      await createPulledMirrorExpense(
        employeeId: empId,
        amount: 5000,
        date: '2026-08-02',
      );
      // والسحبة المرآة من جهاز المصدر تشير لمعرف جهاز المصدر:
      await createMirrorWithdrawal(
        employeeId: empId,
        amount: 5000,
        date: '2026-08-02',
        originReason: 'exp_962',
      );

      final ent = await service.calculateEmployeeEntitlement(emp);
      // بدون الإصلاح: السحبة تُعَد مرتين → totalWithdrawals = 10000
      expect(ent.totalWithdrawals, 5000, reason: 'المرآة يجب ألا تُعَد مرتين');
      expect(ent.netEntitlement, 7000, reason: '12000 - 5000 مرة واحدة فقط');
    });

    test('مرايا متعددة بمبالغ مختلفة وأيام مختلفة تُطابَق كلها', () async {
      final empId = await createEmployee();
      final emp = await (db.select(
        db.employees,
      )..where((e) => e.id.equals(empId))).getSingle();

      // ثلاث مرايا حقيقية (مثل بيانات الأورمو محمد الفعلية)
      final pairs = [
        ('25000', '2026-08-24', 'exp_1138'),
        ('25000', '2026-08-25', 'exp_1148'),
        ('15000', '2026-08-31', 'exp_1187'),
      ];
      for (final (amount, date, reason) in pairs) {
        await createPulledMirrorExpense(
          employeeId: empId,
          amount: double.parse(amount),
          date: date,
        );
        await createMirrorWithdrawal(
          employeeId: empId,
          amount: double.parse(amount),
          date: date,
          originReason: reason,
        );
      }

      final ent = await service.calculateEmployeeEntitlement(emp);
      expect(ent.totalWithdrawals, 65000, reason: 'مرة واحدة لكل مرآة');
      expect(ent.netEntitlement, 12000 - 65000);
    });

    test('نفس المبلغ في يومين مختلفين لا يُخلط بينهما', () async {
      final empId = await createEmployee();
      final emp = await (db.select(
        db.employees,
      )..where((e) => e.id.equals(empId))).getSingle();

      // مصروف 25000 يوم 24 فقط — والسحبة يوم 25 (لا مصروف لها)
      await createPulledMirrorExpense(
        employeeId: empId,
        amount: 25000,
        date: '2026-08-24',
      );
      await createMirrorWithdrawal(
        employeeId: empId,
        amount: 25000,
        date: '2026-08-24',
        originReason: 'exp_1138',
      );
      // سحبة حقيقية (يتيمة) 25000 يوم 25 — يجب أن تُعَد
      await createMirrorWithdrawal(
        employeeId: empId,
        amount: 25000,
        date: '2026-08-25',
        originReason: 'exp_1148',
      );

      final ent = await service.calculateEmployeeEntitlement(emp);
      // 25000 (المرآة) + 25000 (اليتيمة) = 50000 — اليتيمة لا تُختلس بالخطأ
      expect(ent.totalWithdrawals, 50000);
      expect(ent.netEntitlement, 12000 - 50000);
    });

    test('حارس direct_withdrawal_: سحبة مباشرة بنفس مبلغ ويوم مصروف قائم تُعَد', () async {
      final empId = await createEmployee();
      final emp = await (db.select(
        db.employees,
      )..where((e) => e.id.equals(empId))).getSingle();

      // مصروف سلفة قديم بنفس مبلغ ويوم سحبة مباشرة لاحقة — لا علاقة بينهما
      await createPulledMirrorExpense(
        employeeId: empId,
        amount: 19000,
        date: '2026-09-13',
        type: 'سلفة',
      );
      await db.into(db.salaryWithdrawals).insert(
            SalaryWithdrawalsCompanion(
              employeeId: d.Value(empId),
              amount: const d.Value(19000),
              withdrawDate: const d.Value('2026-09-13'),
              withdrawalType: const d.Value('سحب راتب'),
              reason: const d.Value('direct_withdrawal_emp-uuid-cross'),
              hotelDayKey: const d.Value('2026-09-13'),
              localUuid: const d.Value('sw-direct-uuid-19000'),
              createdAt: const d.Value(1000),
              updatedAt: const d.Value(1000),
              lastModified: const d.Value(1000),
            ),
          );

      final ent = await service.calculateEmployeeEntitlement(emp);
      // السلفة (19000) ضمن totalAdvances + السحبة المباشرة (19000) ضمن
      // totalWithdrawals — كلٌّ مرة واحدة، ولا يُختلطان
      expect(ent.totalAdvances, 19000);
      expect(ent.totalWithdrawals, 19000);
      expect(ent.netEntitlement, 12000 - 19000 - 19000);
    });
  });

  group('المرحلة 2-ب: exp_N يطابق serverId المصروف', () {
    test('reason=exp_962 يُخدَّد بمصروف serverId=962 بلا id محلي مطابق', () {
      const candidate = MirrorExpenseCandidate(
        id: 51,
        serverId: 962,
        expenseType: 'سحب راتب',
        amount: 5000,
        date: '2026-08-02',
        hotelDayKey: '2026-08-02',
        relatedId: 9,
      );
      final isMirror = SalaryMirrorMatcher.isMirrorOfReadExpense(
        expenseId: null,
        reason: 'exp_962',
        amount: 5000,
        hotelDayKey: '2026-08-02',
        withdrawDate: '2026-08-02',
        employeeId: 9,
        expenses: [candidate],
      );
      expect(isMirror, isTrue);
    });

    test('مطابقة بيانات: موظف مختلف لا يُخدَّد به (حماية من الربط العابر)', () {
      const candidate = MirrorExpenseCandidate(
        id: 51,
        serverId: null,
        expenseType: 'سحب راتب',
        amount: 5000,
        date: '2026-08-02',
        hotelDayKey: '2026-08-02',
        relatedId: 8, // موظف آخر
      );
      final isMirror = SalaryMirrorMatcher.isMirrorOfReadExpense(
        expenseId: null,
        reason: 'exp_777',
        amount: 5000,
        hotelDayKey: '2026-08-02',
        withdrawDate: '2026-08-02',
        employeeId: 9,
        expenses: [candidate],
      );
      expect(isMirror, isFalse);
    });

    test('يوم مختلف = ليس مرآة (نفس المبلغ عبر يومين)', () {
      const candidate = MirrorExpenseCandidate(
        id: 51,
        serverId: null,
        expenseType: 'سحب راتب',
        amount: 25000,
        date: '2026-08-24',
        hotelDayKey: '2026-08-24',
        relatedId: 9,
      );
      final isMirror = SalaryMirrorMatcher.isMirrorOfReadExpense(
        expenseId: null,
        reason: 'exp_1148',
        amount: 25000,
        hotelDayKey: '2026-08-25',
        withdrawDate: '2026-08-25',
        employeeId: 9,
        expenses: [candidate],
      );
      expect(isMirror, isFalse);
    });
  });
}
