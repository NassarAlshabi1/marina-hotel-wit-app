import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/payment_void_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late PaymentVoidService service;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    service = PaymentVoidService(database);
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'يحفظ إلغاء الدفعة وسبب الإلغاء ويضع سجلَي payment_voids وpayments في Outbox',
    () async {
      await database
          .into(database.payments)
          .insert(
            PaymentsCompanion.insert(
              localUuid: 'payment-void-sync-uuid',
              createdAt: 1723564800,
              updatedAt: 1723564800,
              lastModified: 1723564800,
              amount: 125.0,
              paymentDate: '2026-08-13',
              paymentMethod: 'نقدي',
              revenueType: 'إقامة',
              bookingUuidCache: const drift.Value('booking-void-sync-uuid'),
              hotelDayKey: const drift.Value('2026-08-13'),
            ),
          );

      final completed = await service.voidPayment(
        paymentUuid: 'payment-void-sync-uuid',
        voidReason: 'تصحيح إدخال مكرر',
        voidedBy: 'manager-1',
        approvedBy: 'owner-1',
      );

      expect(completed, isTrue);

      final payment =
          await (database.select(
                database.payments,
              )..where((row) => row.localUuid.equals('payment-void-sync-uuid')))
              .getSingle();
      expect(payment.isVoided, isTrue);
      expect(payment.isImmutable, isTrue);
      expect(payment.voidReason, 'تصحيح إدخال مكرر');
      expect(payment.voidedBy, 'manager-1');
      expect(payment.voidedAt, isNotNull);

      final voidRecord =
          await (database.select(database.paymentVoids)..where(
                (row) =>
                    row.originalPaymentUuid.equals('payment-void-sync-uuid'),
              ))
              .getSingle();
      expect(voidRecord.bookingUuid, 'booking-void-sync-uuid');
      expect(voidRecord.voidedAmount, 125);
      expect(voidRecord.voidReason, 'تصحيح إدخال مكرر');
      expect(voidRecord.approvedBy, 'owner-1');

      final outboxEntries = await database.select(database.outbox).get();
      expect(
        outboxEntries.map((entry) => entry.entity),
        containsAll(<String>['payment_voids', 'payments']),
      );

      final audit =
          await (database.select(database.auditLogs)..where(
                (row) => row.entityUuid.equals('payment-void-sync-uuid'),
              ))
              .getSingle();
      expect(audit.operationType, 'void');
      expect(audit.isFinancial, isTrue);
      expect(audit.amountImpact, 125);
      expect(audit.performedBy, 'manager-1');
    },
  );

  test(
    'legacy void record stores the original hotel-day key, not the timestamp',
    () async {
      await database
          .into(database.payments)
          .insert(
            PaymentsCompanion.insert(
              localUuid: 'legacy-payment-void-uuid',
              createdAt: 1723564800,
              updatedAt: 1723564800,
              lastModified: 1723564800,
              amount: 75.0,
              paymentDate: '2026-08-14T14:00:59',
              paymentMethod: 'نقدي',
              revenueType: 'إقامة',
              bookingUuidCache: const drift.Value('legacy-booking-uuid'),
            ),
          );

      final completed = await service.voidPayment(
        paymentUuid: 'legacy-payment-void-uuid',
        voidReason: 'اختبار اليوم الفندقي',
        voidedBy: 'manager-1',
      );

      expect(completed, isTrue);
      final voidRecord =
          await (database.select(database.paymentVoids)..where(
                (row) =>
                    row.originalPaymentUuid.equals('legacy-payment-void-uuid'),
              ))
              .getSingle();
      expect(voidRecord.hotelDayKey, '2026-08-13');
    },
  );

  test(
    'rejects fractional amount instead of silently rounding the void',
    () async {
      await database
          .into(database.payments)
          .insert(
            PaymentsCompanion.insert(
              localUuid: 'fractional-payment-void-uuid',
              createdAt: 1723564800,
              updatedAt: 1723564800,
              lastModified: 1723564800,
              amount: 12.5,
              paymentDate: '2026-08-13',
              paymentMethod: 'نقدي',
              revenueType: 'إقامة',
              bookingUuidCache: const drift.Value('booking-void-sync-uuid'),
            ),
          );

      expect(
        await service.voidPayment(
          paymentUuid: 'fractional-payment-void-uuid',
          voidReason: 'precision guard',
          voidedBy: 'manager-1',
        ),
        isFalse,
      );
      expect(await database.select(database.paymentVoids).get(), isEmpty);
      expect(await database.select(database.auditLogs).get(), isEmpty);
      expect(
        (await database.select(database.payments).get()).single.isVoided,
        isFalse,
      );
    },
  );
}
