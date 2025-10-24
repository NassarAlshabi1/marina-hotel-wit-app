import 'dart:async';

import 'package:drift/drift.dart' as d;
import '../local_db.dart';
import '../daos/outbox_dao.dart';
import '../daos/cash_transactions_dao.dart';
import '../backup_sync_service.dart';

class CashRepository {
  CashRepository(this.db, {BackupSyncService? backupSyncService})
      : outbox = OutboxDao(db),
        dao = CashTransactionsDao(db, OutboxDao(db)),
        _backupSyncService = backupSyncService;
  final AppDatabase db;
  final OutboxDao outbox;
  final CashTransactionsDao dao;
  final BackupSyncService? _backupSyncService;

  void _scheduleAutoBackup() {
    unawaited(_backupSyncService?.triggerAutoBackup());
  }

  Stream<List<CashTransaction>> watchAll() => dao.watchList();
  Stream<CashTransaction?> watchOne(int id) => dao.watchById(id);

  Future<int> create({int? registerId, required String type, required double amount, String? referenceType, int? referenceId, String? description, required String transactionTime, int? createdBy}) async {
    final id = await dao.insertOne(
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
    _scheduleAutoBackup();
    return id;
  }

  Future<int> update(int id, {int? registerId, String? type, double? amount, String? referenceType, int? referenceId, String? description, String? transactionTime, int? createdBy}) async {
    final rows = await dao.updateById(
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
    if (rows > 0) {
      _scheduleAutoBackup();
    }
    return rows;
  }

  Future<int> delete(int id) async {
    final rows = await dao.softDelete(id);
    if (rows > 0) {
      _scheduleAutoBackup();
    }
    return rows;
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
      _scheduleAutoBackup();
    }
  }

  /// مسح جميع البيانات
  Future<void> clearAllData() async {
    await dao.clearAllData();
    _scheduleAutoBackup();
  }

  /// الحصول على إجمالي عدد السجلات
  Future<int> getRecordCount() async {
    return await dao.getRecordCount();
  }
}
