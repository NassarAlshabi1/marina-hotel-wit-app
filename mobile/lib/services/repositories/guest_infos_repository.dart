import 'package:drift/drift.dart' as d;

import '../../utils/id.dart';
import '../../utils/time.dart';
import '../daos/outbox_dao.dart';
import '../local_db.dart';

class GuestInfosRepository {
  GuestInfosRepository(this._db) : _outboxDao = OutboxDao(_db);

  final AppDatabase _db;
  final OutboxDao _outboxDao;

  /// جلب السجلات غير المحذوفة. يدعم pagination لتقليل الذاكرة في الشاشات.
  Future<List<GuestInfo>> listAll({int? limit, int offset = 0}) async {
    final query = _db.select(_db.guestInfos)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => d.OrderingTerm(
          expression: t.updatedAt,
          mode: d.OrderingMode.desc,
        ),
        (t) => d.OrderingTerm(expression: t.id, mode: d.OrderingMode.desc),
      ]);
    if (limit != null) {
      query.limit(limit, offset: offset);
    }
    return query.get();
  }

  /// مراقبة التغييرات (بدون المحذفة) مع حد اختياري على مستوى SQLite.
  Stream<List<GuestInfo>> watchAll({int? limit, int offset = 0}) {
    final query = _db.select(_db.guestInfos)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => d.OrderingTerm(
          expression: t.updatedAt,
          mode: d.OrderingMode.desc,
        ),
        (t) => d.OrderingTerm(expression: t.id, mode: d.OrderingMode.desc),
      ]);
    if (limit != null) {
      query.limit(limit, offset: offset);
    }
    return query.watch();
  }

  /// إنشاء سجل جديد + كتابة outbox للمزامنة
  Future<int> create({
    required String roomNumber,
    required String guestName,
    required String nationality,
    required String idNumber,
    String idType = 'بطاقة شخصية',
    String? issueDate,
    String? issuePlace,
    String? governorate,
    String? notes,
    bool originIsServer = false,
  }) async {
    return _db.transaction(() async {
      final now = Time.nowEpoch();
      final nowIso = Time.nowIso();
      final uuid = IdGen.uuid();

      final id = await _db
          .into(_db.guestInfos)
          .insert(
            GuestInfosCompanion(
              roomNumber: d.Value(roomNumber),
              guestName: d.Value(guestName),
              nationality: d.Value(nationality),
              idNumber: d.Value(idNumber),
              idType: d.Value(idType),
              issueDate: d.Value(issueDate),
              issuePlace: d.Value(issuePlace),
              governorate: d.Value(governorate),
              notes: d.Value(notes),
              localUuid: d.Value(uuid),
              createdAt: d.Value(now),
              updatedAt: d.Value(now),
              lastModified: d.Value(now),
              createdAtIso: d.Value(nowIso),
              updatedAtIso: d.Value(nowIso),
              version: const d.Value(1),
              origin: d.Value(originIsServer ? 'server' : 'local'),
              vectorClock: const d.Value('{}'),
            ),
          );

      if (!originIsServer) {
        await _outboxDao.merge(
          entity: 'guest_infos',
          op: 'create',
          localUuid: uuid,
          payload: {
            'roomNumber': roomNumber,
            'guestName': guestName,
            'nationality': nationality,
            'idNumber': idNumber,
            'idType': idType,
            'issueDate': issueDate,
            'issuePlace': issuePlace,
            'governorate': governorate,
            'notes': notes,
          },
          clientTs: now,
        );
      }

      return id;
    });
  }

  /// تحديث سجل موجود + كتابة outbox للمزامنة
  Future<void> update(
    int id, {
    required String roomNumber,
    required String guestName,
    required String nationality,
    required String idNumber,
    String idType = 'بطاقة شخصية',
    String issueDate = '',
    String issuePlace = '',
    String governorate = '',
    String notes = '',
    bool originIsServer = false,
  }) async {
    await _db.transaction(() async {
      final now = Time.nowEpoch();
      final nowIso = Time.nowIso();

      // جلب السجل الحالي
      final existing = await (_db.select(
        _db.guestInfos,
      )..where((t) => t.id.equals(id))).getSingleOrNull();

      if (existing == null) {
        return;
      }

      // ✅ OCC: فحص version في WHERE لمنع lost update
      // إذا عدّل جهاز آخر السجل بين القراءة والكتابة، لن يطابق الشرط
      // وسيُرجع 0 صفوف → نكتشف التعارض بدلاً من طمس التعديل الآخر
      await (_db.update(
            _db.guestInfos,
          )..where((t) => t.id.equals(id) & t.version.equals(existing.version)))
          .write(
            GuestInfosCompanion(
              roomNumber: d.Value(roomNumber),
              guestName: d.Value(guestName),
              nationality: d.Value(nationality),
              idNumber: d.Value(idNumber),
              idType: d.Value(idType),
              issueDate: d.Value(issueDate.isEmpty ? null : issueDate),
              issuePlace: d.Value(issuePlace.isEmpty ? null : issuePlace),
              governorate: d.Value(governorate.isEmpty ? null : governorate),
              notes: d.Value(notes.isEmpty ? null : notes),
              updatedAt: d.Value(now),
              lastModified: d.Value(now),
              updatedAtIso: d.Value(nowIso),
              version: d.Value(existing.version + 1),
            ),
          );

      if (!originIsServer) {
        await _outboxDao.merge(
          entity: 'guest_infos',
          op: 'update',
          localUuid: existing.localUuid,
          serverId: existing.serverId,
          payload: {
            'roomNumber': roomNumber,
            'guestName': guestName,
            'nationality': nationality,
            'idNumber': idNumber,
            'idType': idType,
            'issueDate': issueDate.isEmpty ? null : issueDate,
            'issuePlace': issuePlace.isEmpty ? null : issuePlace,
            'governorate': governorate.isEmpty ? null : governorate,
            'notes': notes.isEmpty ? null : notes,
          },
          clientTs: now,
        );
      }
    });
  }

  /// حذف ناعم (soft delete) + كتابة outbox للمزامنة
  Future<void> delete(int id) async {
    await _db.transaction(() async {
      final now = Time.nowEpoch();
      final nowIso = Time.nowIso();

      final existing = await (_db.select(
        _db.guestInfos,
      )..where((t) => t.id.equals(id))).getSingleOrNull();

      if (existing == null) {
        return;
      }

      // soft delete: تعيين deletedAt بدلاً من حذف فعلي
      // ✅ OCC: فحص version في WHERE لمنع lost update
      await (_db.update(
            _db.guestInfos,
          )..where((t) => t.id.equals(id) & t.version.equals(existing.version)))
          .write(
            GuestInfosCompanion(
              deletedAt: d.Value(now),
              updatedAt: d.Value(now),
              lastModified: d.Value(now),
              version: d.Value(existing.version + 1),
              updatedAtIso: d.Value(nowIso),
              deletedAtIso: d.Value(nowIso),
            ),
          );

      await _outboxDao.merge(
        entity: 'guest_infos',
        op: 'update',
        localUuid: existing.localUuid,
        serverId: existing.serverId,
        payload: {'guestName': existing.guestName},
        clientTs: now,
      );
    });
  }
}
