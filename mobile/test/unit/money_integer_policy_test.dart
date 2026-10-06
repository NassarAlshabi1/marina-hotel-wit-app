// test/unit/money_integer_policy_test.dart
//
// ✅ (G-10 — تدقيق الهوية المالية 2026-10-06): سياسة «لا كسور عشرية».
//
// سياسة الفندق (مصدر الحقيقة الوحيد: CurrencyFormatter):
//   - كل مبلغ مالي عدد صحيح بلا كسور عشرية.
//   - الاقتطاع نحو الصفر (لا تقريب لأعلى): 150.5 → 150، 150.99 → 150،
//     -150.5 → -150  (لا نضيف مبلغاً على أحد نتيجة التقريب).
//   - نفس القيمة في: العرض (formatAmount) والإدخال (parseAmount) والعبور
//     عبر مزوّد المزامنة (truncateAmount في المحوّلات والحزم).
//
// الهدف: أي مسار مالي جديد يستخدم [CurrencyFormatter.truncateAmount] بدل
// `round()` — وإلا اختلفت المبالغ بين الأجهزة (150.5 → 151 على جهاز و150 على
// آخر) وانكسرت مطابقة مصروف الرواتب بسحبه المرآة.
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/utils/currency_formatter.dart';

void main() {
  group('سياسة المال — أعداد صحيحة فقط (G-10)', () {
    test('truncateAmount يقتطع نحو الصفر ولا يقرّب لأعلى', () {
      expect(CurrencyFormatter.truncateAmount(150.5), 150);
      expect(CurrencyFormatter.truncateAmount(150.99), 150);
      expect(CurrencyFormatter.truncateAmount(150.0), 150);
      expect(CurrencyFormatter.truncateAmount(-150.5), -150);
      expect(CurrencyFormatter.truncateAmount(-0.9), 0);
      expect(CurrencyFormatter.truncateAmount(0), 0);
    });

    test('truncateAmount حتمي — نفس النتيجة على كل الأجهزة', () {
      // القيمة نفسها يجب أن تُعطي النتيجة نفسها دائماً (لا اعتماد على
      // ترتيب عشوائي أو وقت أو جهاز) — وهذا شرط عدم انحراف المجاميع.
      for (final value in [150.5, 150.49999, 150.99999, -150.5, -150.99999]) {
        final first = CurrencyFormatter.truncateAmount(value);
        final again = CurrencyFormatter.truncateAmount(value);
        expect(again, first);
        expect(first, value.truncate());
      }
    });

    test('wholeAmount يُرجع double بعدد صحيح (لتخزينه في أعمدة REAL)', () {
      expect(CurrencyFormatter.wholeAmount(150.5), 150.0);
      expect(CurrencyFormatter.wholeAmount(-150.5), -150.0);
      expect(CurrencyFormatter.wholeAmount(150.0).isInteger, isTrue);
    });

    test('isWholeAmount يميّز الصحيح عن الكسر', () {
      expect(CurrencyFormatter.isWholeAmount(150.0), isTrue);
      expect(CurrencyFormatter.isWholeAmount(150.5), isFalse);
      expect(CurrencyFormatter.isWholeAmount(-150.0), isTrue);
      expect(CurrencyFormatter.isWholeAmount(-150.1), isFalse);
    });

    test('التطابق بين العرض والإدخال والنقل', () {
      // العرض: 150.5 يظهر 150 (لا كسور)
      expect(CurrencyFormatter.formatAmount(150.5), '150');
      // الإدخال: "150.5" يُحفظ 150
      expect(CurrencyFormatter.parseAmount('150.5'), 150);
      // النقل عبر المزوّد: 150.5 يُرسل 150 — نفس القيمة في كل المراحل.
      expect(
        CurrencyFormatter.truncateAmount(150.5),
        CurrencyFormatter.parseAmount('150.5'),
      );
      expect(
        CurrencyFormatter.formatAmount(150.5),
        '${CurrencyFormatter.truncateAmount(150.5)}',
      );
    });

    test('مبالغ كبيرة وصغيرة تبقى حتمية', () {
      expect(CurrencyFormatter.truncateAmount(1000000.75), 1000000);
      expect(CurrencyFormatter.truncateAmount(-1000000.75), -1000000);
      expect(CurrencyFormatter.truncateAmount(0.5), 0);
      expect(CurrencyFormatter.truncateAmount(-0.5), 0);
    });
  });
}
