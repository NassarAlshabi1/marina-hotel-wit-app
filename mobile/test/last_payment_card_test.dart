import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:marina_hotel_mobile/screens/payments/widgets/last_payment_card.dart';
import 'package:marina_hotel_mobile/services/local_db.dart' as db;

/// اختبارات بطاقة «آخر مبلغ مدفوع» في شاشة معالجة المدفوعات.
///
/// البطاقة عرضية بحتة: تختار أحدث دفعة غير ملغاة وتعرض مبلغها
/// وطريقة الدفع والتاريخ، وتختفي كلياً إن لم توجد أي دفعة صالحة.
void main() {
  final fmt = NumberFormat('#,##0', 'en_US');

  db.Payment payment({
    required int id,
    required double amount,
    required String paymentDate,
    String paymentMethod = 'نقدي',
    bool isVoided = false,
  }) {
    return db.Payment(
      localUuid: 'p-$id',
      id: id,
      createdAt: id,
      updatedAt: id,
      lastModified: id,
      createdAtEpoch: id,
      lastModifiedEpoch: id,
      version: 1,
      origin: 'local',
      vectorClock: '{}',
      deviceId: 'test-device',
      syncTimestamp: id,
      amount: amount,
      paymentDate: paymentDate,
      paymentMethod: paymentMethod,
      revenueType: 'room',
      isPendingBalance: false,
      isVoided: isVoided,
      isImmutable: false,
    );
  }

  Widget buildCard(List<db.Payment> payments) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: MaterialApp(
        home: Scaffold(
          body: LastPaymentCard(payments: payments, currencyFmt: fmt),
        ),
      ),
    );
  }

  testWidgets('تُخفى البطاقة بالكامل عند عدم وجود مدفوعات', (tester) async {
    await tester.pumpWidget(buildCard(const []));
    expect(find.text('آخر مبلغ مدفوع'), findsNothing);
  });

  testWidgets('تُخفى عندما تكون كل المدفوعات ملغاة', (tester) async {
    await tester.pumpWidget(
      buildCard([
        payment(
          id: 1,
          amount: 500,
          paymentDate: '2025-01-15 14:30',
          isVoided: true,
        ),
      ]),
    );
    expect(find.text('آخر مبلغ مدفوع'), findsNothing);
  });

  testWidgets('تعرض المبلغ وطريقة الدفع وتاريخ أحدث دفعة', (tester) async {
    await tester.pumpWidget(
      buildCard([
        payment(id: 1, amount: 300, paymentDate: '2025-01-10T10:00:00'),
        payment(id: 2, amount: 1250, paymentDate: '2025-01-15T14:30:00'),
      ]),
    );
    expect(find.text('آخر مبلغ مدفوع'), findsOneWidget);
    expect(find.text(fmt.format(1250)), findsOneWidget);
    // تاريخ الدفعة الأحدث وليس الأقدم
    expect(find.textContaining('2025/01/15 • 14:30'), findsOneWidget);
    expect(find.textContaining('2025/01/10'), findsNothing);
    expect(find.textContaining('نقدي'), findsOneWidget);
  });

  testWidgets('تتجاهل دفعة ملغاة أحدث وتعرض أقدم دفعة صالحة', (tester) async {
    await tester.pumpWidget(
      buildCard([
        payment(id: 1, amount: 400, paymentDate: '2025-01-12T09:00:00'),
        payment(
          id: 2,
          amount: 9000,
          paymentDate: '2025-01-20T18:00:00',
          isVoided: true,
        ),
      ]),
    );
    expect(find.text(fmt.format(400)), findsOneWidget);
    expect(find.text(fmt.format(9000)), findsNothing);
    expect(find.textContaining('2025/01/12 • 09:00'), findsOneWidget);
    expect(find.textContaining('2025/01/20'), findsNothing);
  });

  testWidgets('تتعامل مع صيغة التاريخ بمسافة بدل T', (tester) async {
    await tester.pumpWidget(
      buildCard([
        payment(id: 1, amount: 700, paymentDate: '2025-02-03 21:05'),
      ]),
    );
    expect(find.text(fmt.format(700)), findsOneWidget);
    expect(find.textContaining('2025/02/03 • 21:05'), findsOneWidget);
  });
}
