import 'dart:convert';

import 'package:drift/drift.dart' as d;
import '../local_db.dart';
import '../../utils/id.dart';
import '../../utils/time.dart';
import 'entity_adapter.dart';
import 'id_resolver.dart';
import 'resolve_result.dart';
import 'source.dart';

class GuestInfosAdapter extends EntityAdapter<GuestInfo, GuestInfosCompanion> {
  GuestInfosAdapter(this.resolver);
  final IdResolver resolver;

  @override
  String get collectionId => 'guest_infos';

  @override
  String get drivePath => 'guest_infos.json';

  @override
  String get tableName => 'guest_infos';

  @override
  Future<ResolveResult> resolveRefs(
    AppDatabase db,
    Map<String, dynamic> json, {
    required Source src,
  }) async {
    final uuid =
        _asString(json, 'localUuid', src) ??
        _asString(json, 'local_uuid', src) ??
        IdGen.uuid();
    // ignore: unused_local_variable
    final serverId =
        _asInt(json, 'serverId', src) ?? _asInt(json, 'server_id', src);
    // ignore: unused_local_variable
    final localId = _asInt(json, 'id', src);

    final createdAt = _epoch(json, 'createdAt', src);
    final lastModified = _epoch(json, 'lastModified', src);

    return ResolveResult(
      bookingLocalId: null,
      bookingUuidCache: uuid,
      createdAtEpoch: createdAt,
      lastModifiedEpoch: lastModified,
    );
  }

  @override
  GuestInfosCompanion fromJson(
    Map<String, dynamic> json, {
    required Source src,
    required ResolveResult refs,
  }) {
    final now = Time.nowEpoch();
    final createdAt =
        refs.createdAtEpoch ?? _epoch(json, 'createdAt', src) ?? now;
    final lastModified =
        refs.lastModifiedEpoch ??
        _epoch(json, 'lastModified', src) ??
        createdAt;

    return GuestInfosCompanion(
      id: _vInt(json, 'id', src),
      localUuid: d.Value(refs.bookingUuidCache ?? IdGen.uuid()),
      serverId: _vInt(json, 'serverId', src),
      roomNumber: d.Value(
        _asString(json, 'roomNumber', src) ?? '',
      ),
      guestName: d.Value(
        _asString(json, 'guestName', src) ?? '',
      ),
      nationality: d.Value(
        _asString(json, 'nationality', src) ?? '',
      ),
      idNumber: d.Value(
        _asString(json, 'idNumber', src) ?? '',
      ),
      idType: _vStr(json, 'idType', src, fallback: 'بطاقة شخصية'),
      issueDate: _vStr(json, 'issueDate', src),
      issuePlace: _vStr(json, 'issuePlace', src),
      governorate: _vStr(json, 'governorate', src),
      notes: _vStr(json, 'notes', src),
      createdAt: d.Value(createdAt),
      updatedAt: d.Value(_epoch(json, 'updatedAt', src) ?? createdAt),
      deletedAt: _vInt(json, 'deletedAt', src),
      lastModified: d.Value(lastModified),
      createdAtIso: _vStr(
        json,
        'createdAtIso',
        src,
        fallback: _asString(json, 'createdAt', src),
      ),
      updatedAtIso: _vStr(json, 'updatedAtIso', src),
      deletedAtIso: _vStr(json, 'deletedAtIso', src),
      createdAtEpoch: _vInt(json, 'createdAtEpoch', src, fallback: createdAt),
      lastModifiedEpoch: _vInt(
        json,
        'lastModifiedEpoch',
        src,
        fallback: lastModified,
      ),
      version: _vInt(json, 'version', src, fallback: 1),
      origin: _vStr(json, 'origin', src, fallback: 'server'),
      vectorClock: _vMapJson(
        json,
        'vectorClock',
        src,
        altKey: 'vector_clock',
        fallback: {},
      ),
    );
  }

