// test/unit/sync_duplicate_mirror_guard_test.dart
//
// ✅ (2026-10-07 — م-4) ازدواج المرآة (سحبة راتب ↔ مصروف) القادم من المزامنة.
//
// الخلل المُثبت من الكود قبل الإصلاح:
//   • m69 أنشأ فهرساً فريداً جزئياً idx_salary_withdrawals_active_expense
//     (مرآة نشطة واحدة لكل expense_uuid) — مشتقاً من D1 0013.
//   • منطق «تبنّي المرآة اليتيمة» موجود في saveFromExpense (مسار إنشاء/
//     تعديل المصروف محلياً) فقط، ولا يعمل على السحب.
//   • المحكّمات ON CONFLICT في BaseRepository تتخطى الفهارس الجزئية
//     (لا تصلح كـ arbiter) ⇒ الإدراج يمر بلا ON CONFLICT فيصطدم بالفهرس
//     ويرمي UNIQUE constraint؛ النتيجة تُبتلع في تحذير سحب صامت:
//     'Failed to sync withdrawal ...' بلا تقرير مراجعة.
//
// القرار الحتمي (لا تخمين): تكرار الهوية مؤكد (نفس expense_uuid = نفس
// العملية المالية) لكن تحديد «المرآة الصحيحة» (قد تختلف المبالغ/الموظف/اليوم)
// لا يُحسم آلياً ⇒ يُتخطى الوارد بتقرير صريح، والحمولة تُسلَّم لمخزن العلاقات
// المعلّقة (G-3) فتنتهي إلى needs_review في تقرير المراجعة.
import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;

