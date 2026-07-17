import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/utils/currency_formatter.dart';

void main() {
  group('CurrencyFormatter', () {
    group('formatAmount', () {
      test('يجب تنسيق الأرقام الصحيحة بفواصل', () {
        expect(CurrencyFormatter.formatAmount(1000), '1,000');
        expect(CurrencyFormatter.formatAmount(10000), '10,000');
        expect(CurrencyFormatter.formatAmount(100000), '100,000');
        expect(CurrencyFormatter.formatAmount(1000000), '1,000,000');
      });

      test('يجب تقريب الكسور العشرية', () {
        expect(CurrencyFormatter.formatAmount(1000.99), '1,000');
        expect(CurrencyFormatter.formatAmount(1000.01), '1,000');
        expect(CurrencyFormatter.formatAmount(1000.5), '1,000');
      });

      test('يجب معالجة الصفر بشكل صحيح', () {
        expect(CurrencyFormatter.formatAmount(0), '0');
        expect(CurrencyFormatter.formatAmount(0.0), '0');
      });

      test('يجب معالجة الأرقام السالبة', () {
        expect(CurrencyFormatter.formatAmount(-1000), '-1,000');
        expect(CurrencyFormatter.formatAmount(-500.5), '-500');
      });

      test('يجب معالجة الأرقام الصغيرة', () {
        expect(CurrencyFormatter.formatAmount(1), '1');
        expect(CurrencyFormatter.formatAmount(99), '99');
        expect(CurrencyFormatter.formatAmount(100), '100');
      });
    });

    group('formatCurrency', () {
      test('يجب أن يعمل مثل formatAmount', () {
        expect(CurrencyFormatter.formatCurrency(5000), '5,000');
        expect(CurrencyFormatter.formatCurrency(12345), '12,345');
      });
    });

    group('formatForDisplay', () {
      test('يجب تنسيق المبلغ للعرض', () {
        expect(CurrencyFormatter.formatForDisplay(15000), '15,000');
        expect(CurrencyFormatter.formatForDisplay(42900), '42,900');
      });
    });

    group('formatForMessage', () {
      test('يجب تنسيق المبلغ للرسائل', () {
        expect(CurrencyFormatter.formatForMessage(25000), '25,000');
      });
    });

    group('parseAmount', () {
      test('يجب تحويل الأرقام الإنجليزية', () {
        expect(CurrencyFormatter.parseAmount('1000'), 1000);
        expect(CurrencyFormatter.parseAmount('5,000'), 5000);
        expect(CurrencyFormatter.parseAmount('15,000'), 15000);
      });

      test('يجب تحويل الأرقام العربية', () {
        expect(CurrencyFormatter.parseAmount('١٠٠٠'), 1000);
        expect(CurrencyFormatter.parseAmount('٥٠٠٠'), 5000);
        expect(CurrencyFormatter.parseAmount('١٥٬٠٠٠'), 15000);
      });

      test('يجب تحويل الأرقام الفارسية', () {
        expect(CurrencyFormatter.parseAmount('۱۰۰۰'), 1000);
        expect(CurrencyFormatter.parseAmount('۵۰۰۰'), 5000);
      });

      test('يجب معالجة الفواصل العربية', () {
        expect(CurrencyFormatter.parseAmount('1٬000'), 1000);
        expect(CurrencyFormatter.parseAmount('1،000'), 1000);
      });

      test('يجب معالجة الكسور العشرية', () {
        expect(CurrencyFormatter.parseAmount('1000.5'), 1000);
        expect(CurrencyFormatter.parseAmount('1000٫5'), 1000);
      });

      test('يجب إزالة المسافات', () {
        expect(CurrencyFormatter.parseAmount('  1000  '), 1000);
        expect(CurrencyFormatter.parseAmount(' 5,000 '), 5000);
      });

      test('يجب إرجاع null للنص غير الصالح', () {
        expect(CurrencyFormatter.parseAmount('abc'), isNull);
        expect(CurrencyFormatter.parseAmount(''), isNull);
        expect(CurrencyFormatter.parseAmount('مبلغ'), isNull);
      });

      test('يجب معالجة الصفر', () {
        expect(CurrencyFormatter.parseAmount('0'), 0);
        expect(CurrencyFormatter.parseAmount('٠'), 0);
      });
    });

    group('formatters', () {
      test('defaultFormatter يجب أن يكون متاحاً', () {
        expect(CurrencyFormatter.defaultFormatter, isNotNull);
        expect(CurrencyFormatter.defaultFormatter.format(1000), '1,000');
      });

      test('decimalFormatter يجب أن يكون متاحاً', () {
        expect(CurrencyFormatter.decimalFormatter, isNotNull);
      });
    });

    group('حالات واقعية من الفندق', () {
      test('أسعار الغرف الشائعة', () {
        expect(CurrencyFormatter.formatAmount(14300), '14,300');
        expect(CurrencyFormatter.formatAmount(42900), '42,900');
        expect(CurrencyFormatter.formatAmount(85000), '85,000');
      });

      test('تحويل مدخلات المستخدم', () {
        expect(CurrencyFormatter.parseAmount('42,900'), 42900);
        expect(CurrencyFormatter.parseAmount('٤٢٬٩٠٠'), 42900);
      });

      test('حساب المبالغ المتبقية', () {
        const total = 42900.0;
        const paid = 20000.0;
        const remaining = total - paid;
        expect(CurrencyFormatter.formatAmount(remaining), '22,900');
      });
    });
  });
}
