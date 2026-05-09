/// Providers for custom lists used across the app.
///
/// Provides dynamic, manageable dropdown lists stored in the
/// `custom_list_items` table. Each list is identified by a `list_key`
/// (e.g. 'expense_type', 'id_type', 'payment_method').
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'repository_providers.dart';

// ── مفاتيح القوائم ──────────────────────────────────────────────

const kListKeyExpenseType = 'expense_type';
const kListKeyIdType = 'id_type';
const kListKeyPaymentMethod = 'payment_method';

// ── القوائم الافتراضية (fallback) ──────────────────────────────

const List<String> kDefaultExpenseTypes = [
  'رواتب',
  'ديزل',
  'صيانة',
  'فواتير كهرباء ومياه',
  'مستلزمات',
  'مساعدة محتاج',
  'اخرى',
];

const List<String> kDefaultIdTypes = [
  'بطاقة شخصية',
  'جواز سفر',
  'رخصة قيادة',
  'بطاقة عسكرية',
  'استبيان',
  'شهادة ميلاد',
];

const List<String> kDefaultPaymentMethods = [
  'نقداً',
  'تحويل بنكي',
];

// ── نموذج عنصر القائمة ─────────────────────────────────────────

class CustomListItem {
  const CustomListItem({
    required this.id,
    required this.listKey,
    required this.name,
    required this.sortOrder,
    required this.isActive,
    required this.isSystem,
  });

  factory CustomListItem.fromRow(Map<String, dynamic> row) {
    return CustomListItem(
      id: row['id'] as int,
      listKey: row['list_key'] as String,
      name: row['name'] as String,
      sortOrder: row['sort_order'] as int,
      isActive: (row['is_active'] as int) == 1,
      isSystem: (row['is_system'] as int) == 1,
    );
  }

  final int id;
  final String listKey;
  final String name;
  final int sortOrder;
  final bool isActive;
  final bool isSystem;
}

// ── Providers ────────────────────────────────────────────────────

/// جلب جميع عناصر قائمة معينة (النشطة فقط للعرض)
final customListProvider =
    FutureProvider.family<List<CustomListItem>, String>((ref, listKey) async {
  final db = ref.read(databaseProvider);
  try {
    final rows = await db.customSelect(
      'SELECT * FROM custom_list_items '
      "WHERE list_key = '$listKey' AND is_active = 1 "
      'ORDER BY sort_order ASC, id ASC',
    ).get();
    if (rows.isEmpty) {
      return _fallbackItems(listKey);
    }
    return rows.map((r) => CustomListItem.fromRow(r.data)).toList();
  } catch (e) {
    return _fallbackItems(listKey);
  }
});

/// جلب جميع عناصر قائمة معينة (بما فيها المعطلة) لإدارة الإعدادات
final customListAllProvider =
    FutureProvider.family<List<CustomListItem>, String>((ref, listKey) async {
  final db = ref.read(databaseProvider);
  try {
    final rows = await db.customSelect(
      'SELECT * FROM custom_list_items '
      "WHERE list_key = '$listKey' "
      'ORDER BY sort_order ASC, id ASC',
    ).get();
    if (rows.isEmpty) {
      return _fallbackItems(listKey);
    }
    return rows.map((r) => CustomListItem.fromRow(r.data)).toList();
  } catch (e) {
    return _fallbackItems(listKey);
  }
});

/// أسماء عناصر القائمة النشطة فقط (للاستخدام المباشر في DropdownButton)
final customListNamesProvider =
    FutureProvider.family<List<String>, String>((ref, listKey) async {
  final items = await ref.watch(customListProvider(listKey).future);
  return items.map((e) => e.name).toList();
});

// ── إجراءات CRUD ────────────────────────────────────────────────

/// إضافة عنصر جديد إلى قائمة
final addCustomListItemProvider =
    FutureProvider.family<AsyncValue<void>, _AddItemArgs>((ref, args) async {
  final db = ref.read(databaseProvider);
  try {
    // حساب sort_order التالي
    final maxRow = await db.customSelect(
      'SELECT MAX(sort_order) as max_order FROM custom_list_items '
      "WHERE list_key = '${args.listKey}'",
    ).get();
    final nextOrder = (maxRow.first.data['max_order'] as int? ?? 0) + 1;
    await db.customStatement(
      'INSERT INTO custom_list_items (list_key, name, sort_order, is_active, is_system) '
      "VALUES ('${args.listKey}', '${args.name.replaceAll("'", "''")}', $nextOrder, 1, 0)",
    );
    ref.invalidate(customListProvider(args.listKey));
    ref.invalidate(customListAllProvider(args.listKey));
    ref.invalidate(customListNamesProvider(args.listKey));
    return const AsyncValue.data(null);
  } catch (e, st) {
    return AsyncValue.error(e, st);
  }
});

