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
//   2) salary_cycles (المسار C): دورة يتيمة الموظف → StateError ولا
//      تُدرَج، وإعادة الاستدعاء ترمي ثانية (لا حالة عالقة ولا فقدان).

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'درع فقدان booking_notes الصامت (المسار B): تخطّي adapter بسبب أب مفقود '
    'يُؤجَّل ثم يفشل المهمة — والملاحظة السليمة تطبَّق وتُشفى اليتيمة لاحقاً',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tmpDir = await Directory.systemTemp.createTemp(
        'notes_silent_loss',
      );
      addTearDown(() async {
        try {
          await tmpDir.delete(recursive: true);
        } catch (_) {
          // أفضل-جهد — أنظمة CI المختلفة قد تبقي مقابض مؤقتة.
        }
      });

      final db = AppDatabase.forTesting(
        NativeDatabase(File('${tmpDir.path}/app.db')),
      );
      addTearDown(db.close);
      AdapterRegistry.initialize(db);
      final manager = AppwriteSyncManager(
        appwriteService: AppwriteService(),
        database: db,
      );

      // الأب الموجود: غرفة 211 وحجزها. الملاحظة اليتيمة تشير لحجز غير موجود.
      await _seedRoom(db, '211', 'room-uuid-211');
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

  test(
    'درع فقدان salary_cycles الصامت (المسار C): يتيم الموظف يفشل المهمة '
    'ولا يُدرَج — وإعادة المحاولة ترمي ثانية بلا حالة عالقة',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final tmpDir = await Directory.systemTemp.createTemp(
        'cycles_silent_loss',
      );
      addTearDown(() async {
        try {
          await tmpDir.delete(recursive: true);
        } catch (_) {
          // أفضل-جهد.
        }
      });

      final db = AppDatabase.forTesting(
        NativeDatabase(File('${tmpDir.path}/app.db')),
      );
      addTearDown(db.close);
      AdapterRegistry.initialize(db);
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

      await expectLater(
        manager.syncSalaryCyclesForTesting([orphanCycle]),
        throwsA(
          isA<StateError>()
              .having((e) => e.message, 'message', contains('salary_cycles'))
              .having((e) => e.message, 'message', contains('orphan')),
        ),
        reason:
            'دورة راتب يتيمة الموظف (لا طابور دائم لها بعكس '
            'salary_withdrawals) يجب أن تفشل المهمة كي لا يتقدم مؤشرها '
            'فوقها — قبل الإصلاح كانت تُتخطى بـ continue فيفقد السجل نهائياً',
      );

      expect(
        await _cycleByUuid(db, 'cycle-uuid-1'),
        isNull,
        reason: 'الدورة اليتيمة لم تُدرَج — ستصل عند وصول الموظف',
      );

      // إعادة الاستدعاء ترمي ثانية: لا حالة عالقة، والإعادة مضمونة كل دورة
      // حتى يصل الموظف (upsert idempotent عند الشفاء).
      await expectLater(
        manager.syncSalaryCyclesForTesting([orphanCycle]),
        throwsA(isA<StateError>()),
        reason: 'إعادة المحاولة ترمي ثانية — العقد مستقر عبر الدورات',
      );
      expect(await _cycleByUuid(db, 'cycle-uuid-1'), isNull);
    },
  );
}
