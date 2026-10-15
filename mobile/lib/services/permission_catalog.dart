/// كتالوج الصلاحيات الموحّد — المصدر الوحيد للوحدات والعمليات
/// وتسمياتها العربية، يستخدمه محرر الصلاحيات وشاشة المستخدمين
/// وأي عرض ملخّص. مفاتيح التخزين لم تتغير: `module` قديم أو
/// `module.action` دقيق — لذا الحسابات الحالية تبقى متوافقة.
library;

class PermissionModule {
  const PermissionModule(this.key, this.label);
  final String key;
  final String label;
}

class PermissionAction {
  const PermissionAction(this.key, this.label, this.shortLabel);
  final String key;
  final String label;

  /// تسمية حرف واحد لشبكة المصفوفة المضغوطة.
  final String shortLabel;
}

abstract final class PermissionCatalog {
  /// الترتيب منطقي لسير العمل اليومي: لوحة → غرف → حجوزات → مدفوعات →
  /// ديون → مصروفات → مالية → تقارير → مخزون → موظفون → ملاحظات →
  /// معلومية → إعدادات (الأخيرة حساسة). عرضي فقط — الفحوص contains-based.
  static const List<PermissionModule> modules = [
    PermissionModule('dashboard', 'لوحة التحكم'),
    PermissionModule('rooms', 'الغرف'),
    PermissionModule('bookings', 'الحجوزات'),
    PermissionModule('payments', 'المدفوعات'),
    PermissionModule('debts', 'الديون'),
    PermissionModule('expenses', 'المصروفات'),
    PermissionModule('finance', 'المالية'),
    PermissionModule('reports', 'التقارير'),
    PermissionModule('inventory', 'المخزون'),
    PermissionModule('employees', 'الموظفون'),
    PermissionModule('notes', 'الملاحظات'),
    PermissionModule('information', 'المعلومية'),
    PermissionModule('settings', 'الإعدادات'),
  ];

  static const List<PermissionAction> actions = [
    PermissionAction('view', 'عرض', 'ع'),
    PermissionAction('create', 'إضافة', 'إ'),
    PermissionAction('update', 'تعديل', 'ت'),
    PermissionAction('delete', 'حذف', 'ح'),
  ];

  static List<String> get moduleKeys => [for (final m in modules) m.key];

  static List<String> get actionKeys => [for (final a in actions) a.key];

  static List<String> keysForModule(String moduleKey) => [
    for (final a in actions) '$moduleKey.${a.key}',
  ];

  /// كل المفاتيح التي يعرضها محرر الصلاحيات: مفاتيح الوحدات القديمة
  /// (للتوافق) ثم المفاتيح الدقيقة لكل وحدة.
  static List<String> get editorKeys => [
    ...moduleKeys,
    for (final m in modules) ...keysForModule(m.key),
  ];

  static String moduleLabel(String key) => switch (key) {
    'dashboard' => 'لوحة التحكم',
    'rooms' => 'الغرف',
    'bookings' => 'الحجوزات',
    'payments' => 'المدفوعات',
    'debts' => 'الديون',
    'employees' => 'الموظفون',
    'expenses' => 'المصروفات',
    'finance' => 'المالية',
    'reports' => 'التقارير',
    'notes' => 'الملاحظات',
    'information' => 'المعلومية',
    'settings' => 'الإعدادات',
    'inventory' => 'المخزون',
    _ => key,
  };

  static String actionLabel(String key) => switch (key) {
    'view' => 'عرض',
    'create' => 'إضافة',
    'update' => 'تعديل',
    'delete' => 'حذف',
    _ => key,
  };

  /// تسمية عربية لأي مفتاح: قديم (`payments`) أو دقيق (`payments.view`).
  static String labelFor(String key) {
    final dot = key.indexOf('.');
    if (dot < 0) return moduleLabel(key);
    return '${actionLabel(key.substring(dot + 1))} '
        '${moduleLabel(key.substring(0, dot))}';
  }

  /// ملخّص مختصر لوحدة واحدة داخل مجموعة صلاحيات: يعيد اسم العمليات
  /// المملوكة ('الكل' عند امتلاك مفتاح الوحدة القديم أو العمليات الأربع).
  static String? moduleSummary(String moduleKey, Set<String> perms) {
    if (perms.contains(moduleKey) || perms.contains('all')) return 'الكل';
    final owned = [
      for (final a in actions)
        if (perms.contains('$moduleKey.${a.key}')) a.label,
    ];
    if (owned.isEmpty) return null;
    if (owned.length == actions.length) return 'الكل';
    return owned.join('، ');
  }

  /// ملخّص كامل مختصر لقائمة الصلاحيات — سطر واحد لكل وحدة مملوكة.
  static List<String> summarize(Set<String> perms) => [
    for (final m in modules)
      if (moduleSummary(m.key, perms) case final s?) '${m.label}: $s',
  ];
}
