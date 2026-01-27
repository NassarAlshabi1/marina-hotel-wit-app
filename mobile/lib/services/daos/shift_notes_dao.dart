import 'package:drift/drift.dart';
import '../local_db.dart';

part 'shift_notes_dao.g.dart';

@DriftAccessor(tables: [ShiftNotes])
class ShiftNotesDao extends DatabaseAccessor<AppDatabase>
    with _$ShiftNotesDaoMixin {
  ShiftNotesDao(super.db);

  // جلب جميع الملاحظات
  Future<List<ShiftNote>> getAllNotes() => select(shiftNotes).get();

  // جلب الملاحظات غير المقروءة فقط
  Future<List<ShiftNote>> getUnreadNotes() =>
      (select(shiftNotes)..where((t) => t.isRead.equals(0))).get();

  // جلب الملاحظات عالية الأولوية
  Future<List<ShiftNote>> getHighPriorityNotes() =>
      (select(shiftNotes)..where((t) => t.priority.equals('high'))).get();

  // إضافة ملاحظة جديدة
  Future<int> addNote({
    required String title,
    required String content,
    String priority = 'medium',
    String shiftType = 'all',
    String? expiresAt,
  }) {
    return into(shiftNotes).insert(
      ShiftNotesCompanion(
        title: Value(title),
        content: Value(content),
        priority: Value(priority),
        shiftType: Value(shiftType),
        createdAt: Value(DateTime.now().toIso8601String()),
        expiresAt: Value(expiresAt),
        isRead: const Value(0),
        createdBy: const Value('user'),
      ),
    );
  }

  // تحديث ملاحظة
  Future<bool> updateNote(
    int id, {
    String? title,
    String? content,
    String? priority,
    String? shiftType,
    String? expiresAt,
  }) async {
    final companion = ShiftNotesCompanion(
      title: title != null ? Value(title) : const Value.absent(),
      content: content != null ? Value(content) : const Value.absent(),
      priority: priority != null ? Value(priority) : const Value.absent(),
      shiftType: shiftType != null ? Value(shiftType) : const Value.absent(),
      expiresAt: expiresAt != null ? Value(expiresAt) : const Value.absent(),
    );

    final rows = await (update(
      shiftNotes,
    )..where((t) => t.id.equals(id))).write(companion);
    return rows > 0;
  }

  // وضع علامة مقروء
  Future<bool> markAsRead(int id) async {
    final rows = await (update(shiftNotes)..where((t) => t.id.equals(id)))
        .write(const ShiftNotesCompanion(isRead: Value(1)));
    return rows > 0;
  }

  // وضع علامة غير مقروء
  Future<bool> markAsUnread(int id) async {
    final rows = await (update(shiftNotes)..where((t) => t.id.equals(id)))
        .write(const ShiftNotesCompanion(isRead: Value(0)));
    return rows > 0;
  }

  // حذف ملاحظة
  Future<bool> deleteNote(int id) async {
    final rows = await (delete(shiftNotes)..where((t) => t.id.equals(id))).go();
    return rows > 0;
  }

  // عدد الملاحظات غير المقروءة
  Future<int> getUnreadCount() async {
    final query = selectOnly(shiftNotes)
      ..addColumns([shiftNotes.id.count()])
      ..where(shiftNotes.isRead.equals(0));
    final result = await query.getSingle();
    return result.read(shiftNotes.id.count()) ?? 0;
  }

  // مراقبة التغييرات على جميع الملاحظات
  Stream<List<ShiftNote>> watchAllNotes() => select(shiftNotes).watch();

  // مراقبة عدد الملاحظات غير المقروءة
  Stream<int> watchUnreadCount() {
    final query = selectOnly(shiftNotes)
      ..addColumns([shiftNotes.id.count()])
      ..where(shiftNotes.isRead.equals(0));
    return query.watchSingle().map(
      (row) => row.read(shiftNotes.id.count()) ?? 0,
    );
  }
}
