/// Providers for custom lists used across the app.
///
/// Provides dynamic, manageable dropdown lists stored in the
/// `custom_list_items` table. Each list is identified by a `list_key`
/// (e.g. 'expense_type', 'id_type', 'payment_method').
library;

import 'package:drift/drift.dart' as drift;
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
  'نقدي',
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

// ── Providers (للقراءة فقط) ─────────────────────────────────────

/// جلب جميع عناصر قائمة معينة (النشطة فقط للعرض)
final customListProvider =
    FutureProvider.family<List<CustomListItem>, String>((ref, listKey) async {
  final db = ref.read(databaseProvider);
  try {
    final rows = await db.customSelect(
      'SELECT * FROM custom_list_items '
      'WHERE list_key = ? AND is_active = 1 '
      'ORDER BY sort_order ASC, id ASC',
      variables: [drift.Variable.withText(listKey)],
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
/// ملاحظة: لا يستخدم fallback — إذا كان الجدول فارغاً يُعرض فارغاً
final customListAllProvider =
    FutureProvider.family<List<CustomListItem>, String>((ref, listKey) async {
  final db = ref.read(databaseProvider);
  try {
    final rows = await db.customSelect(
      'SELECT * FROM custom_list_items '
      'WHERE list_key = ? '
      'ORDER BY sort_order ASC, id ASC',
      variables: [drift.Variable.withText(listKey)],
    ).get();
    return rows.map((r) => CustomListItem.fromRow(r.data)).toList();
  } catch (e) {
    return const [];
  }
});

/// أسماء عناصر القائمة النشطة فقط (للاستخدام المباشر في DropdownButton)
final customListNamesProvider =
    FutureProvider.family<List<String>, String>((ref, listKey) async {
  final items = await ref.watch(customListProvider(listKey).future);
  return items.map((e) => e.name).toList();
});

// ── إجراءات CRUD (دوال async مباشرة — ليست Providers) ──────────

/// إضافة عنصر جديد إلى قائمة
Future<void> addCustomListItem(
  Ref ref,
  String listKey,
  String name,
) async {
  final db = ref.read(databaseProvider);
  // فحص التكرار: هل يوجد عنصر بنفس الاسم في نفس القائمة؟
  final existing = await db.customSelect(
    'SELECT id FROM custom_list_items '
    'WHERE list_key = ? AND name = ?',
    variables: [drift.Variable.withText(listKey), drift.Variable.withText(name)],
  ).get();
  if (existing.isNotEmpty) {
    throw Exception('يوجد عنصر بنفس الاسم "$name" بالفعل');
  }
  // حساب sort_order التالي
  final maxRow = await db.customSelect(
    'SELECT MAX(sort_order) as max_order FROM custom_list_items '
    'WHERE list_key = ?',
    variables: [drift.Variable.withText(listKey)],
  ).get();
  final nextOrder = (maxRow.first.data['max_order'] as int? ?? 0) + 1;
  await db.customStatement(
    'INSERT INTO custom_list_items (list_key, name, sort_order, is_active, is_system) '
    'VALUES (?, ?, ?, 1, 0)',
    [listKey, name, nextOrder],
  );
  _invalidateAll(ref, listKey);
}

/// تعديل اسم عنصر في القائمة
Future<void> updateCustomListItem(
  Ref ref,
  String listKey,
  int id,
  String newName,
) async {
  final db = ref.read(databaseProvider);
  // فحص التكرار: هل يوجد عنصر آخر بنفس الاسم الجديد في نفس القائمة؟
  final existing = await db.customSelect(
    'SELECT id FROM custom_list_items '
    'WHERE list_key = ? AND name = ? AND id != ?',
    variables: [
      drift.Variable.withText(listKey),
      drift.Variable.withText(newName),
      drift.Variable.withInt(id),
    ],
  ).get();
  if (existing.isNotEmpty) {
    throw Exception('يوجد عنصر آخر بنفس الاسم بالفعل');
  }
  await db.customStatement(
    'UPDATE custom_list_items SET name = ? WHERE id = ?',
    [newName, id],
  );
  _invalidateAll(ref, listKey);
}

/// حذف عنصر من القائمة
Future<void> deleteCustomListItem(
  Ref ref,
  String listKey,
  int id,
) async {
  final db = ref.read(databaseProvider);
  await db.customStatement(
    'DELETE FROM custom_list_items WHERE id = ?',
    [id],
  );
  _invalidateAll(ref, listKey);
}

/// تفعيل/تعطيل عنصر
Future<void> toggleCustomListItem(
  Ref ref,
  String listKey,
  int id,
  bool active,
) async {
  final db = ref.read(databaseProvider);
  await db.customStatement(
    'UPDATE custom_list_items SET is_active = ? WHERE id = ?',
    [if (active) 1 else 0, id],
  );
  _invalidateAll(ref, listKey);
}

/// إعادة ترتيب العناصر
Future<void> reorderCustomListItems(
  Ref ref,
  String listKey,
  List<int> ids,
) async {
  final db = ref.read(databaseProvider);
  for (var i = 0; i < ids.length; i++) {
    await db.customStatement(
      'UPDATE custom_list_items SET sort_order = ? WHERE id = ?',
      [i + 1, ids[i]],
    );
  }
  _invalidateAll(ref, listKey);
}

/// إعادة تحميل جميع providers المرتبطة بقائمة معينة
void _invalidateAll(Ref ref, String listKey) {
  ref.invalidate(customListProvider(listKey));
  ref.invalidate(customListAllProvider(listKey));
  ref.invalidate(customListNamesProvider(listKey));
}

// ── Provider قديم متوافق (أنواع المصروفات) ────────────────────

/// Provides the list of expense type strings (backward compatible).
final expenseTypesProvider = FutureProvider<List<String>>((ref) async {
  try {
    return await ref.watch(customListNamesProvider(kListKeyExpenseType).future);
  } catch (_) {
    return kDefaultExpenseTypes;
  }
});

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
