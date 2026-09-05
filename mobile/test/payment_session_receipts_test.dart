import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:marina_hotel_mobile/services/adapters/adapter_registry.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/payment_session_context.dart';
import 'package:marina_hotel_mobile/services/repositories/payments_repository.dart';
import 'package:marina_hotel_mobile/utils/hotel_time_engine.dart';

void main() {
  test(
    'current session payment total is isolated and excludes non-received rows',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(() async {
        PaymentSessionContext.clear();
        await db.close();
      });

      AdapterRegistry.initialize(db);
      final repository = PaymentsRepository(db);
      const paymentDate = '2026-08-21T15:00:00.000Z';
      final hotelDay = HotelTimeEngine.getHotelDayKeyFromIso(paymentDate);

      PaymentSessionContext.start(
        userId: 1,
        userName: 'User 1',
        sessionUuid: 'session-user-1',
      );
      await repository.create(
        amount: 100,
        paymentDate: paymentDate,
        paymentMethod: 'نقدي',
        revenueType: 'room',
      );

      PaymentSessionContext.start(
        userId: 2,
        userName: 'User 2',
        sessionUuid: 'session-user-2',
      );
      await repository.create(
        amount: 250,
        paymentDate: paymentDate,
        paymentMethod: 'نقدي',
        revenueType: 'room',
      );

      PaymentSessionContext.start(
        userId: 1,
        userName: 'User 1',
        sessionUuid: 'session-user-1',
      );
      final pendingId = await repository.create(
        amount: 40,
        paymentDate: paymentDate,
        paymentMethod: 'نقدي',
        revenueType: 'room',
        isPendingBalance: true,
      );
      final voidedId = await repository.create(
        amount: 60,
        paymentDate: paymentDate,
        paymentMethod: 'نقدي',
        revenueType: 'room',
      );
      await (db.update(db.payments)..where((p) => p.id.equals(voidedId))).write(
        PaymentsCompanion(isVoided: Value(true)),
      );

      final total = await repository.watchTotalByCurrentPaymentSession().first;

      expect(total, 100);
      expect(pendingId, greaterThan(0));
    },
  );

  test(
    'current session total spans hotel-day boundary (no clip at 14:01)',
    () async {
      // ✅ (2026-09-05) النوبة قد تعبر حد 14:01 فتتوزع استلاماتها على
      // مفتاحي يوم فندقي — الإجمالي الصحيح «أثناء النوبة» = الكل.
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(() async {
        PaymentSessionContext.clear();
        await db.close();
      });

      AdapterRegistry.initialize(db);
      final repository = PaymentsRepository(db);
      // مفتاحان فندقيان مختلفان (قبل وبعد حد 14:01) لنفس الجلسة.
      // نفس اليوم التقويمي حول حد 14:01: 13:00 ← مفتاح اليوم السابق
      // الفندقي، 15:00 ← مفتاح يومه الفندقي (نوبة تعبر الحد).
      const dayAPayment = '2026-08-20T13:00:00.000Z';
      const dayBPayment = '2026-08-20T15:00:00.000Z';
      final keyA = HotelTimeEngine.getHotelDayKeyFromIso(dayAPayment);
      final keyB = HotelTimeEngine.getHotelDayKeyFromIso(dayBPayment);
      expect(keyA, isNot(keyB), reason: 'يجب أن يكونا مفتاحين مختلفين');

      PaymentSessionContext.start(
        userId: 1,
        userName: 'User 1',
        sessionUuid: 'session-cross-boundary',
      );
      await repository.create(
        amount: 300,
        paymentDate: dayAPayment,
        paymentMethod: 'نقدي',
        revenueType: 'room',
      );
      await repository.create(
        amount: 450,
        paymentDate: dayBPayment,
        paymentMethod: 'نقدي',
        revenueType: 'room',
      );

      final total = await repository.watchTotalByCurrentPaymentSession().first;
      expect(total, 750);
    },
  );

  test(
    'shift summaries exclude the current system user and keep employee receipts',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(() async {
        PaymentSessionContext.clear();
        await db.close();
      });

      AdapterRegistry.initialize(db);
      final repository = PaymentsRepository(db);
      const paymentDate = '2026-08-21T15:00:00.000Z';
      final hotelDay = HotelTimeEngine.getHotelDayKeyFromIso(paymentDate);

      PaymentSessionContext.start(
        userId: 1,
        userName: 'مدير النظام',
        sessionUuid: 'session-admin',
      );
      await repository.create(
        amount: 161500,
        paymentDate: paymentDate,
        paymentMethod: 'نقدي',
        revenueType: 'room',
      );

      PaymentSessionContext.start(
        userId: 7,
        userName: 'موظف الاستقبال',
        sessionUuid: 'session-employee',
      );
      await repository.create(
        amount: 250,
        paymentDate: paymentDate,
        paymentMethod: 'نقدي',
        revenueType: 'room',
      );

      final summaries = await repository
          .watchPaymentShiftSummaries(hotelDay, excludedUserId: 1)
          .first;

      expect(summaries, hasLength(1));
      expect(summaries.single.userId, 7);
      expect(summaries.single.userName, 'موظف الاستقبال');
      expect(summaries.single.totalAmount, 250);
    },
  );

  test(
    'shift summaries show full session total across the 14:01 boundary',
    () async {
      // ✅ (2026-09-05) نوبة تعبر حد 14:01: استلامات قبل الحد تحمل
      // مفتاح اليوم السابق وبعده مفتاح اليوم — يجب أن تُجمع في صف
      // واحد بإجمالي النوبة الكامل، لا أن يُقتطع جزء النوبة.
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(() async {
        PaymentSessionContext.clear();
        await db.close();
      });

      AdapterRegistry.initialize(db);
      final repository = PaymentsRepository(db);
      const yesterdayPortion = '2026-08-20T13:00:00.000Z';
      const todayPortion = '2026-08-20T15:00:00.000Z';
      final todayKey = HotelTimeEngine.getHotelDayKeyFromIso(todayPortion);
      expect(
        HotelTimeEngine.getHotelDayKeyFromIso(yesterdayPortion),
        isNot(todayKey),
      );

      PaymentSessionContext.start(
        userId: 1,
        userName: 'المدير',
        sessionUuid: 'session-admin',
      );

      PaymentSessionContext.start(
        userId: 7,
        userName: 'موظف الاستقبال',
        sessionUuid: 'session-night-shift',
      );
      await repository.create(
        amount: 200,
        paymentDate: yesterdayPortion,
        paymentMethod: 'نقدي',
        revenueType: 'room',
      );
      await repository.create(
        amount: 500,
        paymentDate: todayPortion,
        paymentMethod: 'نقدي',
        revenueType: 'room',
      );

      final summaries = await repository
          .watchPaymentShiftSummaries(todayKey, excludedUserId: 1)
          .first;

      expect(summaries, hasLength(1));
      expect(summaries.single.sessionUuid, 'session-night-shift');
      expect(summaries.single.totalAmount, 700);
      expect(summaries.single.paymentCount, 2);
    },
  );

  test(
    'shift summaries exclude sessions older than the two-hotel-day window',
    () async {
      // جلسة أقدم من النافذة (قبل اليوم السابق) لا تظهر — لا تراكم
      // تاريخي بلا حدود على لوحة اليوم.
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(() async {
        PaymentSessionContext.clear();
        await db.close();
      });

      AdapterRegistry.initialize(db);
      final repository = PaymentsRepository(db);
      const todayIso = '2026-08-22T20:00:00.000Z';
      const ancientIso = '2026-08-19T09:00:00.000Z';
      final todayKey = HotelTimeEngine.getHotelDayKeyFromIso(todayIso);
      expect(
        HotelTimeEngine.previousHotelDayKey(todayKey),
        '2026-08-21',
        reason: 'مفتاح اليوم السابق للنافذة',
      );

      PaymentSessionContext.start(
        userId: 1,
        userName: 'المدير',
        sessionUuid: 'session-admin',
      );
      PaymentSessionContext.start(
        userId: 9,
        userName: 'موظف قديم',
        sessionUuid: 'session-ancient',
      );
      await repository.create(
        amount: 999,
        paymentDate: ancientIso,
        paymentMethod: 'نقدي',
        revenueType: 'room',
      );

      final summaries = await repository
          .watchPaymentShiftSummaries(todayKey, excludedUserId: 1)
          .first;
      expect(summaries, isEmpty);
    },
  );

  test(
    'shift summaries keep another device user with the same local id',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(() async {
        PaymentSessionContext.clear();
        await db.close();
      });

      AdapterRegistry.initialize(db);
      final repository = PaymentsRepository(db);
      const paymentDate = '2026-08-21T15:00:00.000Z';
      final hotelDay = HotelTimeEngine.getHotelDayKeyFromIso(paymentDate);

      PaymentSessionContext.start(
        userId: 1,
        userName: 'المدير',
        cloudUserId: 'cloud-manager',
        sessionUuid: 'session-manager',
      );
      await repository.create(
        amount: 100,
        paymentDate: paymentDate,
        paymentMethod: 'نقدي',
        revenueType: 'room',
      );

      // نفس المعرف المحلي قد يمثل مستخدماً مختلفاً على جهاز آخر.
      PaymentSessionContext.start(
        userId: 1,
        userName: 'المستخدم 1',
        cloudUserId: 'cloud-user-1',
        sessionUuid: 'session-user-1',
      );
      await repository.create(
        amount: 17000,
        paymentDate: paymentDate,
        paymentMethod: 'نقدي',
        revenueType: 'room',
      );

      final savedPayments = await db.select(db.payments).get();
      expect(savedPayments.last.receivedByCloudId, 'cloud-user-1');

      final summaries = await repository
          .watchPaymentShiftSummaries(
            hotelDay,
            excludedUserName: 'المدير',
            excludedUserCloudId: 'cloud-manager',
          )
          .first;

      expect(summaries, hasLength(1));
      expect(summaries.single.userId, 1);
      expect(summaries.single.userName, 'المستخدم 1');
      expect(summaries.single.totalAmount, 17000);
    },
  );
}
