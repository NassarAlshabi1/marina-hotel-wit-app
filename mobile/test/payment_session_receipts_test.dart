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

      final total = await repository
          .watchTotalByCurrentPaymentSession(hotelDay)
          .first;

      expect(total, 100);
      expect(pendingId, greaterThan(0));
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
}
