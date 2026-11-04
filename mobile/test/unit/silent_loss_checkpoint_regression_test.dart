// test/unit/silent_loss_checkpoint_regression_test.dart
//
// ✅ درع انحدار لتعميم عقد «لا يتقدّم المؤشر فوق الفشل» (2026-11-03) على
// بقية الكيانات — امتداد bookings_pull_checkpoint_regression_test.dart
// (إصلاح 724610cf الذي أصلح bookings وحدها).
//
// التشخيص الكامل قبل هذا الإصلاح — ثلاثة مسارات فقدان صامت مؤكدة:
//   A) استثناء تطبيق مستند يُبتلع بتحذير داخل حلقة المستندات → مؤشر
//      المجموعة يثبّت على max($updatedAt) للمستندات المُحضَّرة (لا
//      المطبَّقة) → المستند يفلت من كل دلتا لاحقة إلى الأبد.
//   B) BaseRepository.shouldSkip يُرجع -1 عند تعذّر حل الأب FK — وكانت
//      دوال السحب تتجاهل قيمة الإرجاع تماماً: لا استثناء أصلاً، فقط
//      «نجاح» صامت والمؤشر يتقدم فوق المستند.
//   C) يتيم الموظف في salary_cycles كان يُتخطى بـ continue — لا طابور
//      دائماً لهذا الكيان (بعكس salary_withdrawals التي لها طابور
//      SharedPreferences دائم يشفي عبر الدورات).
//
// المختبر هنا (الكود الإنتاجي نفسه عبر جسور ForTesting — بلا محاكاة):
//   1) booking_notes (المسار B): ملاحظة يتيمة (حجز أب مفقود) → تأجيل →
//      فشل إعادة المحاولة → StateError؛ الملاحظة السليمة في نفس الدفعة
//      مطبَّقة (تطبيق جزئي محفوظ)؛ الشفاء الذاتي عند وصول الحجز لاحقاً.
//   2) salary_cycles (المسار C): ✅ (2026-11-04 — وثيقة §4.1/§8.1) تحدّث
//      العقد: الدورة اليتيمة تُحفظ **دائماً** في جدول pending_links
//      (payload كامل قابل لإعادة التطبيق) بلا رمي ولا إدراج — المؤشر
//      قد يتقدم لأن الـ payload محفوظ محلياً بشكل دائم («لا يجوز التقدم
//      إذا لم يتم حفظه»)، وإعادة المحاولة بعد وصول الموظف تطبّقه
//      (_retryPendingFinancialLinks) وتعلّم الصف كمحلول بلا حذف.
//
// ⚠️ قاعدة واحدة لكل الملف (نفس قيد phase0_data_integrity_test):
// AppwriteSyncManager singleton بمُنشئ factory يتجاهل المعامل بعد أول
// إنشاء — إقفال القاعدة لكل اختبار يترك المدير يشير لقاعدة مُغلقة
// («Can't re-open a database after closing it»)، فكان الاختبار الثاني
// يفشل بعزلٍ زائف. التنظيف بين الاختبارين (الأبناء قبل الآباء).

// ignore_for_file: lines_longer_than_80_chars

import 'package:appwrite/models.dart' as models;
import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:marina_hotel_mobile/services/adapters/adapter_registry.dart';
import 'package:marina_hotel_mobile/services/appwrite_service.dart';
import 'package:marina_hotel_mobile/services/appwrite_sync_manager.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';

const int _kBaseEpochSec = 1760000000;

models.Document _bookingDoc({
  required String uuid,
  required String roomNumber,
  required int lastModified,
}) {
  return models.Document(
    $id: uuid,
    $sequence: 0,
    $collectionId: 'bookings',
    $databaseId: 'marina',
    $createdAt: '2026-11-01T00:00:00.000Z',
    $updatedAt: '2026-11-01T12:00:00.000Z',
    $permissions: const <String>[],
    data: <String, dynamic>{
      'localUuid': uuid,
      'roomNumber': roomNumber,
      'guestName': 'ضيف اختبار',
      'guestPhone': '0500000000',
      'guestNationality': 'يمني',
      'checkinDate': '2026-11-01T14:00:00.000Z',
      'status': 'نشط',
      'expectedNights': 3,
      'createdAt': _kBaseEpochSec,
      'lastModified': lastModified,
      'vectorClock': '{}',
      'deviceId': 'device-A',
    },
  );
}

