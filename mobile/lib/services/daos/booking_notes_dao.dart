import 'package:drift/drift.dart';
import '../../utils/id.dart';
import '../../utils/time.dart';
import '../local_db.dart';
import 'outbox_dao.dart';

part 'booking_notes_dao.g.dart';

@DriftAccessor(tables: [BookingNotes])
class BookingNotesDao extends DatabaseAccessor<AppDatabase>
    with _$BookingNotesDaoMixin {
  BookingNotesDao(super.db, this.outboxDao);
  final OutboxDao outboxDao;

  Future<List<BookingNote>> list({
    int? bookingId,
    bool includeDeleted = false,
  }) async {
    final q = select(bookingNotes);
    if (!includeDeleted) {
      q.where((t) => t.deletedAt.isNull());
    }
    if (bookingId != null) {
      q.where((t) => t.bookingId.equals(bookingId));
    }
    return q.get();
  }

  Stream<List<BookingNote>> watchByBooking(
    int bookingId, {
    bool includeDeleted = false,
  }) {
    final q = select(bookingNotes)..where((t) => t.bookingId.equals(bookingId));
    if (!includeDeleted) {
      q.where((t) => t.deletedAt.isNull());
    }
    return q.watch();
  }

  Future<BookingNote?> getById(int id) =>
      (select(bookingNotes)..where((t) => t.id.equals(id))).getSingleOrNull();
  Stream<BookingNote?> watchById(int id) =>
      (select(bookingNotes)..where((t) => t.id.equals(id))).watchSingleOrNull();

  Future<int> insertOne(
    BookingNotesCompanion data, {
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
      final id = await into(bookingNotes).insert(comp);
      if (!originIsServer) {
        await outboxDao.merge(
          entity: 'booking_notes',
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
    BookingNotesCompanion data, {
    bool originIsServer = false,
  }) async {
    return db.transaction(() async {
      final now = Time.nowEpoch();
      final existing = await getById(id);
      if (existing == null) {
        return 0;
      }
      // ✅ إصلاح: عند originIsServer=true، نستخدم lastModified من البيانات الواردة
      // بدلاً من تعيين now، لمنع إعادة رفع البيانات المسحوبة من السيرفر
      final effectiveLastModified =
          originIsServer && data.lastModified.present
              ? data.lastModified
              : Value(now);
      final comp = data.copyWith(
        updatedAt: Value(now),
        lastModified: effectiveLastModified,
        version: Value(existing.version + 1),
      );
      final rows = await (update(
        bookingNotes,
      )..where((t) => t.id.equals(id))).write(comp);
      if (rows > 0 && !originIsServer) {
        await outboxDao.merge(
          entity: 'booking_notes',
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
      if (existing == null) {
        return 0;
      }
      final rows = await (update(bookingNotes)..where((t) => t.id.equals(id)))
          .write(
            BookingNotesCompanion(
              deletedAt: Value(now),
              updatedAt: Value(now),
              lastModified: Value(now),
            ),
          );
      if (rows > 0 && !originIsServer) {
        // ✅ نستخدم 'update' بدلاً من 'delete' لأن softDelete يحدّث deletedAt
        // ولا يحذف المستند من Appwrite — الجهاز الآخر يحتاج رؤية deletedAt
        await outboxDao.merge(
          entity: 'booking_notes',
          op: 'update',
          localUuid: existing.localUuid,
          serverId: existing.serverId,
          payload: {'id': id},
          clientTs: now,
        );
      }
      return rows;
    });
  }

  Map<String, dynamic> _payloadFrom(
    BookingNotesCompanion comp, {
    BookingNote? base,
  }) {
    final m = <String, dynamic>{};
    if (comp.bookingId.present) {
      m['booking_id'] = comp.bookingId.value;
    }
    if (comp.noteText.present) {
      m['note_text'] = comp.noteText.value;
    }
    if (comp.alertType.present) {
      m['alert_type'] = comp.alertType.value;
    }
    if (comp.alertUntil.present) {
      m['alert_until'] = comp.alertUntil.value;
    }
    if (comp.isActive.present) {
      m['is_active'] = comp.isActive.value;
    }
    return m;
  }

  // دوال النسخ الاحتياطي

  /// تصدير جميع ملاحظات الحجوزات إلى JSON
  Future<List<Map<String, dynamic>>> exportToJson() async {
    final notesList = await list();
    return notesList.map((note) => note.toJson()).toList();
  }

  /// استيراد ملاحظات الحجوزات من JSON
  Future<void> importFromJson(
    List<Map<String, dynamic>> data, {
    bool clearExisting = false,
  }) async {
    if (clearExisting) {
      await delete(bookingNotes).go();
    }

    for (final noteJson in data) {
      final note = BookingNote.fromJson(noteJson);
      await into(bookingNotes).insertOnConflictUpdate(
        BookingNotesCompanion(
          bookingId: Value(note.bookingId),
          noteText: Value(note.noteText),
          alertType: Value(note.alertType),
          alertUntil: Value(note.alertUntil),
          isActive: Value(note.isActive),
          localUuid: Value(note.localUuid),
          serverId: Value(note.serverId),
          createdAt: Value(note.createdAt),
          updatedAt: Value(note.updatedAt),
          deletedAt: Value(note.deletedAt),
          lastModified: Value(note.lastModified),
          version: Value(note.version),
          origin: Value(note.origin),
        ),
      );
    }
  }

  /// الحصول على عدد السجلات
  Future<int> getRecordCount() async {
    final query = selectOnly(bookingNotes)
      ..addColumns([bookingNotes.id.count()]);
    final result = await query.getSingle();
    return result.read(bookingNotes.id.count()) ?? 0;
  }

  /// مسح جميع البيانات
  Future<void> clearAllData() async {
    await delete(bookingNotes).go();
  }
}
