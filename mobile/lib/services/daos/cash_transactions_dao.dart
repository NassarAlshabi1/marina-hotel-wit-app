import 'package:drift/drift.dart';
import '../../utils/id.dart';
import '../../utils/time.dart';
import '../local_db.dart';
import 'outbox_dao.dart';

part 'cash_transactions_dao.g.dart';

@DriftAccessor(tables: [CashTransactions])
class CashTransactionsDao extends DatabaseAccessor<AppDatabase> with _$CashTransactionsDaoMixin {
  CashTransactionsDao(AppDatabase db, this.outboxDao) : super(db);
  final OutboxDao outboxDao;

  Future<List<CashTransaction>> list({String? type, String? from, String? to, bool includeDeleted = false}) async {
    final q = select(cashTransactions);
    if (!includeDeleted) q.where((t) => t.deletedAt.isNull());
    if (type != null && type.isNotEmpty) q.where((t) => t.transactionType.equals(type));
    if (from != null && to != null) q.where((t) => t.transactionTime.isBiggerOrEqualValue(from) & t.transactionTime.isSmallerOrEqualValue(to));
    q.orderBy([(t) => OrderingTerm(expression: t.transactionTime, mode: OrderingMode.desc)]);
    return q.get();
  }

  Future<List<CashTransaction>> listByReference({required String referenceType, required int referenceId, bool includeDeleted = false}) async {
    final q = select(cashTransactions)
      ..where((t) => t.referenceType.equals(referenceType) & t.referenceId.equals(referenceId));
    if (!includeDeleted) q.where((t) => t.deletedAt.isNull());
    q.orderBy([(t) => OrderingTerm(expression: t.transactionTime, mode: OrderingMode.desc)]);
    return q.get();
  }

  Stream<List<CashTransaction>> watchList({bool includeDeleted = false}) {
    final q = select(cashTransactions);
    if (!includeDeleted) q.where((t) => t.deletedAt.isNull());
    return q.watch();
  }

  Future<CashTransaction?> getById(int id) => (select(cashTransactions)..where((t) => t.id.equals(id))).getSingleOrNull();
  Stream<CashTransaction?> watchById(int id) => (select(cashTransactions)..where((t) => t.id.equals(id))).watchSingleOrNull();

  Future<int> insertOne(CashTransactionsCompanion data, {bool originIsServer = false}) async {
    final now = Time.nowEpoch();
    final uu = data.localUuid.present ? data.localUuid.value : IdGen.uuid();
    final comp = data.copyWith(
      localUuid: Value(uu),
      createdAt: Value(now),
      updatedAt: Value(now),
      lastModified: Value(now),
      origin: Value(originIsServer ? 'server' : 'local'),
    );
    final id = await into(cashTransactions).insert(comp);
    if (!originIsServer) {
      await outboxDao.merge(entity: 'cash_transactions', op: 'create', localUuid: uu, serverId: comp.serverId.present ? comp.serverId.value : null, payload: _payloadFrom(comp), clientTs: now);
    }
    return id;
  }

  Future<int> updateById(int id, CashTransactionsCompanion data, {bool originIsServer = false}) async {
    final now = Time.nowEpoch();
    final existing = await getById(id);
    if (existing == null) return 0;
    final comp = data.copyWith(updatedAt: Value(now), lastModified: Value(now));
    final rows = await (update(cashTransactions)..where((t) => t.id.equals(id))).write(comp);
    if (rows > 0 && !originIsServer) {
      await outboxDao.merge(entity: 'cash_transactions', op: 'update', localUuid: existing.localUuid, serverId: existing.serverId, payload: _payloadFrom(comp, base: existing), clientTs: now);
    }
    return rows;
  }

  Future<int> softDelete(int id, {bool originIsServer = false}) async {
    final now = Time.nowEpoch();
    final existing = await getById(id);
    if (existing == null) return 0;
    final rows = await (update(cashTransactions)..where((t) => t.id.equals(id))).write(CashTransactionsCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
      lastModified: Value(now),
    ));
    if (rows > 0 && !originIsServer) {
      await outboxDao.merge(entity: 'cash_transactions', op: 'delete', localUuid: existing.localUuid, serverId: existing.serverId, payload: {'id': id}, clientTs: now);
    }
    return rows;
  }

  Map<String, dynamic> _payloadFrom(CashTransactionsCompanion comp, {CashTransaction? base}) {
    final m = <String, dynamic>{};
    if (comp.registerId.present) m['register_id'] = comp.registerId.value;
    if (comp.transactionType.present) m['transaction_type'] = comp.transactionType.value;
    if (comp.amount.present) m['amount'] = comp.amount.value;
    if (comp.referenceType.present) m['reference_type'] = comp.referenceType.value;
    if (comp.referenceId.present) m['reference_id'] = comp.referenceId.value;
    if (comp.description.present) m['description'] = comp.description.value;
    if (comp.transactionTime.present) m['transaction_time'] = comp.transactionTime.value;
    if (comp.createdBy.present) m['created_by'] = comp.createdBy.value;
    return m;
  }

  // دوال النسخ الاحتياطي

  /// تصدير جميع معاملات النقدية إلى JSON
  Future<List<Map<String, dynamic>>> exportToJson() async {
    final transactionsList = await list(includeDeleted: false);
    return transactionsList.map((transaction) => transaction.toJson()).toList();
  }

  /// استيراد معاملات النقدية من JSON
  Future<void> importFromJson(List<Map<String, dynamic>> data, {bool clearExisting = false}) async {
    if (clearExisting) {
      await delete(cashTransactions).go();
    }

    for (final transactionJson in data) {
      final transaction = CashTransaction.fromJson(transactionJson);
      await into(cashTransactions).insertOnConflictUpdate(CashTransactionsCompanion(
        registerId: Value(transaction.registerId),
        transactionType: Value(transaction.transactionType),
        amount: Value(transaction.amount),
        referenceType: Value(transaction.referenceType),
        referenceId: Value(transaction.referenceId),
        description: Value(transaction.description),
        transactionTime: Value(transaction.transactionTime),
        createdBy: Value(transaction.createdBy),
        localUuid: Value(transaction.localUuid),
        serverId: Value(transaction.serverId),
        createdAt: Value(transaction.createdAt),
        updatedAt: Value(transaction.updatedAt),
        deletedAt: Value(transaction.deletedAt),
        lastModified: Value(transaction.lastModified),
        version: Value(transaction.version),
        origin: Value(transaction.origin),
      ));
    }
  }

  /// الحصول على عدد السجلات
  Future<int> getRecordCount() async {
    final query = selectOnly(cashTransactions)..addColumns([cashTransactions.id.count()]);
    final result = await query.getSingle();
    return result.read(cashTransactions.id.count()) ?? 0;
  }

  /// مسح جميع البيانات
  Future<void> clearAllData() async {
    await delete(cashTransactions).go();
  }
}
