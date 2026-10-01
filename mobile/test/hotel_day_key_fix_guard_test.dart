// اختبارات حارس بصمة HotelDayKeyFixService (2026-09-30).
//
// تثبيت سلوك الحارس:
// 1) أول تشغيل يفحص التسعة (لا طوابع) — والثاني يتخطاها كلها.
// 2) تلوث جدول عبر السحب يعيد فحص فحوصه فقط.
// 3) تغيير البيانات (صف جديد) يبطل الطابع عبر البصمة.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/hotel_day_key_fix_service.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.customSelect('SELECT 1').get();
    HotelDayKeyFixService.instance.resetForTesting();
  });

  tearDown(() async {
    await db.close();
  });

  test('first run sweeps all 9, second run skips all 9', () async {
    final svc = HotelDayKeyFixService.instance;

    await svc.runIfNeeded(db);
    expect(svc.lastSweepRan.length, 9);
    expect(svc.lastSweepRan.values.every((ran) => ran), isTrue);

    svc.resetForTesting();
    await svc.runIfNeeded(db);
    expect(svc.lastSweepRan.length, 9);
    expect(svc.lastSweepRan.values.every((ran) => !ran), isTrue);
  });

  test('sync-dirty table re-sweeps only its own sweeps', () async {
    final svc = HotelDayKeyFixService.instance;
    await svc.runIfNeeded(db);

    // تلوث payments عبر مسار السحب الحقيقي (ذاكرة + حفظ مؤجل).
    HotelDayKeyFixService.markTableDirtyFromSync('payments');
    // حفظ حتمي يحاكي الإقلاع التالي (ذاكرة فارغة + تلوث مخزّن).
    await HotelDayKeyFixService.flushDirtyForTesting();
    svc.resetForTesting();

    await svc.runIfNeeded(db);
    expect(svc.lastSweepRan['payments'], isTrue);
    expect(svc.lastSweepRan['expenses'], isFalse);
    expect(svc.lastSweepRan['audit'], isFalse);
    expect(svc.lastSweepRan['withdrawals'], isFalse);
  });

  test('dirty shared sweep re-runs links but not unrelated sweeps', () async {
    final svc = HotelDayKeyFixService.instance;
    await svc.runIfNeeded(db);

    // employees مصدر مشترك: links + withdrawals_uuid يعادان، payments لا.
    HotelDayKeyFixService.markTableDirtyFromSync('employees');
    await HotelDayKeyFixService.flushDirtyForTesting();
    svc.resetForTesting();

    await svc.runIfNeeded(db);
    expect(svc.lastSweepRan['links'], isTrue);
    expect(svc.lastSweepRan['withdrawals_uuid'], isTrue);
    expect(svc.lastSweepRan['payments'], isFalse);
    expect(svc.lastSweepRan['expenses'], isFalse);
  });

  test('new row invalidates fingerprint even without dirty flag', () async {
    final svc = HotelDayKeyFixService.instance;
    await svc.runIfNeeded(db);
    svc.resetForTesting();

    // صف جديد بلا أي تلوث: COUNT يتغير → البصمة تكشف → فحص.
    await db
        .into(db.expenses)
        .insert(
          ExpensesCompanion.insert(
            localUuid: 'fp-test-uuid-1',
            createdAt: 1,
            updatedAt: 2,
            lastModified: 2,
            date: '2026-09-30',
            amount: 10,
            expenseType: 'test',
            description: 'fingerprint probe',
          ),
        );

    await svc.runIfNeeded(db);
    expect(svc.lastSweepRan['expenses'], isTrue);
    expect(svc.lastSweepRan['links'], isTrue);
    expect(svc.lastSweepRan['payments'], isFalse);
  });
}
