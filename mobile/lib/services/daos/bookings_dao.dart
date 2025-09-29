import 'package:drift/drift.dart';
import '../../utils/id.dart';
import '../../utils/time.dart';
import '../local_db.dart';
import 'outbox_dao.dart';

part 'bookings_dao.g.dart';

@DriftAccessor(tables: [Bookings])
class BookingsDao extends DatabaseAccessor<AppDatabase> with _$BookingsDaoMixin {
  BookingsDao(AppDatabase db, this.outboxDao) : super(db);
  final OutboxDao outboxDao;

  Future<List<Booking>> list({String? search, String? roomNumber, String? status, String? from, String? to, bool includeDeleted = false, int? limit, int? offset}) async {
    final q = select(bookings);
    if (!includeDeleted) q.where((t) => t.deletedAt.isNull());
    if (roomNumber != null && roomNumber.isNotEmpty) q.where((t) => t.roomNumber.equals(roomNumber));
    if (status != null && status.isNotEmpty) q.where((t) => t.status.equals(status));
    if (from != null && to != null) q.where((t) => t.checkinDate.isBiggerOrEqualValue(from) & t.checkinDate.isSmallerOrEqualValue(to));
    if (search != null && search.trim().isNotEmpty) {
      final s = '%${search.trim()}%';
      q.where((t) => t.guestName.like(s) | t.guestPhone.like(s));
    }
    q.orderBy([(t) => OrderingTerm(expression: t.checkinDate, mode: OrderingMode.desc)]);
    if (limit != null) q.limit(limit, offset: offset ?? 0);
    return q.get();
  }

  Stream<List<Booking>> watchList({String? roomNumber, String? status, bool includeDeleted = false}) {
    final q = select(bookings);
    if (!includeDeleted) q.where((t) => t.deletedAt.isNull());
    if (roomNumber != null && roomNumber.isNotEmpty) q.where((t) => t.roomNumber.equals(roomNumber));
    if (status != null && status.isNotEmpty) q.where((t) => t.status.equals(status));
    q.orderBy([(t) => OrderingTerm(expression: t.checkinDate, mode: OrderingMode.desc)]);
    return q.watch();
  }

  Future<Booking?> getById(int id) => (select(bookings)..where((t) => t.id.equals(id))).getSingleOrNull();
  Stream<Booking?> watchById(int id) => (select(bookings)..where((t) => t.id.equals(id))).watchSingleOrNull();

  Future<int> insertOne(BookingsCompanion data, {bool originIsServer = false}) async {
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
      await outboxDao.merge(entity: 'bookings', op: 'create', localUuid: uu, serverId: comp.serverId.present ? comp.serverId.value : null, payload: _payloadFrom(comp), clientTs: now);
    }
    return id;
  }

  Future<int> updateById(int id, BookingsCompanion data, {bool originIsServer = false}) async {
    final now = Time.nowEpoch();
    final existing = await getById(id);
    if (existing == null) return 0;
    final comp = data.copyWith(updatedAt: Value(now), lastModified: Value(now));
    final rows = await (update(bookings)..where((t) => t.id.equals(id))).write(comp);
    if (rows > 0 && !originIsServer) {
      await outboxDao.merge(entity: 'bookings', op: 'update', localUuid: existing.localUuid, serverId: existing.serverId, payload: _payloadFrom(comp, base: existing), clientTs: now);
    }
    return rows;
  }

  Future<int> softDelete(int id, {bool originIsServer = false}) async {
    final now = Time.nowEpoch();
    final existing = await getById(id);
    if (existing == null) return 0;
    final rows = await (update(bookings)..where((t) => t.id.equals(id))).write(BookingsCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
      lastModified: Value(now),
    ));
    if (rows > 0 && !originIsServer) {
      await outboxDao.merge(entity: 'bookings', op: 'delete', localUuid: existing.localUuid, serverId: existing.serverId, payload: {'booking_id': existing.serverBookingId}, clientTs: now);
    }
    return rows;
  }

  Map<String, dynamic> _payloadFrom(BookingsCompanion comp, {Booking? base}) {
    final m = <String, dynamic>{};
    if (comp.serverBookingId.present) m['booking_id'] = comp.serverBookingId.value;
    if (comp.roomNumber.present) m['room_number'] = comp.roomNumber.value;
    if (comp.guestName.present) m['guest_name'] = comp.guestName.value;
    if (comp.guestPhone.present) m['guest_phone'] = comp.guestPhone.value;
    if (comp.guestNationality.present) m['guest_nationality'] = comp.guestNationality.value;
    if (comp.guestEmail.present) m['guest_email'] = comp.guestEmail.value;
    if (comp.guestAddress.present) m['guest_address'] = comp.guestAddress.value;
    if (comp.checkinDate.present) m['checkin_date'] = comp.checkinDate.value;
    if (comp.checkoutDate.present) m['checkout_date'] = comp.checkoutDate.value;
    if (comp.status.present) m['status'] = comp.status.value;
    if (comp.notes.present) m['notes'] = comp.notes.value;
    if (comp.calculatedNights.present) m['calculated_nights'] = comp.calculatedNights.value;
    return m;
  }
}
