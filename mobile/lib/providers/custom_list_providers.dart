/// Providers for custom lists used across the app.
///
/// Currently provides [expenseTypesProvider] which fetches the distinct
/// expense types from the local database, combining stored types with
/// sensible defaults so the expenses list always has a working set of
/// categories.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/local_db.dart';
import 'repository_providers.dart';

/// أنواع المصروفات المتاحة — القائمة الأساسية
const List<String> kDefaultExpenseTypes = [
  'رواتب',
  'ديزل',
  'صيانة',
  'فواتير كهرباء ومياه',
  'مستلزمات',
  'مساعدة محتاج',
  'اخرى',
];

/// Provides the list of expense type strings.
///
/// This provider:
/// 1. Queries the local DB for `DISTINCT expense_type` values.
/// 2. Merges them with [kDefaultExpenseTypes] to ensure the standard
///    categories are always available even if no expense of that type
///    has been created yet.
/// 3. Returns a sorted, deduplicated list.
final expenseTypesProvider = FutureProvider<List<String>>((ref) async {
  final db = ref.read(databaseProvider);

  try {
    final query = await db
        .customSelect('SELECT DISTINCT expense_type FROM expenses')
        .get();

    final dbTypes = <String>{};
    for (final row in query) {
      final value = row.data['expense_type'];
      if (value is String && value.trim().isNotEmpty) {
        dbTypes.add(value.trim());
      }
    }

    // Merge with defaults
    final merged = <String>{...dbTypes, ...kDefaultExpenseTypes};

    // Sort: Arabic types alphabetically, with 'اخرى' always last
    final sorted = merged.toList()
      ..sort((a, b) {
        if (a == 'اخرى') return 1;
        if (b == 'اخرى') return -1;
        return a.compareTo(b);
      });

    return sorted;
  } catch (e) {
    // Fallback to defaults if DB query fails
    return kDefaultExpenseTypes;
  }
});
