import 'package:drift/drift.dart';
import '../../utils/id.dart';
import '../../utils/time.dart';
import '../appwrite_sync_manager.dart';
import '../local_db.dart';
import 'outbox_dao.dart';

part 'shift_notes_dao.g.dart';

@DriftAccessor(tables: [ShiftNotes])
class ShiftNotesDao extends DatabaseAccessor<AppDatabase>
    with _$ShiftNotesDaoMixin {
  ShiftNotesDao(super.db, this.outboxDao);

  final OutboxDao outboxDao;

  // جلب جميع الملاحظات (غير المحذوفة، غير القائمة السوداء)
  Future<List<ShiftNote>> getAllNotes() => (select(
    shiftNotes,
  )..where((t) => t.deletedAt.isNull() & t.createdBy.equals('user'))).get();

  // جلب الملاحظات غير المقروءة فقط (غير المحذوفة، غير القائمة السوداء)
  Future<List<ShiftNote>> getUnreadNotes() =>
      (select(shiftNotes)..where(
            (t) =>
                t.isRead.equals(0) &
                t.deletedAt.isNull() &
                t.createdBy.equals('user'),
          ))
          .get();

  // جلب الملاحظات عالية الأولوية (غير المحذوفة، غير القائمة السوداء)
  Future<List<ShiftNote>> getHighPriorityNotes() =>
      (select(
            shiftNotes,
          )..where(
            (t) =>
                t.priority.equals('high') &
                t.deletedAt.isNull() &
                t.createdBy.equals('user'),
          ))
          .get();

  // إضافة ملاحظة جديدة
  Future<int> addNote({
    required String title,
    required String content,
    String priority = 'medium',
    String shiftType = 'all',
    String? expiresAt,
    bool originIsServer = false,
  }) async {
    return transaction(() async {
      final now = Time.nowEpoch();
      final uuid = IdGen.uuid();
      final companion = ShiftNotesCompanion(
        title: Value(title),
        content: Value(content),
        priority: Value(priority),
        shiftType: Value(shiftType),
        createdAt: Value(now), // Using epoch int as per SyncFields
        createdAtIso: Value(DateTime.now().toIso8601String()),
        updatedAt: Value(now),
        lastModified: Value(now),
        expiresAt: expiresAt != null ? Value(expiresAt) : const Value.absent(),
        isRead: const Value(0),
        createdBy: const Value('user'),
        localUuid: Value(uuid),
        deviceId: originIsServer
            ? const Value.absent()
            : Value(AppwriteSyncManager.currentDeviceIdStatic ?? ''),
      );

      final id = await into(shiftNotes).insert(companion);

      if (!originIsServer) {
        await outboxDao.merge(
          entity: 'shift_notes',
          op: 'create',
          localUuid: uuid,
          payload: {
            'title': title,
            'content': content,
            'priority': priority,
            'shift_type': shiftType,
            'expires_at': expiresAt,
            'is_read': 0,
            'created_by': 'user',
          },
          clientTs: now,
        );
      }
      return id;
    });
  }

  // تحديث ملاحظة
  Future<bool> updateNote(
    int id, {
    String? title,
    String? content,
    String? priority,
    String? shiftType,
    String? expiresAt,
    bool originIsServer = false,
    int? serverLastModified,
  }) async {
    return transaction(() async {
      final existing = await (select(
        shiftNotes,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (existing == null) {
        return false;
      }

      final now = Time.nowEpoch();
      // ✅ إصلاح: عند originIsServer=true، نستخدم lastModified من البيانات الواردة
      // بدلاً من تعيين now، لمنع إعادة رفع البيانات المسحوبة من السيرفر
      final effectiveLastModified = originIsServer && serverLastModified != null
          ? Value(serverLastModified)
          : Value(now);
      final companion = ShiftNotesCompanion(
        title: title != null ? Value(title) : const Value.absent(),
        content: content != null ? Value(content) : const Value.absent(),
        priority: priority != null ? Value(priority) : const Value.absent(),
        shiftType: shiftType != null ? Value(shiftType) : const Value.absent(),
        expiresAt: expiresAt != null ? Value(expiresAt) : const Value.absent(),
        updatedAt: Value(now),
        lastModified: effectiveLastModified,
        version: Value(existing.version + 1),
      );

      // ✅ OCC: فحص version في WHERE لمنع lost update
      final rows =
          await (update(
                shiftNotes,
              )..where(
                (t) => t.id.equals(id) & t.version.equals(existing.version),
              ))
              .write(companion);

      if (rows > 0 && !originIsServer) {
        final payload = <String, dynamic>{};
        if (title != null) {
          payload['title'] = title;
        }
        if (content != null) {
          payload['content'] = content;
        }
        if (priority != null) {
          payload['priority'] = priority;
        }
        if (shiftType != null) {
          payload['shift_type'] = shiftType;
        }
        if (expiresAt != null) {
          payload['expires_at'] = expiresAt;
        }

        if (payload.isNotEmpty) {
          await outboxDao.merge(
            entity: 'shift_notes',
            op: 'update',
            localUuid: existing.localUuid,
            serverId: existing.serverId,
            payload: payload,
            clientTs: now,
          );
        }
      }
      return rows > 0;
    });
  }

  // وضع علامة مقروء
  Future<bool> markAsRead(
    int id, {
    bool originIsServer = false,
    int? serverLastModified,
  }) async {
    return transaction(() async {
      final existing = await (select(
        shiftNotes,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (existing == null) {
        return false;
      }

      final now = Time.nowEpoch();
      // ✅ إصلاح: عند originIsServer=true، نستخدم lastModified من البيانات الواردة
      // بدلاً من تعيين now، لمنع إعادة رفع البيانات المسحوبة من السيرفر
      final effectiveLastModified = originIsServer && serverLastModified != null
          ? Value(serverLastModified)
          : Value(now);
      // ✅ OCC: فحص version في WHERE لمنع lost update
      final rows =
          await (update(shiftNotes)..where(
                (t) => t.id.equals(id) & t.version.equals(existing.version),
              ))
              .write(
                ShiftNotesCompanion(
                  isRead: const Value(1),
                  updatedAt: Value(now),
                  lastModified: effectiveLastModified,
                  version: Value(existing.version + 1),
                ),
              );

      if (rows > 0 && !originIsServer) {
        await outboxDao.merge(
          entity: 'shift_notes',
          op: 'update',
          localUuid: existing.localUuid,
          serverId: existing.serverId,
          payload: {'is_read': 1},
          clientTs: now,
        );
      }
      return rows > 0;
    });
  }

  // وضع علامة غير مقروء
  Future<bool> markAsUnread(
    int id, {
    bool originIsServer = false,
    int? serverLastModified,
  }) async {
    return transaction(() async {
      final existing = await (select(
        shiftNotes,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (existing == null) {
        return false;
      }

      final now = Time.nowEpoch();
      // ✅ إصلاح: عند originIsServer=true، نستخدم lastModified من البيانات الواردة
      // بدلاً من تعيين now، لمنع إعادة رفع البيانات المسحوبة من السيرفر
      final effectiveLastModified = originIsServer && serverLastModified != null
          ? Value(serverLastModified)
          : Value(now);
      // ✅ OCC: فحص version في WHERE لمنع lost update
      final rows =
          await (update(shiftNotes)..where(
                (t) => t.id.equals(id) & t.version.equals(existing.version),
              ))
              .write(
                ShiftNotesCompanion(
                  isRead: const Value(0),
                  updatedAt: Value(now),
                  lastModified: effectiveLastModified,
                  version: Value(existing.version + 1),
                ),
              );

      if (rows > 0 && !originIsServer) {
        await outboxDao.merge(
          entity: 'shift_notes',
          op: 'update',
          localUuid: existing.localUuid,
          serverId: existing.serverId,
          payload: {'is_read': 0},
          clientTs: now,
        );
      }
      return rows > 0;
    });
  }

  // حذف ملاحظة
  Future<bool> deleteNote(int id, {bool originIsServer = false}) async {
    return transaction(() async {
      final existing = await (select(
        shiftNotes,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (existing == null) {
        return false; // Already deleted or doesn't exist
      }

      // Soft delete if using SyncFields, but original code used hard delete.
      // SyncFields mixin usually implies soft delete (deletedAt).
      // Let's check if we should soft delete.
      // The original code: final rows = await (delete(shiftNotes)..where((t) => t.id.equals(id))).go();
      // If we hard delete, we lose history for sync unless we track deletions separately.
      // SyncFields adds `deletedAt`. We should use Soft Delete.

      final now = Time.nowEpoch();
      // ✅ OCC: فحص version في WHERE لمنع lost update
      final rows =
          await (update(shiftNotes)..where(
                (t) => t.id.equals(id) & t.version.equals(existing.version),
              ))
              .write(
                ShiftNotesCompanion(
                  deletedAt: Value(now),
                  updatedAt: Value(now),
                  lastModified: Value(now),
                  version: Value(existing.version + 1),
                ),
              );

      if (rows > 0 && !originIsServer) {
        // ✅ نستخدم 'update' بدلاً من 'delete' لأن softDelete يحدّث deletedAt
        // ولا يحذف المستند من Appwrite — الجهاز الآخر يحتاج رؤية deletedAt
        await outboxDao.merge(
          entity: 'shift_notes',
          op: 'update',
          localUuid: existing.localUuid,
          serverId: existing.serverId,
          payload: {}, // Payload often empty for delete, or ID only
          clientTs: now,
        );
      }
      return rows > 0;
    });
  }

  // عدد الملاحظات غير المقروءة (غير المحذوفة، غير القائمة السوداء)
  Future<int> getUnreadCount() async {
    final query = selectOnly(shiftNotes)
      ..addColumns([shiftNotes.id.count()])
      ..where(
        shiftNotes.isRead.equals(0) &
            shiftNotes.deletedAt.isNull() &
            shiftNotes.createdBy.equals('user'),
      );
    final result = await query.getSingle();
    return result.read(shiftNotes.id.count()) ?? 0;
  }

  // مراقبة التغييرات على جميع الملاحظات (غير المحذوفة، غير القائمة السوداء)
  Stream<List<ShiftNote>> watchAllNotes() => (select(
    shiftNotes,
  )..where((t) => t.deletedAt.isNull() & t.createdBy.equals('user'))).watch();

  // مراقبة عدد الملاحظات غير المقروءة (غير المحذوفة، غير القائمة السوداء)
  Stream<int> watchUnreadCount() {
    final query = selectOnly(shiftNotes)
      ..addColumns([shiftNotes.id.count()])
      ..where(
        shiftNotes.isRead.equals(0) &
            shiftNotes.deletedAt.isNull() &
            shiftNotes.createdBy.equals('user'),
      );
    return query.watchSingle().map(
      (row) => row.read(shiftNotes.id.count()) ?? 0,
    );
  }
}
