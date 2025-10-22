import 'package:drift/drift.dart';
import '../../utils/id.dart';
import '../../utils/time.dart';
import '../local_db.dart';
import 'outbox_dao.dart';

part 'expenses_dao.g.dart';

@DriftAccessor(tables: [Expenses])
class ExpensesDao extends DatabaseAccessor<AppDatabase> with _$ExpensesDaoMixin {
  ExpensesDao(AppDatabase db, this.outboxDao) : super(db);
  final OutboxDao outboxDao;

  Future<List<Expense>> list({String? search, String? from, String? to, bool includeDeleted = false}) async {
    final q = select(expenses);
    if (!includeDeleted) q.where((t) => t.deletedAt.isNull());
    if (from != null && to != null) q.where((t) => t.date.isBiggerOrEqualValue(from) & t.date.isSmallerOrEqualValue(to));
    if (search != null && search.trim().isNotEmpty) {
      final s = '%${search.trim()}%';
      q.where((t) => t.description.like(s) | t.expenseType.like(s));
    }
    return q.get();
  }

  Stream<List<Expense>> watchList({bool includeDeleted = false}) {
    final q = select(expenses);
    if (!includeDeleted) q.where((t) => t.deletedAt.isNull());
    return q.watch();
  }

  Future<Expense?> getById(int id) => (select(expenses)..where((t) => t.id.equals(id))).getSingleOrNull();
  Stream<Expense?> watchById(int id) => (select(expenses)..where((t) => t.id.equals(id))).watchSingleOrNull();

  Future<int> insertOne(ExpensesCompanion data, {bool originIsServer = false}) async {
    final now = Time.nowEpoch();
    final uu = data.localUuid.present ? data.localUuid.value : IdGen.uuid();
    final comp = data.copyWith(
      localUuid: Value(uu),
      createdAt: Value(now),
      updatedAt: Value(now),
      lastModified: Value(now),
      origin: Value(originIsServer ? 'server' : 'local'),
    );
    final id = await into(expenses).insert(comp);
    if (!originIsServer) {
      await outboxDao.merge(entity: 'expenses', op: 'create', localUuid: uu, serverId: comp.serverId.present ? comp.serverId.value : null, payload: _payloadFrom(comp), clientTs: now);
    }
    return id;
  }

  Future<int> updateById(int id, ExpensesCompanion data, {bool originIsServer = false}) async {
    final now = Time.nowEpoch();
    final existing = await getById(id);
    if (existing == null) return 0;
    final comp = data.copyWith(updatedAt: Value(now), lastModified: Value(now));
    final rows = await (update(expenses)..where((t) => t.id.equals(id))).write(comp);
    if (rows > 0 && !originIsServer) {
      await outboxDao.merge(entity: 'expenses', op: 'update', localUuid: existing.localUuid, serverId: existing.serverId, payload: _payloadFrom(comp, base: existing), clientTs: now);
    }
    return rows;
  }

  Future<int> softDelete(int id, {bool originIsServer = false}) async {
    final now = Time.nowEpoch();
    final existing = await getById(id);
    if (existing == null) return 0;
    final rows = await (update(expenses)..where((t) => t.id.equals(id))).write(ExpensesCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
      lastModified: Value(now),
    ));
    if (rows > 0 && !originIsServer) {
      await outboxDao.merge(entity: 'expenses', op: 'delete', localUuid: existing.localUuid, serverId: existing.serverId, payload: {'id': id}, clientTs: now);
    }
    return rows;
  }

  Map<String, dynamic> _payloadFrom(ExpensesCompanion comp, {Expense? base}) {
    final m = <String, dynamic>{};
    if (comp.expenseType.present) m['expense_type'] = comp.expenseType.value;
    if (comp.relatedId.present) m['related_id'] = comp.relatedId.value;
    if (comp.description.present) m['description'] = comp.description.value;
    if (comp.amount.present) m['amount'] = comp.amount.value;
    if (comp.date.present) m['date'] = comp.date.value;
    if (comp.cashTransactionId.present) m['cash_transaction_id'] = comp.cashTransactionId.value;
    return m;
  }
}
