// test/unit/salary_withdrawal_relink_identity_regression_test.dart
//
// ✅ (2026-11-04) اختبارات انحدار: هوية رابط المرآة سحبة→مصروف.
//
// المشكلة المُثبتة من دفعة الإنتاج (2026-11-03 22:17 — 79 رسالة
// «رفض ربط السحبة #836/#838/#839»): مسار الربط كان يستقبل قيمة إرجاع
// upsertFromJson كرقم صف، لكن في مسار ON CONFLICT DO UPDATE تعيد
// last_insert_rowid() رقم آخر صف أُدرج فعلياً على الاتصال — لا الصف
// المُحدَّث — فيُختم/يُفحص صف خاطئ مراراً (نفس رقم السحبة المحلية
// يتكرر لعشرات expenseUuid المختلفة).
//
// العقد المُثبَّت هنا (الكود الإنتاجي نفسه عبر syncSalaryWithdrawalsForTesting
// وrelinkMirrorExpenseIdsForTesting):
//  ت1) دفعة فيها إدراج جديد يليه تحديث لسحبة قائمة تحمل مطالبة رابط —
//      الرابط يُكتب على السحبة المُحدَّثة نفسها (هويتها عبر localUuid)
//      لا على السحبة المُدرجة حديثاً التي كان last_insert_rowid
//      يشير إليها (جذر خطأ الإنتاج #836/#838/#839).
//  ت2) مصروف مخزّن بصيغة UUID مختلفة (حالة أحرف/شرطات) عن المطالبة
//      الواردة → الربط يُحل ويُكتب (المطابقة المعيارية، لا الخام).
//  ت3) إعادة الربط المؤجلة (_relinkMirrorExpenseIds) تحل روابط بصيغ
//      UUID مختلطة مخزّنة قبل توحيد الشكل (شرطات/حالة).
//  ت4) إعادة الربط المؤجلة لا تربط سحبة بمصروف موظف مختلف (الحارس
//      داخل SQL الشفاء يعمل بعد التطبيع أيضاً).

import 'dart:io';

