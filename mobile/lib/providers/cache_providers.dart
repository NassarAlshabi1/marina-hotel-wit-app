import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/data_cache.dart';

/// Cache provider for reports - singleton
final dataCacheProvider = Provider<DataCache>((ref) {
  return DataCache();
});

/// Persisted cache provider
final persistedCacheProvider = Provider<PersistedCache>((ref) {
  return PersistedCache();
});

/// Cache keys for different report types
class ReportCacheKeys {
  static const payments = 'report_payments';
  static const expenses = 'report_expenses';
  static const debts = 'report_debts';
  static const incomeExpense = 'report_income_expense';
  static const salary = 'report_salary';

  static String paymentsWithParams(String from, String to, String? room) =>
      'report_payments_${from}_${to}_$room';

  static String expensesWithParams(String from, String to, String? category) =>
      'report_expenses_${from}_${to}_$category';
}
