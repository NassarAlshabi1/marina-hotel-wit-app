// ═══════════════════════════════════════════════════════════════════════
//  salary_withdrawals_stamp_wire_test.dart — قفل عقد الطابع على السلك
//
//  العطل المُثبت قبل الإصلاح:
//   الحمولات كانت تحمل lastModified وحده، والـWorker يُهبط
//   last_modified_epoch إلى 0 عند الغياب (worker/src/database.ts:918):
//       if (!record.last_modified)       record.last_modified = now;
//       if (!record.last_modified_epoch) record.last_modified_epoch = 0;
//   → صف D1 يحمل طابعين متناقضين، وعند السحب يكتبه _vInt في القاعدة
//     المحلية بقيمة 0 خالصة (لأن 0 قيمة موجودة لا غائبة ⇒ لا fallback)
//     فيبقى التناقض على كل جهاز إلى الأبد.
//
//  الاتفاقية الحاكمة: payload_mapper.dart يُرسل 'lastModified' و
//  'lastModifiedEpoch' معاً في 15 كياناً — salary_withdrawals كان
//  الاستثناء الوحيد (حمولاته مبنية يدوياً في المستودع).
//
//  الحارس يُشغّل المنتجين الحقيقيين ثم يمرّر الناتج عبر حد الدفع
//  الحقيقي buildPushOperation — لا يقارن نصوصاً.
// ═══════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/screens/reports/salary_withdrawals_report_screen.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/repositories/expenses_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/salary_withdrawals_repository.dart';
import 'package:marina_hotel_mobile/services/sync/payload_normalizer.dart';
import 'package:marina_hotel_mobile/utils/id.dart';
import 'package:marina_hotel_mobile/utils/time.dart';

Future<int> _insertEmployee(AppDatabase db) {
  final now = Time.nowEpoch();
  return db
      .into(db.employees)
      .insert(
        EmployeesCompanion(
          localUuid: Value(IdGen.uuid()),
          name: const Value('موظف عقد الطابع'),
          basicSalary: const Value(3000.0),
          status: const Value('نشط'),
          createdAt: Value(now),
          updatedAt: Value(now),
          lastModified: Value(now),
        ),
      );
}

/// يبني عملية دفع حقيقية من صف outbox حقيقي ويُرجع حمولتها المُطبَّعة.
Future<Map<String, dynamic>> _wireData(OutboxData o) async {
  final operation = await buildPushOperation(
    o,
    resolveRowVectorClock: (String entity, String localUuid) async => '{}',
  );
  return operation['data']! as Map<String, dynamic>;
}

