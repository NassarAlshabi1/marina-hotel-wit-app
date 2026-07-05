import 'package:drift/drift.dart' as d;

import '../../utils/id.dart';
import '../../utils/time.dart';
import '../local_db.dart';
import 'entity_adapter.dart';
import 'id_resolver.dart';
import 'resolve_result.dart';
import 'source.dart';

class ShiftNotesAdapter extends EntityAdapter<ShiftNote, ShiftNotesCompanion> {
  ShiftNotesAdapter(this.resolver);
  final IdResolver resolver;

  @override
  String get collectionId => 'shift_notes';

  @override
  String get drivePath => 'shift_notes.json';

  @override
  String get tableName => 'shift_notes';

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
      bookingUuidCache: uuid,
      createdAtEpoch: createdAt,
      lastModifiedEpoch: lastModified,
    );
  }

  @override
  ShiftNotesCompanion fromJson(
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

    return ShiftNotesCompanion(
      id: _vInt(json, 'id', src),
      localUuid: d.Value(refs.bookingUuidCache ?? IdGen.uuid()),
      serverId: _vInt(json, 'serverId', src),
      title: _vStr(json, 'title', src),
      content: _vStr(json, 'content', src),
      priority: _vStr(json, 'priority', src, fallback: 'medium'),
      shiftType: _vStr(
        json,
        'shiftType',
        src,
        altKey: 'shift_type',
        fallback: 'all',
      ),
      isRead: _vInt(json, 'isRead', src, altKey: 'is_read', fallback: 0),
      createdBy: _vStr(
        json,
        'createdBy',
        src,
        altKey: 'created_by',
        fallback: 'user',
      ),
      expiresAt: _vStr(json, 'expiresAt', src, altKey: 'expires_at'),
      createdAt: d.Value(createdAt),
      updatedAt: d.Value(_epoch(json, 'updatedAt', src) ?? createdAt),
      deletedAt: _vInt(json, 'deletedAt', src),
      lastModified: d.Value(lastModified),
      // ✅ إصلاح (audit agent-3): إضافة createdAtEpoch و lastModifiedEpoch
      // كانا مفقودين من fromJson → يُخزّنان كـ 0 افتراضياً → يُفقدان عند السحب
      createdAtEpoch: d.Value(_asInt(json, 'createdAtEpoch', src) ?? createdAt),
      lastModifiedEpoch: d.Value(_asInt(json, 'lastModifiedEpoch', src) ?? lastModified),
      createdAtIso: _vStr(
        json,
        'createdAtIso',
        src,
        fallback: _asString(json, 'createdAt', src),
      ),
      updatedAtIso: _vStr(json, 'updatedAtIso', src),
      deletedAtIso: _vStr(json, 'deletedAtIso', src),
      version: _vInt(json, 'version', src, fallback: 1),
      // ✅ إصلاح: عند src=Source.appwrite، نصر على origin='server' دائماً
      // لمنع مشكلة أن البيانات المسحوبة من السيرفر تحمل origin='mobile'
      // مما يمنع _cleanupOutboxAfterPull من تنظيف عناصر outbox بشكل صحيح
      origin: src == Source.appwrite || src == Source.drive
          ? const d.Value('server')
          : _vStr(json, 'origin', src, fallback: 'server'),
      vectorClock: _vStr(json, 'vectorClock', src, altKey: 'vector_clock', fallback: '{}'),
      idempotencyKey: _vStr(json, 'idempotencyKey', src, altKey: 'idempotency_key'),
      deviceId: _vStr(json, 'deviceId', src, altKey: 'device_id', fallback: ''),
    );
  }

  @override
  Map<String, dynamic> toJson(ShiftNote model, {required Source src}) {
    if (src == Source.appwrite) {
      final createdDate = DateTime.fromMillisecondsSinceEpoch(
        model.createdAt * 1000,
      );
      // shiftDate مطلوب في Appwrite — نأخذه من تاريخ الإنشاء
      final shiftDate = createdDate.toIso8601String().substring(0, 10);
      return {
        'localUuid': model.localUuid,
        'title': model.title,
        'content': model.content,
        'priority': model.priority,
        'shiftType': model.shiftType,
        // ✅ إصلاح (P0-1): Appwrite schema يُعرّف isRead كـ boolean.
        // كنا نُرسل `model.isRead` (integer) مما يُسبب "Invalid type" errors.
        // نُحوّل integer (0/1) إلى boolean للمطابقة مع المخطط.
        // PayloadMapper أيضاً يُرسل boolean الآن (تم توحيد السلوك).
        'isRead': model.isRead == 1,
        'createdAt': model.createdAt, // Appwrite يتوقع integer epoch
        'createdAtEpoch': model.createdAtEpoch,
        'createdAtIso': model.createdAtIso,
        'updatedAt': model.updatedAt, // integer epoch — مطلوب
        'updatedAtIso': model.updatedAtIso,
        'deletedAt': model.deletedAt,
        'deletedAtIso': model.deletedAtIso,
        'lastModified': model.lastModified,
        'lastModifiedEpoch': model.lastModifiedEpoch,
        'version': model.version,
        'origin': model.origin,
        'vectorClock': model.vectorClock,
        'idempotencyKey': model.idempotencyKey,
      'deviceId': model.deviceId,
        'createdBy': model.createdBy,
        'shiftDate': shiftDate, // مطلوب — مشتق من createdAt
        'note': model.content, // مطلوب — يوازي content
        if (model.expiresAt != null && model.expiresAt!.isNotEmpty)
          'expiresAt': model.expiresAt,
      };
    }
    return {
      _k(src, 'id', 'id'): model.id,
      _k(src, 'localUuid', 'local_uuid'): model.localUuid,
      _k(src, 'serverId', 'server_id'): model.serverId,
      _k(src, 'title', 'title'): model.title,
      _k(src, 'content', 'content'): model.content,
      _k(src, 'priority', 'priority'): model.priority,
      _k(src, 'shiftType', 'shift_type'): model.shiftType,
      _k(src, 'isRead', 'is_read'): model.isRead,
      _k(src, 'createdBy', 'created_by'): model.createdBy,
      _k(src, 'expiresAt', 'expires_at'): model.expiresAt,
      _k(src, 'createdAt', 'created_at'): model.createdAt,
      _k(src, 'createdAtEpoch', 'created_at_epoch'): model.createdAtEpoch,
      _k(src, 'createdAtIso', 'created_at_iso'): model.createdAtIso,
      _k(src, 'updatedAt', 'updated_at'): model.updatedAt,
      _k(src, 'updatedAtIso', 'updated_at_iso'): model.updatedAtIso,
      _k(src, 'deletedAt', 'deleted_at'): model.deletedAt,
      _k(src, 'deletedAtIso', 'deleted_at_iso'): model.deletedAtIso,
      _k(src, 'lastModified', 'last_modified'): model.lastModified,
      _k(src, 'lastModifiedEpoch', 'last_modified_epoch'): model.lastModifiedEpoch,
      _k(src, 'version', 'version'): model.version,
      _k(src, 'origin', 'origin'): model.origin,
      _k(src, 'vectorClock', 'vector_clock'): model.vectorClock,
      'idempotencyKey': model.idempotencyKey,
      'deviceId': model.deviceId,
    };
  }
}

