// test/unit/salary_withdrawal_mirror_claim_regression_test.dart
//
// ✅ (2026-11-03) اختبارات انحدار: حسم تصادم مطالبة رابط المرآة
// (expense_uuid) في مسار سحب salary_withdrawals.
//
// المشكلة المُثبتة من سجلات الإنتاج (04:54): مستندات سحابة مكررة/قديمة
// يختلف localUuid فيها وتطالب بنفس expenseUuid — الـ upsert الثاني كان
// يفشل بـ SqliteException(2067) على الفهرس الفريد الجزئي
// ux_salary_withdrawals_expense_uuid_active (لا يقبل ON CONFLICT)،
// فيُقيَّد مؤشر المجموعة إلى الأبد: نفس الدفعة تُعاد كل دورة ولا
// يتقدم السحب إطلاقاً.
//
// العقد المُثبَّت هنا (الكود الإنتاجي نفسه عبر syncSalaryWithdrawalsForTesting):
//  ت1) ختم المصروف العكسي (expenses.withdrawal_uuid) يعلن ملكية سحبة
//      قائمة → القادم يُكتب بلا رابط (ولا فشل).
//  ت2) الختم يعلن ملكية السحبة القادمة → الرابط ينتقل إليها وتُخلى
//      عنه السحبة القائمة.
//  ت3) توأم مكرر (موظف+مبلغ+تاريخ) بلا حكم من المصروف → تخطٍّ كامل:
//      لا إدراج ولا فشل — السجل ممثَّل محلياً بالفعل.
//  ت4) غير توأم ولا حكم → أول مطالِب قائم يفوز والقادم بلا رابط.
//  ت5) مصروف لموظف مختلف → نزع المطالبة قبل الكتابة كي لا تحتكر خانة
//      الفهرس وتحجب السحبة الصحيحة (تُثبت أن الخنة تبقى حرة).
//  ت6) الرقمي الخام expenseId البعيد لا يصل عمود expense_id أبداً.
//  ت7) دفعة واحدة بمطالبتين متصادمتين → لا StateError ولا 2067.
//  ت8) سحبات قديمة بلا expenseUuid → ملخص واحد لكل دفعة بدل تحذير
//      لكل سجل (طوفان سجلات الإنتاج) والمؤشر يتقدم فوقها.
//  ت9) مطالبة نزعها حارس التحكيم لا تُحسب «بلا رابط» ولا تُسجل رسالة
//      «وصل بلا expenseUuid» المضللة (سبب النزع مسجّل بسياقه الكامل).
//  ت10) مطالبة تشير لمصروف محذوف ناعماً → لا خطأ «رفض ربط» لكل مستند
//      ولا expense_id، والمطالبة تبقى كما وصلت (لا حذف بيانات) +
//      ملخص واحد لكل دفعة (طوفان ~90 سطراً بدفعة الإنتاج 22:17).
//  ت11) uuid الموظف مخزّن بصيغتين مختلفتين (شرطات) لنفس الموظف →
//      الربط يُكتب — لا «رفض ربط» شكلياً بالمقارنة الخام.

import 'dart:io';

