import 'package:drift/drift.dart';
import '../../utils/id.dart';
import '../../utils/time.dart';
import '../local_db.dart';
import 'outbox_dao.dart';

part 'debts_dao.g.dart';

@DriftAccessor(tables: [Debts])
class DebtsDao extends DatabaseAccessor<AppDatabase> with _$DebtsDaoMixin {
  DebtsDao(AppDatabase db, this.outboxDao) : super(db);
  final OutboxDao outboxDao;

  Future<List<Debt>> list({bool includeDeleted = false}) {
    final query = select(debts);
    if (!includeDeleted) {
      query.where((t) => t.deletedAt.isNull());
    }
    query.orderBy([(t) => OrderingTerm(expression: t.paymentDate, mode: OrderingMode.desc)]);
    return query.get();
  }

  Stream<List<Debt>> watchList({bool includeDeleted = false}) {
    final query = select(debts);
    if (!includeDeleted) {
      query.where((t) => t.deletedAt.isNull());
    }
    query.orderBy([(t) => OrderingTerm(expression: t.paymentDate, mode: OrderingMode.desc)]);
    return query.watch();
  }

  Future<Debt?> getById(int id) {
    return (select(debts)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Stream<Debt?> watchById(int id) {
    return (select(debts)..where((t) => t.id.equals(id))).watchSingleOrNull();
  }

  Future<int> insertOne(DebtsCompanion data) async {
    final now = Time.nowEpoch();
    final uuid = data.localUuid.present ? data.localUuid.value : IdGen.uuid();
    final companion = data.copyWith(
      localUuid: Value(uuid),
      createdAt: Value(now),
      updatedAt: Value(now),
      lastModified: Value(now),
      version: const Value(1),
      origin: const Value('local'),
    );
    return into(debts).insert(companion);
  }

  Future<int> updateById(int id, DebtsCompanion data) async {
    final existing = await getById(id);
    if (existing == null) {
      return 0;
    }
    final now = Time.nowEpoch();
    final companion = data.copyWith(
      updatedAt: Value(now),
      lastModified: Value(now),
    );
    return (update(debts)..where((t) => t.id.equals(id))).write(companion);
  }

  Future<int> softDelete(int id) async {
    final now = Time.nowEpoch();
    return (update(debts)..where((t) => t.id.equals(id))).write(DebtsCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
      lastModified: Value(now),
    ));
  }

  Future<int> hardDelete(int id) {
    return (delete(debts)..where((t) => t.id.equals(id))).go();
  }

  Future<List<Map<String, dynamic>>> exportToJson({bool includeDeleted = false}) async {
    final items = await list(includeDeleted: includeDeleted);
    return items.map((e) => e.toJson()).toList();
  }

  Future<void> importFromJson(List<Map<String, dynamic>> data, {bool clearExisting = false}) async {
    if (clearExisting) {
      await delete(debts).go();
    }
    for (final json in data) {
      final entity = Debt.fromJson(json);
      await into(debts).insertOnConflictUpdate(DebtsCompanion(
        bookingLocalId: Value(entity.bookingLocalId),
        guestName: Value(entity.guestName),
        checkinDate: Value(entity.checkinDate),
        checkoutDate: Value(entity.checkoutDate),
        totalAmount: Value(entity.totalAmount),
        paidAmount: Value(entity.paidAmount),
        remainingAmount: Value(entity.remainingAmount),
        paymentDate: Value(entity.paymentDate),
        pledge: Value(entity.pledge),
        pledgeType: Value(entity.pledgeType),
        note: Value(entity.note),
        localUuid: Value(entity.localUuid),
        serverId: Value(entity.serverId),
        createdAt: Value(entity.createdAt),
        updatedAt: Value(entity.updatedAt),
        deletedAt: Value(entity.deletedAt),
        lastModified: Value(entity.lastModified),
        version: Value(entity.version),
        origin: Value(entity.origin),
      ));
    }
  }

  Future<int> getRecordCount() async {
    final query = selectOnly(debts)..addColumns([debts.id.count()]);
    final result = await query.getSingle();
    return result.read(debts.id.count()) ?? 0;
  }

  Future<void> clearAllData() async {
    await delete(debts).go();
  }
}
