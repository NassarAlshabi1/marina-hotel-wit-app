import 'package:drift/drift.dart';
import '../../utils/id.dart';
import '../../utils/time.dart';
import '../local_db.dart';
import '../sync_core/optimistic_lock_helper.dart';
import 'outbox_dao.dart';
import '../sync_guardian.dart';
import '../adapters/adapter_registry.dart';
import '../adapters/source.dart';

part 'payments_dao.g.dart';

@DriftAccessor(tables: [Payments])
class PaymentsDao extends DatabaseAccessor<AppDatabase>
    with _$PaymentsDaoMixin, OptimisticLockDaoMixin<Payments, Payment> {
  PaymentsDao(super.db, this.outboxDao) : adapters = AdapterRegistry(db);
  final OutboxDao outboxDao;
  final AdapterRegistry adapters;

  Future<List<Payment>> list({
    int? bookingLocalId,
    String? from,
    String? to,
    String? revenueType,
    bool includeDeleted = false,
  }) async {
    final q = select(payments);
    if (!includeDeleted) q.where((t) => t.deletedAt.isNull());
    if (bookingLocalId != null) {
      q.where((t) => t.bookingLocalId.equals(bookingLocalId));
    }
    if (revenueType != null && revenueType.isNotEmpty) {
      q.where((t) => t.revenueType.equals(revenueType));
    }
    if (from != null && to != null) {
      q.where(
        (t) =>
            t.paymentDate.isBiggerOrEqualValue(from) &
            t.paymentDate.isSmallerOrEqualValue(to),
      );
    }
    q.orderBy([
      (t) => OrderingTerm(expression: t.paymentDate, mode: OrderingMode.desc),
    ]);
    return q.get();
  }

  Future<List<Payment>> listForReport({
    String? from,
    String? to,
    String? roomNumber,
    bool includeDeleted = false,
  }) async {
    final q = select(payments);
    if (!includeDeleted) q.where((t) => t.deletedAt.isNull());

    if (from != null && to != null) {
      q.where(
        (t) =>
            t.paymentDate.isBiggerOrEqualValue(from) &
            t.paymentDate.isSmallerOrEqualValue(to),
      );
    }

    if (roomNumber != null && roomNumber.isNotEmpty) {
      q.where((t) => t.roomNumber.equals(roomNumber));
    }

    q.orderBy([
      (t) => OrderingTerm(expression: t.paymentDate, mode: OrderingMode.desc),
    ]);
    return q.get();
  }

  Stream<List<Payment>> watchList({
    int? bookingLocalId,
    bool includeDeleted = false,
  }) {
    final q = select(payments);
    if (!includeDeleted) q.where((t) => t.deletedAt.isNull());
    if (bookingLocalId != null) {
      q.where((t) => t.bookingLocalId.equals(bookingLocalId));
    }
    return q.watch();
  }

  /// جلب المدفوعات لتاريخ محدد
  Future<List<Payment>> listByDate(
    String date, {
    bool includeDeleted = false,
  }) async {
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

  Future<Payment?> getById(int id) =>
      (select(payments)..where((t) => t.id.equals(id))).getSingleOrNull();
  Stream<Payment?> watchById(int id) =>
      (select(payments)..where((t) => t.id.equals(id))).watchSingleOrNull();

  Future<int> insertOne(
    PaymentsCompanion data, {
    bool originIsServer = false,
  }) async {
    return db.transaction(() async {
      final now = Time.nowEpoch();
      final uu = data.localUuid.present ? data.localUuid.value : IdGen.uuid();
      final comp = data.copyWith(
        localUuid: Value(uu),
        createdAt: Value(now),
        updatedAt: Value(now),
        lastModified: Value(now),
        origin: Value(originIsServer ? 'server' : 'local'),
        serverId: data.serverPaymentId.present
            ? Value(data.serverPaymentId.value)
            : const Value.absent(),
      );
      final id = await into(payments).insert(comp);
      if (!originIsServer) {
        await _mergeOutbox(
          op: 'create',
          localUuid: uu,
          serverId: comp.serverId.present ? comp.serverId.value : null,
          clientTs: now,
        );
        SyncGuardian.instance
            .notifyLocalChange(table: 'payments', operation: 'create');
      }
      return id;
    });
  }

  Future<int> updateById(
    int id,
    PaymentsCompanion data, {
    bool originIsServer = false,
  }) async {
    return db.transaction(() async {
      final now = Time.nowEpoch();
      final existing = await getById(id);
      if (existing == null) return 0;
      final comp = data.copyWith(
        updatedAt: Value(now),
        lastModified: Value(now),
      );
      final rows = await (update(
        payments,
      )..where((t) => t.id.equals(id)))
          .write(comp);
      if (rows > 0 && !originIsServer) {
        await _mergeOutbox(
          op: 'update',
          localUuid: existing.localUuid,
          serverId: existing.serverId,
          clientTs: now,
        );
        SyncGuardian.instance
            .notifyLocalChange(table: 'payments', operation: 'update');
      }
      return rows;
    });
  }

  Future<int> softDelete(int id, {bool originIsServer = false}) async {
    return db.transaction(() async {
      final now = Time.nowEpoch();
      final existing = await getById(id);
      if (existing == null) return 0;
      final rows =
          await (update(payments)..where((t) => t.id.equals(id))).write(
        PaymentsCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
          lastModified: Value(now),
        ),
      );
      if (rows > 0 && !originIsServer) {
        await _mergeOutbox(
          op: 'delete',
          localUuid: existing.localUuid,
          serverId: existing.serverId,
          clientTs: now,
        );
        SyncGuardian.instance
            .notifyLocalChange(table: 'payments', operation: 'delete');
      }
      return rows;
    });
  }

  Future<Map<String, dynamic>?> _payloadForLocalUuid(String localUuid) async {
    final row = await (select(payments)
          ..where((t) => t.localUuid.equals(localUuid))
          ..limit(1))
        .getSingleOrNull();
    if (row == null) return null;
    return adapters.payments.toJsonForSource(row, src: Source.appwrite);
  }

  Future<void> _mergeOutbox({
    required String op,
    required String localUuid,
    required int clientTs,
    int? serverId,
  }) async {
    final payload = await _payloadForLocalUuid(localUuid);
    if (payload == null) return;
    await outboxDao.merge(
      entity: 'payments',
      op: op,
      localUuid: localUuid,
      serverId: serverId,
      payload: payload,
      clientTs: clientTs,
    );
  }

  // دوال النسخ الاحتياطي

  /// تصدير جميع المدفوعات إلى JSON
  Future<List<Map<String, dynamic>>> exportToJson() async {
    final paymentsList = await list(includeDeleted: false);
    return paymentsList.map((payment) => payment.toJson()).toList();
  }

  /// استيراد المدفوعات من JSON
  Future<void> importFromJson(
    List<Map<String, dynamic>> data, {
    bool clearExisting = false,
  }) async {
    if (clearExisting) {
      await delete(payments).go();
    }

    for (final paymentJson in data) {
      final payment = Payment.fromJson(paymentJson);
      await into(payments).insertOnConflictUpdate(
        PaymentsCompanion(
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
        ),
      );
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

  @override
  TableInfo<Payments, Payment> get optimisticTable => payments;

  @override
  String get optimisticTableName => 'payments';

  @override
  GeneratedColumn<String> get optimisticLocalUuid => payments.localUuid;

  @override
  GeneratedColumn<int> get optimisticVersion => payments.version;
}
