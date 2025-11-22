import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/restore_fix_service.dart';
import 'package:marina_hotel_mobile/utils/time.dart';
import 'package:marina_hotel_mobile/utils/id.dart';

void main() {
  late AppDatabase database;
  late RestoreFixService service;

  setUp(() async {
    // إنشاء قاعدة بيانات في الذاكرة للاختبار
    database = AppDatabase.forTesting(NativeDatabase.memory());
    service = RestoreFixService(database);
  });

  tearDown(() async {
    await database.close();
  });

  group('RestoreFixService Tests', () {
    
    test('الاختبار الأول: إعادة حساب الليالي من تاريخ سابق', () async {
      // الإعداد: إنشاء حجز من نسخة احتياطية قديمة
      final checkin = DateTime(2024, 11, 5, 19, 0); // الدخول: 5 نوفمبر 7:00 PM
      final checkout = DateTime(2024, 11, 6, 14, 1); // الخروج: 6 نوفمبر 2:01 PM (بعد الساعة المحددة)
      
      final bookingId = await database.into(database.bookings).insert(
        BookingsCompanion(
          localUuid: Value(IdGen.uuid()),
          roomNumber: const Value('101'),
          guestName: const Value('أحمد محمد'),
          guestPhone: const Value('0501234567'),
          guestNationality: const Value('سعودي'),
          checkinDate: Value(checkin.toIso8601String()),
          checkoutDate: Value(checkout.toIso8601String()),
          status: const Value('محجوزة'),
          expectedNights: const Value(1), // قيمة قديمة خاطئة
          calculatedNights: const Value(1), // قيمة قديمة خاطئة
          createdAt: Value(Time.nowEpoch()),
          updatedAt: Value(Time.nowEpoch()),
          lastModified: Value(Time.nowEpoch()),
        ),
      );

      // التنفيذ: تشغيل الإصلاح التلقائي
      final report = await service.runAutoFixAfterRestore();

      // التحقق: يجب أن ينجح الإصلاح وأن يتم تحديث الحجز إلى ليلتين
      expect(report.success, isTrue);
      expect(report.bookingsFixed, equals(1));

      final updatedBooking = await (database.select(database.bookings)
        ..where((b) => b.id.equals(bookingId)))
        .getSingle();

      expect(updatedBooking.calculatedNights, equals(2));
      expect(updatedBooking.expectedNights, equals(2));

      // التحقق من تسجيل الإصلاح
      final logs = await database.select(database.restoreFixLog).get();
      expect(logs, hasLength(greaterThan(0)));
      expect(logs.any((log) => 
        log.targetTable == 'bookings' && 
        log.fieldName == 'calculatedNights'
      ), isTrue);
    });

    test('الاختبار الثاني: اكتشاف عدم تطابق المدفوعات', () async {
      // الإعداد: إنشاء غرفة
      await database.into(database.rooms).insert(
        RoomsCompanion(
          localUuid: Value(IdGen.uuid()),
          roomNumber: const Value('101'),
          type: const Value('single'),
          price: const Value(15000.0),
          status: const Value('محجوزة'),
          createdAt: Value(Time.nowEpoch()),
          updatedAt: Value(Time.nowEpoch()),
          lastModified: Value(Time.nowEpoch()),
        ),
      );

      // إنشاء حجز بليلتين
      final checkin = DateTime(2024, 11, 5, 15, 0);
      final checkout = DateTime(2024, 11, 7, 12, 0);
      final bookingId = await database.into(database.bookings).insert(
        BookingsCompanion(
          localUuid: Value(IdGen.uuid()),
          roomNumber: const Value('101'),
          guestName: const Value('فهد سالم'),
          guestPhone: const Value('0509876543'),
          guestNationality: const Value('سعودي'),
          checkinDate: Value(checkin.toIso8601String()),
          checkoutDate: Value(checkout.toIso8601String()),
          status: const Value('محجوزة'),
          expectedNights: const Value(2),
          calculatedNights: const Value(2),
          createdAt: Value(Time.nowEpoch()),
          updatedAt: Value(Time.nowEpoch()),
          lastModified: Value(Time.nowEpoch()),
        ),
      );

      // إنشاء دفعة لليلة واحدة فقط (15000)، المفروض 30000
      await database.into(database.payments).insert(
        PaymentsCompanion(
          localUuid: Value(IdGen.uuid()),
          bookingLocalId: Value(bookingId),
          amount: const Value(15000.0), // يجب أن يكون 30000
          paymentDate: Value(DateTime.now().toIso8601String()),
          paymentMethod: const Value('cash'),
          revenueType: const Value('room'),
          createdAt: Value(Time.nowEpoch()),
          updatedAt: Value(Time.nowEpoch()),
          lastModified: Value(Time.nowEpoch()),
        ),
      );

      // التنفيذ: تشغيل الإصلاح التلقائي
      final report = await service.runAutoFixAfterRestore();

      // التحقق: يجب أن ينجح الإصلاح ويكتشف عدم التطابق
      expect(report.success, isTrue);

      final logs = await database.select(database.restoreFixLog).get();
      final paymentLogs = logs.where((log) => log.fixType == 'payment_check').toList();
      expect(paymentLogs, isNotEmpty);
      expect(paymentLogs.first.reason, contains('مبلغ الدفع لا يتطابق'));
    });

    test('الاختبار الثالث: تحديث حالة الغرفة بناءً على الحجوزات النشطة', () async {
      // الإعداد: إنشاء غرفة مُعلمة كشاغرة
      await database.into(database.rooms).insert(
        RoomsCompanion(
          localUuid: Value(IdGen.uuid()),
          roomNumber: const Value('102'),
          type: const Value('single'),
          price: const Value(15000.0),
          status: const Value('شاغرة'), // شاغرة
          createdAt: Value(Time.nowEpoch()),
          updatedAt: Value(Time.nowEpoch()),
          lastModified: Value(Time.nowEpoch()),
        ),
      );

      // إنشاء حجز نشط للغرفة 102
      await database.into(database.bookings).insert(
        BookingsCompanion(
          localUuid: Value(IdGen.uuid()),
          roomNumber: const Value('102'),
          guestName: const Value('خالد أحمد'),
          guestPhone: const Value('0508765432'),
          guestNationality: const Value('سعودي'),
          checkinDate: Value(DateTime.now().toIso8601String()),
          status: const Value('محجوزة'), // حجز نشط
          expectedNights: const Value(1),
          calculatedNights: const Value(1),
          createdAt: Value(Time.nowEpoch()),
          updatedAt: Value(Time.nowEpoch()),
          lastModified: Value(Time.nowEpoch()),
        ),
      );

      // التنفيذ: تشغيل الإصلاح التلقائي
      final report = await service.runAutoFixAfterRestore();

      // التحقق: يجب أن تُحدث حالة الغرفة إلى محجوزة
      expect(report.success, isTrue);
      expect(report.roomsUpdated, equals(1));

      final room = await (database.select(database.rooms)
        ..where((r) => r.roomNumber.equals('102')))
        .getSingle();

      expect(room.status, equals('محجوزة')); // يجب أن تكون محجوزة

      // التحقق من تسجيل التغيير
      final logs = await database.select(database.restoreFixLog).get();
      final roomLogs = logs.where((log) => 
        log.targetTable == 'rooms' && 
        log.fieldName == 'status'
      ).toList();
      expect(roomLogs, isNotEmpty);
    });

    test('الاختبار الرابع: اختبار معقد مع حالات متعددة', () async {
      // الإعداد: إنشاء بيانات معقدة مع أخطاء متعددة

      // غرفة 201 - سعر 20000
      await database.into(database.rooms).insert(
        RoomsCompanion(
          localUuid: Value(IdGen.uuid()),
          roomNumber: const Value('201'),
          type: const Value('double'),
          price: const Value(20000.0),
          status: const Value('شاغرة'), // خطأ: يجب أن تكون محجوزة
          createdAt: Value(Time.nowEpoch()),
          updatedAt: Value(Time.nowEpoch()),
          lastModified: Value(Time.nowEpoch()),
        ),
      );

      // حجز بحساب ليالي خطأ
      final checkin = DateTime(2024, 11, 1, 16, 0);
      final checkout = DateTime(2024, 11, 3, 15, 0); // يومين كاملين
      final bookingId = await database.into(database.bookings).insert(
        BookingsCompanion(
          localUuid: Value(IdGen.uuid()),
          roomNumber: const Value('201'),
          guestName: const Value('سارة محمد'),
          guestPhone: const Value('0507654321'),
          guestNationality: const Value('سعودية'),
          checkinDate: Value(checkin.toIso8601String()),
          checkoutDate: Value(checkout.toIso8601String()),
          status: const Value('محجوزة'),
          expectedNights: const Value(1), // خطأ: يجب أن يكون 2
          calculatedNights: const Value(1), // خطأ: يجب أن يكون 2
          createdAt: Value(Time.nowEpoch()),
          updatedAt: Value(Time.nowEpoch()),
          lastModified: Value(Time.nowEpoch()),
        ),
      );

      // دفعة ناقصة
      await database.into(database.payments).insert(
        PaymentsCompanion(
          localUuid: Value(IdGen.uuid()),
          bookingLocalId: Value(bookingId),
          amount: const Value(30000.0), // ناقص: يجب أن يكون 40000 (2 × 20000)
          paymentDate: Value(DateTime.now().toIso8601String()),
          paymentMethod: const Value('card'),
          revenueType: const Value('room'),
          createdAt: Value(Time.nowEpoch()),
          updatedAt: Value(Time.nowEpoch()),
          lastModified: Value(Time.nowEpoch()),
        ),
      );

      // التنفيذ
      final report = await service.runAutoFixAfterRestore();

      // التحقق الشامل
      expect(report.success, isTrue);
      expect(report.bookingsFixed, equals(1));
      expect(report.roomsUpdated, equals(1));
      expect(report.paymentsRecalculated, equals(1));
      expect(report.changes, hasLength(greaterThan(2)));

      // التحقق من إصلاح الحجز
      final updatedBooking = await (database.select(database.bookings)
        ..where((b) => b.id.equals(bookingId)))
        .getSingle();
      expect(updatedBooking.calculatedNights, equals(2));

      // التحقق من إصلاح الغرفة
      final updatedRoom = await (database.select(database.rooms)
        ..where((r) => r.roomNumber.equals('201')))
        .getSingle();
      expect(updatedRoom.status, equals('محجوزة'));

      // التحقق من وجود سجلات متنوعة
      final logs = await database.select(database.restoreFixLog).get();
      final fixTypes = logs.map((log) => log.fixType).toSet();
      expect(fixTypes.contains('nights_recalc'), isTrue);
      expect(fixTypes.contains('room_status'), isTrue);
      expect(fixTypes.contains('payment_check'), isTrue);
    });

    test('الاختبار الخامس: اختبار إنشاء ونقل اللقطة الاحتياطية', () async {
      // الإعداد: بيانات بسيطة
      await database.into(database.rooms).insert(
        RoomsCompanion(
          localUuid: Value(IdGen.uuid()),
          roomNumber: const Value('301'),
          type: const Value('suite'),
          price: const Value(50000.0),
          status: const Value('شاغرة'),
          createdAt: Value(Time.nowEpoch()),
          updatedAt: Value(Time.nowEpoch()),
          lastModified: Value(Time.nowEpoch()),
        ),
      );

      // التنفيذ: إنشاء لقطة احتياطية
      final snapshot = await service.createLocalSnapshot('test');

      // التحقق: يجب أن تحتوي اللقطة على البيانات الصحيحة
      expect(snapshot.filePath, isNotEmpty);
      expect(snapshot.recordCounts['rooms'], equals(1));
      expect(snapshot.recordCounts['bookings'], equals(0));
      expect(snapshot.totalSizeBytes, greaterThan(0));

      // التحقق من وجود الملف
      final file = File(snapshot.filePath);
      expect(await file.exists(), isTrue);
      
      // قراءة وتحقق محتوى الملف
      final content = await file.readAsString();
      final data = jsonDecode(content);
      expect(data['metadata'], isNotNull);
      expect(data['rooms'], isA<List>());
      expect((data['rooms'] as List).length, equals(1));
    });

    test('الاختبار السادس: فحص حساب الليالي مع قاعدة 14:00', () async {
      // حالات مختلفة لحساب الليالي

      // الحالة 1: دخول وخروج في نفس اليوم قبل 14:00
      var checkin1 = DateTime(2024, 11, 5, 10, 0);
      var checkout1 = DateTime(2024, 11, 5, 13, 59);
      expect(Time.nightsWithCutoff(checkin1, checkout: checkout1), equals(1));

      // الحالة 2: دخول وخروج في نفس اليوم بعد 14:00
      var checkin2 = DateTime(2024, 11, 5, 10, 0);
      var checkout2 = DateTime(2024, 11, 5, 14, 01);
      expect(Time.nightsWithCutoff(checkin2, checkout: checkout2), equals(2));

      // الحالة 3: دخول وخروج عبر يومين بالضبط في 14:00
      var checkin3 = DateTime(2024, 11, 5, 15, 0);
      var checkout3 = DateTime(2024, 11, 7, 14, 0);
      expect(Time.nightsWithCutoff(checkin3, checkout: checkout3), equals(2));

      // الحالة 4: دخول وخروج عبر يومين بعد 14:00
      var checkin4 = DateTime(2024, 11, 5, 15, 0);
      var checkout4 = DateTime(2024, 11, 7, 14, 30);
      expect(Time.nightsWithCutoff(checkin4, checkout: checkout4), equals(3));
    });

    test('الاختبار السابع: اختبار تصدير سجلات الإصلاح', () async {
      // الإعداد: تشغيل إصلاح لإنشاء بعض السجلات
      await database.into(database.rooms).insert(
        RoomsCompanion(
          localUuid: Value(IdGen.uuid()),
          roomNumber: const Value('401'),
          type: const Value('single'),
          price: const Value(12000.0),
          status: const Value('شاغرة'),
          createdAt: Value(Time.nowEpoch()),
          updatedAt: Value(Time.nowEpoch()),
          lastModified: Value(Time.nowEpoch()),
        ),
      );

      final checkin = DateTime(2024, 11, 10, 14, 0);
      final checkout = DateTime(2024, 11, 12, 15, 0); // 3 ليالي
      await database.into(database.bookings).insert(
        BookingsCompanion(
          localUuid: Value(IdGen.uuid()),
          roomNumber: const Value('401'),
          guestName: const Value('عبدالله سعد'),
          guestPhone: const Value('0501111111'),
          guestNationality: const Value('سعودي'),
          checkinDate: Value(checkin.toIso8601String()),
          checkoutDate: Value(checkout.toIso8601String()),
          status: const Value('محجوزة'),
          expectedNights: const Value(2), // خطأ: يجب أن يكون 3
          calculatedNights: const Value(2), // خطأ: يجب أن يكون 3
          createdAt: Value(Time.nowEpoch()),
          updatedAt: Value(Time.nowEpoch()),
          lastModified: Value(Time.nowEpoch()),
        ),
      );

      // تشغيل الإصلاح
      await service.runAutoFixAfterRestore();

      // التنفيذ: تصدير السجلات
      final exportedData = await service.exportFixLogsAsJson();

      // التحقق
      expect(exportedData['total_logs'], greaterThan(0));
      expect(exportedData['logs'], isA<List>());
      expect(exportedData['exported_at'], isNotNull);
      
      final logs = exportedData['logs'] as List;
      expect(logs.first['fix_type'], isNotNull);
      expect(logs.first['reason'], isNotNull);
      expect(logs.first['executed_at_iso'], isNotNull);
    });

    test('الاختبار الثامن: حجز نشط بدون checkout - يجب حساب الليالي حتى التاريخ الحالي', () async {
      // الإعداد: إنشاء حجز نشط (checked_in) بدون actualCheckout
      final checkin = DateTime(2024, 1, 10, 10, 0); // 10 يناير
      final plannedCheckout = DateTime(2024, 1, 15, 12, 0); // مخطط للخروج في 15 يناير
      
      // إنشاء غرفة
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
      
      // إنشاء حجز نشط (بدون actualCheckout)
      final bookingId = await database.into(database.bookings).insert(
        BookingsCompanion(
          localUuid: Value(IdGen.uuid()),
          roomNumber: const Value('301'),
          guestName: const Value('محمد أحمد'),
          guestPhone: const Value('0501234567'),
          guestNationality: const Value('سعودي'),
          checkinDate: Value(checkin.toIso8601String()),
          checkoutDate: Value(plannedCheckout.toIso8601String()),
          actualCheckout: const Value.absent(), // لا يوجد checkout فعلي
          status: const Value('checked_in'), // نشط
          expectedNights: const Value(2), // القيمة القديمة من النسخة الاحتياطية
          calculatedNights: const Value(2), // القيمة القديمة من النسخة الاحتياطية
          createdAt: Value(Time.nowEpoch()),
          updatedAt: Value(Time.nowEpoch()),
          lastModified: Value(Time.nowEpoch()),
        ),
      );

      // محاكاة تاريخ الاستعادة (13 يناير)
      final restoreDate = DateTime(2024, 1, 13, 14, 0);
      
      // التنفيذ: تشغيل الإصلاح التلقائي
      final report = await service.runAutoFixAfterRestore();

      // التحقق: يجب أن ينجح الإصلاح
      expect(report.success, isTrue);
      expect(report.bookingsFixed, equals(1));

      // التحقق من تحديث الليالي
      final updatedBooking = await (database.select(database.bookings)
        ..where((b) => b.id.equals(bookingId)))
        .getSingle();

      // الليالي من 10 يناير إلى 13 يناير (الآن) = 3 ليالي
      expect(updatedBooking.calculatedNights, equals(3));
      expect(updatedBooking.expectedNights, equals(3));

      // التحقق من سجل الإصلاح
      final logs = await database.select(database.restoreFixLog).get();
      expect(logs, hasLength(greaterThan(0)));
      
      final nightsLog = logs.firstWhere(
        (log) => log.targetTable == 'bookings' && log.fieldName == 'calculatedNights',
      );
      expect(nightsLog.oldValue, equals('2'));
      expect(nightsLog.newValue, equals('3'));
      expect(nightsLog.reason, contains('التاريخ الحالي'));
    });

    test('الاختبار التاسع: فحص حالات الأخطاء والاستثناءات', () async {
      // اختبار مع بيانات فاسدة
      
      // إنشاء حجز بتاريخ فاسد
      final invalidBookingId = await database.into(database.bookings).insert(
        BookingsCompanion(
          localUuid: Value(IdGen.uuid()),
          roomNumber: const Value('999'), // غرفة غير موجودة
          guestName: const Value('اختبار خطأ'),
          guestPhone: const Value('0500000000'),
          guestNationality: const Value('سعودي'),
          checkinDate: const Value('تاريخ فاسد'), // تاريخ فاسد
          checkoutDate: const Value('2024-13-45'), // تاريخ فاسد
          status: const Value('محجوزة'),
          expectedNights: const Value(1),
          calculatedNights: const Value(1),
          createdAt: Value(Time.nowEpoch()),
          updatedAt: Value(Time.nowEpoch()),
          lastModified: Value(Time.nowEpoch()),
        ),
      );

      // التنفيذ: يجب أن يتعامل مع الأخطاء بأمان
      final report = await service.runAutoFixAfterRestore();

      // التحقق: يجب أن ينجح الإصلاح رغم البيانات الفاسدة
      expect(report.success, isTrue);
      
      // التحقق أن الحجز الفاسد لم يتأثر
      final unchangedBooking = await (database.select(database.bookings)
        ..where((b) => b.id.equals(invalidBookingId)))
        .getSingle();
      expect(unchangedBooking.expectedNights, equals(1)); // لم يتغير
    });
  });
}

// امتداد لقاعدة البيانات لدعم الاختبار
extension on AppDatabase {
  static AppDatabase forTesting(QueryExecutor executor) {
    return _TestAppDatabase(executor);
  }
}

class _TestAppDatabase extends AppDatabase {
  _TestAppDatabase(super.executor);
  
  @override
  int get schemaVersion => 10; // نفس الإصدار في الإنتاج
}