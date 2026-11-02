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

    test('لا ينشئ ترحيلاً عند تجاوز صفر بالضبط', () {
      final result = SalaryCycleCalculator.calculate(
        const SalaryCycleInput(
          basicSalary: 50000,
          withdrawals: 30000,
          advances: 15000,
          deductions: 5000,
        ),
      );

      expect(result.remainingBalance, 0);
      expect(result.carryOverToNext, 0);
      expect(result.hasExceeded, isFalse);
      expect(result.isFullySettled, isTrue);
    });

    test('يحسب تجاوز وحدة مالية واحدة بدقة', () {
      final result = SalaryCycleCalculator.calculate(
        const SalaryCycleInput(basicSalary: 50000, withdrawals: 50001),
      );

      expect(result.remainingBalance, 0);
      expect(result.carryOverToNext, 1);
    });

    test('يستهلك الترحيل السابق قبل إنشاء ترحيل جديد', () {
      final result = SalaryCycleCalculator.calculate(
        const SalaryCycleInput(
          basicSalary: 50000,
          withdrawals: 45000,
          carriedOverFromPrevious: 5000,
        ),
      );

      expect(result.totalBeforeCarryOver, 50000);
      expect(result.remainingBalance, 0);
      expect(result.carryOverToNext, 0);
    });

    test('يدعم ترحيلاً متسلسلاً من شهر إلى الشهر التالي', () {
      final firstMonth = SalaryCycleCalculator.calculate(
        const SalaryCycleInput(basicSalary: 50000, withdrawals: 60000),
      );
      final secondMonth = SalaryCycleCalculator.calculate(
        SalaryCycleInput(
          basicSalary: 50000,
          withdrawals: 55000,
          carriedOverFromPrevious: firstMonth.carryOverToNext,
        ),
      );

      expect(firstMonth.carryOverToNext, 10000);
      expect(secondMonth.totalBeforeCarryOver, 65000);
      expect(secondMonth.carryOverToNext, 15000);
      expect(secondMonth.remainingBalance, 0);
    });

    test('لا يجعل الأقساط المسددة الترحيل أكبر أو صافي المستحق سالباً', () {
      final result = SalaryCycleCalculator.calculate(
        const SalaryCycleInput(
          basicSalary: 50000,
          advances: 20000,
          installmentsPaid: 20000,
          withdrawals: 50000,
        ),
      );

      expect(result.remainingBalance, 0);
      expect(result.carryOverToNext, 20000);
      expect(result.advanceBalance, 0);
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
