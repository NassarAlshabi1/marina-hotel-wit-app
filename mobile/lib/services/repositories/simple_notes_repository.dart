import '../local_db.dart';
import '../daos/shift_notes_dao.dart';
import '../firestore_shift_notes_service.dart';

class SimpleNotesRepository {
  SimpleNotesRepository(
    this.db, {
    FirestoreShiftNotesService? remoteSync,
  })  : dao = ShiftNotesDao(db),
        _remoteSync = remoteSync;
  
  final AppDatabase db;
  final ShiftNotesDao dao;
  final FirestoreShiftNotesService? _remoteSync;

  // جلب جميع الملاحظات
  Future<List<ShiftNote>> getAllNotes() => dao.getAllNotes();

  // جلب الملاحظات غير المقروءة
  Future<List<ShiftNote>> getUnreadNotes() => dao.getUnreadNotes();

  // جلب الملاحظات عالية الأولوية
  Future<List<ShiftNote>> getHighPriorityNotes() => dao.getHighPriorityNotes();

  // إضافة ملاحظة جديدة
  Future<int> addNote({
    required String title,
    required String content,
    String priority = 'medium',
    String shiftType = 'all',
    DateTime? expiresAt,
  }) async {
    final id = await dao.addNote(
      title: title,
      content: content,
      priority: priority,
      shiftType: shiftType,
      expiresAt: expiresAt?.toIso8601String(),
    );

    final note = await dao.getNoteById(id);
    if (note != null) {
      await _remoteSync?.upsertNote(note);
    }

    return id;
  }

  // تحديث ملاحظة
  Future<bool> updateNote(int id, {
    String? title,
    String? content,
    String? priority,
    String? shiftType,
    DateTime? expiresAt,
  }) async {
    final updated = await dao.updateNote(
      id,
      title: title,
      content: content,
      priority: priority,
      shiftType: shiftType,
      expiresAt: expiresAt?.toIso8601String(),
    );

    if (updated) {
      final note = await dao.getNoteById(id);
      if (note != null) {
        await _remoteSync?.upsertNote(note);
      }
    }

    return updated;
  }

  // وضع علامة مقروء/غير مقروء
  Future<bool> markAsRead(int id) async {
    final updated = await dao.markAsRead(id);
    if (updated) {
      final note = await dao.getNoteById(id);
      if (note != null) {
        await _remoteSync?.upsertNote(note);
      }
    }
    return updated;
  }

  Future<bool> markAsUnread(int id) async {
    final updated = await dao.markAsUnread(id);
    if (updated) {
      final note = await dao.getNoteById(id);
      if (note != null) {
        await _remoteSync?.upsertNote(note);
      }
    }
    return updated;
  }

  // حذف ملاحظة
  Future<bool> deleteNote(int id) async {
    final deleted = await dao.deleteNote(id);
    if (deleted) {
      await _remoteSync?.deleteNote(id);
    }
    return deleted;
  }

  // عدد الملاحظات غير المقروءة
  Future<int> getUnreadCount() => dao.getUnreadCount();

  // مراقبة التغييرات
  Stream<List<ShiftNote>> watchAllNotes() => dao.watchAllNotes();
  Stream<int> watchUnreadCount() => dao.watchUnreadCount();
  Stream<List<ShiftNote>> watchUnreadNotes() => dao.watchUnreadNotes();
  Stream<List<ShiftNote>> watchHighPriorityNotes() => dao.watchHighPriorityNotes();
}