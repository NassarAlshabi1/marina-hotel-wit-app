import 'package:drift/drift.dart' as d;
import '../local_db.dart';
import '../daos/outbox_dao.dart';
import '../daos/expenses_dao.dart';
import '../auto_backup_manager.dart';
import '../../utils/time.dart';

class ExpensesRepository {
  ExpensesRepository(this.db)
    : outbox = OutboxDao(db),
      dao = ExpensesDao(db, OutboxDao(db));
  final AppDatabase db;
  final OutboxDao outbox;
  final ExpensesDao dao;

  Stream<List<Expense>> watchAll() => dao.watchList();
  Stream<Expense?> watchOne(int id) => dao.watchById(id);

  Future<int> create({
    required String expenseType,
    int? relatedId,
    required String description,
    required double amount,
    required String date,
  }) async {
    final normalizedDate = Time.safeIsoToDateString(date);
    final hotelDayKey = normalizedDate.isNotEmpty
        ? normalizedDate
        : Time.hotelDayKey();
    final result = await dao.insertOne(
      ExpensesCompanion(
        expenseType: d.Value(expenseType),
        relatedId: d.Value(relatedId),
        description: d.Value(description),
        amount: d.Value(amount),
        date: d.Value(normalizedDate),
        hotelDayKey: d.Value(hotelDayKey),
      ),
    );
    AutoBackupManager.instance.onDataChange(
      'expenses',
      'INSERT',
      recordData: {'amount': amount},
    );
    return result;
  }

  Future<int> update(
    int id, {
    String? expenseType,
    int? relatedId,
    String? description,
    double? amount,
    String? date,
  }) async {
    final normalizedDate = date != null ? Time.safeIsoToDateString(date) : null;
    final result = await dao.updateById(
      id,
      ExpensesCompanion(
        expenseType: expenseType != null
            ? d.Value(expenseType)
            : const d.Value.absent(),
        relatedId: d.Value(relatedId),
        description: description != null
            ? d.Value(description)
            : const d.Value.absent(),
        amount: amount != null ? d.Value(amount) : const d.Value.absent(),
        date: normalizedDate != null
            ? d.Value(normalizedDate)
            : const d.Value.absent(),
        hotelDayKey: normalizedDate != null
            ? d.Value(normalizedDate)
            : const d.Value.absent(),
      ),
    );
    if (result > 0) {
      AutoBackupManager.instance.onDataChange(
        'expenses',
        'UPDATE',
        recordData: {'id': id},
      );
    }
    return result;
  }

  Future<int> delete(int id) async {
    final result = await dao.softDelete(id);
    if (result > 0) {
      AutoBackupManager.instance.onDataChange(
        'expenses',
        'DELETE',
        recordData: {'id': id},
      );
    }
    return result;
  }

  // دوال النسخ الاحتياطي

  /// تصدير بيانات المصروفات
  Future<Map<String, dynamic>> exportData() async {
    final expensesData = await dao.exportToJson();
    final recordCount = await dao.getRecordCount();

    return {'data': expensesData, 'count': recordCount, 'entity': 'expenses'};
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

  Future<double> getTotalByHotelDayKey(String hotelDayKey) async {
    final expenses = await dao.listByHotelDayKey(hotelDayKey);
    double total = 0;
    for (final expense in expenses) {
      total += expense.amount;
    }
    return total;
  }
}
