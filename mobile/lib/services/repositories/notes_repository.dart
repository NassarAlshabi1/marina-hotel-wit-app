import 'package:drift/drift.dart' as d;
import '../local_db.dart';
import '../daos/outbox_dao.dart';
import '../daos/booking_notes_dao.dart';

class NotesRepository {
  NotesRepository(this.db)
      : outbox = OutboxDao(db),
        dao = BookingNotesDao(db, OutboxDao(db));
  final AppDatabase db;
  final OutboxDao outbox;
  final BookingNotesDao dao;

  Stream<List<BookingNote>> watchByBooking(int bookingId) => dao.watchByBooking(bookingId);
  Future<List<BookingNote>> listAllActive() => dao.list();

  Future<int> create({
    required int bookingId,
    required String noteText,
    required String alertType,
    String? alertUntil,
    bool isActive = true,
  }) {
    return dao.insertOne(
      BookingNotesCompanion(
        bookingId: d.Value(bookingId),
        noteText: d.Value(noteText),
        alertType: d.Value(alertType),
        alertUntil: alertUntil != null ? d.Value(alertUntil) : const d.Value.absent(),
        isActive: d.Value(isActive ? 1 : 0),
      ),
    );
  }

  Future<int> update(int id, {
    String? noteText,
    String? alertType,
    String? alertUntil,
    bool? isActive,
  }) {
    return dao.updateById(
      id,
      BookingNotesCompanion(
        noteText: noteText != null ? d.Value(noteText) : const d.Value.absent(),
        alertType: alertType != null ? d.Value(alertType) : const d.Value.absent(),
        alertUntil: alertUntil != null ? d.Value(alertUntil) : const d.Value.absent(),
        isActive: isActive != null ? d.Value(isActive ? 1 : 0) : const d.Value.absent(),
      ),
    );
  }

  Future<int> delete(int id) => dao.softDelete(id);
}
