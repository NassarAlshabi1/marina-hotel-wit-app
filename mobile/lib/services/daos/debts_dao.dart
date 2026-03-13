import 'package:drift/drift.dart';
import '../../utils/id.dart';
import '../../utils/time.dart';
import '../local_db.dart';
import 'outbox_dao.dart';
import '../sync_guardian.dart';

part 'debts_dao.g.dart';

@DriftAccessor(tables: [Debts])
class DebtsDao extends DatabaseAccessor<AppDatabase> with _$DebtsDaoMixin {
  DebtsDao(super.db, this.outboxDao);
  final OutboxDao outboxDao;

  Future<List<Debt>> list({bool includeDeleted = false}) {
    final query = select(debts);
    if (!includeDeleted) {
      query.where((t) => t.deletedAt.isNull());
    }
    query.orderBy([
      (t) => OrderingTerm(expression: t.paymentDate, mode: OrderingMode.desc),
    ]);
    return query.get();
  }

  Future<List<Debt>> listByBookingLocalId(
    int bookingLocalId, {
    bool includeDeleted = false,
  }) {
    final query = select(debts)
      ..where((t) => t.bookingLocalId.equals(bookingLocalId));
    if (!includeDeleted) {
      query.where((t) => t.deletedAt.isNull());
    }
    query.orderBy([
      (t) => OrderingTerm(expression: t.paymentDate, mode: OrderingMode.desc),
    ]);
    return query.get();
  }

  Stream<List<Debt>> watchList({bool includeDeleted = false}) {
    final query = select(debts);
    if (!includeDeleted) {
      query.where((t) => t.deletedAt.isNull());
    }
    query.orderBy([
      (t) => OrderingTerm(expression: t.paymentDate, mode: OrderingMode.desc),
    ]);
    return query.watch();
  }

  Future<Debt?> getById(int id) {
    return (select(debts)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Stream<Debt?> watchById(int id) {
    return (select(debts)..where((t) => t.id.equals(id))).watchSingleOrNull();
  }

  Future<int> insertOne(
    DebtsCompanion data, {
    bool originIsServer = false,
  }) async {
    return db.transaction(() async {
      final now = Time.nowEpoch();
      final uuid = data.localUuid.present ? data.localUuid.value : IdGen.uuid();
      final companion = data.copyWith(
        localUuid: Value(uuid),
        createdAt: Value(now),
        updatedAt: Value(now),
        lastModified: Value(now),
        version: const Value(1),
        origin: Value(originIsServer ? 'server' : 'local'),
      );
      final id = await into(debts).insert(companion);
      if (!originIsServer) {
        await outboxDao.merge(
          entity: 'debts',
          op: 'create',
          localUuid: uuid,
          serverId:
              companion.serverId.present ? companion.serverId.value : null,
          payload: _payloadFrom(companion),
          clientTs: now,
        );
        SyncGuardian.instance
            .notifyLocalChange(table: 'debts', operation: 'create');
      }
      return id;
    });
  }

  Future<int> updateById(
    int id,
    DebtsCompanion data, {
    bool originIsServer = false,
  }) async {
    return db.transaction(() async {
      final existing = await getById(id);
      if (existing == null) {
        return 0;
      }
      final now = Time.nowEpoch();
      final companion = data.copyWith(
        updatedAt: Value(now),
        lastModified: Value(now),
      );
      final rows = await (update(
        debts,
      )..where((t) => t.id.equals(id)))
          .write(companion);
      if (rows > 0 && !originIsServer) {
        await outboxDao.merge(
          entity: 'debts',
          op: 'update',
          localUuid: existing.localUuid,
          serverId: existing.serverId,
          payload: _payloadFrom(companion, base: existing),
          clientTs: now,
        );
        SyncGuardian.instance
            .notifyLocalChange(table: 'debts', operation: 'update');
      }
      return rows;
    });
  }

  Future<int> softDelete(int id, {bool originIsServer = false}) async {
    return db.transaction(() async {
      final now = Time.nowEpoch();
      final existing = await getById(id);
      if (existing == null) return 0;
      final rows = await (update(debts)..where((t) => t.id.equals(id))).write(
        DebtsCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
          lastModified: Value(now),
        ),
      );
      if (rows > 0 && !originIsServer) {
        await outboxDao.merge(
          entity: 'debts',
          op: 'delete',
          localUuid: existing.localUuid,
          serverId: existing.serverId,
          payload: {'debt_id': existing.serverId},
          clientTs: now,
        );
        SyncGuardian.instance
            .notifyLocalChange(table: 'debts', operation: 'delete');
      }
      return rows;
    });
  }

  Future<int> hardDelete(int id, {bool originIsServer = false}) {
    return (delete(debts)..where((t) => t.id.equals(id))).go();
  }

  Future<List<Map<String, dynamic>>> exportToJson({
    bool includeDeleted = false,
  }) async {
    final items = await list(includeDeleted: includeDeleted);
    return items.map((e) => e.toJson()).toList();
  }

  Map<String, dynamic> _payloadFrom(DebtsCompanion comp, {Debt? base}) {
    final m = <String, dynamic>{};
    if (comp.bookingLocalId.present) {
      m['bookingLocalId'] = comp.bookingLocalId.value;
    }
    if (comp.guestName.present) m['guestName'] = comp.guestName.value;
    if (comp.checkinDate.present) m['checkinDate'] = comp.checkinDate.value;
    if (comp.checkoutDate.present) m['checkoutDate'] = comp.checkoutDate.value;
    if (comp.dateRecorded.present) m['dateRecorded'] = comp.dateRecorded.value;
    if (comp.debtReason.present) m['debtReason'] = comp.debtReason.value;
    if (comp.totalAmount.present) m['totalAmount'] = comp.totalAmount.value;
    if (comp.paidAmount.present) m['paidAmount'] = comp.paidAmount.value;
    if (comp.remainingAmount.present) {
      m['remainingAmount'] = comp.remainingAmount.value;
    }
    if (comp.paymentDate.present) m['paymentDate'] = comp.paymentDate.value;
    if (comp.isSettled.present) m['isSettled'] = comp.isSettled.value;
    if (comp.pledge.present) m['pledge'] = comp.pledge.value;
    if (comp.pledgeType.present) m['pledgeType'] = comp.pledgeType.value;
    if (comp.note.present) m['note'] = comp.note.value;
    return m;
  }

  Future<void> importFromJson(
    List<Map<String, dynamic>> data, {
    bool clearExisting = false,
  }) async {
    if (clearExisting) {
      await delete(debts).go();
    }
    for (final json in data) {
      final entity = Debt.fromJson(json);
      await into(debts).insertOnConflictUpdate(
        DebtsCompanion(
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
        ),
      );
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
