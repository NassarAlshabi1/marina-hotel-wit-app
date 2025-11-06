import 'package:drift/drift.dart' as d;
import '../local_db.dart';
import '../auto_backup_manager.dart';
import '../daos/outbox_dao.dart';
import '../daos/cash_transactions_dao.dart';

class CashRepository {
  CashRepository(this.db)
      : outbox = OutboxDao(db),
        dao = CashTransactionsDao(db, OutboxDao(db));
  final AppDatabase db;
  final OutboxDao outbox;
  final CashTransactionsDao dao;

  Stream<List<CashTransaction>> watchAll() => dao.watchList();
  Stream<CashTransaction?> watchOne(int id) => dao.watchById(id);

  Future<int> create({int? registerId, required String type, required double amount, String? referenceType, int? referenceId, String? description, required String transactionTime, int? createdBy}) async {
    final transactionId = await dao.insertOne(
      CashTransactionsCompanion(
        registerId: d.Value(registerId),
        transactionType: d.Value(type),
        amount: d.Value(amount),
        referenceType: d.Value(referenceType),
        referenceId: d.Value(referenceId),
        description: d.Value(description),
        transactionTime: d.Value(transactionTime),
        createdBy: d.Value(createdBy),
      ),
    );

    // تسجيل التغيير للنسخ التلقائي
    AutoBackupManager.instance.onDataChange(
      'cash_transactions',
      'CREATE',
      recordData: {
        'id': transactionId,
        'type': type,
        'amount': amount,
      },
    );

    return transactionId;
  }

  Future<int> update(int id, {int? registerId, String? type, double? amount, String? referenceType, int? referenceId, String? description, String? transactionTime, int? createdBy}) async {
    final updatedRows = await dao.updateById(
      id,
      CashTransactionsCompanion(
        registerId: d.Value(registerId),
        transactionType: type != null ? d.Value(type) : const d.Value.absent(),
        amount: amount != null ? d.Value(amount) : const d.Value.absent(),
        referenceType: d.Value(referenceType),
        referenceId: d.Value(referenceId),
        description: description != null ? d.Value(description) : const d.Value.absent(),
        transactionTime: transactionTime != null ? d.Value(transactionTime) : const d.Value.absent(),
        createdBy: d.Value(createdBy),
      ),
    );

    if (updatedRows > 0) {
      // تسجيل التغيير للنسخ التلقائي
      AutoBackupManager.instance.onDataChange(
        'cash_transactions',
        'UPDATE',
        recordData: {
          'id': id,
          'type': type,
          'amount': amount,
        },
      );
    }

    return updatedRows;
  }

  Future<int> delete(int id) async {
    // الحصول على بيانات المعاملة قبل الحذف
    final transaction = await (db.select(db.cashTransactions)..where((t) => t.id.equals(id))).getSingleOrNull();
    
    final deletedRows = await dao.softDelete(id);

    if (deletedRows > 0 && transaction != null) {
      // تسجيل التغيير للنسخ التلقائي
      AutoBackupManager.instance.onDataChange(
        'cash_transactions',
        'DELETE',
        recordData: {
          'id': id,
          'type': transaction.transactionType,
          'amount': transaction.amount,
        },
      );
    }

    return deletedRows;
  }

  // دوال النسخ الاحتياطي

  /// تصدير بيانات المعاملات النقدية
  Future<Map<String, dynamic>> exportData() async {
    final transactionsData = await dao.exportToJson();
    final recordCount = await dao.getRecordCount();
    
    return {
      'data': transactionsData,
      'count': recordCount,
      'entity': 'cash_transactions',
    };
  }

  /// استيراد بيانات المعاملات النقدية
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
}
