// ============================================================================
//  PaymentModels — Unit Tests
// ============================================================================
//  اختبارات نماذج المدفوعات (lib/models/payment_models.dart):
//    - PaymentMethod / PaymentStatus — أسماء العرض العربية والعدد
//    - Payment — fromJson/toJson (رحلة ذهاب وعودة كاملة)، حقل amount
//      كـ int و double، copyWith (تغيير + حفظ القيم الأخرى)
//    - BookingPaymentSummary — isFullyPaid و paidPercentage (حالات
//      عادية، صفر إجمالي، دفع زائد)
//
//  هذه اختبارات منطق خالص بلا شبكة ولا قاعدة بيانات — مستقرة تماماً.
// ============================================================================

library marina_hotel_mobile.test.payment_models_test;

import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/models/payment_models.dart';

Payment _payment({
  double amount = 15000,
  String? notes,
  String? referenceNumber,
}) {
  final now = DateTime(2026, 9, 24, 12);
  return Payment(
    id: 'p-1',
    bookingId: 'b-1',
    amount: amount,
    method: PaymentMethod.cash,
    status: PaymentStatus.completed,
    paymentDate: now,
    receivedBy: 'موظف الاستقبال',
    createdAt: now,
    updatedAt: now,
    notes: notes,
    referenceNumber: referenceNumber,
  );
}

void main() {
  group('PaymentMethod', () {
    test('عدد القيم خمسة وأسماؤها العربية صحيحة', () {
      expect(PaymentMethod.values.length, 5);
      expect(PaymentMethod.cash.displayName, 'نقدي');
      expect(PaymentMethod.card.displayName, 'بطاقة ائتمانية');
      expect(PaymentMethod.transfer.displayName, 'تحويل بنكي');
      expect(PaymentMethod.check.displayName, 'شيك');
      expect(PaymentMethod.installment.displayName, 'تقسيط');
    });
  });

  group('PaymentStatus', () {
    test('عدد القيم أربعة وأسماؤها العربية صحيحة', () {
      expect(PaymentStatus.values.length, 4);
      expect(PaymentStatus.pending.displayName, 'في الانتظار');
      expect(PaymentStatus.completed.displayName, 'مكتمل');
      expect(PaymentStatus.failed.displayName, 'فشل');
      expect(PaymentStatus.refunded.displayName, 'مسترد');
    });
  });

  group('Payment toJson/fromJson', () {
    test('رحلة ذهاب وعودة تحفظ كل الحقول', () {
      final payment = _payment(
        notes: 'دفعة أولى',
        referenceNumber: 'REF-42',
      );
      final restored = Payment.fromJson(payment.toJson());

      expect(restored.id, payment.id);
      expect(restored.bookingId, payment.bookingId);
      expect(restored.amount, payment.amount);
      expect(restored.method, payment.method);
      expect(restored.status, payment.status);
      expect(restored.paymentDate, payment.paymentDate);
      expect(restored.receivedBy, payment.receivedBy);
      expect(restored.createdAt, payment.createdAt);
      expect(restored.updatedAt, payment.updatedAt);
      expect(restored.notes, payment.notes);
      expect(restored.referenceNumber, payment.referenceNumber);
    });

    test('يقبل amount كـ int من JSON ويعيده double', () {
      final json = _payment().toJson()..['amount'] = 20000;
      final restored = Payment.fromJson(json);

      expect(restored.amount, isA<double>());
      expect(restored.amount, 20000.0);
    });

    test('الحقول الاختيارية الفارغة تبقى null بعد الجولة', () {
      final restored = Payment.fromJson(_payment().toJson());

      expect(restored.notes, isNull);
      expect(restored.referenceNumber, isNull);
      expect(restored.cardLastFourDigits, isNull);
      expect(restored.bankName, isNull);
    });

    test('toIdempotentJson غير مطلوب — toJson يرمّز enum بالاسم', () {
      final json = _payment().toJson();

      expect(json['method'], 'cash');
      expect(json['status'], 'completed');
    });
  });

  group('Payment copyWith', () {
    test('يغيّر الحقل المطلوب فقط ويحافظ على البقية', () {
      final original = _payment(
        amount: 15000,
        notes: 'ملاحظة أصلية',
        referenceNumber: 'REF-1',
      );
      final updated = original.copyWith(
        amount: 25000,
        method: PaymentMethod.card,
        status: PaymentStatus.refunded,
      );

      expect(updated.amount, 25000);
      expect(updated.method, PaymentMethod.card);
      expect(updated.status, PaymentStatus.refunded);
      // الحقول غير الممرة تبقى كما هي
      expect(updated.id, original.id);
      expect(updated.bookingId, original.bookingId);
      expect(updated.notes, original.notes);
      expect(updated.referenceNumber, original.referenceNumber);
      expect(updated.receivedBy, original.receivedBy);
      expect(updated.paymentDate, original.paymentDate);
    });
  });

  group('BookingPaymentSummary', () {
    test('isFullyPaid صحيح عند تسوية كامل المبلغ', () {
      final summary = BookingPaymentSummary(
        bookingId: 'b-1',
        totalAmount: 30000,
        paidAmount: 30000,
        remainingAmount: 0,
        payments: const [],
        overallStatus: PaymentStatus.completed,
      );

      expect(summary.isFullyPaid, isTrue);
      expect(summary.paidPercentage, closeTo(100.0, 0.001));
    });

    test('isFullyPaid خطأ عند وجود متبقٍ', () {
      final summary = BookingPaymentSummary(
        bookingId: 'b-1',
        totalAmount: 30000,
        paidAmount: 10000,
        remainingAmount: 20000,
        payments: const [],
        overallStatus: PaymentStatus.pending,
      );

      expect(summary.isFullyPaid, isFalse);
      expect(summary.paidPercentage, closeTo(10000 / 30000 * 100, 0.001));
    });

    test(
      'paidPercentage يُرجع 0 عندما totalAmount صفر (تجنب القسمة على صفر)',
      () {
        final summary = BookingPaymentSummary(
          bookingId: 'b-1',
          totalAmount: 0,
          paidAmount: 0,
          remainingAmount: 0,
          payments: const [],
          overallStatus: PaymentStatus.pending,
        );

        expect(summary.paidPercentage, 0.0);
      },
    );

    test('الدفع الزائد يعطي isFullyPaid صحيحاً ونسبة أكبر من 100', () {
      final summary = BookingPaymentSummary(
        bookingId: 'b-1',
        totalAmount: 10000,
        paidAmount: 12000,
        remainingAmount: -2000,
        payments: const [],
        overallStatus: PaymentStatus.completed,
      );

      expect(summary.isFullyPaid, isTrue);
      expect(summary.paidPercentage, greaterThan(100));
    });
  });
}
