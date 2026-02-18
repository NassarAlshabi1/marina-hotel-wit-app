import 'dart:convert';

import 'package:drift/drift.dart' as d;
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
  if (a.length < 3 || b.length < 3) return false;
  return a[0] == b[0] && a[1] == b[1] && a[2] == b[2];
}

class BlacklistEntry {
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

  const BlacklistEntry({
    required this.id,
    required this.name,
    this.nationality,
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
    } catch (_) {}
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
      ..where((t) => t.createdBy.equals(_createdByTag))
      ..orderBy([(t) => d.OrderingTerm.desc(t.createdAt)]));
    return query.watch().map((rows) => rows.map(_fromRow).toList());
  }

  Future<List<BlacklistEntry>> listAll() async {
    final rows =
        await (db.select(db.shiftNotes)
              ..where((t) => t.createdBy.equals(_createdByTag))
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
            createdAt: d.Value(DateTime.now().millisecondsSinceEpoch ~/ 1000),
            createdAtIso: d.Value(DateTime.now().toIso8601String()),
            expiresAt: const d.Value(null),
            isRead: const d.Value(0),
            createdBy: const d.Value(_createdByTag),
          ),
        );
    return id;
  }

  Future<bool> updateActive(int id, bool active) async {
    final row = await (db.select(
      db.shiftNotes,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return false;
    Map<String, dynamic> payload = const {};
    try {
      payload = jsonDecode(row.content) as Map<String, dynamic>;
    } catch (_) {}
    payload['active'] = active;
    final updated =
        await (db.update(db.shiftNotes)..where((t) => t.id.equals(id))).write(
          ShiftNotesCompanion(content: d.Value(jsonEncode(payload))),
        );
    return updated > 0;
  }

  Future<bool> delete(int id) async {
    final rows = await (db.delete(
      db.shiftNotes,
    )..where((t) => t.id.equals(id))).go();
    return rows > 0;
  }

  Future<bool> isNameBlacklisted(String name) async {
    final rows = await (db.select(
      db.shiftNotes,
    )..where((t) => t.createdBy.equals(_createdByTag))).get();
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
          if ((payload['active'] as bool?) ?? true) return true;
        } catch (_) {
          return true; // malformed payload -> treat as active match
        }
      }
    }
    return false;
  }
}
