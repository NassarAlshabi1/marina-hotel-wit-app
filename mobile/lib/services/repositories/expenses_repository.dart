import 'package:drift/drift.dart' as d;
import '../drive_backup_service.dart';
import '../local_db.dart';
import '../daos/outbox_dao.dart';
import '../daos/expenses_dao.dart';

class ExpensesRepository {
  ExpensesRepository(this.db, this.backupService)
      : outbox = OutboxDao(db),
        dao = ExpensesDao(db, OutboxDao(db));
  final AppDatabase db;
  final GoogleDriveBackupService backupService;
  final OutboxDao outbox;
  final ExpensesDao dao;

  Stream<List<Expense>> watchAll() => dao.watchList();
  Stream<Expense?> watchOne(int id) => dao.watchById(id);
  Future<List<String>> expenseTypes() => dao.distinctTypes();

  Future<int> create({required String expenseType, int? relatedId, required String description, required double amount, required String date}) async {
    final id = await dao.insertOne(
      ExpensesCompanion(
        expenseType: d.Value(expenseType),
        relatedId: d.Value(relatedId),
        description: d.Value(description),
        amount: d.Value(amount),
        date: d.Value(date),
      ),
    );
    backupService.scheduleAutoBackup('expenses-create');
    return id;
  }

  Future<int> update(int id, {String? expenseType, int? relatedId, String? description, double? amount, String? date}) async {
    final affected = await dao.updateById(
      id,
      ExpensesCompanion(
        expenseType: expenseType != null ? d.Value(expenseType) : const d.Value.absent(),
        relatedId: d.Value(relatedId),
        description: description != null ? d.Value(description) : const d.Value.absent(),
        amount: amount != null ? d.Value(amount) : const d.Value.absent(),
        date: date != null ? d.Value(date) : const d.Value.absent(),
      ),
    );
    if (affected > 0) {
      backupService.scheduleAutoBackup('expenses-update');
    }
    return affected;
  }

  Future<int> delete(int id) async {
    final affected = await dao.softDelete(id);
    if (affected > 0) {
      backupService.scheduleAutoBackup('expenses-delete');
    }
    return affected;
  }
}
