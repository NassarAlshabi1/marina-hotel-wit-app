import 'package:drift/drift.dart' as d;
import '../local_db.dart';
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

  Future<int> create({required String expenseType, int? relatedId, required String description, required double amount, required String date}) => dao.insertOne(
        ExpensesCompanion(
          expenseType: d.Value(expenseType),
          relatedId: d.Value(relatedId),
          description: d.Value(description),
          amount: d.Value(amount),
          date: d.Value(date),
        ),
      );

  Future<int> update(int id, {String? expenseType, int? relatedId, String? description, double? amount, String? date}) => dao.updateById(
        id,
        ExpensesCompanion(
          expenseType: expenseType != null ? d.Value(expenseType) : const d.Value.absent(),
          relatedId: d.Value(relatedId),
          description: description != null ? d.Value(description) : const d.Value.absent(),
          amount: amount != null ? d.Value(amount) : const d.Value.absent(),
          date: date != null ? d.Value(date) : const d.Value.absent(),
        ),
      );

  Future<int> delete(int id) => dao.softDelete(id);
}
