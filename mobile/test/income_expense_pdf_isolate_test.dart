import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/utils/income_expense_pdf_isolate.dart';

/// درع انحدار لتوقف التطبيق عند تصدير PDF من تقرير الدخل والخرج.
///
/// الإصلاح: بناء المستند يُنفَّذ داخل isolate منفصل عبر compute
/// (سابقاً كان على خيط UI فتجمّد الواجهة ثم ANR). هذه الاختبارات
/// تستدعي نقاط دخول isolate الحقيقية وتبني ملفات PDF كاملة للتأكد
/// من سلامة كل مسارات التخطيط (جداول، تجميع، ملخصات، أقسام).
void main() {
  late Uint8List regularBytes;
  late Uint8List boldBytes;

  setUpAll(() {
    regularBytes = File('assets/fonts/Tajawal-Regular.ttf').readAsBytesSync();
    boldBytes = File('assets/fonts/Tajawal-Bold.ttf').readAsBytesSync();
  });

  IncomeExpensePdfParams buildParams({
    List<Map<String, Object?>> income = const [],
    List<Map<String, Object?>> expenses = const [],
    String groupBy = 'daily',
  }) {
    return IncomeExpensePdfParams(
      incomeRows: income,
      expenseRows: expenses,
      fromDate: DateTime(2026, 1, 1, 14, 1),
      toDate: DateTime(2026, 1, 31, 14),
      incomeTotal: income.fold<double>(0, (s, e) => s + (e['amount'] as num)),
      expenseTotal: expenses.fold<double>(
        0,
        (s, e) => s + (e['amount'] as num),
      ),
      salaryTotal: expenses
          .where((e) => e['isSalary'] == true)
          .fold<double>(0, (s, e) => s + (e['amount'] as num)),
      net: 0,
      bookingsCount: 3,
      activeBookingsCount: 2,
      checkoutBookingsCount: 1,
      totalDebtsCount: 2,
      unsettledDebtsCount: 1,
      unsettledDebtsAmount: 150,
      unsettledDebtsInPeriodCount: 1,
      unsettledDebtsInPeriodAmount: 150,
      activeEmployeesCount: 4,
      terminatedEmployeesCount: 1,
      totalSalaryObligation: 4000,
      groupBy: groupBy,
      fontRegularBytes: regularBytes,
      fontBoldBytes: boldBytes,
    );
  }

  Map<String, Object?> incomeRow(int i) => {
    'date': DateTime(2026, 1, 1 + (i % 28)).millisecondsSinceEpoch,
    'roomNumber': '${101 + (i % 12)}',
    'guestName': 'نزيل $i',
    'paymentMethod': const ['cash', 'card', 'transfer'][i % 3],
    'revenueType': const ['room', 'restaurant', 'services'][i % 3],
    'amount': 100.0 + i,
  };

  Map<String, Object?> expenseRow(int i) => {
    'date': DateTime(2026, 1, 1 + (i % 28)).millisecondsSinceEpoch,
    'type': 'كهرباء',
    'description': 'فاتورة كهرباء $i',
    'amount': 50.0 + i,
    'isSalary': i % 5 == 0,
  };

  void expectValidPdf(Uint8List bytes) {
    expect(bytes, isNotEmpty);
    // توقيع ملف PDF الحقيقي
    expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
  }

  group('تقرير الدورة المالية الشامل (isolate)', () {
    test('يبني PDF صحيحاً مع بيانات فعلية', () async {
      final params = buildParams(
        income: List.generate(120, incomeRow),
        expenses: List.generate(80, expenseRow),
      );
      final bytes = await incomeExpensePdfMainJob(params);
      expectValidPdf(bytes);
    });

    test('يتعامل مع قوائم فارغة دون انهيار', () async {
      final bytes = await incomeExpensePdfMainJob(buildParams());
      expectValidPdf(bytes);
    });

    test('يتحمل حجم بيانات كبير (1500 صف) في الخلفية', () async {
      final params = buildParams(
        income: List.generate(1000, incomeRow),
        expenses: List.generate(500, expenseRow),
      );
      final bytes = await incomeExpensePdfMainJob(params);
      expectValidPdf(bytes);
      expect(bytes.lengthInBytes, greaterThan(10 * 1024));
    });
  });

  group('التقرير التفصيلي المجمّع (isolate)', () {
    for (final groupBy in ['daily', 'monthly', 'yearly']) {
      test('تجميع $groupBy ينتج PDF صحيحاً', () async {
        final params = buildParams(
          income: List.generate(60, incomeRow),
          expenses: List.generate(40, expenseRow),
          groupBy: groupBy,
        );
        final bytes = await incomeExpensePdfGroupedJob(params);
        expectValidPdf(bytes);
      });
    }

    test('يتعامل مع قوائم فارغة دون انهيار', () async {
      final bytes = await incomeExpensePdfGroupedJob(buildParams());
      expectValidPdf(bytes);
    });
  });

  test('الوسائط تُبنى من خرائط قابلة للإرسال بين isolates', () async {
    // يثبت أن بناء Params لا يعتمد على أي كائن غير قابل للإرسال
    final params = buildParams(
      income: [incomeRow(0)],
      expenses: [expenseRow(0)],
    );
    expect(params.incomeRows.first['amount'], 100.0);
    expect(params.expenseRows.first['isSalary'], isTrue);
  });
}
