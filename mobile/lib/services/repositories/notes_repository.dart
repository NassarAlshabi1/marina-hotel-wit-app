import 'package:drift/drift.dart' as d;
import '../drive_backup_service.dart';
import '../local_db.dart';
import '../daos/outbox_dao.dart';
import '../daos/booking_notes_dao.dart';

class NotesRepository {
  NotesRepository(this.db, this.backupService)
      : outbox = OutboxDao(db),
        dao = BookingNotesDao(db, OutboxDao(db));
  final AppDatabase db;
  final GoogleDriveBackupService backupService;
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
  }) async {
    final id = await dao.insertOne(
      BookingNotesCompanion(
        bookingId: d.Value(bookingId),
        noteText: d.Value(noteText),
        alertType: d.Value(alertType),
        alertUntil: alertUntil != null ? d.Value(alertUntil) : const d.Value.absent(),
        isActive: d.Value(isActive ? 1 : 0),
      ),
    );
    backupService.scheduleAutoBackup('notes-create');
    return id;
  }

  Future<int> update(int id, {
    String? noteText,
    String? alertType,
    String? alertUntil,
    bool? isActive,
  }) async {
    final affected = await dao.updateById(
      id,
      BookingNotesCompanion(
        noteText: noteText != null ? d.Value(noteText) : const d.Value.absent(),
        alertType: alertType != null ? d.Value(alertType) : const d.Value.absent(),
        alertUntil: alertUntil != null ? d.Value(alertUntil) : const d.Value.absent(),
        isActive: isActive != null ? d.Value(isActive ? 1 : 0) : const d.Value.absent(),
      ),
    );
    if (affected > 0) {
      backupService.scheduleAutoBackup('notes-update');
    }
    return affected;
  }

  Future<int> delete(int id) async {
    final affected = await dao.softDelete(id);
    if (affected > 0) {
      backupService.scheduleAutoBackup('notes-delete');
    }
    return affected;
  }
}
