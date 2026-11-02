// test/unit/pull_contract_expenses_test.dart
//
// ✅ (2026-11-05) درع انحدار: تعميم عقد «لا يتقدّم المؤشر فوق الفشل» على
// `expenses` (و`cash_transactions`/`guest_infos`/بقية الكيانات).
//
// قبل هذا الإصلاح: فشل تطبيق مصروف كان يُسجَّل تحذيراً فقط (المسار A)، أو
// يُعاد `-1` من BaseRepository.shouldSkip ويُتجاهل (المسار B) — فيتقدّم مؤشر
// مجموعة expenses إلى max($updatedAt) للمستندات المُحضَّرة، ويخرج المصروف
// الفاشل من كل دلتا لاحقة إلى الأبد (فقدان دائم من التقارير المالية).
//
// المُختبَر هنا بالكود الإنتاجي نفسه (بلا محاكاة) عبر جسر
// [AppwriteSyncManager.syncExpensesForTesting]:
//   - مصروف سليم في نفس الدفعة يُطبَّق ويُحفظ.
//   - مصروف تالف (بلا amount ⇒ NOT NULL) يرفع StateError كي لا يتقدّم المؤشر.
//
// ⚠️ قاعدة واحدة للملف: AppwriteSyncManager بمُنشئ factory singleton يتجاهل
// المعامل بعد الإنشاء الأول (نفس قيد silent_loss_checkpoint_regression_test).

// ignore_for_file: lines_longer_than_80_chars

import 'package:appwrite/models.dart' as models;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:marina_hotel_mobile/services/adapters/adapter_registry.dart';
import 'package:marina_hotel_mobile/services/appwrite_service.dart';
import 'package:marina_hotel_mobile/services/appwrite_sync_manager.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';

const int _kBaseEpochSec = 1760000000;

models.Document _expenseDoc({
  required String uuid,
  required int lastModified,
  double? amount,
}) {
  return models.Document(
    $id: uuid,
    $sequence: 0,
    $collectionId: 'expenses',
    $databaseId: 'marina',
    $createdAt: '2026-11-01T00:00:00.000Z',
    $updatedAt: '2026-11-01T12:00:00.000Z',
    $permissions: const <String>[],
    data: <String, dynamic>{
      'localUuid': uuid,
      'expenseType': 'other',
      'description': 'مصروف اختبار',
      'date': '2026-11-01',
      // الحقل مقصود غيابه في المستند التالف: عمود amount في SQLite
      // NOT NULL بلا قيمة افتراضية ⇒ فشل تطبيق حقيقي في القاعدة.
      if (amount != null) 'amount': amount,
      'createdAt': _kBaseEpochSec,
      'lastModified': lastModified,
      'vectorClock': '{}',
      'deviceId': 'device-A',
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUpAll(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    AdapterRegistry.initialize(db);
  });

  tearDownAll(() async {
    await db.close();
  });

  setUp(() async {
    await db.delete(db.expenses).go();
  });

  test(
    'مصروف تالف لا يُسجَّل «نجاحاً»: الدفعة ترمي StateError والمصروف السليم يُطبَّق',
    () async {
      final manager = AppwriteSyncManager(
        appwriteService: AppwriteService(),
        database: db,
      );

      final good = _expenseDoc(
        uuid: 'expense-uuid-good',
        amount: 150.0,
        lastModified: _kBaseEpochSec + 10,
      );
      final corrupt = _expenseDoc(
        uuid: 'expense-uuid-corrupt',
        lastModified: _kBaseEpochSec + 20,
      );

      await expectLater(
        manager.syncExpensesForTesting([good, corrupt]),
        throwsA(isA<StateError>()),
        reason:
            'الفشل يجب أن يصل للمحرك كي لا يتقدّم مؤشر expenses فوق المصروف '
            '(عقد «لا فقدان صامت»)',
      );

      final rows = await db.select(db.expenses).get();
      final uuids = rows.map((r) => r.localUuid).toSet();
      expect(
        uuids,
        contains('expense-uuid-good'),
        reason: 'التطبيق الجزئي محفوظ — المصروف السليم لا يُلغى بفشل غيره',
      );
      expect(
        uuids,
        isNot(contains('expense-uuid-corrupt')),
        reason: 'المستند التالف لم يُطبَّق فعلاً، لذا لا يجوز اعتباره ناجحاً',
      );
    },
  );

  test('دفعة سليمة كاملة لا ترمي (لا إيجابيات كاذبة)', () async {
    final manager = AppwriteSyncManager(
      appwriteService: AppwriteService(),
      database: db,
    );

    final applied = await manager.syncExpensesForTesting([
      _expenseDoc(
        uuid: 'expense-uuid-ok-1',
        amount: 20.0,
        lastModified: _kBaseEpochSec + 30,
      ),
      _expenseDoc(
        uuid: 'expense-uuid-ok-2',
        amount: 40.0,
        lastModified: _kBaseEpochSec + 40,
      ),
    ]);

    expect(applied, 2);
    final rows = await db.select(db.expenses).get();
    expect(rows.length, 2);
  });
}
