import 'package:drift/drift.dart' as d;

import '../../utils/id.dart';
import '../../utils/time.dart';
import '../daos/outbox_dao.dart';
import '../local_db.dart';

String _normalizeArabic(String input) {
  var s = input.trim();
  s = s.replaceAll(
    RegExp('[\u0617-\u061A\u064B-\u0652\u0670\u0653-\u065F\u06D6-\u06ED]'),
    '',
  ); // tashkeel
  s = s.replaceAll('\u0640', ''); // tatweel
  s = s.replaceAll(RegExp('[إأٱآ]'), 'ا');
  s = s.replaceAll('ؤ', 'و');
  s = s.replaceAll('ئ', 'ي');
  s = s.replaceAll('ى', 'ي');
  s = s.replaceAll(
    RegExp('[^\u0621-\u064A0-9 ]+'),
    ' ',
  ); // keep arabic letters, digits, space
  s = s.replaceAll(RegExp(' +'), ' ').trim();
  return s.toLowerCase();
}

List<String> _tokens(String name) => _normalizeArabic(
  name,
).split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();

bool _tripleMatch(List<String> a, List<String> b) {
  if (a.length < 3 || b.length < 3) {
    return false;
  }
  return a[0] == b[0] && a[1] == b[1] && a[2] == b[2];
}

class BlacklistEntry {
  const BlacklistEntry({
    required this.id,
    required this.name,
    required this.createdAt,
    this.nationality,
    this.nationalId,
    this.phone,
    this.reason,
    this.notes,
    this.reportedBy = 'police',
    this.active = true,
    this.localUuid,
    this.serverId,
    this.version,
  });
  final int id;
  final String name;
  final String? nationality;
  final String? nationalId;
  final String? phone;
  final String? reason;
  final String? notes;
  final String reportedBy;
  final bool active;
  final DateTime createdAt;
  final String? localUuid;
  final int? serverId;
  final int? version;
}

class BlacklistRepository {
  BlacklistRepository(this.db) : _outboxDao = OutboxDao(db);
  final AppDatabase db;
  final OutboxDao _outboxDao;

  BlacklistEntry _fromRow(BlacklistData row) {
    return BlacklistEntry(
      id: row.id,
      name: row.name,
      nationality: row.nationality,
      nationalId: row.nationalId,
      phone: row.phone,
      reason: row.reason,
      notes: row.notes,
      reportedBy: row.reportedBy,
      active: row.active,
      createdAt: row.createdAtIso != null
          ? DateTime.tryParse(row.createdAtIso!) ?? DateTime.fromMillisecondsSinceEpoch(row.createdAt * 1000)
          : DateTime.fromMillisecondsSinceEpoch(row.createdAt * 1000),
      localUuid: row.localUuid,
      serverId: row.serverId,
      version: row.version,
    );
  }

