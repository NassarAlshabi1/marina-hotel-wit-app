// test/unit/bookings_pull_checkpoint_regression_test.dart
//
// ✅ درع انحدار لفقدان bookings الصامت (2026-11-02) — تقرير المستخدم:
// «في شاشة dashboard زر سحب التغييرات لم يتم سحب التغييرات bookings».
//
// السبب الجذري (pre-fix):
//   _syncBookings كان يسجّل فشل تطبيق مستند الحجز تحذيراً فقط
//   (logWarning) ثم يعود طبيعياً → UnifiedPullEngine يثبّت مؤشر مجموعة
//   bookings على أقصى $updatedAt للمستندات المُحضّرة (لا المطبَّقة) →
//   أي حجز فشل تطبيقه يفلت من كل دلتا لاحقة ($updatedAt < المؤشر)
//   إلى الأبد — فقدان صامت دائم، والزر يعرض «نجاح».
//
// الإصلاح المختبر هنا (الكود الإنتاجي نفسه بلا محاكاة — نفس منهجية
// pull_commit_visibility_test.dart عبر جسر syncBookingsForTesting):
//
//   A) حجز بغرفة غير موجودة (فشل FK) → StateError تُرفع بعد مرحلتي
//      المعالجة والتأجيل، مع بقاء الحجوزات السليمة في نفس الدفعة
//      مطبَّقة (تطبيق جزئي محفوظ) وعدم إدراج الحجز الفاشل.
//      المحرك (run) يلتقطها → failedCollections=['bookings'] → مؤشر
//      المجموعة لا يتقدم → إعادة المحاولة في الدورة التالية.
//   B) وصول الأب (الغرفة) لاحقاً → نفس الدفعة تُطبَّق نظيفاً — إثبات أن
//      تصميم «لا تتقدم فوق الفشل» يُشفى ذاتياً ولا يعلّق المزامنة.
//   C) عقد SyncResult: failedCollections/hasPullFailures — الأساس الذي
//      يعتمد عليه زر لوحة التحكم الآن لعرض «سحب جزئي» بدل النجاح الكاذب.

// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

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

Future<void> _seedRoom(AppDatabase db, String roomNumber, String uuid) async {
  await db
      .into(db.rooms)
      .insert(
        RoomsCompanion(
          roomNumber: d.Value(roomNumber),
          type: const d.Value('عادية'),
          price: const d.Value(120.0),
          status: const d.Value('شاغرة'),
          localUuid: d.Value(uuid),
          createdAt: const d.Value(_kBaseEpochSec),
          updatedAt: const d.Value(_kBaseEpochSec),
          lastModified: const d.Value(_kBaseEpochSec),
        ),
      );
}

