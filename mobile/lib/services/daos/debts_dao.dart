import 'package:drift/drift.dart';
import '../../utils/id.dart';
import '../../utils/time.dart';
import '../adapters/adapter_registry.dart';
import '../appwrite_sync_manager.dart';
import '../local_db.dart';
import 'outbox_dao.dart';

part 'debts_dao.g.dart';

@DriftAccessor(tables: [Debts])
class DebtsDao extends DatabaseAccessor<AppDatabase> with _$DebtsDaoMixin {
  DebtsDao(super.db, this.outboxDao, [AdapterRegistry? a])
    : adapters = a ?? AdapterRegistry.instance;
  final AdapterRegistry adapters;
  final OutboxDao outboxDao;

  Future<List<Debt>> list({
    bool includeDeleted = false,
    int? limit,
    int? offset,
  }) {
    final query = select(debts);
    if (!includeDeleted) {
      query.where((t) => t.deletedAt.isNull());
    }
    query.orderBy([
      (t) => OrderingTerm(expression: t.paymentDate, mode: OrderingMode.desc),
    ]);
    if (limit != null) {
      query.limit(limit, offset: offset);
    }
    return query.get();
  }

  Future<List<Debt>> listByBookingLocalId(
    int bookingLocalId, {
    bool includeDeleted = false,
    int? limit,
    int? offset,
  }) {
    final query = select(debts)
      ..where((t) => t.bookingLocalId.equals(bookingLocalId));
    if (!includeDeleted) {
      query.where((t) => t.deletedAt.isNull());
    }
    query.orderBy([
      (t) => OrderingTerm(expression: t.paymentDate, mode: OrderingMode.desc),
    ]);
    if (limit != null) {
      query.limit(limit, offset: offset);
    }
    return query.get();
  }

  Stream<List<Debt>> watchList({
    bool includeDeleted = false,
    int? limit,
    int offset = 0,
  }) {
    final query = select(debts);
    if (!includeDeleted) {
      query.where((t) => t.deletedAt.isNull());
    }
    query.orderBy([
      (t) => OrderingTerm(expression: t.paymentDate, mode: OrderingMode.desc),
    ]);
    if (limit != null) {
      query.limit(limit, offset: offset);
    }
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
        deviceId: originIsServer
            ? const Value.absent()
            : Value(AppwriteSyncManager.currentDeviceIdStatic ?? ''),
      );
      final id = await into(debts).insert(companion);
      if (!originIsServer) {
        await outboxDao.merge(
          entity: 'debts',
          op: 'create',
          localUuid: uuid,
          serverId: companion.serverId.present
              ? companion.serverId.value
              : null,
          payload: _payloadFrom(companion),
          clientTs: now,
        );
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
      // ✅ إصلاح: عند originIsServer=true، نستخدم lastModified من البيانات الواردة
      // بدلاً من تعيين now، لمنع إعادة رفع البيانات المسحوبة من السيرفر
      final effectiveLastModified = originIsServer && data.lastModified.present
          ? data.lastModified
          : Value(now);
      final companion = data.copyWith(
        updatedAt: Value(now),
        lastModified: effectiveLastModified,
        version: Value(existing.version + 1),
      );
      final rows = await (update(
        debts,
      )..where((t) => t.id.equals(id))).write(companion);
      if (rows > 0 && !originIsServer) {
        await outboxDao.merge(
          entity: 'debts',
          op: 'update',
          localUuid: existing.localUuid,
          serverId: existing.serverId,
          payload: _payloadFrom(companion, base: existing),
          clientTs: now,
        );
      }
      return rows;
    });
  }

  Future<int> softDelete(int id, {bool originIsServer = false}) async {
    return db.transaction(() async {
      final now = Time.nowEpoch();
      final existing = await getById(id);
      if (existing == null) {
        return 0;
      }
      final rows = await (update(debts)..where((t) => t.id.equals(id))).write(
        DebtsCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
          lastModified: Value(now),
        ),
      );
      if (rows > 0 && !originIsServer) {
        // ✅ نستخدم 'update' بدلاً من 'delete' لأن softDelete يحدّث deletedAt
        // ولا يحذف المستند من Appwrite — الجهاز الآخر يحتاج رؤية deletedAt
        await outboxDao.merge(
          entity: 'debts',
          op: 'update',
          localUuid: existing.localUuid,
          serverId: existing.serverId,
          payload: {'debt_id': existing.serverId},
          clientTs: now,
        );
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
      m['booking_local_id'] = comp.bookingLocalId.value;
    }
    if (comp.guestName.present) {
      m['guest_name'] = comp.guestName.value;
    }
    if (comp.checkinDate.present) {
      m['checkin_date'] = comp.checkinDate.value;
    }
    if (comp.checkoutDate.present) {
      m['checkout_date'] = comp.checkoutDate.value;
    }
    if (comp.dateRecorded.present) {
      m['date_recorded'] = comp.dateRecorded.value;
    }
    if (comp.debtReason.present) {
      m['debt_reason'] = comp.debtReason.value;
    }
    if (comp.totalAmount.present) {
      m['total_amount'] = comp.totalAmount.value;
    }
    if (comp.paidAmount.present) {
      m['paid_amount'] = comp.paidAmount.value;
    }
    if (comp.remainingAmount.present) {
      m['remaining_amount'] = comp.remainingAmount.value;
    }
    if (comp.paymentDate.present) {
      m['payment_date'] = comp.paymentDate.value;
    }
    if (comp.isSettled.present) {
      m['is_settled'] = comp.isSettled.value;
    }
    if (comp.pledge.present) {
      m['pledge'] = comp.pledge.value;
    }
    if (comp.pledgeType.present) {
      m['pledge_type'] = comp.pledgeType.value;
    }
    if (comp.note.present) {
      m['note'] = comp.note.value;
    }
    return m;
  }

  Future<void> importFromJson(
    List<Map<String, dynamic>> data, {
    bool clearExisting = false,
  }) async {
    await transaction(() async {
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
    });
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
