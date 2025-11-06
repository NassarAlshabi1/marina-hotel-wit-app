import 'package:drift/drift.dart' as d;
import '../local_db.dart';
import '../auto_backup_manager.dart';
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
  }) async {
    final noteId = await dao.insertOne(
      BookingNotesCompanion(
        bookingId: d.Value(bookingId),
        noteText: d.Value(noteText),
        alertType: d.Value(alertType),
        alertUntil: alertUntil != null ? d.Value(alertUntil) : const d.Value.absent(),
        isActive: d.Value(isActive ? 1 : 0),
      ),
    );

    // تسجيل التغيير للنسخ التلقائي
    AutoBackupManager.instance.onDataChange(
      'booking_notes',
      'CREATE',
      recordData: {
        'id': noteId,
        'booking_id': bookingId,
        'alert_type': alertType,
      },
    );

    return noteId;
  }

  Future<int> update(int id, {
    String? noteText,
    String? alertType,
    String? alertUntil,
    bool? isActive,
  }) async {
    final updatedRows = await dao.updateById(
      id,
      BookingNotesCompanion(
        noteText: noteText != null ? d.Value(noteText) : const d.Value.absent(),
        alertType: alertType != null ? d.Value(alertType) : const d.Value.absent(),
        alertUntil: alertUntil != null ? d.Value(alertUntil) : const d.Value.absent(),
        isActive: isActive != null ? d.Value(isActive ? 1 : 0) : const d.Value.absent(),
      ),
    );

    if (updatedRows > 0) {
      // تسجيل التغيير للنسخ التلقائي
      AutoBackupManager.instance.onDataChange(
        'booking_notes',
        'UPDATE',
        recordData: {
          'id': id,
          'alert_type': alertType,
          'is_active': isActive,
        },
      );
    }

    return updatedRows;
  }

  Future<int> delete(int id) async {
    // الحصول على بيانات الملاحظة قبل الحذف
    final note = await (db.select(db.bookingNotes)..where((n) => n.id.equals(id))).getSingleOrNull();
    
    final deletedRows = await dao.softDelete(id);

    if (deletedRows > 0 && note != null) {
      // تسجيل التغيير للنسخ التلقائي
      AutoBackupManager.instance.onDataChange(
        'booking_notes',
        'DELETE',
        recordData: {
          'id': id,
          'booking_id': note.bookingId,
          'alert_type': note.alertType,
        },
      );
    }

    return deletedRows;
  }

  // دوال النسخ الاحتياطي

  /// تصدير بيانات الملاحظات
  Future<Map<String, dynamic>> exportData() async {
    final notesData = await dao.exportToJson();
    final recordCount = await dao.getRecordCount();
    
    return {
      'data': notesData,
      'count': recordCount,
      'entity': 'booking_notes',
    };
  }

  /// استيراد بيانات الملاحظات
  Future<void> importData(Map<String, dynamic> data) async {
    if (data.containsKey('data') && data['data'] is List) {
      await dao.importFromJson(
        List<Map<String, dynamic>>.from(data['data']), 
        clearExisting: false,
      );
    }
  }

  /// مسح جميع البيانات
  Future<void> clearAllData() async {
    await dao.clearAllData();
  }

  /// الحصول على إجمالي عدد السجلات
  Future<int> getRecordCount() async {
    return await dao.getRecordCount();
  }
}
