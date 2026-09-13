import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/utils/salary_expense_classification.dart';

/// عقد «مصروفات الرواتب = استحقاقات الموظف» — طبقة التصنيف النقدي.
///
/// العلاقة مع SalaryEntitlementService (المصدر الحقيقي للاستحقاق):
/// - الأنواع النقدية هنا = ما تقرأه الخدمة كسحبيات (سحب راتب/رواتب/سحب من
///   الراتب) وسلف (سلفة) — أي كل نقد خرج للموظف ويُخصم من استحقاقه.
/// - الأنواع غير النقدية هنا = ما تقرأه الخدمة كخصومات (خصم راتب/خصم من
///   الراتب/خصم/غياب) — تُخصم من الاستحقاق فقط ولا تُحسب مصروفات.
void main() {
  group('isCashSalaryExpense — مطابقة تامة (بلا wildcard)', () {
    test('تعترف بأنواع النقد الأربعة فقط', () {
      expect(SalaryExpenseClassification.isCashSalaryExpense('رواتب'), isTrue);
      expect(
        SalaryExpenseClassification.isCashSalaryExpense('سحب راتب'),
        isTrue,
      );
      expect(
        SalaryExpenseClassification.isCashSalaryExpense('سحب من الراتب'),
        isTrue,
      );
      expect(SalaryExpenseClassification.isCashSalaryExpense('سلفة'), isTrue);
    });

    test('تتجاهل الفرطف الطرفية (trim)', () {
      expect(
        SalaryExpenseClassification.isCashSalaryExpense(' سلفة '),
        isTrue,
      );
      expect(
        SalaryExpenseClassification.isCashSalaryExpense('سحب راتب '),
        isTrue,
      );
    });

    test('ترفض الخصوم غير النقدية — كان wildcard يحسبها مضخمة', () {
      expect(
        SalaryExpenseClassification.isCashSalaryExpense('خصم راتب'),
        isFalse,
      );
      expect(
        SalaryExpenseClassification.isCashSalaryExpense('خصم من الراتب'),
        isFalse,
      );
      expect(SalaryExpenseClassification.isCashSalaryExpense('خصم'), isFalse);
      expect(SalaryExpenseClassification.isCashSalaryExpense('غياب'), isFalse);
    });

    test('ترفض الأنواع غير المرتبطة بالرواتب', () {
      expect(
        SalaryExpenseClassification.isCashSalaryExpense('كهرباء'),
        isFalse,
      );
      expect(SalaryExpenseClassification.isCashSalaryExpense('مياه'), isFalse);
      expect(SalaryExpenseClassification.isCashSalaryExpense(''), isFalse);
      // نص يحتوي «راتب» دون أن يكون نوعاً نقدياً معترفاً به —
      // سلوك wildcard القديم كان يقبله خطأً
      expect(
        SalaryExpenseClassification.isCashSalaryExpense('بدل راتب سكن'),
        isFalse,
      );
    });
  });

  group('isNonCashDeduction — الخصوم تخصم من الاستحقاق فقط', () {
    test('تعترف بأنواع الخصوم الأربعة', () {
      expect(
        SalaryExpenseClassification.isNonCashDeduction('خصم راتب'),
        isTrue,
      );
      expect(
        SalaryExpenseClassification.isNonCashDeduction('خصم من الراتب'),
        isTrue,
      );
      expect(SalaryExpenseClassification.isNonCashDeduction('خصم'), isTrue);
      expect(SalaryExpenseClassification.isNonCashDeduction('غياب'), isTrue);
    });

    test('ترفض أنواع النقد (السلفة نقد وليست خصماً)', () {
      expect(
        SalaryExpenseClassification.isNonCashDeduction('سلفة'),
        isFalse,
      );
      expect(
        SalaryExpenseClassification.isNonCashDeduction('سحب راتب'),
        isFalse,
      );
      expect(
        SalaryExpenseClassification.isNonCashDeduction('رواتب'),
        isFalse,
      );
      expect(
        SalaryExpenseClassification.isNonCashDeduction('سحب من الراتب'),
        isFalse,
      );
    });
  });

  group('ثوابت العقد المحاسبي', () {
    test('لا تقاطع بين النقد والخصوم (كل صف يُصنف مرة واحدة)', () {
      final intersection = SalaryExpenseClassification.cashSalaryTypes
          .toSet()
          .intersection(
            SalaryExpenseClassification.nonCashDeductionTypes.toSet(),
          );
      expect(intersection, isEmpty);
    });

    test('الأنواع النقدية = ما تخصمه خدمة الاستحقاق كسحبيات وسلف', () {
      // salary_entitlement_service.dart:
      // type == 'سحب راتب' || 'رواتب' || 'سحب من الراتب' → withdrawals
      // type == 'سلفة' → advances
      const entitlementCashTypes = {
        'سحب راتب',
        'رواتب',
        'سحب من الراتب',
        'سلفة',
      };
      expect(
        SalaryExpenseClassification.cashSalaryTypes.toSet(),
        equals(entitlementCashTypes),
      );
    });

    test('الأنواع غير النقدية = ما تخصمه خدمة الاستحقاق كخصومات', () {
      // salary_entitlement_service.dart:
      // 'خصم من الراتب' (يدوي) + 'خصم راتب' || 'خصم' || 'غياب' → deductions
      // (أما أقساط «قسط سلفة» التلقائية فتُتابع كرصيد سلفة ولا تُخصم مرتين)
      const entitlementDeductionTypes = {
        'خصم من الراتب',
        'خصم راتب',
        'خصم',
        'غياب',
      };
      expect(
        SalaryExpenseClassification.nonCashDeductionTypes.toSet(),
        equals(entitlementDeductionTypes),
      );
    });
  });
}
