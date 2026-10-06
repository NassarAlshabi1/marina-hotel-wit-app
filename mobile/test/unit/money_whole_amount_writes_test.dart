// test/unit/money_whole_amount_writes_test.dart
//
// ✅ G-10 (تدقيق الهوية المالية 2026-10-06): سياسة «لا كسور عشرية».
//
// هذا الاختبار يُثبت أن **كل عملية تَخزِن مبلغاً** تكتبه عدداً صحيحاً
// (اقتطاع نحو الصفر) — لا في الشاشة فقط، ولا في النقل فقط:
//   rooms.price · employees.basic_salary · cash_transactions.amount ·
//   debts (total/paid/remaining) · وتقسيم أقساط السلفة على المصروفات
//   والسحوبات المرآة.
//
// ولأن الاقتطاع حتمي (نفس القيمة → نفس الناتج على كل جهاز)، فإن مجموع
// المصروف = مجموع السحوبات المرآة، فلا ينحرف الرصيد بين الأجهزة.
import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/repositories/cash_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/debts_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/employees_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/expenses_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/rooms_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/salary_withdrawals_repository.dart';
import 'package:marina_hotel_mobile/services/salary_advance_installments_service.dart';
import 'package:marina_hotel_mobile/utils/currency_formatter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  double sum(Iterable<num> values) =>
      values.fold<double>(0, (s, v) => s + v.toDouble());

  group('كتابة المبالغ — لا كسور عشرية (G-10)', () {
    test('rooms.price يُخزَّن عدداً صحيحاً', () async {
      await RoomsRepository(db).create(
        roomNumber: 'G10-101',
        type: 'single',
        price: 15000.75,
        status: 'available',
      );

      final room = await (db.select(
        db.rooms,
      )..where((r) => r.roomNumber.equals('G10-101'))).getSingle();

      expect(room.price, 15000, reason: '15000.75 → 15000 (لا 15001)');
    });

    test('employees.basic_salary يُخزَّن عدداً صحيحاً', () async {
      final id = await EmployeesRepository(
        db,
      ).create(name: 'موظف G-10', status: 'active', basicSalary: 45000.99);

      final employee = await (db.select(
        db.employees,
      )..where((e) => e.id.equals(id))).getSingle();

      expect(employee.basicSalary, 45000, reason: '45000.99 → 45000');
    });

    test('cash_transactions.amount يُخزَّن عدداً صحيحاً', () async {
      final id = await CashRepository(db).create(
        type: 'in',
        amount: 999.5,
        transactionTime: '2026-10-06T10:00:00',
      );

      final row = await (db.select(
        db.cashTransactions,
      )..where((t) => t.id.equals(id))).getSingle();

      expect(row.amount, 999, reason: '999.5 → 999 (لا 1000)');
    });

    test('debts: الإجمالي والمدفوع والمتبقي كلها أعداد صحيحة', () async {
      final id = await DebtsRepository(db).create(
        guestName: 'مدين G-10',
        checkinDate: '2026-10-01',
        checkoutDate: '2026-10-03',
        totalAmount: 1200.75,
        paidAmount: 200.25,
        paymentDate: '2026-10-06',
      );

      final debt = await (db.select(
        db.debts,
      )..where((t) => t.id.equals(id))).getSingle();

      expect(debt.totalAmount, 1200);
      expect(debt.paidAmount, 200);
      // 1000.5 → 1000: الاقتطاع نحو الصفر لا يزيد المتبقي على المدين
      expect(debt.remainingAmount, 1000);
      expect(
        CurrencyFormatter.isWholeAmount(debt.remainingAmount),
        isTrue,
        reason: 'لا كسور في أي عمود مالي',
      );
    });

    test(
      'أقساط السلفة: مصروفها وسحوبتها المرآة ومجموع أقساطها = السلفة بالضبط',
      () async {
        final employeeId = await db
            .into(db.employees)
            .insert(
              const EmployeesCompanion(
                name: d.Value('موظف الأقساط'),
                basicSalary: d.Value(1000),
                status: d.Value('active'),
                hireDate: d.Value('2026-01-01'),
                localUuid: d.Value('emp-g10-split'),
                createdAt: d.Value(1),
                updatedAt: d.Value(1),
                lastModified: d.Value(1),
              ),
            );

        final service = SalaryAdvanceInstallmentsService(
          db,
          ExpensesRepository(db),
          SalaryWithdrawalsRepository(db),
        );

        // سلفة بكسر + 3 أقساط: 1000.5 → 1000 (اقتطاع)، والقسط الأخير
        // يستوعب الباقي ⇒ 333 + 333 + 334 = 1000.
        await service.createInstallmentAdvance(
          employeeId: employeeId,
          totalAmount: 1000.5,
          advanceDate: '2026-10-06',
          description: 'سلفة اختبار',
          installments: 3,
        );

        final advanceExpenses = await (db.select(
          db.expenses,
        )..where((e) => e.expenseType.equals('سلفة'))).get();
        final installmentExpenses = await (db.select(
          db.expenses,
        )..where((e) => e.expenseType.equals('خصم من الراتب'))).get();
        final withdrawals = await db.select(db.salaryWithdrawals).get();

        // 1) مصروف السلفة عدد صحيح
        expect(advanceExpenses, hasLength(1));
        expect(advanceExpenses.single.amount, 1000);

        // 2) الأقساط: 3 أعداد صحيحة مجموعها = السلفة (لا فقدان ريال)
        expect(installmentExpenses, hasLength(3));
        for (final e in installmentExpenses) {
          expect(
            CurrencyFormatter.isWholeAmount(e.amount),
            isTrue,
            reason: 'قسط بكسر: ${e.amount}',
          );
        }
        expect(
          sum(installmentExpenses.map((e) => e.amount)),
          advanceExpenses.single.amount,
          reason: 'مجموع الأقساط يجب أن يساوي السلفة بالضبط',
        );
        expect(
          installmentExpenses.map((e) => e.amount).toList(),
          [333.0, 333.0, 334.0],
          reason: 'القسط الأخير يستوعب الباقي (333,333,334)',
        );

        // 3) السحوبات المرآة: سلفة موجبة + أقساط سالبة بنفس القيم
        expect(withdrawals, hasLength(4));
        for (final w in withdrawals) {
          expect(
            CurrencyFormatter.isWholeAmount(w.amount),
            isTrue,
            reason: 'سحبة بكسر: ${w.amount}',
          );
        }
        final advanceWithdrawal = withdrawals.firstWhere((w) => w.amount > 0);
        final installmentWithdrawals = withdrawals.where((w) => w.amount < 0);
        expect(advanceWithdrawal.amount, advanceExpenses.single.amount);
        expect(
          -sum(installmentWithdrawals.map((w) => w.amount)),
          advanceWithdrawal.amount,
          reason: 'مجموع السحوبات السالبة = السلفة (لا زيادة ولا نقصان)',
        );
      },
    );
  });
}