import 'package:marina_hotel_mobile/services/adapters/id_resolver.dart';
import 'package:marina_hotel_mobile/services/adapters/salary_withdrawals_adapter.dart';
import 'package:marina_hotel_mobile/services/adapters/source.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/repositories/base_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late SalaryWithdrawalsAdapter adapter;
  late BaseRepository<SalaryWithdrawal, SalaryWithdrawalsCompanion> repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    adapter = SalaryWithdrawalsAdapter(IdResolver(db));
    repo = BaseRepository<SalaryWithdrawal, SalaryWithdrawalsCompanion>(
      db: db,
      table: db.salaryWithdrawals,
      adapter: adapter,
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> insertEmployee(String uuid) => db
      .into(db.employees)
      .insert(
        EmployeesCompanion(
          name: const d.Value('موظف اختبار'),
          basicSalary: const d.Value(1000),
          status: const d.Value('active'),
          localUuid: d.Value(uuid),
          createdAt: const d.Value(1000),
          updatedAt: const d.Value(1000),
          lastModified: const d.Value(1000),
        ),
      );

  Future<int> insertWithdrawal({
    required String localUuid,
    required int employeeId,
    String? expenseUuid,
    int? expenseId,
    double amount = 100,
    int? deletedAt,
  }) => db
      .into(db.salaryWithdrawals)
      .insert(
        SalaryWithdrawalsCompanion(
          employeeId: d.Value(employeeId),
          amount: d.Value(amount),
          withdrawDate: const d.Value('2026-10-01'),
          hotelDayKey: const d.Value('2026-10-01'),
          expenseUuid: expenseUuid != null
              ? d.Value(expenseUuid)
              : const d.Value.absent(),
          expenseId: expenseId != null
              ? d.Value(expenseId)
              : const d.Value.absent(),
          localUuid: d.Value(localUuid),
          createdAt: const d.Value(1000),
          updatedAt: const d.Value(1000),
          lastModified: const d.Value(1000),
          deletedAt: deletedAt != null
              ? d.Value(deletedAt)
              : const d.Value.absent(),
        ),
      );

  Map<String, dynamic> incomingPayload({
    required String localUuid,
    String expenseUuid = 'exp-uuid-1',
    double amount = 100,
  }) => <String, dynamic>{
    'localUuid': localUuid,
    'employeeUuid': 'emp-uuid-1',
    'expenseUuid': expenseUuid,
    'amount': amount,
    'withdrawDate': '2026-10-01',
    'hotelDayKey': '2026-10-01',
    'reason': 'exp_7',
  };

  group('حارس التكرار المؤكد بالهوية (expense_uuid)', () {
    test('مرآة مكررة نشطة قادمة من السحب ⇒ تخطٍّ صريح بسبب مفهوم', () async {
      final empId = await insertEmployee('emp-uuid-1');
      await insertWithdrawal(
        localUuid: 'wd-local-1',
        employeeId: empId,
        expenseUuid: 'exp-uuid-1',
      );

      final refs = await adapter.resolveRefs(
        db,
        incomingPayload(localUuid: 'wd-dup-2'),
        src: Source.appwrite,
      );
      expect(refs.shouldSkip, isTrue);
      expect(refs.skipReason, contains('مرآة مكررة'));
      expect(refs.skipReason, contains('exp-uuid-1'));
      expect(refs.skipReason, contains('مراجعة بشرية'));
    });

    test('مصروف مختلف (uuid آخر) ⇒ لا تخطّي', () async {
      final empId = await insertEmployee('emp-uuid-1');
      await insertWithdrawal(
        localUuid: 'wd-local-1',
        employeeId: empId,
        expenseUuid: 'exp-uuid-1',
      );

      final refs = await adapter.resolveRefs(
        db,
        incomingPayload(localUuid: 'wd-other', expenseUuid: 'exp-uuid-9'),
        src: Source.appwrite,
      );
      expect(refs.shouldSkip, isFalse);
    });

    test('المرآة المحلية محذوفة (soft delete) ⇒ الإدراج مسموح', () async {
      final empId = await insertEmployee('emp-uuid-1');
      await insertWithdrawal(
        localUuid: 'wd-local-deleted',
        employeeId: empId,
        expenseUuid: 'exp-uuid-1',
        deletedAt: 2000,
      );

      final refs = await adapter.resolveRefs(
        db,
        incomingPayload(localUuid: 'wd-new'),
        src: Source.appwrite,
      );
      expect(refs.shouldSkip, isFalse);
    });

    test('مصدر محلي ⇒ لا يُطبَّق الحارس (لا ازدواج عبر الأجهزة هناك)', () async {
      final empId = await insertEmployee('emp-uuid-1');
      await insertWithdrawal(
        localUuid: 'wd-local-1',
        employeeId: empId,
        expenseUuid: 'exp-uuid-1',
      );
      final refs = await adapter.resolveRefs(
        db,
        incomingPayload(localUuid: 'wd-dup-2'),
        src: Source.local,
      );
      expect(refs.shouldSkip, isFalse);
    });
  });

  group('التكامل مع BaseRepository: لا استثناء ولا فقدان', () {
    test('upsertFromJson يلتقط الحمولة (G-3) ويعيد -1 بلا رمي', () async {
      final empId = await insertEmployee('emp-uuid-1');
      await insertWithdrawal(
        localUuid: 'wd-local-1',
        employeeId: empId,
        expenseUuid: 'exp-uuid-1',
      );

      final deferred = <Map<String, dynamic>>[];
      repo.setSkippedRecordSink((
        json, {
        required String tableName,
        required String collectionId,
        required Source src,
        required String? skipReason,
      }) async {
        deferred.add({
          'json': json,
          'tableName': tableName,
          'collectionId': collectionId,
          'src': src,
          'skipReason': skipReason,
        });
      });

      final result = await repo.upsertFromJson(
        incomingPayload(localUuid: 'wd-dup-2'),
        src: Source.appwrite,
      );

      expect(result, equals(-1), reason: 'تخطٍّ صريح لا استثناء');

      final active = await (db.select(
        db.salaryWithdrawals,
      )..where((t) => t.expenseUuid.equals('exp-uuid-1') & t.deletedAt.isNull()))
          .get();
      expect(active, hasLength(1), reason: 'لا مرآة نشطة ثانية');
      expect(active.single.localUuid, equals('wd-local-1'));

      expect(deferred, hasLength(1), reason: 'لا تخطّي صامت — الحمولة محفوظة');
      expect(deferred.single['collectionId'], equals('salary_withdrawals'));
      expect(
        deferred.single['skipReason'] as String,
        contains('مرآة مكررة'),
      );
      final payload = deferred.single['json'] as Map<String, dynamic>;
      expect(payload['localUuid'], equals('wd-dup-2'));
      expect(payload['amount'], equals(100));
    });

    test('الفهرس الفريد الجزئي m69 قائم ويرفض النشط الثاني (سبب الحارس)',
        () async {
      final empId = await insertEmployee('emp-uuid-1');
      await insertWithdrawal(
        localUuid: 'wd-local-1',
        employeeId: empId,
        expenseUuid: 'exp-uuid-1',
      );

      // الفهرس موجود (m69 — D1 0013)
      final indexes = await db
          .customSelect("PRAGMA index_list('salary_withdrawals')")
          .get();
      expect(
        indexes.map((r) => r.data['name'].toString()),
        contains('idx_salary_withdrawals_active_expense'),
      );

      // إدراج مباشر ثانٍ (يتجاوز طبقة المحوّلات) يفشل بالقيود — هذا ما كان
      // يرميه مسار السحب القديم ويبتلع تحذيره.
      await expectLater(
        insertWithdrawal(
          localUuid: 'wd-dup-raw',
          employeeId: empId,
          expenseUuid: 'exp-uuid-1',
        ),
        throwsA(isA<SqliteException>()),
      );

      // والصف الموجود سليم — لم يتأثر بالفشل
      final active = await (db.select(
        db.salaryWithdrawals,
      )..where((t) => t.localUuid.equals('wd-local-1'))).getSingle();
      expect(active.expenseUuid, equals('exp-uuid-1'));
    });
  });
}
