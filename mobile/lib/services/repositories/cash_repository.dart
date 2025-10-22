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

  Future<int> create({int? registerId, required String type, required double amount, String? referenceType, int? referenceId, String? description, required String transactionTime, int? createdBy}) => dao.insertOne(
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

  Future<int> update(int id, {int? registerId, String? type, double? amount, String? referenceType, int? referenceId, String? description, String? transactionTime, int? createdBy}) => dao.updateById(
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

  Future<int> delete(int id) => dao.softDelete(id);
}
