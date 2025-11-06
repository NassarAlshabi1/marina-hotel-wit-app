import 'package:drift/drift.dart' as d;
import '../local_db.dart';
import '../auto_backup_manager.dart';
import '../daos/outbox_dao.dart';
import '../daos/expenses_dao.dart';

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
    final expenseId = await dao.insertOne(
      ExpensesCompanion(
        expenseType: d.Value(expenseType),
        relatedId: d.Value(relatedId),
        description: d.Value(description),
        amount: d.Value(amount),
        date: d.Value(date),
      ),
    );

    // تسجيل التغيير للنسخ التلقائي
    AutoBackupManager.instance.onDataChange(
      'expenses',
      'CREATE',
      recordData: {
        'id': expenseId,
        'expense_type': expenseType,
        'amount': amount,
        'description': description,
      },
    );

    return expenseId;
  }

  Future<int> update(int id, {String? expenseType, int? relatedId, String? description, double? amount, String? date}) async {
    final updatedRows = await dao.updateById(
      id,
      ExpensesCompanion(
        expenseType: expenseType != null ? d.Value(expenseType) : const d.Value.absent(),
        relatedId: d.Value(relatedId),
        description: description != null ? d.Value(description) : const d.Value.absent(),
        amount: amount != null ? d.Value(amount) : const d.Value.absent(),
        date: date != null ? d.Value(date) : const d.Value.absent(),
      ),
    );

    if (updatedRows > 0) {
      // تسجيل التغيير للنسخ التلقائي
      AutoBackupManager.instance.onDataChange(
        'expenses',
        'UPDATE',
        recordData: {
          'id': id,
          'expense_type': expenseType,
          'amount': amount,
          'description': description,
        },
      );
    }

    return updatedRows;
  }

  Future<int> delete(int id) async {
    // الحصول على بيانات المصروف قبل الحذف
    final expense = await (db.select(db.expenses)..where((e) => e.id.equals(id))).getSingleOrNull();
    
    final deletedRows = await dao.softDelete(id);

    if (deletedRows > 0 && expense != null) {
      // تسجيل التغيير للنسخ التلقائي
      AutoBackupManager.instance.onDataChange(
        'expenses',
        'DELETE',
        recordData: {
          'id': id,
          'expense_type': expense.expenseType,
          'amount': expense.amount,
        },
      );
    }

    return deletedRows;
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
