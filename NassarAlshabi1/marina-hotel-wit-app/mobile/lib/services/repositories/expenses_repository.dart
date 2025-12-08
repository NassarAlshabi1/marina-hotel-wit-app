import 'package:drift/drift.dart' as d;
import '../local_db.dart';
import '../daos/outbox_dao.dart';
import '../daos/expenses_dao.dart';
import '../google_drive_auto_sync_engine.dart';

class ExpensesRepository {
  ExpensesRepository(this.db)
      : outbox = OutboxDao(db),
        dao = ExpensesDao(db, OutboxDao(db));
  final AppDatabase db;
  final OutboxDao outbox;
  final ExpensesDao dao;

  Stream<List<Expense>> watchAll() => dao.watchList();
  Stream<Expense?> watchOne(int id) => dao.watchById(id);

  Future<int> create({required String expenseType, int? relatedId, required String description, required double amount, required String date}) async {
    final result = await dao.insertOne(
      ExpensesCompanion(
        expenseType: d.Value(expenseType),
        relatedId: d.Value(relatedId),
        description: d.Value(description),
        amount: d.Value(amount),
        date: d.Value(date),
      ),
    );
    AutoSyncEngine.instance.notifyDataChange(table: 'expenses', operation: 'INSERT', count: 1);
    return result;
  }

  Future<int> update(int id, {String? expenseType, int? relatedId, String? description, double? amount, String? date}) async {
    final result = await dao.updateById(
      id,
      ExpensesCompanion(
        expenseType: expenseType != null ? d.Value(expenseType) : const d.Value.absent(),
        relatedId: d.Value(relatedId),
        description: description != null ? d.Value(description) : const d.Value.absent(),
        amount: amount != null ? d.Value(amount) : const d.Value.absent(),
        date: date != null ? d.Value(date) : const d.Value.absent(),
      ),
    );
    if (result > 0) {
      AutoSyncEngine.instance.notifyDataChange(table: 'expenses', operation: 'UPDATE', count: 1);
    }
    return result;
  }

  Future<int> delete(int id) async {
    final result = await dao.softDelete(id);
    if (result > 0) {
      AutoSyncEngine.instance.notifyDataChange(table: 'expenses', operation: 'DELETE', count: 1);
    }
    return result;
  }

  // دوال النسخ الاحتياطي

  /// تصدير بيانات المصروفات
  Future<Map<String, dynamic>> exportData() async {
    final expensesData = await dao.exportToJson();
    final recordCount = await dao.getRecordCount();
    
    return {
      'data': expensesData,
      'count': recordCount,
      'entity': 'expenses',
    };
  }

  /// استيراد بيانات المصروفات
  Future<void> importData(Map<String, dynamic> data) async {
    if (data.containsKey('data') && data['data'] is List) {
      await dao.importFromJson(
        List<Map<String, dynamic>>.from(data['data']), 
        clearExisting: false,
      );
    }
  }

  /// مسح جميع البيانات
  Future<void> clearAllData() async {
    await dao.clearAllData();
  }

  /// الحصول على إجمالي عدد السجلات
  Future<int> getRecordCount() async {
    return await dao.getRecordCount();
  }

  /// الحصول على إجمالي المصروفات لتاريخ محدد
  Future<double> getTotalByDate(String date) async {
    final expenses = await dao.listByDate(date);
    double total = 0;
    for (final expense in expenses) {
      total += expense.amount;
    }
    return total;
  }
}
