import 'package:drift/drift.dart';
import '../../utils/id.dart';
import '../../utils/time.dart';
import '../local_db.dart';
import 'outbox_dao.dart';

part 'booking_notes_dao.g.dart';

@DriftAccessor(tables: [BookingNotes])
class BookingNotesDao extends DatabaseAccessor<AppDatabase> with _$BookingNotesDaoMixin {
  BookingNotesDao(AppDatabase db, this.outboxDao) : super(db);
  final OutboxDao outboxDao;

  Future<List<BookingNote>> list({int? bookingId, bool includeDeleted = false}) async {
    final q = select(bookingNotes);
    if (!includeDeleted) q.where((t) => t.deletedAt.isNull());
    if (bookingId != null) q.where((t) => t.bookingId.equals(bookingId));
    return q.get();
  }

  Stream<List<BookingNote>> watchByBooking(int bookingId, {bool includeDeleted = false}) {
    final q = select(bookingNotes)..where((t) => t.bookingId.equals(bookingId));
    if (!includeDeleted) q.where((t) => t.deletedAt.isNull());
    return q.watch();
  }

  Future<BookingNote?> getById(int id) => (select(bookingNotes)..where((t) => t.id.equals(id))).getSingleOrNull();
  Stream<BookingNote?> watchById(int id) => (select(bookingNotes)..where((t) => t.id.equals(id))).watchSingleOrNull();

  Future<int> insertOne(BookingNotesCompanion data, {bool originIsServer = false}) async {
    final now = Time.nowEpoch();
    final uu = data.localUuid.present ? data.localUuid.value : IdGen.uuid();
    final comp = data.copyWith(
      localUuid: Value(uu),
      createdAt: Value(now),
      updatedAt: Value(now),
      lastModified: Value(now),
      origin: Value(originIsServer ? 'server' : 'local'),
    );
    final id = await into(bookingNotes).insert(comp);
    if (!originIsServer) {
      await outboxDao.merge(entity: 'booking_notes', op: 'create', localUuid: uu, serverId: comp.serverId.present ? comp.serverId.value : null, payload: _payloadFrom(comp), clientTs: now);
    }
    return id;
  }

  Future<int> updateById(int id, BookingNotesCompanion data, {bool originIsServer = false}) async {
    final now = Time.nowEpoch();
    final existing = await getById(id);
    if (existing == null) return 0;
    final comp = data.copyWith(updatedAt: Value(now), lastModified: Value(now));
    final rows = await (update(bookingNotes)..where((t) => t.id.equals(id))).write(comp);
    if (rows > 0 && !originIsServer) {
      await outboxDao.merge(entity: 'booking_notes', op: 'update', localUuid: existing.localUuid, serverId: existing.serverId, payload: _payloadFrom(comp, base: existing), clientTs: now);
    }
    return rows;
  }

  Future<int> softDelete(int id, {bool originIsServer = false}) async {
    final now = Time.nowEpoch();
    final existing = await getById(id);
    if (existing == null) return 0;
    final rows = await (update(bookingNotes)..where((t) => t.id.equals(id))).write(BookingNotesCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
      lastModified: Value(now),
    ));
    if (rows > 0 && !originIsServer) {
      await outboxDao.merge(entity: 'booking_notes', op: 'delete', localUuid: existing.localUuid, serverId: existing.serverId, payload: {'id': id}, clientTs: now);
    }
    return rows;
  }

  Map<String, dynamic> _payloadFrom(BookingNotesCompanion comp, {BookingNote? base}) {
    final m = <String, dynamic>{};
    if (comp.bookingId.present) m['booking_id'] = comp.bookingId.value;
    if (comp.noteText.present) m['note_text'] = comp.noteText.value;
    if (comp.alertType.present) m['alert_type'] = comp.alertType.value;
    if (comp.alertUntil.present) m['alert_until'] = comp.alertUntil.value;
    if (comp.isActive.present) m['is_active'] = comp.isActive.value;
    return m;
  }
}
