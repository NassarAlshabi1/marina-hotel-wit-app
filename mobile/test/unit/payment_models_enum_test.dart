// ============================================================================
//  Marina Hotel — Unit Tests: Payment Models Enums
//  ============================================================
//  اختبارات unit لـ PaymentMethod و PaymentStatus enums.
//  نُقلت من integration_test/booking_payment_test.dart لأن flutter test
//  integration_test/ يرفض تشغيل unit tests (test()) مع integration tests
//  (testWidgets()) في نفس invocation.
// ============================================================================

import 'package:flutter_test/flutter_test.dart';

import 'package:marina_hotel_mobile/models/payment_models.dart';

void main() {
  group('PaymentMethod enum', () {
    test('يحتوي على 5 طرق دفع', () {
      expect(PaymentMethod.values.length, 5);
    });

    test('يحتوي على أسماء عربية صحيحة', () {
      expect(PaymentMethod.cash.displayName, 'نقدي');
      expect(PaymentMethod.card.displayName, 'بطاقة ائتمانية');
      expect(PaymentMethod.transfer.displayName, 'تحويل بنكي');
      expect(PaymentMethod.check.displayName, 'شيك');
      expect(PaymentMethod.installment.displayName, 'تقسيط');
    });

    test('كل طريقة لها أيقونة', () {
      for (final method in PaymentMethod.values) {
        expect(
          method.icon,
          isNotNull,
          reason: 'الطريقة $method يجب أن لها أيقونة',
        );
      }
    });

    test('كل طريقة لها لون مميز', () {
      for (final method in PaymentMethod.values) {
        expect(
          method.color,
          isNotNull,
          reason: 'الطريقة $method يجب أن لها لون',
        );
      }
    });
  });

  group('PaymentStatus enum', () {
    test('يحتوي على 4 حالات', () {
      expect(PaymentStatus.values.length, 4);
    });

    test('يحتوي على أسماء عربية صحيحة', () {
      expect(PaymentStatus.completed.displayName, 'مكتمل');
      expect(PaymentStatus.pending.displayName, 'في الانتظار');
      expect(PaymentStatus.failed.displayName, 'فشل');
      expect(PaymentStatus.refunded.displayName, 'مسترد');
    });

    test('كل حالة لها لون مميز', () {
      for (final status in PaymentStatus.values) {
        expect(
          status.color,
          isNotNull,
          reason: 'الحالة $status يجب أن لها لون',
        );
      }
    });
  });
}
