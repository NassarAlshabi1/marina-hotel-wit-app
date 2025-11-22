import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/restore_fix_service.dart';
import 'package:marina_hotel_mobile/services/google_drive_backup_service.dart';
import 'package:marina_hotel_mobile/utils/time.dart';
import 'package:marina_hotel_mobile/utils/id.dart';

/// اختبار تكامل شامل لسيناريو الاستعادة مع حجوزات نشطة بفترات مختلفة
void main() {
  late AppDatabase database;
  late RestoreFixService service;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    service = RestoreFixService(database);
  });

  tearDown(() async {
    await database.close();
  });

  group('سيناريوهات الاستعادة - حجوزات نشطة بفترات مختلفة', () {
    
    /// سيناريو 1: نزيل مكث 3 أيام
    test('نزيل مكث 3 أيام - استعادة في اليوم الرابع', () async {
      // الإعداد: إنشاء غرفة
      await database.into(database.rooms).insert(
        RoomsCompanion(
          localUuid: Value(IdGen.uuid()),
          roomNumber: const Value('301'),
          type: const Value('single'),
          price: const Value(15000.0),
          status: const Value('محجوزة'),
          createdAt: Value(Time.nowEpoch()),
          updatedAt: Value(Time.nowEpoch()),
          lastModified: Value(Time.nowEpoch()),
        ),
      );

      // إنشاء حجز نشط
      final checkinDate = DateTime(2025, 1, 10, 10, 0); // دخول يوم 10
      final plannedCheckout = DateTime(2025, 1, 20, 12, 0); // مخطط للخروج يوم 20
      
      final bookingId = await database.into(database.bookings).insert(
        BookingsCompanion(
          localUuid: Value(IdGen.uuid()),
          roomNumber: const Value('301'),
          guestName: const Value('أحمد محمد'),
          guestPhone: const Value('0501234567'),
          guestNationality: const Value('سعودي'),
          checkinDate: Value(checkinDate.toIso8601String()),
          checkoutDate: Value(plannedCheckout.toIso8601String()),
          actualCheckout: const Value.absent(), // لا يوجد checkout فعلي
          status: const Value('checked_in'),
          expectedNights: const Value(3), // القيمة في النسخة (يوم 13)
          calculatedNights: const Value(3),
          createdAt: Value(Time.nowEpoch()),
          updatedAt: Value(Time.nowEpoch()),
          lastModified: Value(Time.nowEpoch()),
        ),
      );

      // إضافة مدفوعات ليوم 13 (3 ليالي)
      await database.into(database.payments).insert(
        PaymentsCompanion(
          localUuid: Value(IdGen.uuid()),
          bookingLocalId: Value(bookingId),
          amount: const Value(45000.0), // 3 × 15000
          paymentDate: Value(DateTime(2025, 1, 13, 10, 0).toIso8601String()),
          paymentMethod: const Value('cash'),
          revenueType: const Value('room'),
          createdAt: Value(Time.nowEpoch()),
          updatedAt: Value(Time.nowEpoch()),
          lastModified: Value(Time.nowEpoch()),
        ),
      );

      // محاكاة تاريخ النسخة الاحتياطية
      final backupDate = DateTime(2025, 1, 13, 20, 0); // نسخة يوم 13

      // السيناريو: الاستعادة في يوم 14 (بعد يوم واحد)
      // الليالي الفعلية يجب أن تكون: 10→11, 11→12, 12→13, 13→14 = 4 ليالي
      final restoreDate = DateTime(2025, 1, 14, 10, 0);
      
      // التنفيذ: تشغيل الإصلاح التلقائي (سيستخدم DateTime.now())
      // ملاحظة: في الاختبار، now() سيكون وقت تشغيل الاختبار
      // لكن في التطبيق الفعلي، سيكون التاريخ الحالي عند الاستعادة
      final report = await service.runAutoFixAfterRestore(backupTimestamp: backupDate);

      // التحقق
      expect(report.success, isTrue);
      expect(report.bookingsFixed, greaterThanOrEqualTo(1));

      final updatedBooking = await (database.select(database.bookings)
        ..where((b) => b.id.equals(bookingId)))
        .getSingle();

      // الليالي يجب أن تُحدّث بناءً على التاريخ الحالي
      // من 10 يناير إلى الآن (وقت تشغيل الاختبار)
      final expectedNights = Time.nightsWithCutoff(checkinDate, checkout: DateTime.now());
      expect(updatedBooking.calculatedNights, equals(expectedNights));

      // التحقق من سجل الإصلاح
      final logs = await database.select(database.restoreFixLog).get();
      expect(logs, isNotEmpty);
      
      final nightsLog = logs.where(
        (log) => log.targetTable == 'bookings' && 
                log.fieldName == 'calculatedNights' &&
                log.targetRecordId == bookingId
      ).toList();
      
      if (nightsLog.isNotEmpty) {
        expect(nightsLog.first.reason, contains('التاريخ الحالي'));
      }
    });

    /// سيناريو 2: نزيل مكث 5 أيام
    test('نزيل مكث 5 أيام - استعادة في اليوم السادس', () async {
      await database.into(database.rooms).insert(
        RoomsCompanion(
          localUuid: Value(IdGen.uuid()),
          roomNumber: const Value('302'),
          type: const Value('double'),
          price: const Value(20000.0),
          status: const Value('محجوزة'),
          createdAt: Value(Time.nowEpoch()),
          updatedAt: Value(Time.nowEpoch()),
          lastModified: Value(Time.nowEpoch()),
        ),
      );

      final checkinDate = DateTime(2025, 1, 1, 14, 0); // دخول يوم 1
      final plannedCheckout = DateTime(2025, 1, 15, 12, 0); // مخطط 15
      
      final bookingId = await database.into(database.bookings).insert(
        BookingsCompanion(
          localUuid: Value(IdGen.uuid()),
          roomNumber: const Value('302'),
          guestName: const Value('فهد سالم'),
          guestPhone: const Value('0509876543'),
          guestNationality: const Value('سعودي'),
          checkinDate: Value(checkinDate.toIso8601String()),
          checkoutDate: Value(plannedCheckout.toIso8601String()),
          actualCheckout: const Value.absent(),
          status: const Value('checked_in'),
          expectedNights: const Value(5), // في النسخة يوم 6
          calculatedNights: const Value(5),
          createdAt: Value(Time.nowEpoch()),
          updatedAt: Value(Time.nowEpoch()),
          lastModified: Value(Time.nowEpoch()),
        ),
      );

      // دفعة ليوم 6 (5 ليالي)
      await database.into(database.payments).insert(
        PaymentsCompanion(
          localUuid: Value(IdGen.uuid()),
          bookingLocalId: Value(bookingId),
          amount: const Value(100000.0), // 5 × 20000
          paymentDate: Value(DateTime(2025, 1, 6, 10, 0).toIso8601String()),
          paymentMethod: const Value('card'),
          revenueType: const Value('room'),
          createdAt: Value(Time.nowEpoch()),
          updatedAt: Value(Time.nowEpoch()),
          lastModified: Value(Time.nowEpoch()),
        ),
      );

      final backupDate = DateTime(2025, 1, 6, 22, 0); // نسخة يوم 6
      final report = await service.runAutoFixAfterRestore(backupTimestamp: backupDate);

      expect(report.success, isTrue);

      final updatedBooking = await (database.select(database.bookings)
        ..where((b) => b.id.equals(bookingId)))
        .getSingle();

      // الليالي من 1 يناير إلى الآن
      final expectedNights = Time.nightsWithCutoff(checkinDate, checkout: DateTime.now());
      expect(updatedBooking.calculatedNights, equals(expectedNights));
      
      // التحقق من تحذير المدفوعات
      final logs = await database.select(database.restoreFixLog).get();
      final paymentLogs = logs.where((log) => log.fixType == 'payment_check').toList();
      
      // يجب أن يكون هناك تحذير لأن المبلغ المدفوع أقل من المتوقع
      if (expectedNights > 5) {
        expect(paymentLogs, isNotEmpty);
      }
    });

    /// سيناريو 3: نزيل مكث 30 يوماً (شهر كامل)
    test('نزيل مكث شهراً كاملاً - استعادة بعد أسبوع', () async {
      await database.into(database.rooms).insert(
        RoomsCompanion(
          localUuid: Value(IdGen.uuid()),
          roomNumber: const Value('303'),
          type: const Value('suite'),
          price: const Value(50000.0),
          status: const Value('محجوزة'),
          createdAt: Value(Time.nowEpoch()),
          updatedAt: Value(Time.nowEpoch()),
          lastModified: Value(Time.nowEpoch()),
        ),
      );

      final checkinDate = DateTime(2024, 12, 1, 15, 0); // دخول 1 ديسمبر
      final plannedCheckout = DateTime(2025, 2, 1, 12, 0); // مخطط شهرين
      
      final bookingId = await database.into(database.bookings).insert(
        BookingsCompanion(
          localUuid: Value(IdGen.uuid()),
          roomNumber: const Value('303'),
          guestName: const Value('عبدالله خالد'),
          guestPhone: const Value('0507654321'),
          guestNationality: const Value('كويتي'),
          checkinDate: Value(checkinDate.toIso8601String()),
          checkoutDate: Value(plannedCheckout.toIso8601String()),
          actualCheckout: const Value.absent(),
          status: const Value('checked_in'),
          expectedNights: const Value(30), // 30 يوم في النسخة
          calculatedNights: const Value(30),
          createdAt: Value(Time.nowEpoch()),
          updatedAt: Value(Time.nowEpoch()),
          lastModified: Value(Time.nowEpoch()),
        ),
      );

      // دفعة جزئية
      await database.into(database.payments).insert(
        PaymentsCompanion(
          localUuid: Value(IdGen.uuid()),
          bookingLocalId: Value(bookingId),
          amount: const Value(1500000.0), // 30 × 50000
          paymentDate: Value(DateTime(2024, 12, 31, 10, 0).toIso8601String()),
          paymentMethod: const Value('bank_transfer'),
          revenueType: const Value('room'),
          createdAt: Value(Time.nowEpoch()),
          updatedAt: Value(Time.nowEpoch()),
          lastModified: Value(Time.nowEpoch()),
        ),
      );

      final backupDate = DateTime(2024, 12, 31, 23, 59); // نسخة 31 ديسمبر
      final report = await service.runAutoFixAfterRestore(backupTimestamp: backupDate);

      expect(report.success, isTrue);

      final updatedBooking = await (database.select(database.bookings)
        ..where((b) => b.id.equals(bookingId)))
        .getSingle();

      // الليالي من 1 ديسمبر إلى الآن (يناير)
      final expectedNights = Time.nightsWithCutoff(checkinDate, checkout: DateTime.now());
      expect(updatedBooking.calculatedNights, equals(expectedNights));
      expect(updatedBooking.calculatedNights, greaterThan(30)); // يجب أن يكون أكثر من 30
      
      debugPrint('📊 نتائج الاختبار:');
      debugPrint('   الليالي في النسخة: 30');
      debugPrint('   الليالي بعد الإصلاح: ${updatedBooking.calculatedNights}');
      debugPrint('   الفرق: ${updatedBooking.calculatedNights - 30} ليلة');
    });

    /// سيناريو 4: نزيل مكث 50 يوماً
    test('نزيل مكث 50 يوماً - استعادة في اليوم 51', () async {
      await database.into(database.rooms).insert(
        RoomsCompanion(
          localUuid: Value(IdGen.uuid()),
          roomNumber: const Value('304'),
          type: const Value('vip'),
          price: const Value(100000.0),
          status: const Value('محجوزة'),
          createdAt: Value(Time.nowEpoch()),
          updatedAt: Value(Time.nowEpoch()),
          lastModified: Value(Time.nowEpoch()),
        ),
      );

      final checkinDate = DateTime(2024, 11, 1, 16, 0); // دخول 1 نوفمبر
      final plannedCheckout = DateTime(2025, 2, 1, 12, 0); // مخطط 3 أشهر
      
      final bookingId = await database.into(database.bookings).insert(
        BookingsCompanion(
          localUuid: Value(IdGen.uuid()),
          roomNumber: const Value('304'),
          guestName: const Value('سلطان عبدالعزيز'),
          guestPhone: const Value('0505555555'),
          guestNationality: const Value('إماراتي'),
          checkinDate: Value(checkinDate.toIso8601String()),
          checkoutDate: Value(plannedCheckout.toIso8601String()),
          actualCheckout: const Value.absent(),
          status: const Value('checked_in'),
          expectedNights: const Value(50), // 50 يوم في النسخة
          calculatedNights: const Value(50),
          createdAt: Value(Time.nowEpoch()),
          updatedAt: Value(Time.nowEpoch()),
          lastModified: Value(Time.nowEpoch()),
        ),
      );

      // دفعات متعددة
      await database.into(database.payments).insert(
        PaymentsCompanion(
          localUuid: Value(IdGen.uuid()),
          bookingLocalId: Value(bookingId),
          amount: const Value(5000000.0), // 50 × 100000
          paymentDate: Value(DateTime(2024, 12, 20, 10, 0).toIso8601String()),
          paymentMethod: const Value('bank_transfer'),
          revenueType: const Value('room'),
          createdAt: Value(Time.nowEpoch()),
          updatedAt: Value(Time.nowEpoch()),
          lastModified: Value(Time.nowEpoch()),
        ),
      );

      final backupDate = DateTime(2024, 12, 20, 23, 0); // نسخة 20 ديسمبر (50 يوم من الدخول)
      final report = await service.runAutoFixAfterRestore(backupTimestamp: backupDate);

      expect(report.success, isTrue);

      final updatedBooking = await (database.select(database.bookings)
        ..where((b) => b.id.equals(bookingId)))
        .getSingle();

      // الليالي من 1 نوفمبر إلى الآن
      final expectedNights = Time.nightsWithCutoff(checkinDate, checkout: DateTime.now());
      expect(updatedBooking.calculatedNights, equals(expectedNights));
      expect(updatedBooking.calculatedNights, greaterThan(50)); // أكثر من 50 يوم
      
      // التحقق من تحذير نقص المدفوعات
      final logs = await database.select(database.restoreFixLog).get();
      final paymentLogs = logs.where((log) => 
        log.fixType == 'payment_check' && 
        log.targetRecordId == bookingId
      ).toList();
      
      expect(paymentLogs, isNotEmpty); // يجب أن يكون هناك تحذير
      
      debugPrint('📊 نتائج اختبار 50 يوم:');
      debugPrint('   الليالي في النسخة: 50');
      debugPrint('   الليالي بعد الإصلاح: ${updatedBooking.calculatedNights}');
      debugPrint('   المبلغ المدفوع: 5,000,000');
      debugPrint('   المبلغ المتوقع: ${updatedBooking.calculatedNights * 100000}');
      debugPrint('   الفرق: ${(updatedBooking.calculatedNights * 100000) - 5000000}');
    });

    /// سيناريو 5: حجوزات متعددة بفترات مختلفة
    test('حجوزات متعددة - فترات مختلفة (1 يوم، 7 أيام، 15 يوم)', () async {
      // إضافة 3 غرف
      for (int i = 1; i <= 3; i++) {
        await database.into(database.rooms).insert(
          RoomsCompanion(
            localUuid: Value(IdGen.uuid()),
            roomNumber: Value('40$i'),
            type: const Value('single'),
            price: const Value(15000.0),
            status: const Value('محجوزة'),
            createdAt: Value(Time.nowEpoch()),
            updatedAt: Value(Time.nowEpoch()),
            lastModified: Value(Time.nowEpoch()),
          ),
        );
      }

      // حجز 1: مكث يوم واحد
      final checkin1 = DateTime.now().subtract(const Duration(days: 1));
      await database.into(database.bookings).insert(
        BookingsCompanion(
          localUuid: Value(IdGen.uuid()),
          roomNumber: const Value('401'),
          guestName: const Value('نزيل 1'),
          guestPhone: const Value('0501111111'),
          guestNationality: const Value('سعودي'),
          checkinDate: Value(checkin1.toIso8601String()),
          checkoutDate: Value(DateTime.now().add(const Duration(days: 5)).toIso8601String()),
          actualCheckout: const Value.absent(),
          status: const Value('checked_in'),
          expectedNights: const Value(1),
          calculatedNights: const Value(1),
          createdAt: Value(Time.nowEpoch()),
          updatedAt: Value(Time.nowEpoch()),
          lastModified: Value(Time.nowEpoch()),
        ),
      );

      // حجز 2: مكث 7 أيام
      final checkin2 = DateTime.now().subtract(const Duration(days: 7));
      await database.into(database.bookings).insert(
        BookingsCompanion(
          localUuid: Value(IdGen.uuid()),
          roomNumber: const Value('402'),
          guestName: const Value('نزيل 2'),
          guestPhone: const Value('0502222222'),
          guestNationality: const Value('سعودي'),
          checkinDate: Value(checkin2.toIso8601String()),
          checkoutDate: Value(DateTime.now().add(const Duration(days: 10)).toIso8601String()),
          actualCheckout: const Value.absent(),
          status: const Value('checked_in'),
          expectedNights: const Value(7),
          calculatedNights: const Value(7),
          createdAt: Value(Time.nowEpoch()),
          updatedAt: Value(Time.nowEpoch()),
          lastModified: Value(Time.nowEpoch()),
        ),
      );

      // حجز 3: مكث 15 يوم
      final checkin3 = DateTime.now().subtract(const Duration(days: 15));
      await database.into(database.bookings).insert(
        BookingsCompanion(
          localUuid: Value(IdGen.uuid()),
          roomNumber: const Value('403'),
          guestName: const Value('نزيل 3'),
          guestPhone: const Value('0503333333'),
          guestNationality: const Value('سعودي'),
          checkinDate: Value(checkin3.toIso8601String()),
          checkoutDate: Value(DateTime.now().add(const Duration(days: 20)).toIso8601String()),
          actualCheckout: const Value.absent(),
          status: const Value('checked_in'),
          expectedNights: const Value(15),
          calculatedNights: const Value(15),
          createdAt: Value(Time.nowEpoch()),
          updatedAt: Value(Time.nowEpoch()),
          lastModified: Value(Time.nowEpoch()),
        ),
      );

      final report = await service.runAutoFixAfterRestore();

      expect(report.success, isTrue);
      expect(report.bookingsFixed, greaterThanOrEqualTo(3));

      // التحقق من كل حجز
      final allBookings = await database.select(database.bookings).get();
      
      for (final booking in allBookings) {
        final checkin = DateTime.parse(booking.checkinDate);
        final expectedNights = Time.nightsWithCutoff(checkin, checkout: DateTime.now());
        
        expect(booking.calculatedNights, equals(expectedNights));
        debugPrint('✅ الحجز ${booking.roomNumber}: ${booking.calculatedNights} ليلة');
      }
    });

    /// سيناريو 6: نزيل تم checkout - يجب ألا يتغير
    test('حجز مكتمل (مع actualCheckout) - يجب أن يبقى كما هو', () async {
      await database.into(database.rooms).insert(
        RoomsCompanion(
          localUuid: Value(IdGen.uuid()),
          roomNumber: const Value('305'),
          type: const Value('single'),
          price: const Value(15000.0),
          status: const Value('شاغرة'),
          createdAt: Value(Time.nowEpoch()),
          updatedAt: Value(Time.nowEpoch()),
          lastModified: Value(Time.nowEpoch()),
        ),
      );

      final checkinDate = DateTime(2025, 1, 10, 10, 0);
      final checkoutDate = DateTime(2025, 1, 15, 12, 0);
      final actualCheckoutDate = DateTime(2025, 1, 13, 11, 0); // تم الخروج الفعلي
      
      final bookingId = await database.into(database.bookings).insert(
        BookingsCompanion(
          localUuid: Value(IdGen.uuid()),
          roomNumber: const Value('305'),
          guestName: const Value('حجز مكتمل'),
          guestPhone: const Value('0500000000'),
          guestNationality: const Value('سعودي'),
          checkinDate: Value(checkinDate.toIso8601String()),
          checkoutDate: Value(checkoutDate.toIso8601String()),
          actualCheckout: Value(actualCheckoutDate.toIso8601String()), // ✅ تم الخروج
          status: const Value('مكتمل'),
          expectedNights: const Value(3),
          calculatedNights: const Value(3),
          createdAt: Value(Time.nowEpoch()),
          updatedAt: Value(Time.nowEpoch()),
          lastModified: Value(Time.nowEpoch()),
        ),
      );

      final report = await service.runAutoFixAfterRestore();

      expect(report.success, isTrue);

      final updatedBooking = await (database.select(database.bookings)
        ..where((b) => b.id.equals(bookingId)))
        .getSingle();

      // يجب أن تبقى الليالي كما هي (3) لأنه تم الخروج
      final expectedNights = Time.nightsWithCutoff(checkinDate, checkout: actualCheckoutDate);
      expect(updatedBooking.calculatedNights, equals(expectedNights));
      expect(updatedBooking.calculatedNights, equals(3)); // لم يتغير ✅
      
      debugPrint('✅ الحجز المكتمل لم يتغير: ${updatedBooking.calculatedNights} ليلة');
    });

    /// سيناريو 7: اختبار شامل - نسخة واستعادة كاملة
    test('سيناريو كامل: إنشاء نسخة واستعادتها مع التحقق من جميع البيانات', () async {
      // === المرحلة 1: إنشاء بيانات كاملة ===
      
      // إضافة غرف
      await database.into(database.rooms).insert(
        RoomsCompanion(
          localUuid: Value(IdGen.uuid()),
          roomNumber: const Value('501'),
          type: const Value('single'),
          price: const Value(15000.0),
          status: const Value('محجوزة'),
          createdAt: Value(Time.nowEpoch()),
          updatedAt: Value(Time.nowEpoch()),
          lastModified: Value(Time.nowEpoch()),
        ),
      );

      // حجز نشط (بدأ قبل 5 أيام)
      final checkinDate = DateTime.now().subtract(const Duration(days: 5));
      final plannedCheckout = DateTime.now().add(const Duration(days: 10));
      
      final bookingId = await database.into(database.bookings).insert(
        BookingsCompanion(
          localUuid: Value(IdGen.uuid()),
          roomNumber: const Value('501'),
          guestName: const Value('محمد علي'),
          guestPhone: const Value('0506666666'),
          guestNationality: const Value('سعودي'),
          checkinDate: Value(checkinDate.toIso8601String()),
          checkoutDate: Value(plannedCheckout.toIso8601String()),
          actualCheckout: const Value.absent(),
          status: const Value('checked_in'),
          expectedNights: const Value(5),
          calculatedNights: const Value(5),
          createdAt: Value(Time.nowEpoch()),
          updatedAt: Value(Time.nowEpoch()),
          lastModified: Value(Time.nowEpoch()),
        ),
      );

      // دفعة لـ 5 ليالي
      await database.into(database.payments).insert(
        PaymentsCompanion(
          localUuid: Value(IdGen.uuid()),
          bookingLocalId: Value(bookingId),
          amount: const Value(75000.0), // 5 × 15000
          paymentDate: Value(DateTime.now().subtract(const Duration(days: 1)).toIso8601String()),
          paymentMethod: const Value('cash'),
          revenueType: const Value('room'),
          createdAt: Value(Time.nowEpoch()),
          updatedAt: Value(Time.nowEpoch()),
          lastModified: Value(Time.nowEpoch()),
        ),
      );

      // === المرحلة 2: إنشاء نسخة احتياطية ===
      
      final backupDate = DateTime.now().subtract(const Duration(hours: 2)); // قبل ساعتين
      
      // تصدير البيانات (محاكاة النسخة الاحتياطية)
      final roomsData = await database.select(database.rooms).get();
      final bookingsData = await database.select(database.bookings).get();
      final paymentsData = await database.select(database.payments).get();
      
      final backupData = {
        'metadata': {
          'backup_timestamp': backupDate.toIso8601String(),
          'app_version': '1.2.0+3',
          'database_version': 10,
          'total_records': roomsData.length + bookingsData.length + paymentsData.length,
          'device_info': 'Test Device',
        },
        'rooms': roomsData.map((r) => r.toJson()).toList(),
        'bookings': bookingsData.map((b) => b.toJson()).toList(),
        'payments': paymentsData.map((p) => p.toJson()).toList(),
      };

      // === المرحلة 3: محاكاة الحذف ===
      
      await database.delete(database.rooms).go();
      await database.delete(database.bookings).go();
      await database.delete(database.payments).go();
      
      // التحقق من أن البيانات فارغة
      final emptyBookings = await database.select(database.bookings).get();
      expect(emptyBookings, isEmpty);

      // === المرحلة 4: الاستعادة ===
      
      // استعادة الغرف
      for (final roomJson in backupData['rooms'] as List) {
        await database.into(database.rooms).insert(Room.fromJson(roomJson));
      }
      
      // استعادة الحجوزات
      for (final bookingJson in backupData['bookings'] as List) {
        await database.into(database.bookings).insert(Booking.fromJson(bookingJson));
      }
      
      // استعادة المدفوعات
      for (final paymentJson in backupData['payments'] as List) {
        await database.into(database.payments).insert(Payment.fromJson(paymentJson));
      }

      // === المرحلة 5: تشغيل الإصلاح التلقائي ===
      
      final metadata = backupData['metadata'] as Map<String, dynamic>;
      final backupTimestamp = DateTime.parse(metadata['backup_timestamp']);
      
      final report = await service.runAutoFixAfterRestore(backupTimestamp: backupTimestamp);

      // === المرحلة 6: التحقق الشامل ===
      
      expect(report.success, isTrue);
      expect(report.bookingsFixed, greaterThanOrEqualTo(1));
      expect(report.roomsUpdated, greaterThanOrEqualTo(1));

      final restoredBooking = await (database.select(database.bookings)
        ..where((b) => b.id.equals(bookingId)))
        .getSingle();

      // الليالي يجب أن تكون من checkinDate إلى الآن
      final expectedNights = Time.nightsWithCutoff(checkinDate, checkout: DateTime.now());
      expect(restoredBooking.calculatedNights, equals(expectedNights));
      expect(restoredBooking.calculatedNights, greaterThan(5)); // أكثر من 5 أيام

      // التحقق من تحذير المدفوعات
      final expectedTotal = restoredBooking.calculatedNights * 15000.0;
      expect(expectedTotal, greaterThan(75000.0)); // يجب أن يكون أكثر من المدفوع

      debugPrint('📊 نتائج السيناريو الكامل:');
      debugPrint('   الليالي في النسخة: 5');
      debugPrint('   الليالي بعد الاستعادة: ${restoredBooking.calculatedNights}');
      debugPrint('   المبلغ المدفوع: 75,000');
      debugPrint('   المبلغ المتوقع: $expectedTotal');
      debugPrint('   الدين المتبقي: ${expectedTotal - 75000}');
      debugPrint('   عدد الحجوزات المصلحة: ${report.bookingsFixed}');
      debugPrint('   عدد الغرف المحدثة: ${report.roomsUpdated}');
    });

    /// سيناريو 8: اختبار قاعدة الساعة 14:00 مع الاستعادة
    test('قاعدة الساعة 14:00 - checkout قبل وبعد 14:00', () async {
      await database.into(database.rooms).insert(
        RoomsCompanion(
          localUuid: Value(IdGen.uuid()),
          roomNumber: const Value('601'),
          type: const Value('single'),
          price: const Value(10000.0),
          status: const Value('محجوزة'),
          createdAt: Value(Time.nowEpoch()),
          updatedAt: Value(Time.nowEpoch()),
          lastModified: Value(Time.nowEpoch()),
        ),
      );

      final checkinDate = DateTime(2025, 1, 10, 10, 0);
      
      // حالة 1: الاستعادة قبل الساعة 14:00 في نفس اليوم
      final restoreTimeAM = DateTime(2025, 1, 11, 13, 59);
      final nightsBeforeCutoff = Time.nightsWithCutoff(checkinDate, checkout: restoreTimeAM);
      expect(nightsBeforeCutoff, equals(1)); // يوم واحد

      // حالة 2: الاستعادة بعد الساعة 14:00 في نفس اليوم
      final restoreTimePM = DateTime(2025, 1, 11, 14, 01);
      final nightsAfterCutoff = Time.nightsWithCutoff(checkinDate, checkout: restoreTimePM);
      expect(nightsAfterCutoff, equals(2)); // يومين (بسبب تجاوز 14:00)

      // حالة 3: الاستعادة في اليوم الثالث بعد 14:00
      final restoreDay3 = DateTime(2025, 1, 12, 15, 30);
      final nightsDay3 = Time.nightsWithCutoff(checkinDate, checkout: restoreDay3);
      expect(nightsDay3, equals(3)); // 3 ليالي

      debugPrint('✅ قاعدة الساعة 14:00 تعمل بشكل صحيح:');
      debugPrint('   قبل 14:00 → ${nightsBeforeCutoff} ليلة');
      debugPrint('   بعد 14:00 → ${nightsAfterCutoff} ليلة');
      debugPrint('   يوم 3 بعد 14:00 → ${nightsDay3} ليلة');
    });
  });
}

extension on AppDatabase {
  static AppDatabase forTesting(QueryExecutor executor) {
    return _TestAppDatabase(executor);
  }
}

class _TestAppDatabase extends AppDatabase {
  _TestAppDatabase(QueryExecutor executor) : super._internal(executor);
  
  _TestAppDatabase._internal(super.executor);
  
  @override
  int get schemaVersion => 10;
}
