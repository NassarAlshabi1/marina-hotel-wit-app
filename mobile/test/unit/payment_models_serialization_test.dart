// اختبارات نماذج المدفوعات: Payment (fromJson/toJson/copyWith) +
// BookingPaymentSummary + Receipt (الحقول الافتراضية) + Invoice.generatePdfBytes
// (توليد PDF فعلي داخل بيئة الاختبار — الخطوط محمّلة من rootBundle،
//  ولا يمس قناة Printing المنصة إطلاقاً).
//
// الهدف: رفع تغطية lib/models/payment_models.dart (كانت 0.9%).

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/models/payment_models.dart';

Payment _payment({
  String? referenceNumber,
  String? notes,
  PaymentMethod? method,
}) {
  return Payment(
    id: 'pay-1',
    bookingId: 'bk-42',
    amount: 12500.5,
    method: method ?? PaymentMethod.cash,
    status: PaymentStatus.completed,
    paymentDate: DateTime(2026, 9, 1, 15, 30),
    receivedBy: 'موظف الاستقبال',
    createdAt: DateTime(2026, 9, 1, 15, 30),
    updatedAt: DateTime(2026, 9, 2, 10, 0),
    notes: notes,
    referenceNumber: referenceNumber,
    cardLastFourDigits: null,
    bankName: null,
  );
}