Future<Booking?> _bookingByUuid(AppDatabase db, String uuid) {
  return (db.select(
    db.bookings,
  )..where((b) => b.localUuid.equals(uuid))).getSingleOrNull();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'درع فقدان bookings الصامت: فشل التطبيق يرفع StateError (المؤشر لا يتقدم) والدفعة تُشفى عند وصول الأب',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tmpDir = await Directory.systemTemp.createTemp(
        'bookings_pull_regression',
      );
      addTearDown(() async {
        try {
          await tmpDir.delete(recursive: true);
        } catch (_) {
          // أفضل-جهد — أنظمة CI المختلفة قد تبقي مقابض مؤقتة.
        }
      });

      // قاعدة ملف حقيقية (WAL من beforeOpen الإنتاجي) — FK مفعّل،
      // تماماً كما في الإنتاج: حجز بغرفة غير موجودة يفشل على مستوى
      // SQLite لا في محاكاة.
      final db = AppDatabase.forTesting(
        NativeDatabase(File('${tmpDir.path}/app.db')),
      );
      addTearDown(db.close);
      AdapterRegistry.initialize(db);

      // المدير الحقيقي (مُنشئ factory بلا شبكة — تعيينات حقول فقط)،
      // نفس نمط pull_commit_visibility_test.dart.
      final manager = AppwriteSyncManager(
        appwriteService: AppwriteService(),
        database: db,
      );

      // الأب الموجود: غرفة 211 فقط. الحجز الجيد يشير إليها؛ الحجز
      // الفاشل يشير إلى غرفة 999 غير الموجودة (سيناريو rooms وصلت
      // متأخرة/ناقصة عن bookings في نفس الدورة).
      await _seedRoom(db, '211', 'room-uuid-211');

      final goodDoc = _bookingDoc(
        uuid: 'booking-uuid-good',
        roomNumber: '211',
        lastModified: _kBaseEpochSec + 10,
      );
      final badDoc = _bookingDoc(
        uuid: 'booking-uuid-bad',
        roomNumber: '999',
        lastModified: _kBaseEpochSec + 20,
      );

      // ═══════════════════════════════════════════════════════════════
      // الفصل A — فشل FK: StateError + تطبيق جزئي محفوظ + لا إدراج للفاشل
      // ═══════════════════════════════════════════════════════════════
      await expectLater(
        manager.syncBookingsForTesting([goodDoc, badDoc]),
        throwsA(
          isA<StateError>()
              .having((e) => e.message, 'message', contains('bookings'))
              .having(
                (e) => e.message,
                'message',
                contains('checkpoint must not advance'),
              ),
        ),
        reason:
            'الحجز الفاشل (غرفة مفقودة) يجب أن يفشل المهمة كلها كي يسجّله '
            'المحرك في failedCollections ولا يثبّت مؤشر bookings فوقه — '
            'هذا هو جوهر إصلاح الفقدان الصامت',
      );

      // الحجز السليم في نفس الدفعة مطبَّق — الفشل لا يلغي ما نجح.
      final goodAfterCycle1 = await _bookingByUuid(db, 'booking-uuid-good');
      expect(
        goodAfterCycle1,
        isNotNull,
        reason: 'التطبيق الجزئي محفوظ: الحجز السليم وصل رغم فشل زميله',
      );
      expect(goodAfterCycle1!.roomNumber, '211');

      // الحجز الفاشل غير مدرَج — لا صف نصف مكسور.
      final badAfterCycle1 = await _bookingByUuid(db, 'booking-uuid-bad');
      expect(
        badAfterCycle1,
        isNull,
        reason: 'الحجز الفاشل لم يُدرَج — سيصل كاملاً عند إعادة المحاولة',
      );

      // ═══════════════════════════════════════════════════════════════
      // الفصل B — وصول الأب (الغرفة 999) في دورة لاحقة: نفس الدفعة
      // تُطبَّق نظيفاً — تصميم «لا تتقدم فوق الفشل» يُشفى ذاتياً.
      // ═══════════════════════════════════════════════════════════════
      await _seedRoom(db, '999', 'room-uuid-999');

      final processed = await manager.syncBookingsForTesting([goodDoc, badDoc]);
      expect(processed, 2, reason: 'كلا الحجزين عالج بنجاح هذه المرة');

      final badAfterCycle2 = await _bookingByUuid(db, 'booking-uuid-bad');
      expect(
        badAfterCycle2,
        isNotNull,
        reason:
            'بعد وصول الغرفة المفقودة، الحجز المؤجل يُطبَّق في الدورة '
            'التالية — الدلتا أعادت تقديمه لأن المؤشر لم يتقدم فوقه',
      );
      expect(badAfterCycle2!.roomNumber, '999');
      expect(badAfterCycle2.status, 'نشط');
    },
  );

  test('عقد SyncResult: failedCollections يجعل الفشل الجزئي مرئياً', () {
    // ✅ هذا هو الأساس الذي يعتمد عليه زر لوحة التحكم الآن: قبل
    // الإصلاح لم يكن للمستهلكين أي وسيلة لمعرفة أن bookings لم تصل.
    final clean = SyncResult(
      status: SyncStatus.success,
      timestamp: DateTime.now(),
      duration: Duration.zero,
    );
    expect(clean.hasPullFailures, isFalse);
    expect(clean.failedCollections, isEmpty);

    final partial = SyncResult(
      status: SyncStatus.partial,
      recordsPulled: 42,
      failedCollections: const ['bookings'],
      timestamp: DateTime.now(),
      duration: Duration.zero,
    );
    expect(partial.hasPullFailures, isTrue);
    expect(partial.failedCollections, contains('bookings'));
    expect(
      partial.isSuccess,
      isFalse,
      reason: 'partial ليس نجاحاً — لا يجوز عرض «تم السحب بنجاح» عليه',
    );
  });
}