/// التأكيد الجوهري: الطابعان يصلان معاً وغير صفريين ومتساويين.
Future<void> _expectBothStampsOnWire(
  OutboxData o, {
  required String why,
}) async {
  final data = await _wireData(o);
  final lastModified = data['last_modified'];
  final lastModifiedEpoch = data['last_modified_epoch'];

  expect(
    lastModified,
    isA<int>(),
    reason: '$why — op=${o.op} لا يحمل last_modified على السلك',
  );
  expect(
    lastModifiedEpoch,
    isA<int>(),
    reason:
        '$why — op=${o.op} يرسل last_modified بلا last_modified_epoch: '
        'الـWorker يُهبطه 0 فيصبح الطابقان متناقضين في D1',
  );
  expect(
    lastModified,
    greaterThan(0),
    reason: '$why — طابع صفري يعني أنه لم يصعد أصلاً',
  );
  expect(
    lastModifiedEpoch,
    lastModified,
    reason:
        '$why — الحقلان مرآتان لحدث واحد؛ اختلافهما يعني أن أحدهما '
        'مجمَّد عند قيمة سابقة',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ExpensesRepository expensesRepo;
  late SalaryWithdrawalsRepository salaryRepo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    expensesRepo = ExpensesRepository(db);
    salaryRepo = SalaryWithdrawalsRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<List<OutboxData>> salaryOutbox() => (db.select(
    db.outbox,
  )..where((t) => t.entity.equals('salary_withdrawals'))).get();

  test(
    'كل مسار كتابة للسحوبات يرفع الطابعين معاً على السلك',
    () async {
      final employeeId = await _insertEmployee(db);
      const date = '2026-10-08';

      // ── المسار 1: إنشاء عبر saveFromExpense ──
      final expenseId = await expensesRepo.create(
        expenseType: 'سحب راتب',
        relatedId: employeeId,
        description: 'سحب راتب',
        amount: 100,
        date: date,
        hotelDayKey: date,
      );
      await salaryRepo.saveFromExpense(
        expenseId: expenseId,
        employeeId: employeeId,
        action: 'سحب راتب',
        amount: 100,
        date: date,
      );

      // ── المسار 2: تعديل نفس المصروف ──
      await salaryRepo.saveFromExpense(
        expenseId: expenseId,
        employeeId: employeeId,
        action: 'سحب راتب',
        amount: 250,
        date: date,
      );

      // ── المسار 3: حذف ناعم عبر تحويل النوع ──
      await salaryRepo.deleteByExpenseId(expenseId);

      // ── المسار 4: إنشاء مباشر ──
      final expense2 = await expensesRepo.create(
        expenseType: 'سحب راتب',
        relatedId: employeeId,
        description: 'سحب راتب مباشر',
        amount: 75,
        date: date,
        hotelDayKey: date,
      );
      await salaryRepo.createFromExpense(
        expenseId: expense2,
        employeeId: employeeId,
        reason: 'سحب مباشر',
        amount: 75,
        date: date,
      );

      final rows = await salaryOutbox();
      expect(
        rows,
        isNotEmpty,
        reason: 'لا يقفل الحارس شيئاً إن لم ينتج المسارات حمولة',
      );
      expect(
        rows.map((o) => o.op).toSet(),
        containsAll(<String>{'create', 'update'}),
        reason: 'يجب تغطية الإنشاء والتحديث معاً',
      );
      for (final row in rows) {
        await _expectBothStampsOnWire(row, why: 'مسار كتابة المستودع');
      }
    },
  );

  test(
    'الطابع يتساوى محلياً بعد الإنشاء وبعد التعديل',
    () async {
      final employeeId = await _insertEmployee(db);
      const date = '2026-10-08';
      final expenseId = await expensesRepo.create(
        expenseType: 'سحب راتب',
        relatedId: employeeId,
        description: 'سحب راتب',
        amount: 100,
        date: date,
        hotelDayKey: date,
      );
      await salaryRepo.saveFromExpense(
        expenseId: expenseId,
        employeeId: employeeId,
        action: 'سحب راتب',
        amount: 100,
        date: date,
      );
      final created = (await salaryRepo.listActive()).single;
      expect(
        created.lastModifiedEpoch,
        created.lastModified,
        reason: 'بعد الإنشاء',
      );

      await salaryRepo.saveFromExpense(
        expenseId: expenseId,
        employeeId: employeeId,
        action: 'سحب راتب',
        amount: 250,
        date: date,
      );
      final updated = (await salaryRepo.listActive()).single;
      expect(
        updated.lastModifiedEpoch,
        updated.lastModified,
        reason: 'بعد التعديل — ترك أحدهما يجعلهما يتناقضان',
      );
    },
  );

  test(
    'تنظيف تكرار التقرير يرفع الطابعين معاً على السلك',
    () async {
      final employeeId = await _insertEmployee(db);
      const date = '2026-10-08';

      // سحوبة مرتبطة بمصروف حقيقي (= المرآة المُرسّاة)
      final expenseId = await expensesRepo.create(
        expenseType: 'سحب راتب',
        relatedId: employeeId,
        description: 'سحب راتب',
        amount: 100,
        date: date,
        hotelDayKey: date,
      );
      await salaryRepo.saveFromExpense(
        expenseId: expenseId,
        employeeId: employeeId,
        action: 'سحب راتب',
        amount: 100,
        date: date,
      );

      // مرآة رابطها مكسور: علامة exp_ لهدف غير موجود، بنفس
      // الموظف/المبلغ/اليوم — المرشح الوحيد فتُحذف كمكرر مؤكد.
      final now = Time.nowEpoch();
      await db
          .into(db.salaryWithdrawals)
          .insert(
            SalaryWithdrawalsCompanion(
              localUuid: Value(IdGen.uuid()),
              employeeId: Value(employeeId),
              amount: const Value(100),
              withdrawDate: const Value(date),
              reason: const Value('exp_999999'),
              hotelDayKey: const Value(date),
              withdrawalType: const Value('سحب راتب'),
              createdAt: Value(now),
              updatedAt: Value(now),
              lastModified: Value(now),
            ),
          );

      // نعزل حمولة التقرير وحدها حتى يُنسب أي outbox لمسارها.
      await db.delete(db.outbox).go();

      final live = await salaryRepo.listActive();
      final result = await dedupeMirrorDuplicates(
        db,
        withdrawals: live,
        fromHotelDay: date,
        toHotelDay: date,
      );
      expect(
        result.orphansDeleted,
        1,
        reason: 'السيناريو يجب أن يحذف المرآة المكسورة — وإلا لا يقفل الحارس',
      );

      final rows = await salaryOutbox();
      expect(
        rows,
        hasLength(1),
        reason: 'الحذف الناعم من مسار التقرير يمرّ بصف outbox واحد',
      );
      await _expectBothStampsOnWire(
        rows.single,
        why: 'dedupeMirrorDuplicates في تقرير السحوبات',
      );

      // ومحلياً: السحوبات الباقية تحمل طابعين متساويين
      for (final sw in await salaryRepo.listActive()) {
        expect(sw.lastModifiedEpoch, sw.lastModified);
      }
    },
  );
}
