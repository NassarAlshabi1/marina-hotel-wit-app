import 'package:drift/drift.dart';
import '../../utils/id.dart';
import '../../utils/time.dart';
import '../local_db.dart';
import 'outbox_dao.dart';

part 'payments_dao.g.dart';

@DriftAccessor(tables: [Payments])
class PaymentsDao extends DatabaseAccessor<AppDatabase> with _$PaymentsDaoMixin {
  PaymentsDao(super.db, this.outboxDao);
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

  /// جلب المدفوعات لتاريخ محدد
  Future<List<Payment>> listByDate(String date, {bool includeDeleted = false}) async {
    final q = select(payments);
    if (!includeDeleted) q.where((t) => t.deletedAt.isNull());
    q.where((t) => t.paymentDate.like('$date%'));
    return q.get();
  }

  Future<List<Payment>> listByHotelDayKey(
    String hotelDayKey, {
    bool includeDeleted = false,
    String? revenueType,
  }) async {
    final q = select(payments);
    if (!includeDeleted) q.where((t) => t.deletedAt.isNull());

    final startIso = Time.hotelDayStartIso(hotelDayKey);
    final endIso = Time.hotelDayEndIso(hotelDayKey);

    final byKey = payments.hotelDayKey.equals(hotelDayKey);
    final byRangeFallback = payments.hotelDayKey.isNull() &
        payments.paymentDate.isBiggerOrEqualValue(startIso) &
        payments.paymentDate.isSmallerThanValue(endIso);

    q.where((t) => byKey | byRangeFallback);

    if (revenueType != null && revenueType.isNotEmpty) {
      q.where((t) => t.revenueType.equals(revenueType));
    }

    return q.get();
  }

  Future<Payment?> getById(int id) => (select(payments)..where((t) => t.id.equals(id))).getSingleOrNull();
  Stream<Payment?> watchById(int id) => (select(payments)..where((t) => t.id.equals(id))).watchSingleOrNull();

  Future<int> insertOne(PaymentsCompanion data, {bool originIsServer = false}) async {
    return db.transaction(() async {
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
        await outboxDao.merge(
          entity: 'payments',
          op: 'create',
          localUuid: uu,
          serverId: comp.serverId.present ? comp.serverId.value : null,
          payload: _payloadFrom(comp),
          clientTs: now,
        );
      }
      return id;
    });
  }

  Future<int> updateById(int id, PaymentsCompanion data, {bool originIsServer = false}) async {
    return db.transaction(() async {
      final now = Time.nowEpoch();
      final existing = await getById(id);
      if (existing == null) return 0;
      final comp = data.copyWith(updatedAt: Value(now), lastModified: Value(now));
      final rows = await (update(payments)..where((t) => t.id.equals(id))).write(comp);
      if (rows > 0 && !originIsServer) {
        await outboxDao.merge(
          entity: 'payments',
          op: 'update',
          localUuid: existing.localUuid,
          serverId: existing.serverId,
          payload: _payloadFrom(comp, base: existing),
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
      if (existing == null) return 0;
      final rows = await (update(payments)..where((t) => t.id.equals(id))).write(PaymentsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        lastModified: Value(now),
      ));
      if (rows > 0 && !originIsServer) {
        await outboxDao.merge(
          entity: 'payments',
          op: 'delete',
          localUuid: existing.localUuid,
          serverId: existing.serverId,
          payload: {'payment_id': existing.serverPaymentId},
          clientTs: now,
        );
      }
      return rows;
    });
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
    if (comp.hotelDayKey.present) m['hotel_day_key'] = comp.hotelDayKey.value;
    if (comp.cashTransactionLocalId.present) m['cash_transaction_local_id'] = comp.cashTransactionLocalId.value;
    if (comp.cashTransactionServerId.present) m['cash_transaction_id'] = comp.cashTransactionServerId.value;
    return m;
  }

  // دوال النسخ الاحتياطي

  /// تصدير جميع المدفوعات إلى JSON
  Future<List<Map<String, dynamic>>> exportToJson() async {
    final paymentsList = await list(includeDeleted: false);
    return paymentsList.map((payment) => payment.toJson()).toList();
  }

  /// استيراد المدفوعات من JSON
  Future<void> importFromJson(List<Map<String, dynamic>> data, {bool clearExisting = false}) async {
    if (clearExisting) {
      await delete(payments).go();
    }

    for (final paymentJson in data) {
      final payment = Payment.fromJson(paymentJson);
      await into(payments).insertOnConflictUpdate(PaymentsCompanion(
        serverPaymentId: Value(payment.serverPaymentId),
        bookingLocalId: Value(payment.bookingLocalId),
        serverBookingId: Value(payment.serverBookingId),
        roomNumber: Value(payment.roomNumber),
        amount: Value(payment.amount),
        paymentDate: Value(payment.paymentDate),
        notes: Value(payment.notes),
        paymentMethod: Value(payment.paymentMethod),
        revenueType: Value(payment.revenueType),
        hotelDayKey: Value(payment.hotelDayKey),
        linkedDebtUuid: Value(payment.linkedDebtUuid),
        bookingUuidCache: Value(payment.bookingUuidCache),
        cashTransactionLocalId: Value(payment.cashTransactionLocalId),
        cashTransactionServerId: Value(payment.cashTransactionServerId),
        localUuid: Value(payment.localUuid),
        serverId: Value(payment.serverId),
        createdAt: Value(payment.createdAt),
        updatedAt: Value(payment.updatedAt),
        deletedAt: Value(payment.deletedAt),
        lastModified: Value(payment.lastModified),
        version: Value(payment.version),
        origin: Value(payment.origin),
      ));
    }
  }

  /// الحصول على عدد السجلات
  Future<int> getRecordCount() async {
    final query = selectOnly(payments)..addColumns([payments.id.count()]);
    final result = await query.getSingle();
    return result.read(payments.id.count()) ?? 0;
  }

  /// مسح جميع البيانات
  Future<void> clearAllData() async {
    await delete(payments).go();
  }
}
