import 'package:drift/drift.dart';

import '../adapters/adapter_registry.dart';
import '../local_db.dart';
import 'outbox_dao.dart';

part 'payments_dao.g.dart';

@DriftAccessor(tables: [Payments])
class PaymentsDao extends DatabaseAccessor<AppDatabase> with _$PaymentsDaoMixin {
  PaymentsDao(super.db, this.outboxDao, this.adapters);
  final OutboxDao outboxDao;
  final AdapterRegistry adapters;

  Future<List<Payment>> list() async {
    return (select(payments)..where((t) => t.deletedAt.isNull())..orderBy([(t) => OrderingTerm(expression: t.paymentDate, mode: OrderingMode.desc)])).get();
  }

  Stream<List<Payment>> watchList({bool includeDeleted = false}) {
    final q = select(payments);
    if (!includeDeleted) {
      q.where((t) => t.deletedAt.isNull());
    }
    q.orderBy([(t) => OrderingTerm(expression: t.paymentDate, mode: OrderingMode.desc)]);
    return q.watch();
  }

  Future<Payment?> getById(int id) => (select(payments).where((t) => t.id.equals(id))).getSingleOrNull();

  Future<int> insertOne(PaymentsCompanion data, {bool originIsServer = false}) async {
    return db.transaction(() async {
      final insertedId = await into(payments).insert(data);
      if (!originIsServer) {
        // Outbox merge handled by repository layer
      }
      return insertedId;
    });
  }

  Future<int> updateById(int id, PaymentsCompanion data, {bool originIsServer = false}) async {
    return db.transaction(() async {
      final existing = await getById(id);
      if (existing == null) return 0;
      final comp = data.copyWith(
        updatedAt: Value(Time.nowEpoch()),
        lastModified: Value(Time.nowEpoch()),
        version: Value(existing.version + 1),
      );
      await update(payments).replace(comp);
      if (!originIsServer) {
        // Outbox merge handled by repository layer
      }
      return 1;
    });
  }

  Future<int> softDelete(int id, {bool originIsServer = false}) async {
    return db.transaction(() async {
      final existing = await getById(id);
      if (existing == null) return 0;
      await (update(payments)..where((t) => t.id.equals(id))).write(
        PaymentsCompanion(
          deletedAt: Value(Time.nowEpoch()),
          updatedAt: Value(Time.nowEpoch()),
          lastModified: Value(Time.nowEpoch()),
          version: Value(existing.version + 1),
        ),
      );
      if (!originIsServer) {
        // Outbox merge handled by repository layer
      }
      return 1;
    });
  }

  Future<int> getRecordCount() async {
    final query = selectOnly(payments)..addColumns([payments.id.count()]);
    final result = await query.getSingle();
    return result.read(payments.id.count()) ?? 0;
  }

  Future<void> clearAllData() async {
    await delete(payments).go();
  }

  Future<void> importFromJson(List<Map<String, dynamic>> data, {bool clearExisting = false}) async {
    await transaction(() async {
      if (clearExisting) {
        await delete(payments).go();
      }
      for (final payJson in data) {
        final pay = Payment.fromJson(payJson);
        await into(payments).insertOnConflictUpdate(
          PaymentsCompanion(
            id: Value(pay.id),
            localUuid: Value(pay.localUuid),
            serverId: Value(pay.serverId),
            bookingLocalId: Value(pay.bookingLocalId),
            serverBookingId: Value(pay.serverBookingId),
            roomNumber: Value(pay.roomNumber),
            amount: Value(pay.amount),
            paymentDate: Value(pay.paymentDate),
            notes: Value(pay.notes),
            paymentMethod: Value(pay.paymentMethod),
            revenueType: Value(pay.revenueType),
            hotelDayKey: Value(pay.hotelDayKey),
            isPendingBalance: Value(pay.isPendingBalance),
            bookingUuidCache: Value(pay.bookingUuidCache),
            createdAt: Value(pay.createdAt),
            updatedAt: Value(pay.updatedAt),
            deletedAt: Value(pay.deletedAt),
            lastModified: Value(pay.lastModified),
            version: Value(pay.version),
            origin: Value(pay.origin),
            createdAtIso: Value(pay.createdAtIso),
            updatedAtIso: Value(pay.updatedAtIso),
            deletedAtIso: Value(pay.deletedAtIso),
            createdAtEpoch: Value(pay.createdAtEpoch),
            lastModifiedEpoch: Value(pay.lastModifiedEpoch),
            vectorClock: Value(pay.vectorClock),
          ),
        );
      }
    });
  }

  Future<List<Map<String, dynamic>>> exportToJson() async {
    final list = await this.list();
    return list.map((e) => e.toJson()).toList();
  }
}
