/// ثوابت أنواع المصروفات المرتبطة بالرواتب
/// توحيد الأسماء لمنع الأخطاء الناتجة عن الكتابة اليدوية
class SalaryExpenseTypes {
  /// نوع المصروف الرئيسي للموظفين
  static const String salary = 'رواتب';

  /// سحب من الراتب (الافتراضي)
  static const String withdrawal = 'سحب من الراتب';
  
  /// خصم من الراتب
  static const String deduction = 'خصم من الراتب';
  
  /// سلفة
  static const String advance = 'سلفة';

  /// الأسماء القديمة للتوافق مع البيانات القديمة
  static const String withdrawalLegacy = 'سحب راتب';
  static const String deductionLegacy = 'خصم راتب';

  /// خصم عام
  static const String deductionGeneric = 'خصم';
  
  /// غياب
  static const String absence = 'غياب';

  /// أنواع إجراءات الرواتب المعروضة في القائمة المنسدلة
  static const List<String> salaryActions = [
    withdrawal,
    deduction,
    advance,
  ];

  /// قائمة بأنواع مصروفات الموظفين كلها للفحص
  static const List<String> allSalaryTypes = [
    withdrawal,
    withdrawalLegacy,
    salary,
    deduction,
    deductionLegacy,
    deductionGeneric,
    absence,
    advance,
  ];

  /// هل هذا النوع هو نوع راتبي؟
  static bool isSalaryType(String type) {
    return type == withdrawal || type == deduction || type == advance;
  }
}

/// ثوابت أنواع وسائل الدفع
class PaymentMethodTypes {
  static const String cash = 'نقدي';
  static const String bankTransfer = 'تحويل بنكي';
}

/// ثوابت أنواع الهوية
class IdTypes {
  static const String personalCard = 'بطاقة شخصية';
  static const String passport = 'جواز سفر';
  static const String driversLicense = 'رخصة قيادة';
}