/// تعديل اسم عنصر في القائمة
final updateCustomListItemProvider =
    FutureProvider.family<AsyncValue<void>, _UpdateItemArgs>((ref, args) async {
  final db = ref.read(databaseProvider);
  try {
    await db.customStatement(
      "UPDATE custom_list_items SET name = '${args.newName.replaceAll("'", "''")}' "
      'WHERE id = ${args.id}',
    );
    ref.invalidate(customListProvider(args.listKey));
    ref.invalidate(customListAllProvider(args.listKey));
    ref.invalidate(customListNamesProvider(args.listKey));
    return const AsyncValue.data(null);
  } catch (e, st) {
    return AsyncValue.error(e, st);
  }
});

/// حذف عنصر من القائمة
final deleteCustomListItemProvider =
    FutureProvider.family<AsyncValue<void>, _DeleteItemArgs>((ref, args) async {
  final db = ref.read(databaseProvider);
  try {
    await db.customStatement(
      'DELETE FROM custom_list_items WHERE id = ${args.id}',
    );
    ref.invalidate(customListProvider(args.listKey));
    ref.invalidate(customListAllProvider(args.listKey));
    ref.invalidate(customListNamesProvider(args.listKey));
    return const AsyncValue.data(null);
  } catch (e, st) {
    return AsyncValue.error(e, st);
  }
});

/// تفعيل/تعطيل عنصر
final toggleCustomListItemProvider =
    FutureProvider.family<AsyncValue<void>, _ToggleItemArgs>((ref, args) async {
  final db = ref.read(databaseProvider);
  try {
    await db.customStatement(
      'UPDATE custom_list_items SET is_active = ${args.active ? 1 : 0} '
      'WHERE id = ${args.id}',
    );
    ref.invalidate(customListProvider(args.listKey));
    ref.invalidate(customListAllProvider(args.listKey));
    ref.invalidate(customListNamesProvider(args.listKey));
    return const AsyncValue.data(null);
  } catch (e, st) {
    return AsyncValue.error(e, st);
  }
});

/// إعادة ترتيب العناصر
final reorderCustomListProvider =
    FutureProvider.family<AsyncValue<void>, _ReorderArgs>((ref, args) async {
  final db = ref.read(databaseProvider);
  try {
    for (var i = 0; i < args.ids.length; i++) {
      await db.customStatement(
        'UPDATE custom_list_items SET sort_order = ${i + 1} WHERE id = ${args.ids[i]}',
      );
    }
    ref.invalidate(customListProvider(args.listKey));
    ref.invalidate(customListAllProvider(args.listKey));
    ref.invalidate(customListNamesProvider(args.listKey));
    return const AsyncValue.data(null);
  } catch (e, st) {
    return AsyncValue.error(e, st);
  }
});

// ── Provider قديم متوافق (أنواع المصروفات) ────────────────────

/// Provides the list of expense type strings (backward compatible).
final expenseTypesProvider = FutureProvider<List<String>>((ref) async {
  try {
    return await ref.watch(customListNamesProvider(kListKeyExpenseType).future);
  } catch (_) {
    return kDefaultExpenseTypes;
  }
});

// ── فئات المساعدة ───────────────────────────────────────────────

class _AddItemArgs {
  const _AddItemArgs({required this.listKey, required this.name});
  final String listKey;
  final String name;
}

class _UpdateItemArgs {
  const _UpdateItemArgs({
    required this.listKey,
    required this.id,
    required this.newName,
  });
  final String listKey;
  final int id;
  final String newName;
}

class _DeleteItemArgs {
  const _DeleteItemArgs({required this.listKey, required this.id});
  final String listKey;
  final int id;
}

class _ToggleItemArgs {
  const _ToggleItemArgs({
    required this.listKey,
    required this.id,
    required this.active,
  });
  final String listKey;
  final int id;
  final bool active;
}

class _ReorderArgs {
  const _ReorderArgs({required this.listKey, required this.ids});
  final String listKey;
  final List<int> ids;
}

// ── Fallback ─────────────────────────────────────────────────────

List<CustomListItem> _fallbackItems(String listKey) {
  final defaults = switch (listKey) {
    kListKeyExpenseType => kDefaultExpenseTypes,
    kListKeyIdType => kDefaultIdTypes,
    kListKeyPaymentMethod => kDefaultPaymentMethods,
    _ => <String>[],
  };
  return defaults.asMap().entries.map((e) {
    return CustomListItem(
      id: -(e.key + 1), // معرّف سلبي للعناصر الافتراضية
      listKey: listKey,
      name: e.value,
      sortOrder: e.key + 1,
      isActive: true,
      isSystem: listKey == kListKeyExpenseType && e.value == 'رواتب',
    );
  }).toList();
}
