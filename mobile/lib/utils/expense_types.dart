import 'package:flutter/material.dart';

/// أنواع المصروفات — المصدر الوحيد لتصنيف المصروفات
///
/// يضمن اتساق التصنيف بين جميع شاشات التطبيق.
/// أي تغيير في أنواع المصروفات يجب أن يمر من هنا.
class ExpenseTypes {
  ExpenseTypes._();

  // ── فئات العرض (Categories) ──────────────────────────────────

  /// الفئة العامة للرواتب — تُعرض في القوائم المنسدلة والفلترة
  static const String salaryCategory = 'رواتب';

  // ── أنواع التخزين (Storage Types) ────────────────────────────
  // هذه الأنواع هي الوحيدة التي تُخزّن في قاعدة البيانات

  /// سحب راتب (Withdrawal)
  static const String salaryWithdraw = 'سحب راتب';

  /// خصم من الراتب (Deduction)
  static const String salaryDeduction = 'خصم من الراتب';

  // ── الأنواع البديلة (Alternate/Legacy) ───────────────────────
  // تُستخدم للمطابقة عند قراءة بيانات قديمة

  static const String salaryWithdrawLegacy = 'سحب من الراتب';
  static const String salaryDeductionLegacy = 'خصم راتب';
  static const String salaryAdvance = 'سلفة';
  static const String simpleDeduction = 'خصم';
  static const String absence = 'غياب';

  // ── التوابع (Utilities) ──────────────────────────────────────

  /// جميع أنواع التخزين الفعلية للرواتب
  static const List<String> salaryStorageTypes = [
    salaryWithdraw,
    salaryDeduction,
  ];

  /// جميع الصيغ الممكنة للرواتب (للمطابقة)
  static const List<String> allSalaryForms = [
    salaryCategory,
    salaryWithdraw,
    salaryWithdrawLegacy,
    salaryDeduction,
    salaryDeductionLegacy,
    salaryAdvance,
    simpleDeduction,
    absence,
  ];

  /// هل النوع مرتبط بالرواتب؟
  static bool isSalaryType(String type) {
    for (final keyword in allSalaryForms) {
      if (type.contains(keyword)) {
        return true;
      }
    }
    return false;
  }

  /// تحويل نوع راتب من أي صيغة إلى صيغة التخزين الموحّدة
  static String normalizeSalaryType(String type) {
    // خصم / غياب / خصم راتب / خصم من الراتب ← خصم من الراتب
    if (type.contains(salaryDeduction) ||
        type.contains(salaryDeductionLegacy) ||
        type.contains(simpleDeduction) ||
        type.contains(absence)) {
      return salaryDeduction;
    }
    // سلفة تعامل كسحب راتب
    if (type.contains(salaryAdvance)) {
      return salaryWithdraw;
    }
    // أي صيغة أخرى → سحب راتب
    return salaryWithdraw;
  }

  /// تحويل نوع التخزين إلى صيغة العرض (للـ report)
  static String normalizeForDisplay(String type) {
    if (type.contains(salaryDeduction) || type.contains(salaryDeductionLegacy)) {
      return salaryDeduction;
    }
    if (type.contains(salaryWithdraw) || type.contains(salaryWithdrawLegacy)) {
      return salaryWithdraw;
    }
    return type;
  }

  /// أيقونات وألوان أنواع المصروفات
  static const Map<String, ExpenseTypeConfig> typeConfig = {
    salaryCategory: ExpenseTypeConfig(Icons.account_balance_wallet, Color(0xFF7B1FA2)),
    salaryWithdraw: ExpenseTypeConfig(Icons.account_balance_wallet, Color(0xFF7B1FA2)),
    salaryWithdrawLegacy: ExpenseTypeConfig(Icons.account_balance_wallet, Color(0xFF7B1FA2)),
    salaryDeduction: ExpenseTypeConfig(Icons.remove_circle_outline, Color(0xFF7B1FA2)),
    salaryDeductionLegacy: ExpenseTypeConfig(Icons.remove_circle_outline, Color(0xFF7B1FA2)),
    salaryAdvance: ExpenseTypeConfig(Icons.credit_card, Color(0xFF7B1FA2)),
    simpleDeduction: ExpenseTypeConfig(Icons.remove_circle_outline, Color(0xFF7B1FA2)),
    absence: ExpenseTypeConfig(Icons.block, Color(0xFF7B1FA2)),
    'ديزل': ExpenseTypeConfig(Icons.local_gas_station, Color(0xFFFFC107)),
    'صيانة': ExpenseTypeConfig(Icons.build, Color(0xFFFF9800)),
    'فواتير كهرباء ومياه': ExpenseTypeConfig(Icons.electrical_services, Color(0xFF00897B)),
    'مستلزمات': ExpenseTypeConfig(Icons.inventory_2, Color(0xFF3F51B5)),
    'مساعدة محتاج': ExpenseTypeConfig(Icons.volunteer_activism, Color(0xFFEC407A)),
    'اخرى': ExpenseTypeConfig(Icons.more_horiz, Color(0xFF9E9E9E)),
  };

  /// الحصول على تهيئة النوع (أيقونة + لون)
  static ExpenseTypeConfig configFor(String type) {
    for (final key in typeConfig.keys) {
      if (type.contains(key)) {
        return typeConfig[key]!;
      }
    }
    return const ExpenseTypeConfig(Icons.receipt, Color(0xFF9E9E9E));
  }
}

/// تهيئة نوع المصروف (أيقونة ولون)
class ExpenseTypeConfig {
  const ExpenseTypeConfig(this.icon, this.color);
  final IconData icon;
  final Color color;
}
