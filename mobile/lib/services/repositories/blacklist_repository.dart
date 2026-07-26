import 'dart:convert';

import 'package:drift/drift.dart' as d;
import 'package:flutter/foundation.dart';

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
}

class BlacklistRepository {
  BlacklistRepository(this.db) : _outboxDao = OutboxDao(db);
  final AppDatabase db;
  final OutboxDao _outboxDao;

  static const _createdByTag = 'blacklist';

  Map<String, dynamic> _toPayload({
    String? nationality,
    String? nationalId,
    String? phone,
    String? reason,
    String? notes,
    String reportedBy = 'police',
    bool active = true,
  }) => {
    'nationality': nationality,
    'nationalId': nationalId,
    'phone': phone,
    'reason': reason,
    'notes': notes,
    'reportedBy': reportedBy,
    'active': active,
  };

  BlacklistEntry _fromRow(ShiftNote row) {
    Map<String, dynamic> payload = const {};
    try {
      payload = jsonDecode(row.content) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('WARN: Failed to parse blacklist JSON: $e');
    }
    return BlacklistEntry(
      id: row.id,
      name: row.title,
      nationality: payload['nationality'] as String?,
      nationalId: payload['nationalId'] as String?,
      phone: payload['phone'] as String?,
      reason: payload['reason'] as String?,
      notes: payload['notes'] as String?,
      reportedBy: (payload['reportedBy'] as String?) ?? 'police',
      active: (payload['active'] as bool?) ?? true,
      createdAt: row.createdAtIso != null
          ? DateTime.tryParse(row.createdAtIso!) ?? DateTime.now()
          : DateTime.fromMillisecondsSinceEpoch(row.createdAt * 1000),
    );
  }

  Stream<List<BlacklistEntry>> watchAll() {
    final query = (db.select(db.shiftNotes)
      ..where((t) => t.createdBy.equals(_createdByTag) & t.deletedAt.isNull())
      ..orderBy([(t) => d.OrderingTerm.desc(t.createdAt)]));
    return query.watch().map((rows) => rows.map(_fromRow).toList());
  }

  Future<List<BlacklistEntry>> listAll() async {
    final rows =
        await (db.select(db.shiftNotes)
              ..where(
                (t) => t.createdBy.equals(_createdByTag) & t.deletedAt.isNull(),
              )
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
    final id = await db
        .into(db.shiftNotes)
        .insert(
          ShiftNotesCompanion(
            title: d.Value(name.trim()),
            content: d.Value(
              jsonEncode(
                _toPayload(
                  nationality: nationality?.trim(),
                  nationalId: nationalId?.trim(),
                  phone: phone?.trim(),
                  reason: reason?.trim(),
                  notes: notes?.trim(),
                  reportedBy: reportedBy,
                  active: active,
                ),
              ),
            ),
            priority: const d.Value('high'),
            shiftType: const d.Value('all'),
            createdAt: d.Value(now),
            createdAtIso: d.Value(DateTime.now().toIso8601String()),
            updatedAt: d.Value(now),
            lastModified: d.Value(now),
            expiresAt: const d.Value(null),
            isRead: const d.Value(0),
            createdBy: const d.Value(_createdByTag),
            localUuid: d.Value(uuid),
          ),
        );

    // إضافة سجل Outbox للمزامنة مع Appwrite
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
  }

  Future<bool> updateActive(int id, bool active) async {
    final row = await (db.select(
      db.shiftNotes,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) {
      return false;
    }
    Map<String, dynamic> payload = const {};
    try {
      payload = jsonDecode(row.content) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('WARN: Failed to parse blacklist JSON: $e');
    }
    payload['active'] = active;
    final now = Time.nowEpoch();
    // ✅ bump version + OCC: فحص version في WHERE لمنع lost update
    final updated =
        await (db.update(
          db.shiftNotes,
        )..where((t) => t.id.equals(id) & t.version.equals(row.version))).write(
          ShiftNotesCompanion(
            content: d.Value(jsonEncode(payload)),
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
    final row = await (db.select(
      db.shiftNotes,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) {
      return false;
    }
    final oldPayload = jsonDecode(row.content) as Map<String, dynamic>;
    final now = Time.nowEpoch();
    final updated =
        await (db.update(
          db.shiftNotes,
        )..where((t) => t.id.equals(id) & t.version.equals(row.version))).write(
          ShiftNotesCompanion(
            title: d.Value(name.trim()),
            content: d.Value(
              jsonEncode(
                _toPayload(
                  nationality: nationality?.trim(),
                  nationalId: nationalId?.trim(),
                  phone: phone?.trim(),
                  reason: reason?.trim(),
                  notes: notes?.trim(),
                  reportedBy:
                      reportedBy ??
                      (oldPayload['reportedBy'] as String?) ??
                      'police',
                  active: (oldPayload['active'] as bool?) ?? true,
                ),
              ),
            ),
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
          'reportedBy':
              reportedBy ?? (oldPayload['reportedBy'] as String?) ?? 'police',
          'active': (oldPayload['active'] as bool?) ?? true,
          'lastModified': now,
        },
        clientTs: now,
      );
    }

    return updated > 0;
  }

  /// ✅ إصلاح: حذف ناعم (soft delete) بدلاً من الحذف الفعلي
  /// لتوافق مع آلية المزامنة التي تعتمد على deletedAt
  Future<bool> delete(int id) async {
    final row = await (db.select(
      db.shiftNotes,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) {
      return false;
    }

    final now = Time.nowEpoch();
    final nowIso = DateTime.now().toUtc().toIso8601String();

    // ✅ حذف ناعم: تعيين deletedAt بدلاً من حذف الصف فعلياً
    final updated =
        await (db.update(db.shiftNotes)..where((t) => t.id.equals(id))).write(
          ShiftNotesCompanion(
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
  }

  Future<bool> isNameBlacklisted(String name) async {
    return await findBlacklistMatch(name) != null;
  }

  /// فحص هل الاسم مطابق لشخص في القائمة السوداء وارجاع بياناته
  /// تطابق: الاسم الكامل أو أول 3 أسماء متطابقة
  /// ✅ إصلاح: استبعاد المحذوفة ناعماً
  Future<BlacklistEntry?> findBlacklistMatch(String name) async {
    final rows =
        await (db.select(
              db.shiftNotes,
            )..where(
              (t) => t.createdBy.equals(_createdByTag) & t.deletedAt.isNull(),
            ))
            .get();
    final nNorm = _normalizeArabic(name);
    final nTokens = _tokens(name);
    for (final row in rows) {
      final rNorm = _normalizeArabic(row.title);
      final rTokens = _tokens(row.title);
      final fullEq = rNorm == nNorm;
      final tripleEq = _tripleMatch(rTokens, nTokens);
      if (fullEq || tripleEq) {
        try {
          final payload = jsonDecode(row.content) as Map<String, dynamic>;
          final active = (payload['active'] as bool?) ?? true;
          if (active) {
            return _fromRow(row);
          }
        } catch (_) {
          return _fromRow(row);
        }
      }
    }
    return null;
  }
}
