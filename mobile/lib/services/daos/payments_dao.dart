import 'package:drift/drift.dart';
import '../../utils/id.dart';
import '../../utils/time.dart';
import '../local_db.dart';
import 'outbox_dao.dart';

part 'payments_dao.g.dart';

@DriftAccessor(tables: [Payments])
class PaymentsDao extends DatabaseAccessor<AppDatabase> with _$PaymentsDaoMixin {
  PaymentsDao(AppDatabase db, this.outboxDao) : super(db);
  final OutboxDao outboxDao;

  Future<List<Payment>> list({int? bookingLocalId, String? from, String? to, String? revenueType, bool includeDeleted = false}) async {
    final q = select(payments);
    if (!includeDeleted) q.where((t) => t.deletedAt.isNull());
    if (bookingLocalId != null) q.where((t) => t.bookingLocalId.equals(bookingLocalId));
    if (revenueType != null && revenueType.isNotEmpty) q.where((t) => t.revenueType.equals(revenueType));
    if (from != null && to != null) q.where((t) => t.paymentDate.isBiggerOrEqualValue(from) & t.paymentDate.isSmallerOrEqualValue(to));
    q.orderBy([(t) => OrderingTerm(expression: t.paymentDate, mode: OrderingMode.desc)]);
    return q.get();
  }

  Stream<List<Payment>> watchList({int? bookingLocalId, bool includeDeleted = false}) {
    final q = select(payments);
    if (!includeDeleted) q.where((t) => t.deletedAt.isNull());
    if (bookingLocalId != null) q.where((t) => t.bookingLocalId.equals(bookingLocalId));
    return q.watch();
  }

  Future<Payment?> getById(int id) => (select(payments)..where((t) => t.id.equals(id))).getSingleOrNull();
  Stream<Payment?> watchById(int id) => (select(payments)..where((t) => t.id.equals(id))).watchSingleOrNull();

  Future<int> insertOne(PaymentsCompanion data, {bool originIsServer = false}) async {
    final now = Time.nowEpoch();
    final uu = data.localUuid.present ? data.localUuid.value : IdGen.uuid();
    final comp = data.copyWith(
      localUuid: Value(uu),
      createdAt: Value(now),
      updatedAt: Value(now),
      lastModified: Value(now),
      origin: Value(originIsServer ? 'server' : 'local'),
      serverId: data.serverPaymentId.present ? Value(data.serverPaymentId.value) : const Value.absent(),
    );
    final id = await into(payments).insert(comp);
    if (!originIsServer) {
      await outboxDao.merge(entity: 'payments', op: 'create', localUuid: uu, serverId: comp.serverId.present ? comp.serverId.value : null, payload: _payloadFrom(comp), clientTs: now);
    }
    return id;
  }

  Future<int> updateById(int id, PaymentsCompanion data, {bool originIsServer = false}) async {
    final now = Time.nowEpoch();
    final existing = await getById(id);
    if (existing == null) return 0;
    final comp = data.copyWith(updatedAt: Value(now), lastModified: Value(now));
    final rows = await (update(payments)..where((t) => t.id.equals(id))).write(comp);
    if (rows > 0 && !originIsServer) {
      await outboxDao.merge(entity: 'payments', op: 'update', localUuid: existing.localUuid, serverId: existing.serverId, payload: _payloadFrom(comp, base: existing), clientTs: now);
    }
    return rows;
  }

  Future<int> softDelete(int id, {bool originIsServer = false}) async {
    final now = Time.nowEpoch();
    final existing = await getById(id);
    if (existing == null) return 0;
    final rows = await (update(payments)..where((t) => t.id.equals(id))).write(PaymentsCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
      lastModified: Value(now),
    ));
    if (rows > 0 && !originIsServer) {
      await outboxDao.merge(entity: 'payments', op: 'delete', localUuid: existing.localUuid, serverId: existing.serverId, payload: {'payment_id': existing.serverPaymentId}, clientTs: now);
    }
    return rows;
  }

  Map<String, dynamic> _payloadFrom(PaymentsCompanion comp, {Payment? base}) {
    final m = <String, dynamic>{};
    if (comp.serverPaymentId.present) m['payment_id'] = comp.serverPaymentId.value;
    if (comp.bookingLocalId.present) m['booking_local_id'] = comp.bookingLocalId.value;
    if (comp.serverBookingId.present) m['booking_id'] = comp.serverBookingId.value;
    if (comp.roomNumber.present) m['room_number'] = comp.roomNumber.value;
    if (comp.amount.present) m['amount'] = comp.amount.value;
    if (comp.paymentDate.present) m['payment_date'] = comp.paymentDate.value;
    if (comp.notes.present) m['notes'] = comp.notes.value;
    if (comp.paymentMethod.present) m['payment_method'] = comp.paymentMethod.value;
    if (comp.revenueType.present) m['revenue_type'] = comp.revenueType.value;
    if (comp.cashTransactionLocalId.present) m['cash_transaction_local_id'] = comp.cashTransactionLocalId.value;
    if (comp.cashTransactionServerId.present) m['cash_transaction_id'] = comp.cashTransactionServerId.value;
    return m;
  }
}
