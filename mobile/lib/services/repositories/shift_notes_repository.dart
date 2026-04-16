import 'package:drift/drift.dart' as d;
import '../local_db.dart' show AppDatabase, BookingNotesCompanion;
import '../daos/booking_notes_dao.dart';
import '../daos/outbox_dao.dart';
import '../../models/shift_note_adapter.dart';

/// Repository للملاحظات العامة (ملاحظات النوبات)
/// يستخدم جدول BookingNotes مع bookingId = -1 للملاحظات العامة
class ShiftNotesRepository {
  ShiftNotesRepository(this.db) : dao = BookingNotesDao(db, OutboxDao(db));

  final AppDatabase db;
  final BookingNotesDao dao;

  /// مراقبة جميع الملاحظات العامة
  Stream<List<ShiftNote>> watchAll() {
    return dao
        .list(bookingId: ShiftNoteAdapter.GENERAL_NOTES_BOOKING_ID)
        .asStream()
        .map(
          (bookingNotes) =>
              bookingNotes.map(ShiftNoteAdapter.fromBookingNote).toList(),
        );
  }

  /// جلب جميع الملاحظات العامة النشطة
  Future<List<ShiftNote>> listAllActive() async {
    final bookingNotes = await dao.list(
      bookingId: ShiftNoteAdapter.GENERAL_NOTES_BOOKING_ID,
      includeDeleted: false,
    );
    return bookingNotes
        .where((note) => note.isActive == 1)
        .map(ShiftNoteAdapter.fromBookingNote)
        .toList();
  }

  /// جلب الملاحظات غير المقروءة
  Future<List<ShiftNote>> listUnread() async {
    final bookingNotes = await dao.list(
      bookingId: ShiftNoteAdapter.GENERAL_NOTES_BOOKING_ID,
      includeDeleted: false,
    );
    return bookingNotes
        .where((note) => note.isActive == 1) // غير مقروءة = نشطة
        .map(ShiftNoteAdapter.fromBookingNote)
        .toList();
  }

  /// جلب الملاحظات عالية الأولوية
  Future<List<ShiftNote>> listHighPriority() async {
    final allNotes = await listAllActive();
    return allNotes
        .where((note) => note.priority == NotePriority.high)
        .toList();
  }

  /// إنشاء ملاحظة جديدة
  Future<int> create(ShiftNote note) async {
    final data = ShiftNoteAdapter.toBookingNoteData(note);
    return await dao.insertOne(
      BookingNotesCompanion(
        bookingId: d.Value(ShiftNoteAdapter.GENERAL_NOTES_BOOKING_ID),
        noteText: d.Value(data['note_text']),
        alertType: d.Value(data['alert_type']),
        alertUntil: data['alert_until'] != null
            ? d.Value(data['alert_until'])
            : const d.Value.absent(),
        isActive: d.Value(data['is_active']),
      ),
    );
  }

  /// تحديث ملاحظة موجودة
  Future<bool> update(ShiftNote note) async {
    final id = int.tryParse(note.id);
    if (id == null) return false;

    final data = ShiftNoteAdapter.toBookingNoteData(note);
    final rows = await dao.updateById(
      id,
      BookingNotesCompanion(
        noteText: d.Value(data['note_text']),
        alertType: d.Value(data['alert_type']),
        alertUntil: data['alert_until'] != null
            ? d.Value(data['alert_until'])
            : const d.Value.absent(),
        isActive: d.Value(data['is_active']),
      ),
    );
    return rows > 0;
  }

  /// وضع علامة مقروء على الملاحظة
  Future<bool> markAsRead(String noteId) async {
    final id = int.tryParse(noteId);
    if (id == null) return false;

    final rows = await dao.updateById(
      id,
      const BookingNotesCompanion(
        isActive: d.Value(0), // isActive = 0 تعني مقروءة
      ),
    );
    return rows > 0;
  }

  /// وضع علامة غير مقروء على الملاحظة
  Future<bool> markAsUnread(String noteId) async {
    final id = int.tryParse(noteId);
    if (id == null) return false;

    final rows = await dao.updateById(
      id,
      const BookingNotesCompanion(
        isActive: d.Value(1), // isActive = 1 تعني غير مقروءة
      ),
    );
    return rows > 0;
  }

  /// حذف ملاحظة (soft delete)
  Future<bool> delete(String noteId) async {
    final id = int.tryParse(noteId);
    if (id == null) return false;

    final rows = await dao.softDelete(id);
    return rows > 0;
  }

  /// جلب ملاحظة بالمعرف
  Future<ShiftNote?> getById(String noteId) async {
    final id = int.tryParse(noteId);
    if (id == null) return null;

    final bookingNote = await dao.getById(id);
    if (bookingNote == null ||
        bookingNote.bookingId != ShiftNoteAdapter.GENERAL_NOTES_BOOKING_ID) {
      return null;
    }

    return ShiftNoteAdapter.fromBookingNote(bookingNote);
  }

  /// عدد الملاحظات غير المقروءة
  Future<int> getUnreadCount() async {
    final unreadNotes = await listUnread();
    return unreadNotes.length;
  }

  /// عدد الملاحظات عالية الأولوية
  Future<int> getHighPriorityCount() async {
    final highPriorityNotes = await listHighPriority();
    return highPriorityNotes.length;
  }
}