// Helpers
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

int? _epoch(Map<String, dynamic> json, String key, Source src) {
  final v = _asInt(json, key, src);
  if (v != null) {
    return v;
  }
  final s = _asString(json, key, src);
  if (s == null) {
    return null;
  }
  final parsed = int.tryParse(s);
  if (parsed != null) {
    return parsed;
  }
  final normalized = s.contains('T') ? s : s.replaceFirst(' ', 'T');
  try {
    return DateTime.parse(normalized).millisecondsSinceEpoch ~/ 1000;
  } catch (_) {
    return null;
  }
}

int? _asInt(Map<String, dynamic> json, String key, Source src) {
  final v = _raw(json, key, src);
  if (v is bool) {
    return v ? 1 : 0;
  }
  if (v is int) {
    return v;
  }
  if (v is num) {
    return v.toInt();
  }
  if (v is String) {
    if (v.contains('-') || v.length > 20) {
      return null;
    }
    return int.tryParse(v);
  }
  return null;
}

String? _asString(Map<String, dynamic> json, String key, Source src) {
  final v = _raw(json, key, src);
  if (v == null) {
    return null;
  }
  return v.toString();
}

Object? _raw(Map<String, dynamic> json, String key, Source src) {
  if (json.containsKey(key)) {
    return json[key];
  }
  final alt = _altKey(key, src);
  if (alt != null && json.containsKey(alt)) {
    return json[alt];
  }
  return null;
}

String _k(Source src, String camel, String snake) =>
    src == Source.drive ? snake : camel;

String? _altKey(String camel, Source src) {
  // ✅ إصلاح: تحويل camelCase → snake_case لجميع المصادر بما فيها Drive
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