models.Document _noteDoc({
  required String uuid,
  required String bookingUuid,
  required int lastModified,
}) {
  return models.Document(
    $id: uuid,
    $sequence: 0,
    $collectionId: 'booking_notes',
    $databaseId: 'marina',
    $createdAt: '2026-11-01T00:00:00.000Z',
    $updatedAt: '2026-11-01T12:00:00.000Z',
    $permissions: const <String>[],
    data: <String, dynamic>{
      'localUuid': uuid,
      'bookingUuidCache': bookingUuid,
      'noteText': 'ملاحظة اختبار',
      'alertType': 'معلومة',
      'createdAt': _kBaseEpochSec,
      'lastModified': lastModified,
      'vectorClock': '{}',
      'deviceId': 'device-A',
    },
  );
}

models.Document _cycleDoc({
  required String uuid,
  required String employeeUuid,
  required int employeeId,
  required int lastModified,
}) {
  return models.Document(
    $id: uuid,
    $sequence: 0,
    $collectionId: 'salary_cycles',
    $databaseId: 'marina',
    $createdAt: '2026-11-01T00:00:00.000Z',
    $updatedAt: '2026-11-01T12:00:00.000Z',
    $permissions: const <String>[],
    data: <String, dynamic>{
      'localUuid': uuid,
      'employeeUuid': employeeUuid,
      'employeeId': employeeId,
      'cycleName': 'دورة اختبار',
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

  // ⚠️ قاعدة واحدة للملف كله (قيد singleton المدير — انظر الترويسة).
  setUpAll(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    AdapterRegistry.initialize(db);
  });

  tearDownAll(() async {
    await db.close();
  });

  // تنظيف بين الاختبارين — الأبناء قبل الآباء لقيود FK (سحب الحجوزات
  // النشطة يبني لياليها عبر refreshForBookingId، فحذف bookings يتطلب
  // مسح booking_nights أولاً؛ بقية الأبناء احترازياً).
  setUp(() async {
    await db.delete(db.bookingNotes).go();
    await db.delete(db.bookingNights).go();
    await db.delete(db.bookingPriceAdjustments).go();
    await db.delete(db.payments).go();
    await db.delete(db.debts).go();
    await db.delete(db.salaryCycles).go();
    await db.delete(db.bookings).go();
    await db.delete(db.rooms).go();
    await db.delete(db.outbox).go();
  });

  test(
    'درع فقدان booking_notes الصامت (المسار B): تخطّي adapter بسبب أب مفقود '
    'يُؤجَّل ثم يفشل المهمة — والملاحظة السليمة تطبَّق وتُشفى اليتيمة لاحقاً',
    () async {
      final manager = AppwriteSyncManager(
        appwriteService: AppwriteService(),
        database: db,
      );

      // غرفة 211 + حجزها. الملاحظة اليتيمة تشير لحجز غير موجود.
      await db
          .into(db.rooms)
          .insert(
            const RoomsCompanion(
              roomNumber: d.Value('211'),
              type: d.Value('عادية'),
              price: d.Value(120.0),
              status: d.Value('شاغرة'),
              localUuid: d.Value('room-uuid-211'),
              createdAt: d.Value(_kBaseEpochSec),
              updatedAt: d.Value(_kBaseEpochSec),
              lastModified: d.Value(_kBaseEpochSec),
            ),
          );
      await manager.syncBookingsForTesting([
        _bookingDoc(
          uuid: 'booking-uuid-good',
          roomNumber: '211',
          lastModified: _kBaseEpochSec + 10,
        ),
      ]);

      final goodNote = _noteDoc(
        uuid: 'note-uuid-good',
        bookingUuid: 'booking-uuid-good',
        lastModified: _kBaseEpochSec + 20,
      );
      final orphanNote = _noteDoc(
        uuid: 'note-uuid-orphan',
        bookingUuid: 'booking-uuid-missing',
        lastModified: _kBaseEpochSec + 30,
      );

      // ═══ الفصل A — المسار B: -1 من shouldSkip يُؤجَّل ثم يفشل المهمة ═══
      await expectLater(
        manager.syncBookingNotesForTesting([goodNote, orphanNote]),
        throwsA(
          isA<StateError>()
              .having((e) => e.message, 'message', contains('booking_notes'))
              .having(
                (e) => e.message,
                'message',
                contains('checkpoint must not advance'),
              ),
        ),
        reason:
            'الملاحظة اليتيمة (حجز أب مفقود → BaseRepository.shouldSkip يرجع '
            '-1) يجب أن تفشل المهمة كي يسجّلها المحرك في failedCollections '
            'ولا يثبّت مؤشر booking_notes فوقها — قبل الإصلاح كانت القيمة '
            '-1 تُتجاهل تماماً فتُفقد الملاحظة نهائياً بلا أي إشارة',
      );

      // التطبيق الجزئي محفوظ: السليمة وصلت رغم فشل زميلتها.
      final goodRow = await _noteByUuid(db, 'note-uuid-good');
      expect(
        goodRow,
        isNotNull,
        reason: 'التطبيق الجزئي محفوظ: الملاحظة السليمة وصلت رغم فشل اليتيمة',
      );
      expect(goodRow!.bookingId, isNotNull);

      // اليتيمة غير مدرَجة — لا صف نصف مكسور.
      final orphanRow = await _noteByUuid(db, 'note-uuid-orphan');
      expect(
        orphanRow,
        isNull,
        reason: 'الملاحظة اليتيمة لم تُدرَج — ستصل كاملة عند وصول الحجز',
      );

      // ═══ الفصل B — الشفاء الذاتي: وصول الأب في دورة لاحقة ═══
      await manager.syncBookingsForTesting([
        _bookingDoc(
          uuid: 'booking-uuid-missing',
          roomNumber: '211',
          lastModified: _kBaseEpochSec + 40,
        ),
      ]);

      final processed = await manager.syncBookingNotesForTesting([
        goodNote,
        orphanNote,
      ]);
      expect(
        processed,
        greaterThanOrEqualTo(1),
        reason: 'بعد وصول الحجز الأب، الدفعة تُطبَّق نظيفاً ولا يوجد رمي',
      );
      final orphanAfterHeal = await _noteByUuid(db, 'note-uuid-orphan');
      expect(
        orphanAfterHeal,
        isNotNull,
        reason:
            'بعد وصول الحجز الأب، الملاحظة اليتيمة تُطبَّق — تصميم «لا يتقدم '
            'المؤشر فوق الفشل» يُشفى ذاتياً ولا يعلّق المزامنة',
      );
    },
  );

  test('درع فقدان salary_cycles الصامت (المسار C): يتيم الموظف يُحفظ دائماً '
      'في pending_links (وثيقة §8.1) — ويُطبَّق عند وصول الموظف', () async {
    // مُنشئ factory: نفس نسخة الاختبار الأول (قاعدة الملف المشتركة،
    // لا تزال مفتوحة — انظر الترويسة).
    final manager = AppwriteSyncManager(
      appwriteService: AppwriteService(),
      database: db,
    );

    // لا موظفين محلياً إطلاقاً — الدورة يتيمة حكماً.
    final orphanCycle = _cycleDoc(
      uuid: 'cycle-uuid-1',
      employeeUuid: 'emp-uuid-missing',
      employeeId: 9,
      lastModified: _kBaseEpochSec + 10,
    );

    // ✅ العقد الجديد (وثيقة §8.1): لا رمي — اليتيم يُحفظ في pending_links
    // ثم يمكن للمؤشر التقدم لأن payload محفوظ محلياً بشكل دائم.
    final processed = await manager.syncSalaryCyclesForTesting([orphanCycle]);
    expect(processed, 0, reason: 'لم يُطبَّق شيء — لكن بلا فقدان (انظر أسفل)');

    // الدورة لم تُدرَج في جدولها — لكنها **محفوظة دائماً** في pending_links.
    expect(
      await _cycleByUuid(db, 'cycle-uuid-1'),
      isNull,
      reason: 'لم تُدرَج في salary_cycles بعد — الأب غير موجود',
    );
    final pendingRow = await (db.select(db.pendingLinks)
          ..where((r) => r.entity.equals('salary_cycles'))
          ..where((r) => r.localUuid.equals('cycle-uuid-1'))
          ..limit(1))
        .getSingleOrNull();
    expect(pendingRow, isNotNull,
        reason: 'الـ payload محفوظ دائماً — لا فقدان صامت (§1.3-1/§8.1)');
    expect(pendingRow!.parentEntity, 'employees');
    expect(pendingRow.parentUuid, 'emp-uuid-missing');
    expect(pendingRow.resolvedAt, isNull);
    expect(pendingRow.attempts, 1);

    // إعادة الاستدعاء تزيد عدّاد المحاولات (upsert) — بلا صف ثانٍ ولا رمي:
    // العقد مستقر عبر الدورات حتى يصل الموظف.
    await manager.syncSalaryCyclesForTesting([orphanCycle]);
    final rows = await db.select(db.pendingLinks).get();
    expect(rows.length, 1, reason: 'القيد الفريد (entity, local_uuid)');
    expect(rows.first.attempts, 2);

    // ═══ الشفاء الذاتي: وصول الموظف ثم إعادة محاولة pending links ═══
    await db.into(db.employees).insert(
          EmployeesCompanion.insert(
            localUuid: 'emp-uuid-missing',
            createdAt: _kBaseEpochSec,
            updatedAt: _kBaseEpochSec,
            lastModified: _kBaseEpochSec,
            name: 'موظف متأخر الوصول',
            basicSalary: 1000,
            status: 'active',
          ),
        );

    final healed = await manager.retryPendingFinancialLinksForTesting();
    expect(healed, greaterThanOrEqualTo(1),
        reason: 'بعد وصول الموظف يُطبَّق الـ payload المحفوظ (§8.1)');

    final cycleAfterHeal = await _cycleByUuid(db, 'cycle-uuid-1');
    expect(cycleAfterHeal, isNotNull,
        reason: 'الدورة تطبَّقت من pending_links عند وصول الموظف');
    final emp = await (db.select(db.employees)
          ..where((e) => e.localUuid.equals('emp-uuid-missing'))
          ..limit(1))
        .getSingle();
    expect(cycleAfterHeal!.employeeId, emp.id,
        reason: 'employeeId اشتُق من employeeUuid (UUID-first — §5.1)');

    final resolvedRow = await (db.select(db.pendingLinks)
          ..where((r) => r.entity.equals('salary_cycles'))
          ..where((r) => r.localUuid.equals('cycle-uuid-1'))
          ..limit(1))
        .getSingleOrNull();
    expect(resolvedRow, isNotNull);
    expect(resolvedRow!.resolvedAt, isNotNull,
        reason: 'الصف يُعلَّم محلولاً — الأثر يبقى بلا حذف (§1.3-1)');
  });
}

Future<BookingNote?> _noteByUuid(AppDatabase db, String uuid) {
  return (db.select(
    db.bookingNotes,
  )..where((t) => t.localUuid.equals(uuid))).getSingleOrNull();
}

Future<SalaryCycle?> _cycleByUuid(AppDatabase db, String uuid) {
  return (db.select(
    db.salaryCycles,
  )..where((t) => t.localUuid.equals(uuid))).getSingleOrNull();
}
