import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/salary_cycle_calculator.dart';

void main() {
  group('SalaryCycleCalculator', () {
    test('يحسب صافي المستحق دون وجود حركات', () {
      final result = SalaryCycleCalculator.calculate(
        const SalaryCycleInput(basicSalary: 50000),
      );

      expect(result.remainingBalance, 50000);
      expect(result.carryOverToNext, 0);
      expect(result.advanceBalance, 0);
    });

    test('يخصم السحب والسلفة والخصم والترحيل السابق', () {
      final result = SalaryCycleCalculator.calculate(
        const SalaryCycleInput(
          basicSalary: 50000,
          withdrawals: 10000,
          advances: 15000,
          deductions: 2000,
          carriedOverFromPrevious: 3000,
        ),
      );

      expect(result.totalBeforeCarryOver, 30000);
      expect(result.remainingBalance, 20000);
      expect(result.carryOverToNext, 0);
    });

    test('لا يخصم أقساط السلفة مرة ثانية من صافي الدورة', () {
      final result = SalaryCycleCalculator.calculate(
        const SalaryCycleInput(
          basicSalary: 50000,
          advances: 15000,
          installmentsPaid: 5000,
        ),
      );

      expect(result.remainingBalance, 35000);
      expect(result.advanceBalance, 10000);
    });

    test('يرحّل العجز إلى الدورة التالية', () {
      final result = SalaryCycleCalculator.calculate(
        const SalaryCycleInput(
          basicSalary: 50000,
          withdrawals: 40000,
          advances: 20000,
          deductions: 5000,
        ),
      );

      expect(result.remainingBalance, 0);
      expect(result.carryOverToNext, 15000);
      expect(result.hasExceeded, isTrue);
    });

    test('يقرب البيانات القديمة ذات الكسور مرة واحدة إلى أعداد صحيحة', () {
      final result = SalaryCycleCalculator.calculate(
        const SalaryCycleInput(
          basicSalary: 50000.7,
          withdrawals: 10000.4,
          advances: 5000.5,
        ),
      );

      expect(result.basicSalary, 50001);
      expect(result.withdrawals, 10000);
      expect(result.advances, 5001);
      expect(result.remainingBalance, 35000);
    });

    test('لا يسمح برصيد سلفة سالب عند تجاوز الأقساط قيمة السلفة', () {
      final result = SalaryCycleCalculator.calculate(
        const SalaryCycleInput(
          basicSalary: 50000,
          advances: 10000,
          installmentsPaid: 12000,
        ),
      );

      expect(result.advanceBalance, 0);
    });
  });
}
