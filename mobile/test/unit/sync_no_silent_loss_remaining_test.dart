// test/unit/sync_no_silent_loss_remaining_test.dart
//
// ✅ (2026-11-03) درع انحدار للكيانات التي كانت **ما زالت** تبتلع الفشل بعد
// تعميم عقد «لا يتقدّم المؤشر فوق الفشل» على بقية المجموعات:
//
//   1) `app_settings` — كان فشل تطبيق مستند الإعدادات يُسجَّل تحذيراً فقط
//      (وكذلك تعذّر فكّ `config_json`) ثم يتقدّم المؤشر ⇒ إعداد لا يُطبَّق
//      على هذا الجهاز إلى الأبد (رموز واتساب/تلجرام قديمة، تقارير خاطئة)
//      بلا أي إشارة. المجموعة غير حرجة في المحرك، لذا رميها لا يُسقط بقية
//      المجموعات — لكنه يمنع تقدّم مؤشرها فتُعاد المحاولة.
//
//   2) `price_adjustments` — بعد تطبيق تعديل السعر بنجاح، كان فشل **إعادة
//      حساب الحجوزات المشتقة** يُبتلع (تحذير فقط) فتبقى الإجماليات المالية
//      مغلوطة على هذا الجهاز بلا مسار شفاء.
//
// المُختبَر بالكود الإنتاجي نفسه بلا محاكاة عبر جسري
// [AppwriteSyncManager.syncAppSettingsForTesting] و
// [AppwriteSyncManager.syncPriceAdjustmentsForTesting].
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

models.Document _doc({
  required String collectionId,
  required String uuid,
  required Map<String, dynamic> data,
  int lastModified = _kBaseEpochSec + 10,
}) {
  return models.Document(
    $id: uuid,
    $sequence: 0,
    $collectionId: collectionId,
    $databaseId: 'marina',
    $createdAt: '2026-11-01T00:00:00.000Z',
    $updatedAt: '2026-11-01T12:00:00.000Z',
    $permissions: const <String>[],
    data: <String, dynamic>{
      'localUuid': uuid,
      'createdAt': _kBaseEpochSec,
      'lastModified': lastModified,
      'vectorClock': '{}',
      'deviceId': 'device-A',
      ...data,
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
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await db.delete(db.priceAdjustments).go();
    await db.delete(db.rooms).go();
  });

  group('app_settings — لا ابتلاع', () {
    test('مستند إعدادات صالح يُطبَّق في SharedPreferences', () async {
      final manager = AppwriteSyncManager(
        appwriteService: AppwriteService(),
        database: db,
      );

      final applied = await manager.syncAppSettingsForTesting([
        _doc(
          collectionId: 'app_settings',
          uuid: 'settings-ok',
          data: <String, dynamic>{'telegram_enabled': true},
        ),
      ]);

      expect(applied, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('telegram_enabled'), isTrue);
    });

    test('مستند تالف يرفع StateError كي لا يتقدّم المؤشر فوقه', () async {
      final manager = AppwriteSyncManager(
        appwriteService: AppwriteService(),
        database: db,
      );

      // 'yes' نص: `value as bool` يرمي TypeError داخل التطبيق.
      final corrupt = _doc(
        collectionId: 'app_settings',
        uuid: 'settings-corrupt',
        data: <String, dynamic>{'telegram_enabled': 'yes'},
      );

      await expectLater(
        manager.syncAppSettingsForTesting([corrupt]),
        throwsA(isA<StateError>()),
        reason:
            'قبل الإصلاح كان الخطأ تحذيراً فقط ويتقدّم المؤشر ⇒ إعداد مفقود '
            'بصمت إلى الأبد',
      );
    });
  });

  group('price_adjustments — فشل إعادة الحساب المشتق', () {
    test(
      'فشل إعادة حساب الحجوزات بعد تطبيق التعديل يمنع تقدّم المؤشر',
      () async {
        await db
            .into(db.rooms)
            .insert(
              RoomsCompanion.insert(
                localUuid: 'room-uuid-1',
                roomNumber: '101',
                type: 'single',
                price: 100.0,
                status: 'available',
                createdAt: _kBaseEpochSec,
                updatedAt: _kBaseEpochSec,
                lastModified: _kBaseEpochSec,
              ),
            );

        final manager = AppwriteSyncManager(
          appwriteService: AppwriteService(),
          database: db,
        );

        // newValue كنص رقمي: المحوّل يفكّه ويُخزّنه (150.0) فينجح الإدراج،
        // لكن كتلة إعادة الحساب تقرأ القيمة الخام من بيانات المستند البعيدة
        // وتُنفّذ `as num` ⇒ TypeError ⇒ مسار الفشل الجديد.
        final doc = _doc(
          collectionId: 'price_adjustments',
          uuid: 'pa-uuid-1',
          data: <String, dynamic>{
            'targetType': 'room',
            'targetUuid': 'room-uuid-1',
            'adjustmentType': 'increase',
            'previousValue': '100',
            'newValue': '150',
            'effectiveDate': '2026-11-01',
            'appliedBy': 'device-A',
          },
        );

        await expectLater(
          manager.syncPriceAdjustmentsForTesting([doc]),
          throwsA(isA<StateError>()),
          reason:
              'فشل إعادة الحساب يعني بقاء إجماليات الحجز مغلوطة محلياً — يجب '
              'أن يُعاد السحب بدل تقدّم المؤشر فوقها',
        );

        final rows = await db.select(db.priceAdjustments).get();
        expect(
          rows.length,
          1,
          reason: 'التعديل نفسه طُبِّق — الفشل من إعادة الحساب لا من الإدراج',
        );

        final room = await (db.select(
          db.rooms,
        )..where((r) => r.localUuid.equals('room-uuid-1'))).getSingle();
        expect(
          room.price,
          100.0,
          reason: 'لم يُحدَّث السعر: الرمي حدث قبل كتابة السعر الجديد',
        );
      },
    );

    test('تعديل بلا هدف غرفة لا يرمي (لا إيجابيات كاذبة)', () async {
      final manager = AppwriteSyncManager(
        appwriteService: AppwriteService(),
        database: db,
      );

      final doc = _doc(
        collectionId: 'price_adjustments',
        uuid: 'pa-uuid-2',
        data: <String, dynamic>{
          'targetType': 'booking',
          'targetUuid': 'booking-uuid-x',
          'adjustmentType': 'increase',
          'previousValue': 100.0,
          'newValue': 150.0,
          'effectiveDate': '2026-11-01',
          'appliedBy': 'device-A',
        },
      );

      final applied = await manager.syncPriceAdjustmentsForTesting([doc]);
      expect(applied, 1);
    });
  });
}
