import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/utils/expense_reason_matcher.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════
  // matchesExpenseRef — مطابقة مرجع المصروف
  // ═══════════════════════════════════════════════════════════════
  group('matchesExpenseRef', () {
    test('يطابق exp_1 مع expenseId=1', () {
      expect(matchesExpenseRef('exp_1', 1), isTrue);
    });

    test('يطابق exp_10 مع expenseId=10', () {
      expect(matchesExpenseRef('exp_10', 10), isTrue);
    });

    test('يطابق exp_100 مع expenseId=100', () {
      expect(matchesExpenseRef('exp_100', 100), isTrue);
    });

    test('لا يطابق exp_1 مع expenseId=10 (إصلاح حرج: negative lookahead)', () {
      // هذا هو الاختبار الأهم — exp_1 لا يجب أن يطابق expenseId=10
      expect(matchesExpenseRef('exp_1', 10), isFalse);
    });

    test('لا يطابق exp_10 مع expenseId=1', () {
      expect(matchesExpenseRef('exp_10', 1), isFalse);
    });

    test('لا يطابق exp_10 مع expenseId=100', () {
      expect(matchesExpenseRef('exp_10', 100), isFalse);
    });

    test('لا يطابق exp_100 مع expenseId=10', () {
      expect(matchesExpenseRef('exp_100', 10), isFalse);
    });

    test('reason=null يعيد false', () {
      expect(matchesExpenseRef(null, 1), isFalse);
    });

    test('reason فارغ يعيد false', () {
      expect(matchesExpenseRef('', 1), isFalse);
    });

    test('reason بدون نمط exp_ يعيد false', () {
      expect(matchesExpenseRef('رواتب', 1), isFalse);
      expect(matchesExpenseRef('direct_withdrawal_123', 123), isFalse);
    });

    test('يطابق ضمن نص مختلط — "exp_5,exp_10" مع expenseId=5', () {
      expect(matchesExpenseRef('exp_5,exp_10', 5), isTrue);
    });

    test('يطابق ضمن نص مختلط — "exp_5,exp_10" مع expenseId=10', () {
      expect(matchesExpenseRef('exp_5,exp_10', 10), isTrue);
    });

    test('لا يطابق ضمن نص مختلط — "exp_5,exp_10" مع expenseId=1', () {
      expect(matchesExpenseRef('exp_5,exp_10', 1), isFalse);
    });

    test('exp_0 مع expenseId=0', () {
      expect(matchesExpenseRef('exp_0', 0), isTrue);
    });

    test('أنماط حدودية: exp_1 في نهاية السلسلة', () {
      expect(matchesExpenseRef('some text exp_1', 1), isTrue);
    });

    test('أنماط حدودية: exp_1 في بداية السلسلة', () {
      expect(matchesExpenseRef('exp_1 some text', 1), isTrue);
    });

    test('exp_1 لا يطابق expenseId=12 أو 13 أو 100', () {
      expect(matchesExpenseRef('exp_1', 12), isFalse);
      expect(matchesExpenseRef('exp_1', 13), isFalse);
      expect(matchesExpenseRef('exp_1', 100), isFalse);
    });
  });
}
