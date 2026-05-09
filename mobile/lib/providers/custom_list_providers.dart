/// Providers for custom lists used across the app.
///
/// Provides dynamic expense types loaded from the `expense_types` table
/// with full CRUD support (add, edit, delete, reorder, toggle active).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'repository_providers.dart';

/// نموذج نوع المصروف
class ExpenseTypeInfo {
  final int id;
  final String name;
  final int sortOrder;
  final bool isActive;
  final bool isSystem;

  const ExpenseTypeInfo({
    required this.id,
    required this.name,
    required this.sortOrder,
    required this.isActive,
    required this.isSystem,
  });

  factory ExpenseTypeInfo.fromRow(Map<String, dynamic> data) {
    return ExpenseTypeInfo(
      id: data['id'] as int,
      name: data['name'] as String,
      sortOrder: data['sort_order'] as int,
      isActive: (data['is_active'] as int) == 1,
      isSystem: (data['is_system'] as int) == 1,
    );
  }
}

/// Provides the list of **active** expense type names for dropdowns.
///
/// This provider:
/// 1. Queries the `expense_types` table for active types only.
/// 2. Orders by `sort_order`.
/// 3. Returns a list of name strings ready for dropdown items.
final expenseTypesProvider = FutureProvider<List<String>>((ref) async {
  final db = ref.read(databaseProvider);

  try {
    final query = await db
        .customSelect(
          'SELECT * FROM expense_types WHERE is_active = 1 ORDER BY sort_order ASC, name ASC',
        )
        .get();

    return query.map((row) => row.data['name'] as String).toList();
  } catch (e) {
    // إذا لم يكن الجدول موجوداً بعد (قبل الترحيل)، أرجع القائمة الافتراضية
    return const [
      'رواتب',
      'ديزل',
      'صيانة',
      'فواتير كهرباء ومياه',
      'مستلزمات',
      'مساعدة محتاج',
      'اخرى',
    ];
  }
});

/// Provides the full list of expense types (including inactive) for the settings screen.
final allExpenseTypesProvider = FutureProvider<List<ExpenseTypeInfo>>((ref) async {
  final db = ref.read(databaseProvider);

  try {
    final query = await db
        .customSelect(
          'SELECT * FROM expense_types ORDER BY sort_order ASC, name ASC',
        )
        .get();

    return query.map((row) => ExpenseTypeInfo.fromRow(row.data)).toList();
  } catch (e) {
    return const [];
  }
});

/// مفتاح لإجبار تحديث القوائم بعد التعديل
final _expenseTypesRefreshKey = StateProvider<int>((ref) => 0);

/// إجبار تحديث قوائم أنواع المصروفات
void refreshExpenseTypes(WidgetRef ref) {
  final current = ref.read(_expenseTypesRefreshKey);
  ref.read(_expenseTypesRefreshKey.notifier).state = current + 1;
  ref.invalidate(expenseTypesProvider);
  ref.invalidate(allExpenseTypesProvider);
}

/// إضافة نوع مصروف جديد
Future<bool> addExpenseType(WidgetRef ref, String name) async {
  final db = ref.read(databaseProvider);
  try {
    // الحصول على أكبر sort_order
    final maxResult = await db
        .customSelect('SELECT MAX(sort_order) as max_order FROM expense_types')
        .get();
    final maxOrder = maxResult.first.data['max_order'] as int? ?? -1;

    await db.customInsert(
      'INSERT INTO expense_types (name, sort_order, is_active, is_system) VALUES (?, ?, 1, 0)',
      variables: [
        Variable<String>(name.trim()),
        Variable<int>(maxOrder + 1),
      ],
    );
    refreshExpenseTypes(ref);
    return true;
  } catch (e) {
    return false;
  }
}

/// تعديل اسم نوع مصروف
Future<bool> updateExpenseType(WidgetRef ref, int id, String newName) async {
  final db = ref.read(databaseProvider);
  try {
    await db.customUpdate(
      'UPDATE expense_types SET name = ? WHERE id = ?',
      variables: [
        Variable<String>(newName.trim()),
        Variable<int>(id),
      ],
    );
    refreshExpenseTypes(ref);
    return true;
  } catch (e) {
    return false;
  }
}

/// حذف نوع مصروف (فقط إذا لم يكن نظامياً)
Future<bool> deleteExpenseType(WidgetRef ref, int id) async {
  final db = ref.read(databaseProvider);
  try {
    // التحقق من أنه ليس نوعاً نظامياً
    final check = await db
        .customSelect('SELECT is_system FROM expense_types WHERE id = ?',
            variables: [Variable<int>(id)])
        .get();
    if (check.isEmpty) return false;
    if ((check.first.data['is_system'] as int) == 1) return false;

    await db.customDelete(
      'DELETE FROM expense_types WHERE id = ?',
      variables: [Variable<int>(id)],
    );
    refreshExpenseTypes(ref);
    return true;
  } catch (e) {
    return false;
  }
}

/// تفعيل/تعطيل نوع مصروف (فقط إذا لم يكن نظامياً)
Future<bool> toggleExpenseTypeActive(WidgetRef ref, int id, bool isActive) async {
  final db = ref.read(databaseProvider);
  try {
    // التحقق من أنه ليس نوعاً نظامياً
    final check = await db
        .customSelect('SELECT is_system FROM expense_types WHERE id = ?',
            variables: [Variable<int>(id)])
        .get();
    if (check.isEmpty) return false;
    if ((check.first.data['is_system'] as int) == 1) return false;

    await db.customUpdate(
      'UPDATE expense_types SET is_active = ? WHERE id = ?',
      variables: [
        Variable<int>(isActive ? 1 : 0),
        Variable<int>(id),
      ],
    );
    refreshExpenseTypes(ref);
    return true;
  } catch (e) {
    return false;
  }
}

/// تحديث ترتيب أنواع المصروفات (reorder)
Future<bool> reorderExpenseTypes(WidgetRef ref, List<int> orderedIds) async {
  final db = ref.read(databaseProvider);
  try {
    for (var i = 0; i < orderedIds.length; i++) {
      await db.customUpdate(
        'UPDATE expense_types SET sort_order = ? WHERE id = ?',
        variables: [
          Variable<int>(i),
          Variable<int>(orderedIds[i]),
        ],
      );
    }
    refreshExpenseTypes(ref);
    return true;
  } catch (e) {
    return false;
  }
}
