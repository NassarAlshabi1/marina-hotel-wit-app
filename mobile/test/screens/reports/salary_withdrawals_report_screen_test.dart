// ignore_for_file: lines_longer_than_80_chars
import 'package:flutter_test/flutter_test.dart';

import 'package:marina_hotel_mobile/screens/reports/salary_withdrawals_report_screen.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/salary_mirror_matcher.dart';

/// 🔬 تقرير سحبيات الرواتب — إصلاح التكرار عند تعديل مبلغ مصروف راتب
/// (2026-09-24).
///
/// خلافاً لتقرير المصروفات (`bug_repro_expense_edit_test.dart`) الذي
/// يملك شبكة أمان (SalaryMirrorMatcher.isMirrorOfReadExpense) لأنه يعرض
/// المصروف من جدول expenses مباشرة، تقرير سحبيات الرواتب مصدره الوحيد
/// جدول salary_withdrawals — فحين تفشل شاشة التعديل في تبنّي المرآة
/// اليتيمة (مثلاً: أكثر من مصروف راتب لنفس الموظف في نفس اليوم)، يبقى
/// صفّان يمثّلان نفس مصروف الراتب ويُحسب المبلغ مرتين في هذا التقرير
/// تحديداً. هذا الاختبار يثبت أن [dedupeMirrorDuplicates] يمنع ذلك.
void main() {
  const day = '2026-09-25';

  SalaryWithdrawal sw({
    required int id,
    required int employeeId,
    required double amount,
    String? reason,
    int? expenseId,
    int updatedAt = 1000,
  }) {
    return SalaryWithdrawal(
      localUuid: 'uuid-$id',
      createdAt: 1000,
      updatedAt: updatedAt,
      lastModified: updatedAt,
      createdAtEpoch: 1000,
      lastModifiedEpoch: updatedAt,
      version: 1,
      origin: 'local',
      vectorClock: '{}',
      deviceId: '',
      syncTimestamp: 0,
      id: id,
      employeeId: employeeId,
      amount: amount,
      withdrawDate: day,
      hotelDayKey: day,
      reason: reason,
      withdrawalType: 'سحب راتب',
      expenseId: expenseId,
    );
  }

  MirrorExpenseCandidate expense({
    required int id,
    required int relatedId,
    double amount = 150,
  }) {
    return MirrorExpenseCandidate(
      id: id,
      serverId: null,
      expenseType: 'سحب راتب',
      amount: amount,
      date: day,
      hotelDayKey: day,
      relatedId: relatedId,
    );
  }

  test(
    'مرآة يتيمة + مرآة مُرسّاة على نفس المصروف → تُدمَجان في سحبة واحدة',
    () {
      // exp=10 محلي حقيقي — سحبة مُرسّاة عليه بنجاح (رابط صحيح).
      final anchored = sw(
        id: 1,
        employeeId: 5,
        amount: 150,
        reason: 'exp_10',
        expenseId: 10,
        updatedAt: 2000, // الأحدث — نتيجة التعديل
      );
      // مرآة يتيمة قديمة — رابطها أجنبي (معرّف جهاز المصدر 962) لا يقابل
      // أي مصروف محلي، لكنها لنفس الموظف/اليوم/العائلة النقدية.
      final orphan = sw(
        id: 2,
        employeeId: 5,
        amount: 100, // المبلغ القديم قبل التعديل
        reason: 'exp_962',
        expenseId: 962,
        updatedAt: 1000,
      );

      final expenses = [expense(id: 10, relatedId: 5, amount: 150)];
      final result = dedupeMirrorDuplicates([anchored, orphan], expenses);

      expect(result, hasLength(1));
      expect(result.single.id, anchored.id);
      final total = result.fold<double>(0, (s, r) => s + r.amount);
      expect(total, 150, reason: 'قبل الإصلاح كان المجموع 250 (مكرر)');
    },
  );

  test(
    'يتيمتان بلا أي مرآة مُرسّاة لنفس المفتاح → تُبقي الأحدث فقط',
    () {
      // لا مصروف محلي يحلّ أياً منهما — مثلاً عُدّل المبلغ مرتين قبل
      // أي مزامنة ناجحة تُنشئ رابطاً صالحاً.
      final older = sw(
        id: 1,
        employeeId: 5,
        amount: 100,
        reason: 'exp_962',
        expenseId: 962,
        updatedAt: 1000,
      );
      final newer = sw(
        id: 2,
        employeeId: 5,
        amount: 150,
        reason: 'exp_962',
        expenseId: 962,
        updatedAt: 2000,
      );

      final result = dedupeMirrorDuplicates([older, newer], const []);

      expect(result, hasLength(1));
      expect(result.single.id, newer.id);
      expect(result.single.amount, 150);
    },
  );

  test('مصروفا راتب مختلفان لنفس الموظف/اليوم → لا يُدمَجان', () {
    final first = sw(
      id: 1,
      employeeId: 5,
      amount: 100,
      reason: 'exp_10',
      expenseId: 10,
    );
    final second = sw(
      id: 2,
      employeeId: 5,
      amount: 200,
      reason: 'exp_11',
      expenseId: 11,
    );
    final expenses = [
      expense(id: 10, relatedId: 5, amount: 100),
      expense(id: 11, relatedId: 5, amount: 200),
    ];

    final result = dedupeMirrorDuplicates([first, second], expenses);

    expect(result, hasLength(2));
    final total = result.fold<double>(0, (s, r) => s + r.amount);
    expect(total, 300);
  });

  test(
    'حالة غامضة: مُرسّاتان + يتيمة لنفس المفتاح → لا حذف (تفادي إخفاء سحبة حقيقية)',
    () {
      final anchoredA = sw(
        id: 1,
        employeeId: 5,
        amount: 100,
        reason: 'exp_10',
        expenseId: 10,
      );
      final anchoredB = sw(
        id: 2,
        employeeId: 5,
        amount: 200,
        reason: 'exp_11',
        expenseId: 11,
      );
      final orphan = sw(
        id: 3,
        employeeId: 5,
        amount: 50,
        reason: 'exp_962',
        expenseId: 962,
      );
      final expenses = [
        expense(id: 10, relatedId: 5, amount: 100),
        expense(id: 11, relatedId: 5, amount: 200),
      ];

      final result = dedupeMirrorDuplicates(
        [anchoredA, anchoredB, orphan],
        expenses,
      );

      // لا نحذف في حالة الغموض — نُبقي الثلاثة جميعاً.
      expect(result, hasLength(3));
    },
  );

  test('سحبة مباشرة (direct_withdrawal_) لا تُدمَج أبداً حتى لو تشابهت', () {
    final direct1 = sw(
      id: 1,
      employeeId: 5,
      amount: 100,
      reason: 'direct_withdrawal_a',
    );
    final direct2 = sw(
      id: 2,
      employeeId: 5,
      amount: 100,
      reason: 'direct_withdrawal_b',
    );

    final result = dedupeMirrorDuplicates([direct1, direct2], const []);

    expect(result, hasLength(2));
  });

  test('سحبة بلا أي علامة مرآة (سجل يدوي قديم) تبقى كما هي', () {
    final legacy = sw(id: 1, employeeId: 5, amount: 100, reason: null);

    final result = dedupeMirrorDuplicates([legacy], const []);

    expect(result, hasLength(1));
    expect(result.single.id, legacy.id);
  });
}
