import 'package:drift/drift.dart';
import '../../utils/id.dart';
import '../../utils/time.dart';
import '../local_db.dart';
import '../sync_core/optimistic_lock_helper.dart';
import 'outbox_dao.dart';

part 'bookings_dao.g.dart';

@DriftAccessor(tables: [Bookings])
class BookingsDao extends DatabaseAccessor<AppDatabase>
    with _$BookingsDaoMixin, OptimisticLockDaoMixin<Bookings, Booking> {
  BookingsDao(super.db, this.outboxDao);
  final OutboxDao outboxDao;

  Future<List<Booking>> list({
    String? search,
    String? roomNumber,
    String? status,
    String? from,
    String? to,
    bool includeDeleted = false,
    int? limit,
    int? offset,
  }) async {
    final q = select(bookings);
    if (!includeDeleted) q.where((t) => t.deletedAt.isNull());
    if (roomNumber != null && roomNumber.isNotEmpty) {
      q.where((t) => t.roomNumber.equals(roomNumber));
    }
    if (status != null && status.isNotEmpty) {
      q.where((t) => t.status.equals(status));
    }
    if (from != null && to != null) {
      q.where(
        (t) =>
            t.checkinDate.isBiggerOrEqualValue(from) &
            t.checkinDate.isSmallerOrEqualValue(to),
      );
    }
    if (search != null && search.trim().isNotEmpty) {
      final s = '%${search.trim()}%';
      q.where((t) => t.guestName.like(s) | t.guestPhone.like(s));
    }
    q.orderBy([
      (t) => OrderingTerm(expression: t.checkinDate, mode: OrderingMode.desc),
    ]);
    if (limit != null) q.limit(limit, offset: offset ?? 0);
    return q.get();
  }

  Stream<List<Booking>> watchList({
    String? roomNumber,
    String? status,
    bool includeDeleted = false,
  }) {
    final q = select(bookings);
    if (!includeDeleted) q.where((t) => t.deletedAt.isNull());
    if (roomNumber != null && roomNumber.isNotEmpty) {
      q.where((t) => t.roomNumber.equals(roomNumber));
    }
    if (status != null && status.isNotEmpty) {
      q.where((t) => t.status.equals(status));
    }
    q.orderBy([
      (t) => OrderingTerm(expression: t.checkinDate, mode: OrderingMode.desc),
    ]);
    return q.watch();
  }

  Future<Booking?> getById(int id) =>
      (select(bookings)..where((t) => t.id.equals(id))).getSingleOrNull();
  Stream<Booking?> watchById(int id) =>
      (select(bookings)..where((t) => t.id.equals(id))).watchSingleOrNull();

  Future<int> insertOne(
    BookingsCompanion data, {
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
      );
      final id = await into(bookings).insert(comp);
      if (!originIsServer) {
        await outboxDao.merge(
          entity: 'bookings',
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

  Future<int> updateById(
    int id,
    BookingsCompanion data, {
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
        bookings,
      )..where((t) => t.id.equals(id))).write(comp);
      if (rows > 0 && !originIsServer) {
        await outboxDao.merge(
          entity: 'bookings',
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
      final rows = await (update(bookings)..where((t) => t.id.equals(id)))
          .write(
            BookingsCompanion(
              deletedAt: Value(now),
              updatedAt: Value(now),
              lastModified: Value(now),
            ),
          );
      if (rows > 0 && !originIsServer) {
        await outboxDao.merge(
          entity: 'bookings',
          op: 'delete',
          localUuid: existing.localUuid,
          serverId: existing.serverId,
          payload: {'booking_id': existing.serverBookingId},
          clientTs: now,
        );
      }
      return rows;
    });
  }

  Future<int> deleteById(int id, {bool originIsServer = false}) =>
      softDelete(id, originIsServer: originIsServer);

  Future<List<Booking>> getAll({bool includeDeleted = false}) {
    final query = select(bookings);
    if (!includeDeleted) {
      query.where((t) => t.deletedAt.isNull());
    }
    return query.get();
  }

  Future<List<Booking>> getByRoomNumber(
    String roomNumber, {
    bool includeDeleted = false,
  }) {
    final query = select(bookings)
      ..where((t) => t.roomNumber.equals(roomNumber));
    if (!includeDeleted) {
      query.where((t) => t.deletedAt.isNull());
    }
    return query.get();
  }

  Future<List<Booking>> getByStatus(
    String status, {
    bool includeDeleted = false,
  }) {
    final query = select(bookings)..where((t) => t.status.equals(status));
    if (!includeDeleted) {
      query.where((t) => t.deletedAt.isNull());
    }
    return query.get();
  }

  Map<String, dynamic> _payloadFrom(BookingsCompanion comp, {Booking? base}) {
    final m = <String, dynamic>{};
    if (comp.serverBookingId.present) {
      m['booking_id'] = comp.serverBookingId.value;
    }
    if (comp.roomNumber.present) m['room_number'] = comp.roomNumber.value;
    if (comp.guestName.present) m['guest_name'] = comp.guestName.value;
    if (comp.guestPhone.present) m['guest_phone'] = comp.guestPhone.value;
    if (comp.guestIdType.present) m['guest_id_type'] = comp.guestIdType.value;
    if (comp.guestIdNumber.present) {
      m['guest_id_number'] = comp.guestIdNumber.value;
    }
    if (comp.guestIdIssueDate.present) {
      m['guest_id_issue_date'] = comp.guestIdIssueDate.value;
    }
    if (comp.guestIdIssuePlace.present) {
      m['guest_id_issue_place'] = comp.guestIdIssuePlace.value;
    }
    if (comp.guestNationality.present) {
      m['guest_nationality'] = comp.guestNationality.value;
    }
    if (comp.guestEmail.present) m['guest_email'] = comp.guestEmail.value;
    if (comp.guestAddress.present) m['guest_address'] = comp.guestAddress.value;
    if (comp.checkinDate.present) m['checkin_date'] = comp.checkinDate.value;
    if (comp.checkoutDate.present) m['checkout_date'] = comp.checkoutDate.value;
    if (comp.actualCheckout.present) {
      m['actual_checkout'] = comp.actualCheckout.value;
    }
    if (comp.status.present) m['status'] = comp.status.value;
    if (comp.notes.present) m['notes'] = comp.notes.value;
    if (comp.expectedNights.present) {
      m['expected_nights'] = comp.expectedNights.value;
    }
    if (comp.calculatedNights.present) {
      m['calculated_nights'] = comp.calculatedNights.value;
    }
    return m;
  }

  // دوال النسخ الاحتياطي

  /// تصدير جميع الحجوزات إلى JSON
  Future<List<Map<String, dynamic>>> exportToJson() async {
    final bookingsList = await list(includeDeleted: false);
    return bookingsList.map((booking) => booking.toJson()).toList();
  }

  /// استيراد الحجوزات من JSON
  Future<void> importFromJson(
    List<Map<String, dynamic>> data, {
    bool clearExisting = false,
  }) async {
    if (clearExisting) {
      await delete(bookings).go();
    }

    for (final bookingJson in data) {
      final booking = Booking.fromJson(bookingJson);
      await into(bookings).insertOnConflictUpdate(
        BookingsCompanion(
          id: Value(booking.id),
          serverBookingId: Value(booking.serverBookingId),
          roomNumber: Value(booking.roomNumber),
          guestName: Value(booking.guestName),
          guestPhone: Value(booking.guestPhone),
          guestIdType: Value(booking.guestIdType),
          guestIdNumber: Value(booking.guestIdNumber),
          guestIdIssueDate: Value(booking.guestIdIssueDate),
          guestIdIssuePlace: Value(booking.guestIdIssuePlace),
          guestNationality: Value(booking.guestNationality),
          guestEmail: Value(booking.guestEmail),
          guestAddress: Value(booking.guestAddress),
          checkinDate: Value(booking.checkinDate),
          checkoutDate: Value(booking.checkoutDate),
          actualCheckout: Value(booking.actualCheckout),
          status: Value(booking.status),
          notes: Value(booking.notes),
          expectedNights: Value(booking.expectedNights),
          calculatedNights: Value(booking.calculatedNights),
          localUuid: Value(booking.localUuid),
          serverId: Value(booking.serverId),
          createdAt: Value(booking.createdAt),
          updatedAt: Value(booking.updatedAt),
          deletedAt: Value(booking.deletedAt),
          lastModified: Value(booking.lastModified),
          version: Value(booking.version),
          origin: Value(booking.origin),
        ),
      );
    }
  }

  /// الحصول على عدد السجلات
  Future<int> getRecordCount() async {
    final query = selectOnly(bookings)..addColumns([bookings.id.count()]);
    final result = await query.getSingle();
    return result.read(bookings.id.count()) ?? 0;
  }

  /// مسح جميع البيانات
  Future<void> clearAllData() async {
    await delete(bookings).go();
  }

  @override
  TableInfo<Bookings, Booking> get optimisticTable => bookings;

  @override
  String get optimisticTableName => 'bookings';

  @override
  GeneratedColumn<String> get optimisticLocalUuid => bookings.localUuid;

  @override
  GeneratedColumn<int> get optimisticVersion => bookings.version;
}