import 'package:appwrite/models.dart' as models;
import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/adapters/adapter_registry.dart';
import 'package:marina_hotel_mobile/services/appwrite_logger.dart';
import 'package:marina_hotel_mobile/services/appwrite_service.dart';
import 'package:marina_hotel_mobile/services/appwrite_sync_manager.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ✅ مجلد مستقر طوال عمر ملف الاختبار + mock خاص لـ path_provider —
  // ClientIO.init() في Appwrite SDK يعمل fire-and-forget وينشئ
  // <documents>/cookies؛ إذا كان مجلد flutter_test_config الوهمي محذوفاً
  // لحظة التشغيل يتسرب PathNotFoundException غير معالج ويفشل الاختبار
  // بلا أي علاقة بمنطقه (نفس نمط appwrite_connection_reconfigure_test).
  late final Directory stableDocsDir;

  setUpAll(() async {
    stableDocsDir = await Directory.systemTemp.createTemp(
      'sw_mirror_claim_test_',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (MethodCall methodCall) async => stableDocsDir.path,
        );
  });

  tearDownAll(() async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    try {
      if (stableDocsDir.existsSync()) {
        await stableDocsDir.delete(recursive: true);
      }
    } catch (_) {
      // silent — best-effort cleanup
    }
  });

  // ⚠️ قاعدة واحدة لكل الملف: AppwriteSyncManager و AdapterRegistry
  // singleton بمُنشئ factory يتجاهل المعامل بعد أول إنشاء — قاعدة واحدة
  // طوال الملف وإلا أشار المدير لقاعدة مُغلقة (نفس قيد phase0).
  late final AppDatabase db;

  setUpAll(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    AdapterRegistry.initialize(db);
  });

  tearDownAll(() async {
    await db.close();
  });

  setUp(() async {
    // إعادة تهيئة متجر SharedPreferences (طابور اليتامى الدائم) عزل
    // اختبار عن الآخر.
    SharedPreferences.setMockInitialValues({});
    // نظافة قبل كل اختبار (الأبناء قبل الآباء لقيود FK).
    await db.delete(db.salaryWithdrawals).go();
    await db.delete(db.expenses).go();
    await db.delete(db.employees).go();
    AppwriteSyncManager.updateStaticDeviceId('device-test');
  });

  tearDown(() async {
    AppwriteSyncManager.updateStaticDeviceId(null);
  });

  Future<int> addEmployee(String uuid) => db
      .into(db.employees)
      .insert(
        EmployeesCompanion(
          name: const d.Value('موظف الاختبار'),
          basicSalary: const d.Value(10000),
          status: const d.Value('active'),
          hireDate: const d.Value('2026-01-01'),
          localUuid: d.Value(uuid),
          createdAt: const d.Value(1000),
          updatedAt: const d.Value(1000),
          lastModified: const d.Value(1000),
        ),
      );

  Future<int> addExpense({
    String uuid = 'exp-uuid-1',
    String? employeeUuid,
    String? withdrawalUuid,
  }) => db
      .into(db.expenses)
      .insert(
        ExpensesCompanion(
          expenseType: const d.Value('سحب راتب'),
          description: const d.Value('مصروف مرآة اختبار'),
          amount: const d.Value(3000),
          date: const d.Value('2026-05-25'),
          localUuid: d.Value(uuid),
          employeeUuid: employeeUuid == null
              ? const d.Value.absent()
              : d.Value(employeeUuid),
          withdrawalUuid: withdrawalUuid == null
              ? const d.Value.absent()
              : d.Value(withdrawalUuid),
          createdAt: const d.Value(1000),
          updatedAt: const d.Value(1000),
          lastModified: const d.Value(1000),
        ),
      );

  Future<void> addWithdrawal({
    required String uuid,
    required int employeeId,
    String? employeeUuid,
    double amount = 3000,
    String date = '2026-05-25',
    String? expenseUuid,
  }) async {
    await db
        .into(db.salaryWithdrawals)
        .insert(
          SalaryWithdrawalsCompanion(
            localUuid: d.Value(uuid),
            employeeId: d.Value(employeeId),
            employeeUuid: employeeUuid == null
                ? const d.Value.absent()
                : d.Value(employeeUuid),
            amount: d.Value(amount),
            withdrawDate: d.Value(date),
            expenseUuid: expenseUuid == null
                ? const d.Value.absent()
                : d.Value(expenseUuid),
            createdAt: const d.Value(1000),
            updatedAt: const d.Value(1000),
            lastModified: const d.Value(1000),
          ),
        );
  }

  models.Document withdrawalDoc({
    required String uuid,
    String employeeUuid = 'emp-a',
    double amount = 3000,
    String date = '2026-05-25',
    String? expenseUuid,
    int? expenseId,
  }) {
    return models.Document(
      $id: uuid,
      $sequence: 1,
      $collectionId: 'salary_withdrawals',
      $databaseId: 'marina',
      $createdAt: '2026-10-01T00:00:00.000Z',
      $updatedAt: '2026-10-01T12:00:00.000Z',
      $permissions: const <String>[],
      data: <String, dynamic>{
        'localUuid': uuid,
        'employeeUuid': employeeUuid,
        'amount': amount,
        'withdrawDate': date,
        'withdrawalType': 'سحب راتب',
        'reason': 'exp_test',
        'createdAt': 1760000000,
        'lastModified': 1760000100,
        'version': 1,
        'deviceId': 'device-A',
        if (expenseUuid != null) 'expenseUuid': expenseUuid,
        if (expenseId != null) 'expenseId': expenseId,
      },
    );
  }

  Future<SalaryWithdrawal?> rowByUuid(String uuid) =>
      (db.select(db.salaryWithdrawals)
            ..where((t) => t.localUuid.equals(uuid))
            ..limit(1))
          .getSingleOrNull();

  AppwriteSyncManager newManager() =>
      AppwriteSyncManager(appwriteService: AppwriteService(), database: db);

  test(
    'ت1: المصروف يعلن ملكية السحبة القائمة → القادم يُكتب بلا رابط ولا فشل',
    () async {
      final empId = await addEmployee('emp-a');
      await addExpense(employeeUuid: 'emp-a', withdrawalUuid: 'sw-orig');
      await addWithdrawal(
        uuid: 'sw-orig',
        employeeId: empId,
        employeeUuid: 'emp-a',
        expenseUuid: 'exp-uuid-1',
      );

      final manager = newManager();
      // قبل الإصلاح: SqliteException(2067) → StateError → مؤشر مقيَّد للأبد.
      final applied = await manager.syncSalaryWithdrawalsForTesting([
        withdrawalDoc(
          uuid: 'sw-dup',
          expenseUuid: 'exp-uuid-1',
          expenseId: 999,
        ),
      ]);

      expect(applied, 1);
      final dup = await rowByUuid('sw-dup');
      expect(dup, isNotNull, reason: 'السحبة القادمة تُطبَّق بلا رابط مرآة');
      expect(dup!.expenseUuid, isNull, reason: 'المطالبة المنزوعة لا تُخزَّن');
      expect(dup.expenseId, isNull, reason: 'الرقمي الخام 999 لا يُخزَّن');
      final orig = await rowByUuid('sw-orig');
      expect(orig!.expenseUuid, 'exp-uuid-1', reason: 'الرابط يبقى لصاحبه');
    },
  );

  test(
    'ت2: المصروف يعلن ملكية السحبة القادمة → الرابط ينتقل إليها وتُخلى عنه القائمة',
    () async {
      final empId = await addEmployee('emp-a');
      final expenseId = await addExpense(
        employeeUuid: 'emp-a',
        withdrawalUuid: 'sw-new',
      );
      await addWithdrawal(
        uuid: 'sw-orig',
        employeeId: empId,
        employeeUuid: 'emp-a',
        expenseUuid: 'exp-uuid-1',
      );

      final manager = newManager();
      final applied = await manager.syncSalaryWithdrawalsForTesting([
        withdrawalDoc(
          uuid: 'sw-new',
          expenseUuid: 'exp-uuid-1',
          expenseId: 999,
        ),
      ]);

      expect(applied, 1);
      final fresh = await rowByUuid('sw-new');
      expect(
        fresh!.expenseUuid,
        'exp-uuid-1',
        reason: 'صاحب الرابط الموثوق يستلمه',
      );
      expect(
        fresh.expenseId,
        expenseId,
        reason: 'حل المرآة بعد الرفع يكتب expense_id المحلي الصحيح',
      );
      final orig = await rowByUuid('sw-orig');
      expect(
        orig!.expenseUuid,
        isNull,
        reason: 'المتنازع القائم يُخلى عن الرابط',
      );
      expect(orig.expenseId, isNull);
    },
  );

  test(
    'ت3: توأم مكرر (موظف+مبلغ+تاريخ) بلا حكم من المصروف → تخطٍّ كامل بلا إدراج',
    () async {
      final empId = await addEmployee('emp-a');
      await addWithdrawal(
        uuid: 'sw-orig',
        employeeId: empId,
        employeeUuid: 'emp-a',
        expenseUuid: 'exp-uuid-1',
      );

      final manager = newManager();
      final applied = await manager.syncSalaryWithdrawalsForTesting([
        withdrawalDoc(
          uuid: 'sw-dup',
          expenseUuid: 'exp-uuid-1',
          expenseId: 999,
        ),
      ]);

      expect(applied, 0, reason: 'المكرر ممثَّل محلياً — لا إدراج ولا فشل');
      expect(await rowByUuid('sw-dup'), isNull);
      final orig = await rowByUuid('sw-orig');
      expect(orig!.expenseUuid, 'exp-uuid-1');
    },
  );

  test(
    'ت4: غير توأم ولا حكم → أول مطالِب قائم يفوز والقادم بلا رابط',
    () async {
      final empId = await addEmployee('emp-a');
      await addWithdrawal(
        uuid: 'sw-orig',
        employeeId: empId,
        employeeUuid: 'emp-a',
        expenseUuid: 'exp-uuid-1',
      );

      final manager = newManager();
      final applied = await manager.syncSalaryWithdrawalsForTesting([
        withdrawalDoc(
          uuid: 'sw-other',
          amount: 999,
          date: '2026-06-01',
          expenseUuid: 'exp-uuid-1',
          expenseId: 999,
        ),
      ]);

      expect(applied, 1);
      final other = await rowByUuid('sw-other');
      expect(other, isNotNull);
      expect(other!.expenseUuid, isNull, reason: 'الرابط لأول مطالِب قائم');
      expect(other.expenseId, isNull);
      final orig = await rowByUuid('sw-orig');
      expect(orig!.expenseUuid, 'exp-uuid-1');
    },
  );

  test(
    'ت5: مصروف لموظف مختلف → نزع المطالبة قبل الكتابة وتبقى الخانة حرة لصاحبها',
    () async {
      await addEmployee('emp-a');
      await addEmployee('emp-b');
      await addExpense(employeeUuid: 'emp-b', withdrawalUuid: 'sw-right');

      final manager = newManager();
      final applied = await manager.syncSalaryWithdrawalsForTesting([
        // سحبة موظف A تطالب بمصروف موظف B — زوج فاسد من الحقبة الرقمية.
        withdrawalDoc(uuid: 'sw-x', expenseUuid: 'exp-uuid-1', expenseId: 999),
        // السحبة الصحيحة (موظف B) تصل بعدها في نفس الدفعة.
        withdrawalDoc(
          uuid: 'sw-right',
          employeeUuid: 'emp-b',
          expenseUuid: 'exp-uuid-1',
          expenseId: 999,
        ),
      ]);

      expect(applied, 2);
      final corrupted = await rowByUuid('sw-x');
      expect(
        corrupted!.expenseUuid,
        isNull,
        reason: 'المطالبة الفاسدة نُزعت قبل احتلال خانة الفهرس الفريد',
      );
      final rightful = await rowByUuid('sw-right');
      expect(
        rightful!.expenseUuid,
        'exp-uuid-1',
        reason: 'الخانة بقيت حرة فاستلمها صاحبها الحقيقي دون 2067',
      );
    },
  );

  test(
    'ت6: الرقمي الخام expenseId البعيد لا يصل عمود expense_id أبداً',
    () async {
      await addEmployee('emp-a');

      final manager = newManager();
      final applied = await manager.syncSalaryWithdrawalsForTesting([
        withdrawalDoc(uuid: 'sw-plain', expenseId: 999),
      ]);

      expect(applied, 1);
      final row = await rowByUuid('sw-plain');
      // قبل الإصلاح: الـ adapter كان ينسخ 999 (id جهاز المصدر) خاماً إلى
      // العمود فيبقى رابطاً خاطئاً إن لم يُحلّ UUID المرآة لاحقاً.
      expect(row!.expenseId, isNull);
      expect(row.expenseUuid, isNull);
    },
  );

  test('ت7: دفعة واحدة بمطالبتين متصادمتين → لا StateError ولا 2067', () async {
    await addEmployee('emp-a');

    final manager = newManager();
    // قبل الإصلاح: المستند الثاني يفشل بـ 2067 → failed.isNotEmpty →
    // StateError → المؤشر لا يتقدم → إعادة لا نهائية لنفس الدفعة.
    final applied = await manager.syncSalaryWithdrawalsForTesting([
      withdrawalDoc(uuid: 'sw-a', expenseUuid: 'exp-uuid-1', expenseId: 999),
      withdrawalDoc(
        uuid: 'sw-b',
        amount: 999,
        date: '2026-06-01',
        expenseUuid: 'exp-uuid-1',
        expenseId: 999,
      ),
    ]);

    expect(applied, 2, reason: 'كلتا السحبتين طُبقتا دون أي استثناء');
    final first = await rowByUuid('sw-a');
    expect(first!.expenseUuid, 'exp-uuid-1', reason: 'أول مطالبة في الدفعة');
    final second = await rowByUuid('sw-b');
    expect(second!.expenseUuid, isNull, reason: 'الثانية بلا رابط — لا فشل');
  });

  test(
    'ت8: سحبات قديمة بلا expenseUuid → ملخص واحد لكل دفعة بدل تحذير لكل سجل',
    () async {
      await addEmployee('emp-a');
      final logger = AppwriteLogger();
      final manager = newManager();
      logger.clearLogs();

      final applied = await manager.syncSalaryWithdrawalsForTesting([
        withdrawalDoc(uuid: 'sw-legacy-1', expenseId: 101),
        withdrawalDoc(uuid: 'sw-legacy-2', expenseId: 102),
        withdrawalDoc(uuid: 'sw-legacy-3', expenseId: 103),
      ]);

      expect(applied, 3, reason: 'السجلات القديمة تُطبَّق كاملة بلا فشل');
      for (final uuid in ['sw-legacy-1', 'sw-legacy-2', 'sw-legacy-3']) {
        final row = await rowByUuid(uuid);
        expect(row, isNotNull, reason: 'السجل القديم يُخزَّن');
        expect(row!.expenseId, isNull, reason: 'الرقمي الخام لا يُكتب');
        expect(row.expenseUuid, isNull);
      }

      final relinkLogs = logger
          .getLogs()
          .where((l) => l.tag == 'SYNC_RELINK')
          .toList();
      // قبل الإصلاح: 3 تحذيرات «arrived without expenseUuid» — واحد لكل
      // سجل (طوفان في السحب الأولي لجهاز جديد بمئات السحبات التاريخية).
      expect(
        relinkLogs.where((l) => l.message.contains('arrived without')).length,
        0,
        reason: 'لا تحذير لكل سجل بعد الإصلاح',
      );
      final summaries = relinkLogs
          .where((l) => l.message.contains('بلا expenseUuid'))
          .toList();
      expect(summaries.length, 1, reason: 'سطر ملخص واحد لكل الدفعة');
      expect(
        summaries.single.message,
        contains('3'),
        reason: 'الملخص يذكر العدد كاملاً',
      );
      expect(summaries.single.level, LogLevel.info);
    },
  );

  test(
    'ت9: مطالبة نُزعت بالتحكيم لا تُحسب «بلا رابط» ولا تُسجل تحذيراً مضللاً',
    () async {
      await addEmployee('emp-a');
      await addEmployee('emp-b');
      // مصروف موظف B بلا ختم ملكية (withdrawal_uuid) — يكفي وجوده محلياً
      // ليثبت حارس التحكيم أن سحبة موظف A تطالب بمصروف غيرها (زوج فاسد).
      await addExpense(employeeUuid: 'emp-b');
      final logger = AppwriteLogger();
      final manager = newManager();
      logger.clearLogs();

      final applied = await manager.syncSalaryWithdrawalsForTesting([
        withdrawalDoc(
          uuid: 'sw-corrupt',
          expenseUuid: 'exp-uuid-1',
          expenseId: 999,
        ),
      ]);

      expect(applied, 1);
      final row = await rowByUuid('sw-corrupt');
      expect(row, isNotNull, reason: 'السحبة تُخزَّن بلا رابط مرآة');
      expect(row!.expenseUuid, isNull, reason: 'المطالبة الفاسدة نُزعت');

      final relinkLogs = logger
          .getLogs()
          .where((l) => l.tag == 'SYNC_RELINK')
          .toList();
      expect(
        relinkLogs.where((l) => l.message.contains('نُزعت مطالبة')).length,
        1,
        reason: 'قرار التحكيم يُسجَّل مرة واحدة بسياقه الكامل',
      );
      expect(
        relinkLogs.where((l) => l.message.contains('arrived without')).length,
        0,
        reason:
            'لا رسالة «وصل بلا expenseUuid» لمطالبة نزعها التحكيم — '
            'المستند وصل بمطالبة وحُسمت بقرار مسجّل',
      );
      expect(
        relinkLogs.where((l) => l.message.contains('بلا expenseUuid')).length,
        0,
        reason: 'المطالبة المنزوعة لا تُحسب سجلاً قديماً بلا رابط',
      );
    },
  );

  test(
    'ت10: مطالبة تشير لمصروف محذوف ناعماً → لا خطأ «رفض ربط» ولا رابط مرآة',
    () async {
      await addEmployee('emp-a');
      await addEmployee('emp-b');
      // مصروفات محذوفة ناعماً لموظف B — مطالبات سحبات موظف A تشير إليها
      // (مرايا دُمجت/أزواج فاسدة من الحقبة الرقمية). حارس التحكيم لا
      // يراها أصلاً (يستثني deleted_at) فتمرّ المطالبات صامتة قبل الكتابة،
      // وكان حل المرآة يصطدم بها فيخطئ لكل مستند.
      for (final expenseUuid in ['exp-del-1', 'exp-del-2', 'exp-del-3']) {
        await addExpense(uuid: expenseUuid, employeeUuid: 'emp-b');
        await (db.update(db.expenses)
              ..where((e) => e.localUuid.equals(expenseUuid)))
            .write(const ExpensesCompanion(deletedAt: d.Value(1770000000)));
      }
      final logger = AppwriteLogger();
      final manager = newManager();
      logger.clearLogs();

      final applied = await manager.syncSalaryWithdrawalsForTesting([
        withdrawalDoc(uuid: 'sw-d1', expenseUuid: 'exp-del-1', expenseId: 999),
        withdrawalDoc(uuid: 'sw-d2', expenseUuid: 'exp-del-2', expenseId: 999),
        withdrawalDoc(uuid: 'sw-d3', expenseUuid: 'exp-del-3', expenseId: 999),
      ]);

      expect(applied, 3, reason: 'كل السحبات تُطبَّق بلا فشل');
      for (final uuid in ['sw-d1', 'sw-d2', 'sw-d3']) {
        final row = await rowByUuid(uuid);
        expect(row, isNotNull, reason: 'السحبة تُخزَّن');
        // قبل الإصلاح: خطأ «رفض ربط ... employeeUuid mismatch» لكل مستند
        // (طوفان ~90 سطراً في دفعة إنتاج واحدة 2026-11-03 22:17).
        expect(row!.expenseId, isNull, reason: 'المصروف المحذوف لا يُحلّ إليه');
        expect(
          row.expenseUuid,
          isNotNull,
          reason: 'المطالبة تبقى مخزّنة كما وصلت — لا حذف بيانات',
        );
      }
      final relinkLogs = logger
          .getLogs()
          .where((l) => l.tag == 'SYNC_RELINK')
          .toList();
      expect(
        relinkLogs.where((l) => l.message.contains('رفض ربط')).length,
        0,
        reason: 'لا خطأ لكل مستند — الحارس لم يرَ المحذوف أصلاً',
      );
      final deadSummaries = relinkLogs
          .where((l) => l.message.contains('محذوف ناعماً'))
          .toList();
      expect(deadSummaries.length, 1, reason: 'ملخص واحد للدفعة كلها');
      expect(
        deadSummaries.single.message,
        contains('3'),
        reason: 'الملخص يذكر العدد كاملاً',
      );
      expect(deadSummaries.single.level, LogLevel.info);
    },
  );

  test(
    'ت11: uuid الموظف بصيغتين مختلفتين لنفس الموظف → الربط يُكتب ولا «رفض» شكلي',
    () async {
      await addEmployee('emp-a');
      // مصروف حيّ لنفس الموظف لكن uuid الموظف مخزّن بلا شرطة — اختلاف
      // تنسيق لا هوية (الحارس يوحّد المقارنة فيسمح بالمطالبة). قبل
      // الإصلاح: المقارنة الخام في حل المرآة ترفض الربط خطأً.
      final expenseRowId = await addExpense(
        uuid: 'exp-live-1',
        employeeUuid: 'empa',
      );
      final logger = AppwriteLogger();
      final manager = newManager();
      logger.clearLogs();

      final applied = await manager.syncSalaryWithdrawalsForTesting([
        withdrawalDoc(
          uuid: 'sw-fmt',
          expenseUuid: 'exp-live-1',
          expenseId: 999,
        ),
      ]);

      expect(applied, 1);
      final row = await rowByUuid('sw-fmt');
      expect(row, isNotNull);
      expect(
        row!.expenseId,
        expenseRowId,
        reason: 'نفس الموظف بعد التوحيد → الرابط يُكتب',
      );
      final relinkLogs = logger
          .getLogs()
          .where((l) => l.tag == 'SYNC_RELINK')
          .toList();
      expect(
        relinkLogs.where((l) => l.message.contains('رفض ربط')).length,
        0,
        reason: 'اختلاف التنسيق ليس mismatch حقيقياً',
      );
    },
  );
}
