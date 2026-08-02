// ignore_for_file: lines_longer_than_80_chars

import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/daos/bookings_dao.dart';
import 'package:marina_hotel_mobile/services/daos/outbox_dao.dart';
import 'package:marina_hotel_mobile/services/daos/rooms_dao.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';

/// اختبارات انحدارية لـ BookingsDao.updateById.
///
/// السبب: كان updateById يستخدم update(bookings).replace(comp) التي تتطلب
/// كل required columns (localUuid, createdAt, roomNumber, guestName, guestPhone)
/// لأن replace يعمل بـ INSERT semantics. هذا سبّب InvalidDataException عند
/// تسجيل المغادرة (checkout) لأن BookingsRepository.update يُنشأ Companion
/// جزئي فقط. الإصلاح: استخدام (update(bookings)..where((t) => t.id.equals(id)))
/// .write(comp) الذي يتجاهل Value.absent() ويحدّث الحقول الحاضرة فقط.
///
/// هذه الاختبارات تمنع الانحدار إذا حاول أحد العودة إلى replace.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late BookingsDao bookingsDao;
  late RoomsDao roomsDao;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final outboxDao = OutboxDao(db);
    bookingsDao = BookingsDao(db, outboxDao);
    roomsDao = RoomsDao(db, outboxDao);
  });

  tearDown(() async {
    await db.close();
  });

  /// Helper: إنشاء غرفة في قاعدة البيانات (مطلوبة كـ foreign key).
  Future<String> _seedRoom(String roomNumber, {String status = 'شاغرة'}) async {
    return roomsDao.insertOne(
      RoomsCompanion(
        roomNumber: d.Value(roomNumber),
        type: const d.Value('عادية'),
        price: const d.Value(100.0),
        status: d.Value(status),
        localUuid: d.Value('room-$roomNumber-uuid'),
      ),
    );
  }

  /// Helper: إنشاء حجز في قاعدة البيانات.
  Future<int> _seedBooking({
    required String roomNumber,
    String guestName = 'أحمد',
    String guestPhone = '0501234567',
    String status = 'نشط',
  }) async {
    return bookingsDao.insertOne(
      BookingsCompanion(
        roomNumber: d.Value(roomNumber),
        guestName: d.Value(guestName),
        guestPhone: d.Value(guestPhone),
        guestNationality: const d.Value('يمني'),
        checkinDate: d.Value(DateTime.now().toIso8601String()),
        status: d.Value(status),
        localUuid: const d.Value('booking-test-uuid'),
      ),
    );
  }

  group('BookingsDao.updateById — إصلاح InvalidDataException', () {
    test('EC-1: تحديث جزئي بحقل واحد (status فقط) لا يُسبب InvalidDataException', () async {
      // Arrange
      await _seedRoom('101');
      final bookingId = await _seedBooking(roomNumber: '101');

      // Act: تحديث status فقط — هذا السيناريو كان يفشل قبل الإصلاح
      // لأن replace يتطلب localUuid, createdAt, roomNumber, guestName, guestPhone
      // في Companion، لكن BookingsRepository.update يُنشأ Companion جزئي.
      final result = await bookingsDao.updateById(
        bookingId,
        BookingsCompanion(
          status: const d.Value('مكتمل'),
          actualCheckout: d.Value(DateTime.now().toIso8601String()),
          calculatedNights: const d.Value(3),
        ),
      );

      // Assert
      expect(result, 1, reason: 'يجب أن يُحدِّث صفّاً واحداً');
      final updated = await bookingsDao.getById(bookingId);
      expect(updated, isNotNull);
      expect(updated!.status, 'مكتمل');
      expect(updated.calculatedNights, 3);
      expect(updated.actualCheckout, isNotNull);
      // الحقول required يجب أن تبقى كما هي (لم تُمَس)
      expect(updated.localUuid, 'booking-test-uuid');
      expect(updated.guestName, 'أحمد');
      expect(updated.guestPhone, '0501234567');
      expect(updated.roomNumber, '101');
    });

    test('EC-2: تحديث بـ Companion شبه فارغ (فقط actualCheckout) يعمل', () async {
      // Arrange
      await _seedRoom('102');
      final bookingId = await _seedBooking(roomNumber: '102');

      // Act: تحديث actualCheckout فقط — الحالة الكلاسيكية لتسجيل المغادرة
      final result = await bookingsDao.updateById(
        bookingId,
        BookingsCompanion(
          actualCheckout: d.Value(DateTime.now().toIso8601String()),
        ),
      );

      // Assert
      expect(result, 1);
      final updated = await bookingsDao.getById(bookingId);
      expect(updated, isNotNull);
      expect(updated!.actualCheckout, isNotNull);
      // version يجب أن يزداد بمقدار 1 (يُعين في copyWith داخل updateById)
      expect(updated.version, greaterThan(1));
    });

    test('EC-3: تحديث بـ Companion فارغ تماماً لا يكسر البيانات', () async {
      // Arrange
      await _seedRoom('103');
      final bookingId = await _seedBooking(roomNumber: '103');
      final beforeUpdate = await bookingsDao.getById(bookingId);
      expect(beforeUpdate, isNotNull);
      final versionBefore = beforeUpdate!.version;

      // Act: Companion فارغ — write() يرجع 0 (لا حقول للتحديث)
      // لكن updateById يُضيف updatedAt + lastModified + version عبر copyWith
      final result = await bookingsDao.updateById(
        bookingId,
        const BookingsCompanion(),
      );

      // Assert: يجب أن ينجح التحديث (يحدّث version و updatedAt)
      expect(result, 1);
      final afterUpdate = await bookingsDao.getById(bookingId);
      expect(afterUpdate, isNotNull);
      expect(afterUpdate!.version, versionBefore + 1);
      // الحقول الأخرى يجب أن تبقى كما هي
      expect(afterUpdate.guestName, beforeUpdate.guestName);
      expect(afterUpdate.guestPhone, beforeUpdate.guestPhone);
      expect(afterUpdate.roomNumber, beforeUpdate.roomNumber);
    });

    test('EC-4: updateById على ID غير موجود يرجع 0 بدون استثناء', () async {
      // Act: ID غير موجود
      final result = await bookingsDao.updateById(
        99999,
        const BookingsCompanion(status: d.Value('مكتمل')),
      );

      // Assert
      expect(result, 0);
    });

    test('EC-5: تحديث guestPhone فقط (سيناريو شائع في booking_payment_screen)', () async {
      // Arrange
      await _seedRoom('104');
      final bookingId = await _seedBooking(roomNumber: '104');

      // Act: تحديث رقم الهاتف فقط — سيناريو booking_payment_screen.dart:2104
      final result = await bookingsDao.updateById(
        bookingId,
        BookingsCompanion(guestPhone: const d.Value('0509876543')),
      );

      // Assert
      expect(result, 1);
      final updated = await bookingsDao.getById(bookingId);
      expect(updated, isNotNull);
      expect(updated!.guestPhone, '0509876543');
      // الحقول الأخرى يجب أن تبقى
      expect(updated.guestName, 'أحمد');
      expect(updated.roomNumber, '104');
    });

    test('EC-6: تحديث discount و discountType معاً', () async {
      // Arrange
      await _seedRoom('105');
      final bookingId = await _seedBooking(roomNumber: '105');

      // Act: سيناريو booking_payment_screen.dart:2909
      final result = await bookingsDao.updateById(
        bookingId,
        const BookingsCompanion(
          discount: d.Value(50.0),
          discountType: d.Value('total'),
        ),
      );

      // Assert
      expect(result, 1);
      final updated = await bookingsDao.getById(bookingId);
      expect(updated, isNotNull);
      expect(updated!.discount, 50.0);
      expect(updated.discountType, 'total');
    });
  });
}