  @override
  Map<String, dynamic> toJson(GuestInfo model, {required Source src}) {
    if (src == Source.appwrite) {
      return {
        'localUuid': model.localUuid,
        'id': model.id,
        'roomNumber': model.roomNumber,
        'guestName': model.guestName,
        'nationality': model.nationality,
        'idNumber': model.idNumber,
        'idType': model.idType,
        if (model.issueDate != null) 'issueDate': model.issueDate,
        if (model.issuePlace != null) 'issuePlace': model.issuePlace,
        if (model.governorate != null) 'governorate': model.governorate,
        if (model.notes != null) 'notes': model.notes,
        'createdAt': model.createdAt,
        'updatedAt': model.updatedAt,
        'lastModified': model.lastModified,
        'version': model.version,
        'origin': model.origin,
        'vectorClock': jsonEncode(model.vectorClock ?? {}),
      };
    }
    return {
      _k(src, 'id', 'id'): model.id,
      _k(src, 'localUuid', 'local_uuid'): model.localUuid,
      _k(src, 'serverId', 'server_id'): model.serverId,
      _k(src, 'roomNumber', 'room_number'): model.roomNumber,
      _k(src, 'guestName', 'guest_name'): model.guestName,
      _k(src, 'nationality', 'nationality'): model.nationality,
      _k(src, 'idNumber', 'id_number'): model.idNumber,
      _k(src, 'idType', 'id_type'): model.idType,
      _k(src, 'issueDate', 'issue_date'): model.issueDate,
      _k(src, 'issuePlace', 'issue_place'): model.issuePlace,
      _k(src, 'governorate', 'governorate'): model.governorate,
      _k(src, 'notes', 'notes'): model.notes,
      _k(src, 'createdAt', 'created_at'): model.createdAt,
      _k(src, 'updatedAt', 'updated_at'): model.updatedAt,
      _k(src, 'deletedAt', 'deleted_at'): model.deletedAt,
      _k(src, 'lastModified', 'last_modified'): model.lastModified,
      _k(src, 'createdAtIso', 'created_at_iso'): model.createdAtIso,
      _k(src, 'updatedAtIso', 'updated_at_iso'): model.updatedAtIso,
      _k(src, 'deletedAtIso', 'deleted_at_iso'): model.deletedAtIso,
      _k(src, 'createdAtEpoch', 'created_at_epoch'): model.createdAtEpoch,
      _k(src, 'lastModifiedEpoch', 'last_modified_epoch'):
          model.lastModifiedEpoch,
      _k(src, 'version', 'version'): model.version,
      _k(src, 'origin', 'origin'): model.origin,
      _k(src, 'vectorClock', 'vector_clock'): jsonEncode(
        model.vectorClock ?? {},
      ),
    };
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────

d.Value<int> _vInt(
  Map<String, dynamic> json,
  String key,
  Source src, {
  String? altKey,
  int? fallback,
}) {
  final v =
      _asInt(json, key, src) ??
      (altKey != null ? _asInt(json, altKey, src) : null) ??
      fallback;
  return v == null ? const d.Value.absent() : d.Value(v);
}

d.Value<String> _vStr(
  Map<String, dynamic> json,
  String key,
  Source src, {
  String? altKey,
  String? fallback,
}) {
  final v =
      _asString(json, key, src) ??
      (altKey != null ? _asString(json, altKey, src) : null) ??
      fallback;
  return v == null ? const d.Value.absent() : d.Value(v);
}

d.Value<Map<String, dynamic>> _vMapJson(
  Map<String, dynamic> json,
  String key,
  Source src, {
  String? altKey,
  Map<String, dynamic>? fallback,
}) {
  final v =
      _asMap(json, key, src) ??
      (altKey != null ? _asMap(json, altKey, src) : null) ??
      fallback;
  return v == null ? const d.Value.absent() : d.Value(v);
}

Map<String, dynamic>? _asMap(
  Map<String, dynamic> json,
  String key,
  Source src,
) {
  final v = _raw(json, key, src);
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return Map<String, dynamic>.from(v);
  if (v is String) {
    try {
      final decoded = jsonDecode(v);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
  }
  return null;
}

int? _epoch(Map<String, dynamic> json, String key, Source src) {
  final v = _asInt(json, key, src);
  if (v != null) return v;
  final s = _asString(json, key, src);
  if (s == null) return null;
  final parsed = int.tryParse(s);
  if (parsed != null) return parsed;
  final normalized = s.contains('T') ? s : s.replaceFirst(' ', 'T');
  try {
    return DateTime.parse(normalized).millisecondsSinceEpoch ~/ 1000;
  } catch (_) {
    return null;
  }
}

int? _asInt(Map<String, dynamic> json, String key, Source src) {
  final v = _raw(json, key, src);
  if (v is bool) return v ? 1 : 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) {
    if (v.contains('-') || v.length > 20) return null;
    return int.tryParse(v);
  }
  return null;
}

String? _asString(Map<String, dynamic> json, String key, Source src) {
  final v = _raw(json, key, src);
  if (v == null) return null;
  return v.toString();
}

Object? _raw(Map<String, dynamic> json, String key, Source src) {
  if (json.containsKey(key)) return json[key];
  final alt = _altKey(key, src);
  if (alt != null && json.containsKey(alt)) return json[alt];
  return null;
}

String _k(Source src, String camel, String snake) =>
    src == Source.drive ? snake : camel;

String? _altKey(String camel, Source src) {
  if (src == Source.drive) return camel;
  final buf = StringBuffer();
  for (var i = 0; i < camel.length; i++) {
    final c = camel[i];
    if (c.toUpperCase() == c && c.toLowerCase() != c) {
      buf.write('_');
      buf.write(c.toLowerCase());
    } else {
      buf.write(c);
    }
  }
  return buf.toString();
}
