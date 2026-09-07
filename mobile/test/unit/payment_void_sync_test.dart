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
    },
  );
}
