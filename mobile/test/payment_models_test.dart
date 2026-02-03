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
      expect(PaymentStatus.values, contains(PaymentStatus.partial));
      expect(PaymentStatus.values, contains(PaymentStatus.completed));
      expect(PaymentStatus.values, contains(PaymentStatus.refunded));
    });

    test('يجب أن تحتوي على أسماء عربية صحيحة', () {
      expect(PaymentStatus.pending.displayName, 'في الانتظار');
      expect(PaymentStatus.partial.displayName, 'دفع جزئي');
      expect(PaymentStatus.completed.displayName, 'مكتمل');
      expect(PaymentStatus.refunded.displayName, 'مسترد');
    });

    test('يجب أن تحتوي على ألوان مميزة', () {
      expect(PaymentStatus.pending.color, Colors.orange);
      expect(PaymentStatus.partial.color, Colors.blue);
      expect(PaymentStatus.completed.color, Colors.green);
      expect(PaymentStatus.refunded.color, Colors.red);
    });
  });

  group('BookingPaymentSummary', () {
    test('يجب حساب المبلغ المتبقي بشكل صحيح', () {
      final summary = BookingPaymentSummary(
        bookingId: 'test-booking-1',
        guestName: 'أحمد',
        roomNumber: '101',
        totalAmount: 50000,
        paidAmount: 20000,
        payments: [],
      );

      expect(summary.remainingAmount, 30000);
    });

    test('يجب حساب نسبة الدفع بشكل صحيح', () {
      final summary = BookingPaymentSummary(
        bookingId: 'test-booking-2',
        guestName: 'محمد',
        roomNumber: '102',
        totalAmount: 100000,
        paidAmount: 25000,
        payments: [],
      );

      expect(summary.paymentProgress, 0.25);
    });

    test('يجب أن تكون isFullyPaid صحيحة عند الدفع الكامل', () {
      final fullyPaid = BookingPaymentSummary(
        bookingId: 'test-booking-3',
        guestName: 'علي',
        roomNumber: '103',
        totalAmount: 50000,
        paidAmount: 50000,
        payments: [],
      );

      expect(fullyPaid.isFullyPaid, isTrue);
      expect(fullyPaid.remainingAmount, 0);
      expect(fullyPaid.paymentProgress, 1.0);
    });

    test('يجب أن تكون isFullyPaid خاطئة عند الدفع الجزئي', () {
      final partialPaid = BookingPaymentSummary(
        bookingId: 'test-booking-4',
        guestName: 'سعيد',
        roomNumber: '104',
        totalAmount: 50000,
        paidAmount: 30000,
        payments: [],
      );

      expect(partialPaid.isFullyPaid, isFalse);
    });

    test('يجب معالجة الدفع الزائد بشكل صحيح', () {
      final overPaid = BookingPaymentSummary(
        bookingId: 'test-booking-5',
        guestName: 'خالد',
        roomNumber: '105',
        totalAmount: 50000,
        paidAmount: 60000,
        payments: [],
      );

      expect(overPaid.remainingAmount, -10000);
      expect(overPaid.isFullyPaid, isTrue);
    });

    test('يجب معالجة المبلغ صفر', () {
      final zeroPaid = BookingPaymentSummary(
        bookingId: 'test-booking-6',
        guestName: 'فهد',
        roomNumber: '106',
        totalAmount: 50000,
        paidAmount: 0,
        payments: [],
      );

      expect(zeroPaid.remainingAmount, 50000);
      expect(zeroPaid.paymentProgress, 0.0);
      expect(zeroPaid.isFullyPaid, isFalse);
    });

    test('يجب إرجاع حالة الدفع الصحيحة', () {
      final pending = BookingPaymentSummary(
        bookingId: 'test-1',
        guestName: 'ضيف',
        roomNumber: '101',
        totalAmount: 50000,
        paidAmount: 0,
        payments: [],
      );
      expect(pending.status, PaymentStatus.pending);

      final partial = BookingPaymentSummary(
        bookingId: 'test-2',
        guestName: 'ضيف',
        roomNumber: '102',
        totalAmount: 50000,
        paidAmount: 25000,
        payments: [],
      );
      expect(partial.status, PaymentStatus.partial);

      final completed = BookingPaymentSummary(
        bookingId: 'test-3',
        guestName: 'ضيف',
        roomNumber: '103',
        totalAmount: 50000,
        paidAmount: 50000,
        payments: [],
      );
      expect(completed.status, PaymentStatus.completed);
    });

    test('حالات واقعية من الفندق', () {
      final realCase = BookingPaymentSummary(
        bookingId: 'booking-302',
        guestName: 'فايز جهلان',
        roomNumber: '302',
        totalAmount: 42900,
        paidAmount: 0,
        payments: [],
      );

      expect(realCase.remainingAmount, 42900);
      expect(realCase.paymentProgress, 0.0);
      expect(realCase.status, PaymentStatus.pending);
    });
  });

  group('PaymentRecord', () {
    test('يجب إنشاء سجل دفع بشكل صحيح', () {
      final record = PaymentRecord(
        id: 'pay-1',
        bookingId: 'booking-1',
        amount: 15000,
        method: PaymentMethod.cash,
        date: DateTime(2024, 1, 15, 10, 30),
      );

      expect(record.id, 'pay-1');
      expect(record.bookingId, 'booking-1');
      expect(record.amount, 15000);
      expect(record.method, PaymentMethod.cash);
      expect(record.date.year, 2024);
    });

    test('يجب دعم جميع طرق الدفع', () {
      for (final method in PaymentMethod.values) {
        final record = PaymentRecord(
          id: 'pay-${method.name}',
          bookingId: 'booking-1',
          amount: 10000,
          method: method,
          date: DateTime.now(),
        );
        expect(record.method, method);
      }
    });
  });
}