import 'package:appwrite/models.dart' as models;
import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/adapters/adapter_registry.dart';
import 'package:marina_hotel_mobile/services/appwrite_service.dart';
import 'package:marina_hotel_mobile/services/appwrite_sync_manager.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ✅ مجلد مستقر طوال عمر ملف الاختبار + mock خاص لـ path_provider —
  // ClientIO.init() في Appwrite SDK يعمل fire-and-forget وينشئ
  // <documents>/cookies (نفس نمط salary_withdrawal_mirror_claim_regression).
  late final Directory stableDocsDir;

  setUpAll(() async {
    stableDocsDir = await Directory.systemTemp.createTemp(
      'sw_relink_identity_test_',
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
    SharedPreferences.setMockInitialValues({});
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

  test('ت1: إدراج جديد يليه تحديث سحبة قائمة تحمل مطالبة → الرابط يُكتب على '
      'المُحدَّثة نفسها لا على المُدرجة حديثاً (جذر #836/#838/#839)', () async {
    final empId = await addEmployee('emp-a');
    final expenseId = await addExpense(
      employeeUuid: 'emp-a',
      withdrawalUuid: 'sw-orig',
    );
    // سحبة قائمة بلا مطالبة — سيأتي مستندها لاحقاً في الدفعة حاملاً
    // المطالبة (تحديث conflict-update، لا إدراج).
    await addWithdrawal(
      uuid: 'sw-orig',
      employeeId: empId,
      employeeUuid: 'emp-a',
      amount: 3000,
    );

    final manager = newManager();
    // الترتيب مقصود: الإدراج الجديد أولاً (يثبّت last_insert_rowid
    // على صفه) ثم التحديث — قبل الإصلاح كان الربط يستقبل رقم الصف
    // المُدرج حديثاً فيختمه خطأً (نفس موظف → ختم صامت خاطئ).
    final applied = await manager.syncSalaryWithdrawalsForTesting([
      withdrawalDoc(uuid: 'sw-new', amount: 500, date: '2026-06-01'),
      withdrawalDoc(uuid: 'sw-orig', expenseUuid: 'exp-uuid-1', expenseId: 999),
    ]);

    expect(applied, 2);
    final updated = await rowByUuid('sw-orig');
    expect(updated, isNotNull);
    expect(
      updated!.expenseId,
      expenseId,
      reason: 'الرابط يُكتب على السحبة المُحدَّثة صاحبة المطالبة',
    );
    expect(updated.expenseUuid, 'exp-uuid-1');
    final inserted = await rowByUuid('sw-new');
    expect(inserted, isNotNull);
    expect(
      inserted!.expenseId,
      isNull,
      reason:
          'السحبة المُدرجة حديثاً لا تُختم برابط لا تملكه — '
          'كان last_insert_rowid يشير إليها قبل الإصلاح',
    );
  });

  test('ت2: مصروف مخزّن بصيغة UUID مختلفة (حالة/شرطات) عن المطالبة → الربط '
      'يُحل ويُكتب بالمطابقة المعيارية', () async {
    await addEmployee('emp-a');
    // المصروف مخزّن بأحرف كبيرة مع شرطات (حقبة قبل توحيد الشكل)،
    // والمطالبة الواردة بلا شرطات وبأحرف صغيرة — هوية واحدة.
    final expenseId = await addExpense(
      uuid: '9F86D081-8842-4D75-A1C6-1700DA11F1AB',
      employeeUuid: 'EMP-A',
      withdrawalUuid: 'sw-fmt',
    );

    final manager = newManager();
    final applied = await manager.syncSalaryWithdrawalsForTesting([
      withdrawalDoc(
        uuid: 'sw-fmt',
        expenseUuid: '9f86d08188424d75a1c61700da11f1ab',
      ),
    ]);

    expect(applied, 1);
    final w = await rowByUuid('sw-fmt');
    expect(w, isNotNull);
    expect(
      w!.expenseId,
      expenseId,
      reason: 'اختلاف الشرطات/حالة الأحرف لا ينشئ هوية جديدة',
    );
  });

  test(
    'ت3: إعادة الربط المؤجلة تحل روابط بصيغ UUID مختلطة مخزّنة قبل توحيد الشكل',
    () async {
      final empId = await addEmployee('emp-a');
      // سحبة وصلت بمطالبتها قبل وصول المصروف (expenseNotLocal)،
      // والمصروف وصل لاحقاً بصيغة مختلفة عن المخزّن على السحبة.
      await addWithdrawal(
        uuid: 'sw-late',
        employeeId: empId,
        employeeUuid: 'emp-a',
        expenseUuid: '9F86D081-8842-4D75-A1C6-1700DA11F1AB',
      );
      final expenseId = await addExpense(
        uuid: '9f86d08188424d75a1c61700da11f1ab',
        employeeUuid: 'emp-a',
      );

      final manager = newManager();
      final relinked = await manager.relinkMirrorExpenseIdsForTesting();

      expect(relinked, greaterThan(0));
      final w = await rowByUuid('sw-late');
      expect(w, isNotNull);
      expect(
        w!.expenseId,
        expenseId,
        reason: 'مسار الشفاء يستخدم نفس المطابقة المعيارية',
      );
    },
  );

  test(
    'ت4: إعادة الربط المؤجلة لا تربط سحبة بمصروف موظف مختلف (الحارس داخل SQL الشفاء)',
    () async {
      final empA = await addEmployee('emp-a');
      await addEmployee('emp-b');
      await addWithdrawal(
        uuid: 'sw-mm',
        employeeId: empA,
        employeeUuid: 'emp-a',
        expenseUuid: 'exp-mm',
      );
      await addExpense(uuid: 'exp-mm', employeeUuid: 'emp-b');

      final manager = newManager();
      final relinked = await manager.relinkMirrorExpenseIdsForTesting();

      expect(relinked, 0);
      final w = await rowByUuid('sw-mm');
      expect(w, isNotNull);
      expect(
        w!.expenseId,
        isNull,
        reason: 'مصروف موظف مختلف لا يُربط حتى في مسار الشفاء',
      );
    },
  );
}
