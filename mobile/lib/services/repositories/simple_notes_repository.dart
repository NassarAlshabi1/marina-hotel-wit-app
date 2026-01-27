import '../local_db.dart';
import '../daos/shift_notes_dao.dart';
import '../../models/shift_note_adapter.dart' as adapter;

class SimpleNotesRepository {
  SimpleNotesRepository(this.db) : dao = ShiftNotesDao(db);

  final AppDatabase db;
  final ShiftNotesDao dao;

  // جلب جميع الملاحظات
  Future<List<adapter.ShiftNote>> getAllNotes() async {
    final dbNotes = await dao.getAllNotes();
    return dbNotes.map(_convertToModel).toList();
  }

  // جلب الملاحظات غير المقروءة
  Future<List<adapter.ShiftNote>> getUnreadNotes() async {
    final dbNotes = await dao.getUnreadNotes();
    return dbNotes.map(_convertToModel).toList();
  }

  // جلب الملاحظات عالية الأولوية
  Future<List<adapter.ShiftNote>> getHighPriorityNotes() async {
    final dbNotes = await dao.getHighPriorityNotes();
    return dbNotes.map(_convertToModel).toList();
  }

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
  Future<bool> updateNote(
    String id, {
    String? title,
    String? content,
    String? priority,
    String? shiftType,
    DateTime? expiresAt,
  }) {
    final intId = int.tryParse(id) ?? 0;
    return dao.updateNote(
      intId,
      title: title,
      content: content,
      priority: priority,
      shiftType: shiftType,
      expiresAt: expiresAt?.toIso8601String(),
    );
  }

  // وضع علامة مقروء/غير مقروء
  Future<bool> markAsRead(String id) {
    final intId = int.tryParse(id) ?? 0;
    return dao.markAsRead(intId);
  }

  Future<bool> markAsUnread(String id) {
    final intId = int.tryParse(id) ?? 0;
    return dao.markAsUnread(intId);
  }

  // حذف ملاحظة
  Future<bool> deleteNote(String id) {
    final intId = int.tryParse(id) ?? 0;
    return dao.deleteNote(intId);
  }

  // عدد الملاحظات غير المقروءة
  Future<int> getUnreadCount() => dao.getUnreadCount();

  // مراقبة التغييرات
  Stream<List<adapter.ShiftNote>> watchAllNotes() {
    return dao.watchAllNotes().map(
          (dbNotes) => dbNotes.map(_convertToModel).toList(),
        );
  }

  Stream<int> watchUnreadCount() => dao.watchUnreadCount();

  // تحويل من نوع قاعدة البيانات إلى نوع النموذج
  adapter.ShiftNote _convertToModel(ShiftNote dbNote) {
    final priority = dbNote.priority == 'high'
        ? adapter.NotePriority.high
        : dbNote.priority == 'medium'
            ? adapter.NotePriority.medium
            : adapter.NotePriority.low;
    final shiftType = dbNote.shiftType == 'morning'
        ? adapter.ShiftType.morning
        : dbNote.shiftType == 'evening'
            ? adapter.ShiftType.evening
            : dbNote.shiftType == 'night'
                ? adapter.ShiftType.night
                : adapter.ShiftType.all;

    return adapter.ShiftNote(
      id: dbNote.id.toString(),
      title: dbNote.title,
      content: dbNote.content,
      priority: priority,
      shiftType: shiftType,
      createdAt: DateTime.parse(dbNote.createdAt),
      expiresAt: dbNote.expiresAt != null
          ? DateTime.tryParse(dbNote.expiresAt!)
          : null,
      isRead: dbNote.isRead == 1,
      createdBy: dbNote.createdBy,
    );
  }
}
