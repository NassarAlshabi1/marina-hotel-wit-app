import 'dart:convert';

import 'package:drift/drift.dart' as d;
import '../local_db.dart';

class BlacklistEntry {
  final int id;
  final String name;
  final String? nationalId;
  final String? phone;
  final String? reason;
  final String? notes;
  final String reportedBy;
  final bool active;
  final DateTime createdAt;

  const BlacklistEntry({
    required this.id,
    required this.name,
    this.nationalId,
    this.phone,
    this.reason,
    this.notes,
    this.reportedBy = 'police',
    this.active = true,
    required this.createdAt,
  });
}

class BlacklistRepository {
  BlacklistRepository(this.db);
  final AppDatabase db;

  static const _createdByTag = 'blacklist';

  Map<String, dynamic> _toPayload({
    String? nationalId,
    String? phone,
    String? reason,
    String? notes,
    String reportedBy = 'police',
    bool active = true,
  }) => {
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
    } catch (_) {}
    return BlacklistEntry(
      id: row.id,
      name: row.title,
      nationalId: payload['nationalId'] as String?,
      phone: payload['phone'] as String?,
      reason: payload['reason'] as String?,
      notes: payload['notes'] as String?,
      reportedBy: (payload['reportedBy'] as String?) ?? 'police',
      active: (payload['active'] as bool?) ?? true,
      createdAt: DateTime.tryParse(row.createdAt) ?? DateTime.now(),
    );
  }

  Stream<List<BlacklistEntry>> watchAll() {
    final query = (db.select(db.shiftNotes)
      ..where((t) => t.createdBy.equals(_createdByTag))
      ..orderBy([(t) => d.OrderingTerm.desc(t.createdAt)]));
    return query.watch().map((rows) => rows.map(_fromRow).toList());
  }

  Future<List<BlacklistEntry>> listAll() async {
    final rows = await (db.select(db.shiftNotes)
          ..where((t) => t.createdBy.equals(_createdByTag))
          ..orderBy([(t) => d.OrderingTerm.desc(t.createdAt)])).
        get();
    return rows.map(_fromRow).toList();
  }

  Future<int> addEntry({
    required String name,
    String? nationalId,
    String? phone,
    String? reason,
    String? notes,
    String reportedBy = 'police',
    bool active = true,
  }) async {
    final id = await db.into(db.shiftNotes).insert(ShiftNotesCompanion(
      title: d.Value(name.trim()),
      content: d.Value(jsonEncode(_toPayload(
        nationalId: nationalId?.trim(),
        phone: phone?.trim(),
        reason: reason?.trim(),
        notes: notes?.trim(),
        reportedBy: reportedBy,
        active: active,
      ))),
      priority: const d.Value('high'),
      shiftType: const d.Value('all'),
      createdAt: d.Value(DateTime.now().toIso8601String()),
      expiresAt: const d.Value(null),
      isRead: const d.Value(0),
      createdBy: const d.Value(_createdByTag),
    ));
    return id;
  }

  Future<bool> updateActive(int id, bool active) async {
    final row = await (db.select(db.shiftNotes)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return false;
    Map<String, dynamic> payload = const {};
    try { payload = jsonDecode(row.content) as Map<String, dynamic>; } catch (_) {}
    payload['active'] = active;
    final updated = await (db.update(db.shiftNotes)..where((t) => t.id.equals(id))).write(
      ShiftNotesCompanion(
        content: d.Value(jsonEncode(payload)),
      ),
    );
    return updated > 0;
  }

  Future<bool> delete(int id) async {
    final rows = await (db.delete(db.shiftNotes)..where((t) => t.id.equals(id))).go();
    return rows > 0;
  }

  Future<bool> isNameBlacklisted(String name) async {
    final rows = await (db.select(db.shiftNotes)..where((t) => t.createdBy.equals(_createdByTag))).get();
    final n = name.trim().toLowerCase();
    for (final row in rows) {
      if (row.title.trim().toLowerCase() == n) {
        try {
          final payload = jsonDecode(row.content) as Map<String, dynamic>;
          if ((payload['active'] as bool?) ?? true) return true;
        } catch (_) {
          return true; // treat malformed payload as active
        }
      }
    }
    return false;
  }
}