void main() {
  group('Payment JSON', () {
    test('toJson يحتوي المفاتيح الصحيحة وأسماء enum و ISO', () {
      final p = _payment(notes: 'دفعة أولى', referenceNumber: 'REF-9');
      final json = p.toJson();

      expect(json['id'], 'pay-1');
      expect(json['bookingId'], 'bk-42');
      expect(json['amount'], 12500.5);
      expect(json['method'], 'cash');
      expect(json['status'], 'completed');
      expect(json['paymentDate'], '2026-09-01T15:30:00.000');
      expect(json['createdAt'], '2026-09-01T15:30:00.000');
      expect(json['updatedAt'], '2026-09-02T10:00:00.000');
      expect(json['notes'], 'دفعة أولى');
      expect(json['referenceNumber'], 'REF-9');
      expect(json['cardLastFourDigits'], isNull);
      expect(json['bankName'], isNull);
      expect(json['receivedBy'], 'موظف الاستقبال');
    });

    test('round-trip toJson → fromJson يحفظ جميع الحقول', () {
      final p = _payment(notes: 'ملاحظة', referenceNumber: 'R-1');
      final restored = Payment.fromJson(p.toJson());

      expect(restored.id, p.id);
      expect(restored.bookingId, p.bookingId);
      expect(restored.amount, p.amount);
      expect(restored.method, p.method);
      expect(restored.status, p.status);
      expect(restored.paymentDate, p.paymentDate);
      expect(restored.notes, p.notes);
      expect(restored.referenceNumber, p.referenceNumber);
      expect(restored.receivedBy, p.receivedBy);
      expect(restored.createdAt, p.createdAt);
      expect(restored.updatedAt, p.updatedAt);
    });

    test('fromJson يقبل amount كـ int ويحوله double', () {
      final json = _payment().toJson();
      json['amount'] = 500; // int وليس double
      final p = Payment.fromJson(json);

      expect(p.amount, isA<double>());
      expect(p.amount, 500.0);
    });

    test('fromJson يحل أسماء enum الصحيحة لكل القيم', () {
      for (final m in PaymentMethod.values) {
        final json = _payment().toJson()..['method'] = m.name;
        expect(Payment.fromJson(json).method, m, reason: 'method=${m.name}');
      }
      for (final s in PaymentStatus.values) {
        final json = _payment().toJson()..['status'] = s.name;
        expect(Payment.fromJson(json).status, s, reason: 'status=${s.name}');
      }
    });
  });

  group('Payment copyWith', () {
    test('نسخة كاملة بدون وسائط تحفظ كل الحقول', () {
      final p = _payment(notes: 'n', referenceNumber: 'r');
      final c = p.copyWith();

      expect(c.id, p.id);
      expect(c.amount, p.amount);
      expect(c.method, p.method);
      expect(c.status, p.status);
      expect(c.notes, p.notes);
      expect(c.referenceNumber, p.referenceNumber);
      expect(identical(c, p), isFalse);
    });

    test('التعديل الجزئي يغيّر المطلوب فقط', () {
      final p = _payment();
      final c = p.copyWith(
        id: 'pay-2',
        amount: 99.0,
        method: PaymentMethod.card,
        status: PaymentStatus.refunded,
        notes: 'بطاقة',
        cardLastFourDigits: '1234',
        bankName: 'بنك اليمن',
      );

      expect(c.id, 'pay-2');
      expect(c.amount, 99.0);
      expect(c.method, PaymentMethod.card);
      expect(c.status, PaymentStatus.refunded);
      expect(c.notes, 'بطاقة');
      expect(c.cardLastFourDigits, '1234');
      expect(c.bankName, 'بنك اليمن');
      // غير المتغيّر يبقى
      expect(c.bookingId, p.bookingId);
      expect(c.paymentDate, p.paymentDate);
      expect(c.receivedBy, p.receivedBy);
      // الأصل لم يُمَس
      expect(p.id, 'pay-1');
      expect(p.method, PaymentMethod.cash);
    });
  });

  group('BookingPaymentSummary', () {
    BookingPaymentSummary summary({
      double total = 1000,
      double paid = 400,
      double remaining = 600,
      List<Payment>? payments,
    }) {
      return BookingPaymentSummary(
        bookingId: 'bk-42',
        totalAmount: total,
        paidAmount: paid,
        remainingAmount: remaining,
        payments: payments ?? const [],
        overallStatus: PaymentStatus.pending,
      );
    }

    test('isFullyPaid: متبقي موجب = false، صفر وسالب = true', () {
      expect(summary(remaining: 600).isFullyPaid, isFalse);
      expect(summary(remaining: 0).isFullyPaid, isTrue);
      expect(summary(remaining: -50).isFullyPaid, isTrue);
    });

    test('paidPercentage: الحساب الطبيعي', () {
      final s = summary(total: 1000, paid: 400);
      expect(s.paidPercentage, closeTo(40.0, 0.0001));
    });

    test('paidPercentage: totalAmount صفر يعيد 0 بلا قسمة على صفر', () {
      expect(summary(total: 0, paid: 100).paidPercentage, 0.0);
    });

    test('قائمة الدفعات تُمرّر كما هي', () {
      final payments = [_payment(), _payment(referenceNumber: 'R2')];
      final s = summary(payments: payments);
      expect(s.payments, hasLength(2));
      expect(s.payments.first.referenceNumber, isNull);
      expect(s.payments.last.referenceNumber, 'R2');
    });
  });

  group('Receipt', () {
    test('الحقول الافتراضية للفندق صحيحة', () {
      final r = Receipt(
        receiptNumber: 'RC-1',
        payment: _payment(),
        guestName: 'أحمد',
        guestPhone: '777123456',
        roomNumber: '101',
        generatedAt: DateTime(2026, 9, 6, 20, 0),
      );

      expect(r.hotelName, 'فندق مارينا بلازا');
      expect(r.hotelAddress, 'عدن - اليمن - شارع أحمد قاسم');
      expect(r.hotelPhone, '+967-2-324457');
      expect(r.payment.id, 'pay-1');
    });

    test('تجاوز حقول الفندق يعمل', () {
      final r = Receipt(
        receiptNumber: 'RC-2',
        payment: _payment(),
        guestName: 'سالم',
        guestPhone: '',
        roomNumber: '',
        generatedAt: DateTime(2026, 9, 6),
        hotelName: 'فندق آخر',
        hotelAddress: 'عنوان آخر',
        hotelPhone: '+967-1-000000',
      );

      expect(r.hotelName, 'فندق آخر');
      expect(r.hotelAddress, 'عنوان آخر');
      expect(r.hotelPhone, '+967-1-000000');
    });
  });

  group('Invoice.generatePdfBytes (توليد PDF فعلي داخل الاختبار)', () {
    Future<Uint8List> buildInvoiceBytes(List<Payment> payments) {
      final invoice = Invoice(
        invoiceNumber: 'INV-1',
        bookingId: 'bk-42',
        guestName: 'أحمد سالم',
        guestPhone: '777123456',
        roomNumber: '101',
        checkinDate: DateTime(2026, 8, 30, 14, 1),
        checkoutDate: DateTime(2026, 9, 6, 12, 0),
        nights: 7,
        roomRate: 15000,
        totalAmount: 105000,
        payments: payments,
        remainingAmount: 105000 - payments.fold(0.0, (a, p) => a + p.amount),
        generatedAt: DateTime(2026, 9, 6, 21, 0),
      );
      return invoice.generatePdfBytes();
    }

    test('ينتج bytes بصيغة PDF صحيحة (رأس %PDF)', () async {
      final bytes = await buildInvoiceBytes([_payment()]);
      expect(bytes, isNotEmpty);
      // بنية ملف PDF: يبدأ بـ %PDF-
      final header = String.fromCharCodes(bytes.take(5));
      expect(header, '%PDF-');
    });

    test('فاتورة بدفعات متعددة (مع وبدون رقم مرجع) تنجح', () async {
      final payments = [
        _payment(referenceNumber: 'TRX-77'),
        _payment(), // بلا مرجع
        _payment(method: PaymentMethod.transfer, notes: 'حوالة'),
      ];
      final bytes = await buildInvoiceBytes(payments);
      expect(bytes.length, greaterThan(1000));
      final header = String.fromCharCodes(bytes.take(5));
      expect(header, '%PDF-');
    });

    test('فاتورة بلا دفعات (قائمة فارغة) تنجح', () async {
      final bytes = await buildInvoiceBytes(const []);
      expect(bytes, isNotEmpty);
      final header = String.fromCharCodes(bytes.take(5));
      expect(header, '%PDF-');
    });
  });
}