  Stream<List<BlacklistEntry>> watchAll() {
    final query = (db.select(db.blacklist)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => d.OrderingTerm.desc(t.createdAt)]));
    return query.watch().map((rows) => rows.map(_fromRow).toList());
  }

  Future<List<BlacklistEntry>> listAll() async {
    final rows = await (db.select(db.blacklist)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => d.OrderingTerm.desc(t.createdAt)]))
        .get();
    return rows.map(_fromRow).toList();
  }

  Future<int> addEntry({
    required String name,
    String? nationality,
    String? nationalId,
    String? phone,
    String? reason,
    String? notes,
    String reportedBy = 'police',
    bool active = true,
  }) async {
    final now = Time.nowEpoch();
    final uuid = IdGen.uuid();
    return db.transaction(() async {
      final id = await db
          .into(db.blacklist)
          .insert(
            BlacklistCompanion(
              name: d.Value(name.trim()),
              nationality: d.Value(nationality?.trim()),
              nationalId: d.Value(nationalId?.trim()),
              phone: d.Value(phone?.trim()),
              reason: d.Value(reason?.trim()),
              notes: d.Value(notes?.trim()),
              reportedBy: d.Value(reportedBy),
              active: d.Value(active),
              createdAt: d.Value(now),
              createdAtIso: d.Value(DateTime.now().toIso8601String()),
              updatedAt: d.Value(now),
              lastModified: d.Value(now),
              localUuid: d.Value(uuid),
            ),
          );

      await _outboxDao.merge(
        entity: 'blacklist',
        op: 'create',
        localUuid: uuid,
        payload: {
          'name': name.trim(),
          'nationality': nationality?.trim() ?? '',
          'nationalId': nationalId?.trim() ?? '',
          'phone': phone?.trim() ?? '',
          'reason': reason?.trim() ?? '',
          'notes': notes?.trim() ?? '',
          'reportedBy': reportedBy,
          'active': active,
          'createdAt': now,
          'lastModified': now,
          'origin': 'mobile',
        },
        clientTs: now,
      );

      return id;
    });
  }

  Future<bool> updateActive(int id, bool active) async {
    return db.transaction(() async {
      final row = await (db.select(
        db.blacklist,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null) {
        return false;
      }
      final now = Time.nowEpoch();
      final updated =
          await (db.update(db.blacklist)
                ..where((t) => t.id.equals(id) & t.version.equals(row.version)))
              .write(
                BlacklistCompanion(
                  active: d.Value(active),
                  updatedAt: d.Value(now),
                  lastModified: d.Value(now),
                  version: d.Value(row.version + 1),
                ),
              );

      if (updated > 0) {
        await _outboxDao.merge(
          entity: 'blacklist',
          op: 'update',
          localUuid: row.localUuid,
          serverId: row.serverId,
          payload: {'active': active, 'lastModified': now},
          clientTs: now,
        );
      }

      return updated > 0;
    });
  }

  Future<bool> updateEntry({
    required int id,
    required String name,
    String? nationality,
    String? nationalId,
    String? phone,
    String? reason,
    String? notes,
    String? reportedBy,
  }) async {
    return db.transaction(() async {
      final row = await (db.select(
        db.blacklist,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null) {
        return false;
      }
      final now = Time.nowEpoch();
      final updated =
          await (db.update(db.blacklist)
                ..where((t) => t.id.equals(id) & t.version.equals(row.version)))
              .write(
                BlacklistCompanion(
                  name: d.Value(name.trim()),
                  nationality: d.Value(nationality?.trim()),
                  nationalId: d.Value(nationalId?.trim()),
                  phone: d.Value(phone?.trim()),
                  reason: d.Value(reason?.trim()),
                  notes: d.Value(notes?.trim()),
                  reportedBy: d.Value(reportedBy ?? row.reportedBy),
                  updatedAt: d.Value(now),
                  lastModified: d.Value(now),
                  version: d.Value(row.version + 1),
                ),
              );

      if (updated > 0) {
        await _outboxDao.merge(
          entity: 'blacklist',
          op: 'update',
          localUuid: row.localUuid,
          serverId: row.serverId,
          payload: {
            'name': name.trim(),
            'nationality': nationality?.trim() ?? '',
            'nationalId': nationalId?.trim() ?? '',
            'phone': phone?.trim() ?? '',
            'reason': reason?.trim() ?? '',
            'notes': notes?.trim() ?? '',
            'reportedBy': reportedBy ?? row.reportedBy,
            'active': row.active,
            'lastModified': now,
          },
          clientTs: now,
        );
      }

      return updated > 0;
    });
  }

  /// ✅ إصلاح: حذف ناعم (soft delete) بدلاً من الحذف الفعلي
  /// لتوافق مع آلية المزامنة التي تعتمد على deletedAt
  Future<bool> delete(int id) async {
    return db.transaction(() async {
      final row = await (db.select(
        db.blacklist,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null) {
        return false;
      }

      final now = Time.nowEpoch();
      final nowIso = DateTime.now().toUtc().toIso8601String();

      final updated =
          await (db.update(db.blacklist)..where((t) => t.id.equals(id))).write(
            BlacklistCompanion(
              deletedAt: d.Value(now),
              deletedAtIso: d.Value(nowIso),
              updatedAt: d.Value(now),
              lastModified: d.Value(now),
              version: d.Value(row.version + 1),
            ),
          );

      if (updated > 0) {
        await _outboxDao.merge(
          entity: 'blacklist',
          op: 'update',
          localUuid: row.localUuid,
          serverId: row.serverId,
          payload: {'deletedAt': now, 'lastModified': now},
          clientTs: now,
        );
      }

      return updated > 0;
    });
  }

  Future<bool> isNameBlacklisted(String name) async {
    return await findBlacklistMatch(name) != null;
  }

  /// فحص هل الاسم مطابق لشخص في القائمة السوداء وارجاع بياناته
  /// تطابق: الاسم الكامل أو أول 3 أسماء متطابقة
  /// ✅ إصلاح: استبعاد المحذوفة ناعماً
  Future<BlacklistEntry?> findBlacklistMatch(String name) async {
    final rows = await (db.select(db.blacklist)..where(
          (t) => t.deletedAt.isNull(),
        ))
        .get();
    final nNorm = _normalizeArabic(name);
    final nTokens = _tokens(name);
    for (final row in rows) {
      final rNorm = _normalizeArabic(row.name);
      final rTokens = _tokens(row.name);
      final fullEq = rNorm == nNorm;
      final tripleEq = _tripleMatch(rTokens, nTokens);
      if (fullEq || tripleEq) {
        if (row.active) {
          return _fromRow(row);
        }
      }
    }
    return null;
  }
}