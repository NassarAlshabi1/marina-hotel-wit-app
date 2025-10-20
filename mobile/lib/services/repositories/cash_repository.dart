import 'package:drift/drift.dart' as d;
import '../drive_backup_service.dart';
import '../local_db.dart';
import '../daos/outbox_dao.dart';
import '../daos/cash_transactions_dao.dart';

class CashRepository {
  CashRepository(this.db, this.backupService)
      : outbox = OutboxDao(db),
        dao = CashTransactionsDao(db, OutboxDao(db));
  final AppDatabase db;
  final GoogleDriveBackupService backupService;
  final OutboxDao outbox;
  final CashTransactionsDao dao;

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
    backupService.scheduleAutoBackup('cash-create');
    return id;
  }

  Future<int> update(int id, {int? registerId, String? type, double? amount, String? referenceType, int? referenceId, String? description, String? transactionTime, int? createdBy}) async {
    final affected = await dao.updateById(
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
    if (affected > 0) {
      backupService.scheduleAutoBackup('cash-update');
    }
    return affected;
  }

  Future<int> delete(int id) async {
    final affected = await dao.softDelete(id);
    if (affected > 0) {
      backupService.scheduleAutoBackup('cash-delete');
    }
    return affected;
  }
}
