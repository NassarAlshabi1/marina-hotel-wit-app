/// تصنيف أنواع مصروفات الرواتب — مصدر الحقيقة الموحّد للتدفق النقدي.
///
/// ✅ القاعدة المحاسبية (طلب صاحب الفندق):
/// «مصروفات الرواتب يجب أن تساوي استحقاقات الموظف» — أي أن كل ما يُحسب
/// مصروف رواتب في التقارير يجب أن يكون نقداً خرج فعلاً للموظف، وكل نقد
/// خرج للموظف يجب أن يُخصم من استحقاقه — بطريقة متطابقة في الطرفين.
///
/// لذلك تُقسم أنواع مصروفات الرواتب إلى فئتين:
///
/// 1. **تدفق نقدي (Cash Out)** — المبلغ خرج من الصندوق إلى الموظف فعلاً:
///    - `رواتب` / `سحب راتب` / `سحب من الراتب` → سحب مباشر من الراتب
///    - `سلفة` → سلفة تُسدد بالأقساط، لكنها نقد استلمه الموظف فوراً
///
/// 2. **تسويات استحقاق (Deductions)** — لا يخرج منها نقد، إنما تُنقص
///    صافي استحقاق الموظف فقط:
///    - `خصم من الراتب` (يدوي أو أقساط سلفة المولّدة تلقائياً)
///    - `خصم راتب` / `خصم` / `غياب`
///
/// ⚠️ ملاحظة: الخصوم تُخزَّن في جدول expenses كسجلات موجبة المبلغ، لكنها
/// ليست مصروفات نقدية — تظهر فقط في شاشة استحقاقات الرواتب (إجمالي الخصومات)
/// ولا تدخل في تقارير المصروفات النقدية إطلاقاً.
///
/// ملاحظة توافق: `PayloadMapper.isSalaryExpenseType` تظل أوسع عمداً (تشمل
/// الخصوم) لأنها تُستخدم لصيد السجلات اليتيمة عند الإصلاح والمزامنة، حيث
/// المطلوب التقاط كل ما يمسّ الراتب — لا تستخدمها للتقارير النقدية.
class SalaryExpenseClassifier {
  SalaryExpenseClassifier._();

  /// أنواع التدفق النقدي للموظف (سحب + سلفة).
  static const List<String> _cashOutTypes = [
    'رواتب',
    'سحب راتب',
    'سحب من الراتب',
    'سلفة',
  ];

  /// أنواع تسويات الاستحقاق (خصوم بلا تدفق نقدي).
  static const List<String> _deductionTypes = [
    'خصم من الراتب',
    'خصم راتب',
    'خصم',
    'غياب',
  ];

  /// هل النوع يمثل نقداً خرج للموظف فعلاً (سحب راتب أو سلفة)؟
  ///
  /// هذا هو التعريف الصحيح لـ «مصروفات الرواتب» في كل التقارير النقدية:
  /// تقرير الإيرادات والمصروفات + تقرير المصروفات + مطابقة استحقاقات
  /// الموظفين (السحبيات + السلف).
  static bool isSalaryCashOut(String type) {
    final normalized = type.trim();
    if (normalized.isEmpty) return false;
    if (normalized.contains('سلفة')) return true;
    for (final keyword in _cashOutTypes) {
      if (normalized.contains(keyword)) return true;
    }
    return false;
  }

  /// هل النوع يمثل تسوية استحقاق بلا تدفق نقدي (خصم / غياب)؟
  static bool isSalaryDeduction(String type) {
    final normalized = type.trim();
    if (normalized.isEmpty) return false;
    for (final keyword in _deductionTypes) {
      if (normalized.contains(keyword)) return true;
    }
    return false;
  }

  /// هل النوع مرتبط بالرواتب بأي شكل (نقدي أو تسوية)؟
  /// مفيد لعرض عمود الموظف ولمطابقة السجلات اليتيمة — وليس للتجميع النقدي.
  static bool isSalaryRelated(String type) =>
      isSalaryCashOut(type) || isSalaryDeduction(type);

  /// هل السحب من نوع سلفة (يُحسب ضمن السلف لا ضمن السحبيات)؟
  static bool isAdvanceWithdrawal(String? withdrawalType) {
    final normalized = (withdrawalType ?? '').trim();
    return normalized.contains('سلفة');
  }
}
