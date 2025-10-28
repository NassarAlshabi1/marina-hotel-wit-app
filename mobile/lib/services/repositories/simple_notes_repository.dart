import '../local_db.dart';
import '../daos/shift_notes_dao.dart';

class SimpleNotesRepository {
  SimpleNotesRepository(this.db) : dao = ShiftNotesDao(db);
  
  final AppDatabase db;
  final ShiftNotesDao dao;

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
  }) {
    return dao.addNote(
      title: title,
      content: content,
      priority: priority,
      shiftType: shiftType,
      expiresAt: expiresAt?.toIso8601String(),
    );
  }

  // تحديث ملاحظة
  Future<bool> updateNote(int id, {
    String? title,
    String? content,
    String? priority,
    String? shiftType,
    DateTime? expiresAt,
  }) {
    return dao.updateNote(
      id,
      title: title,
      content: content,
      priority: priority,
      shiftType: shiftType,
      expiresAt: expiresAt?.toIso8601String(),
    );
  }

  // وضع علامة مقروء/غير مقروء
  Future<bool> markAsRead(int id) => dao.markAsRead(id);
  Future<bool> markAsUnread(int id) => dao.markAsUnread(id);

  // حذف ملاحظة
  Future<bool> deleteNote(int id) => dao.deleteNote(id);

  // عدد الملاحظات غير المقروءة
  Future<int> getUnreadCount() => dao.getUnreadCount();

  // مراقبة التغييرات
  Stream<List<ShiftNote>> watchAllNotes() => dao.watchAllNotes();
  Stream<int> watchUnreadCount() => dao.watchUnreadCount();
}