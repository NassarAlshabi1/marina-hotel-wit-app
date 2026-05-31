import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/utils/expense_reason_matcher.dart';

void main() {
  group('matchesExpenseRef', () {
    group('يجب إرجاع false للقيم الفارغة', () {
      test('null يجب أن يرجع false', () {
        expect(matchesExpenseRef(null, 1), isFalse);
      });
    });

    group('يجب إرجاع true للتطابق الصحيح', () {
      test('exp_1 يجب أن يطابق expenseId=1', () {
        expect(matchesExpenseRef('exp_1', 1), isTrue);
      });

      test('exp_5 يجب أن يطابق expenseId=5', () {
        expect(matchesExpenseRef('exp_5', 5), isTrue);
      });

      test('exp_100 يجب أن يطابق expenseId=100', () {
        expect(matchesExpenseRef('exp_100', 100), isTrue);
      });
    });

    group('يجب عدم التطابق مع الأرقام المشابهة', () {
      test('exp_10 يجب ألا يطابق expenseId=1', () {
        expect(matchesExpenseRef('exp_10', 1), isFalse);
      });

      test('exp_100 يجب ألا يطابق expenseId=10', () {
        expect(matchesExpenseRef('exp_100', 10), isFalse);
      });

      test('exp_1000 يجب ألا يطابق expenseId=100', () {
        expect(matchesExpenseRef('exp_1000', 100), isFalse);
      });
    });

    group('يجب إرجاع false عندما لا يوجد مرجع', () {
      test('النص الفارغ لا يجب أن يطابق', () {
        expect(matchesExpenseRef('', 1), isFalse);
      });

      test('النص بدون مرجع لا يجب أن يطابق', () {
        expect(matchesExpenseRef('some text without ref', 1), isFalse);
      });

      test('مرجع مختلف لا يجب أن يطابق', () {
        expect(matchesExpenseRef('payment for exp_2', 1), isFalse);
      });
    });

    group('يجب أن يعمل مع النصوص المعقدة', () {
      test('مرجع في وسط النص', () {
        expect(matchesExpenseRef('payment exp_5 for supplies', 5), isTrue);
      });

      test('مرجع في بداية النص', () {
        expect(matchesExpenseRef('exp_3 deduction', 3), isTrue);
      });

      test('مرجع في نهاية النص', () {
        expect(matchesExpenseRef('deduction exp_7', 7), isTrue);
      });

      test('نص مع أرقام متعددة', () {
        expect(matchesExpenseRef('exp_1 and exp_10', 1), isTrue);
        expect(matchesExpenseRef('exp_1 and exp_10', 10), isTrue);
        expect(matchesExpenseRef('exp_1 and exp_10', 100), isFalse);
      });
    });

    group('يجب أن يتعامل مع expenseId=0', () {
      test('exp_0 يجب أن يطابق expenseId=0', () {
        expect(matchesExpenseRef('exp_0', 0), isTrue);
      });

      test('exp_00 يجب ألا يطابق expenseId=0', () {
        expect(matchesExpenseRef('exp_00', 0), isFalse);
      });
    });
  });
}