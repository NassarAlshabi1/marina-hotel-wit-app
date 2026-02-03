import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/models/payment_models.dart';

void main() {
  group('PaymentMethod', () {
    test('يجب أن تحتوي على جميع طرق الدفع', () {
      expect(PaymentMethod.values.length, 5);
      expect(PaymentMethod.values, contains(PaymentMethod.cash));
      expect(PaymentMethod.values, contains(PaymentMethod.card));
      expect(PaymentMethod.values, contains(PaymentMethod.transfer));
      expect(PaymentMethod.values, contains(PaymentMethod.check));
      expect(PaymentMethod.values, contains(PaymentMethod.installment));
    });

    test('يجب أن تحتوي على أسماء عربية صحيحة', () {
      expect(PaymentMethod.cash.displayName, 'نقدي');
      expect(PaymentMethod.card.displayName, 'بطاقة ائتمانية');
      expect(PaymentMethod.transfer.displayName, 'تحويل بنكي');
      expect(PaymentMethod.check.displayName, 'شيك');
      expect(PaymentMethod.installment.displayName, 'تقسيط');
    });

    test('يجب أن تحتوي على أيقونات', () {
      expect(PaymentMethod.cash.icon, Icons.money);
      expect(PaymentMethod.card.icon, Icons.credit_card);
      expect(PaymentMethod.transfer.icon, Icons.account_balance);
      expect(PaymentMethod.check.icon, Icons.receipt_long);
      expect(PaymentMethod.installment.icon, Icons.schedule);
    });

    test('يجب أن تحتوي على ألوان مميزة', () {
      expect(PaymentMethod.cash.color, Colors.green);
      expect(PaymentMethod.card.color, Colors.blue);
      expect(PaymentMethod.transfer.color, Colors.purple);
      expect(PaymentMethod.check.color, Colors.orange);
      expect(PaymentMethod.installment.color, Colors.indigo);
    });
  });

  group('PaymentStatus', () {
    test('يجب أن تحتوي على جميع الحالات', () {
      expect(PaymentStatus.values.length, 4);
      expect(PaymentStatus.values, contains(PaymentStatus.pending));
      expect(PaymentStatus.values, contains(PaymentStatus.completed));
      expect(PaymentStatus.values, contains(PaymentStatus.failed));
      expect(PaymentStatus.values, contains(PaymentStatus.refunded));
    });

    test('يجب أن تحتوي على أسماء عربية صحيحة', () {
      expect(PaymentStatus.pending.displayName, 'في الانتظار');
      expect(PaymentStatus.completed.displayName, 'مكتمل');
      expect(PaymentStatus.failed.displayName, 'فشل');
      expect(PaymentStatus.refunded.displayName, 'مسترد');
    });

    test('يجب أن تحتوي على ألوان مميزة', () {
      expect(PaymentStatus.pending.color, Colors.orange);
      expect(PaymentStatus.completed.color, Colors.green);
      expect(PaymentStatus.failed.color, Colors.red);
      expect(PaymentStatus.refunded.color, Colors.blue);
    });
  });

  group('BookingPaymentSummary', () {
    test('يجب حفظ المبلغ المتبقي بشكل صحيح', () {
      final summary = BookingPaymentSummary(
        bookingId: 'test-booking-1',
        totalAmount: 50000,
        paidAmount: 20000,
        remainingAmount: 30000,
        payments: [],
        overallStatus: PaymentStatus.pending,
      );

      expect(summary.remainingAmount, 30000);
    });

    test('يجب حساب نسبة الدفع بشكل صحيح', () {
      final summary = BookingPaymentSummary(
        bookingId: 'test-booking-2',
        totalAmount: 100000,
        paidAmount: 25000,
        remainingAmount: 75000,
        payments: [],
        overallStatus: PaymentStatus.pending,
      );

      expect(summary.paidPercentage, 25.0);
    });

    test('يجب أن تكون isFullyPaid صحيحة عند الدفع الكامل', () {
      final fullyPaid = BookingPaymentSummary(
        bookingId: 'test-booking-3',
        totalAmount: 50000,
        paidAmount: 50000,
        remainingAmount: 0,
        payments: [],
        overallStatus: PaymentStatus.completed,
      );

      expect(fullyPaid.isFullyPaid, isTrue);
      expect(fullyPaid.remainingAmount, 0);
      expect(fullyPaid.paidPercentage, 100.0);
    });

    test('يجب أن تكون isFullyPaid خاطئة عند الدفع الجزئي', () {
      final partialPaid = BookingPaymentSummary(
        bookingId: 'test-booking-4',
        totalAmount: 50000,
        paidAmount: 30000,
        remainingAmount: 20000,
        payments: [],
        overallStatus: PaymentStatus.pending,
      );

      expect(partialPaid.isFullyPaid, isFalse);
    });

    test('يجب معالجة الدفع الزائد بشكل صحيح', () {
      final overPaid = BookingPaymentSummary(
        bookingId: 'test-booking-5',
        totalAmount: 50000,
        paidAmount: 60000,
        remainingAmount: -10000,
        payments: [],
        overallStatus: PaymentStatus.completed,
      );

      expect(overPaid.remainingAmount, -10000);
      expect(overPaid.isFullyPaid, isTrue);
      expect(overPaid.paidPercentage, 120.0);
    });

    test('يجب معالجة المبلغ صفر', () {
      final zeroPaid = BookingPaymentSummary(
        bookingId: 'test-booking-6',
        totalAmount: 50000,
        paidAmount: 0,
        remainingAmount: 50000,
        payments: [],
        overallStatus: PaymentStatus.pending,
      );

      expect(zeroPaid.remainingAmount, 50000);
      expect(zeroPaid.paidPercentage, 0.0);
      expect(zeroPaid.isFullyPaid, isFalse);
    });

    test('يجب حفظ حالة الدفع بشكل صحيح', () {
      final pending = BookingPaymentSummary(
        bookingId: 'test-1',
        totalAmount: 50000,
        paidAmount: 0,
        remainingAmount: 50000,
        payments: [],
        overallStatus: PaymentStatus.pending,
      );
      expect(pending.overallStatus, PaymentStatus.pending);

      final failed = BookingPaymentSummary(
        bookingId: 'test-2',
        totalAmount: 50000,
        paidAmount: 0,
        remainingAmount: 50000,
        payments: [],
        overallStatus: PaymentStatus.failed,
      );
      expect(failed.overallStatus, PaymentStatus.failed);

      final completed = BookingPaymentSummary(
        bookingId: 'test-3',
        totalAmount: 50000,
        paidAmount: 50000,
        remainingAmount: 0,
        payments: [],
        overallStatus: PaymentStatus.completed,
      );
      expect(completed.overallStatus, PaymentStatus.completed);
    });

    test('حالات واقعية من الفندق', () {
      final realCase = BookingPaymentSummary(
        bookingId: 'booking-302',
        totalAmount: 42900,
        paidAmount: 0,
        remainingAmount: 42900,
        payments: [],
        overallStatus: PaymentStatus.pending,
      );

      expect(realCase.remainingAmount, 42900);
      expect(realCase.paidPercentage, 0.0);
      expect(realCase.overallStatus, PaymentStatus.pending);
    });
  });

  group('Payment', () {
    test('يجب إنشاء سجل دفع بشكل صحيح', () {
      final record = Payment(
        id: 'pay-1',
        bookingId: 'booking-1',
        amount: 15000,
        method: PaymentMethod.cash,
        status: PaymentStatus.completed,
        paymentDate: DateTime(2024, 1, 15, 10, 30),
        receivedBy: 'admin',
        createdAt: DateTime(2024, 1, 15, 10, 31),
        updatedAt: DateTime(2024, 1, 15, 10, 31),
      );

      expect(record.id, 'pay-1');
      expect(record.bookingId, 'booking-1');
      expect(record.amount, 15000);
      expect(record.method, PaymentMethod.cash);
      expect(record.status, PaymentStatus.completed);
      expect(record.paymentDate.year, 2024);
    });

    test('يجب دعم جميع طرق الدفع', () {
      for (final method in PaymentMethod.values) {
        final record = Payment(
          id: 'pay-${method.name}',
          bookingId: 'booking-1',
          amount: 10000,
          method: method,
          status: PaymentStatus.pending,
          paymentDate: DateTime.now(),
          receivedBy: 'system',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        expect(record.method, method);
      }
    });
  });
}
