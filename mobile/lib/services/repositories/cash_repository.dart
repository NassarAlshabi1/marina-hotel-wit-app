import 'package:drift/drift.dart' as d;
import '../local_db.dart';
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

  Future<List<CashTransaction>> listByReference({
    required String referenceType,
    required int referenceId,
    bool includeDeleted = false,
  }) => dao.listByReference(
    referenceType: referenceType,
    referenceId: referenceId,
    includeDeleted: includeDeleted,
  );

  Future<int> create({
    int? registerId,
    required String type,
    required double amount,
    String? referenceType,
    int? referenceId,
    String? description,
    required String transactionTime,
    int? createdBy,
  }) => dao.insertOne(
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

  Future<int> update(
    int id, {
    int? registerId,
    String? type,
    double? amount,
    String? referenceType,
    int? referenceId,
    String? description,
    String? transactionTime,
    int? createdBy,
  }) => dao.updateById(
    id,
    CashTransactionsCompanion(
      // ✅ استخدام Value.absent() بدلاً من Value(null) لمنع مسح الحقول
      registerId: registerId != null ? d.Value(registerId) : const d.Value.absent(),
      transactionType: type != null ? d.Value(type) : const d.Value.absent(),
      amount: amount != null ? d.Value(amount) : const d.Value.absent(),
      referenceType: referenceType != null ? d.Value(referenceType) : const d.Value.absent(),
      referenceId: referenceId != null ? d.Value(referenceId) : const d.Value.absent(),
      description: description != null
          ? d.Value(description)
          : const d.Value.absent(),
      transactionTime: transactionTime != null
          ? d.Value(transactionTime)
          : const d.Value.absent(),
      createdBy: createdBy != null ? d.Value(createdBy) : const d.Value.absent(),
    ),
  );

  Future<int> delete(int id) => dao.softDelete(id);

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
        List<Map<String, dynamic>>.from(data['data'] as List),
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
