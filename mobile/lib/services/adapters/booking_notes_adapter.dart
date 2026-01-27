import 'package:drift/drift.dart' as d;

import '../local_db.dart';
import '../../utils/id.dart';
import '../../utils/time.dart';
import 'entity_adapter.dart';
import 'id_resolver.dart';
import 'resolve_result.dart';
import 'source.dart';

class BookingNotesAdapter
    extends EntityAdapter<BookingNote, BookingNotesCompanion> {
  BookingNotesAdapter(this.resolver);
  final IdResolver resolver;

  @override
  String get collectionId => 'booking_notes';

  @override
  String get drivePath => 'booking_notes.json';

  @override
  String get tableName => 'booking_notes';

  @override
  Future<ResolveResult> resolveRefs(AppDatabase db, Map<String, dynamic> json,
      {required Source src}) async {
    final bookingUuid = _asString(json, 'bookingUuidCache', src) ??
        _asString(json, 'booking_uuid_cache', src) ??
        _asString(json, 'booking_uuid', src);
    final bookingLocalId =
        _asInt(json, 'bookingId', src) ?? _asInt(json, 'booking_id', src);
    final resolvedId = await resolver.resolveBooking(
        localId: bookingLocalId, serverId: null, uuid: bookingUuid);
    final createdAt = _epoch(json, 'createdAt', src);
    final lastModified = _epoch(json, 'lastModified', src);
    return ResolveResult(
      bookingLocalId: resolvedId,
      bookingUuidCache: bookingUuid,
      createdAtEpoch: createdAt,
      lastModifiedEpoch: lastModified,
    );
  }

  @override
  BookingNotesCompanion fromJson(Map<String, dynamic> json,
      {required Source src, required ResolveResult refs}) {
    final now = Time.nowEpoch();
    final createdAt =
        refs.createdAtEpoch ?? _epoch(json, 'createdAt', src) ?? now;
    final lastModified = refs.lastModifiedEpoch ??
        _epoch(json, 'lastModified', src) ??
        createdAt;
    return BookingNotesCompanion(
      id: _vInt(json, 'id', src),
      localUuid: d.Value(_asString(json, 'localUuid', src) ??
          _asString(json, 'local_uuid', src) ??
          IdGen.uuid()),
      serverId: _vInt(json, 'serverId', src),
      bookingId: refs.bookingLocalId != null
          ? d.Value(refs.bookingLocalId!)
          : _vInt(json, 'bookingId', src) ?? _vInt(json, 'booking_id', src),
      noteText: _vStr(json, 'noteText', src) ??
          _vStr(json, 'note_text', src) ??
          const d.Value(''),
      alertType: _vStr(json, 'alertType', src) ??
          _vStr(json, 'alert_type', src) ??
          const d.Value(''),
      alertUntil:
          _vStr(json, 'alertUntil', src) ?? _vStr(json, 'alert_until', src),
      isActive: _vInt(json, 'isActive', src) ?? const d.Value(1),
      createdAt: d.Value(createdAt),
      updatedAt: d.Value(_epoch(json, 'updatedAt', src) ?? createdAt),
      deletedAt: _vInt(json, 'deletedAt', src),
      lastModified: d.Value(lastModified),
      createdAtIso: _vStr(json, 'createdAtIso', src),
      updatedAtIso: _vStr(json, 'updatedAtIso', src),
      deletedAtIso: _vStr(json, 'deletedAtIso', src),
      createdAtEpoch: _vInt(json, 'createdAtEpoch', src) ?? d.Value(createdAt),
      lastModifiedEpoch:
          _vInt(json, 'lastModifiedEpoch', src) ?? d.Value(lastModified),
      version: _vInt(json, 'version', src) ?? const d.Value(1),
      origin: _vStr(json, 'origin', src) ?? const d.Value('server'),
      vectorClock: _vStr(json, 'vectorClock', src) ??
          _vStr(json, 'vector_clock', src) ??
          const d.Value('{}'),
    );
  }

  @override
  Map<String, dynamic> toJson(BookingNote model, {required Source src}) {
    return {
      _k(src, 'id', 'id'): model.id,
      _k(src, 'localUuid', 'local_uuid'): model.localUuid,
      _k(src, 'serverId', 'server_id'): model.serverId,
      _k(src, 'bookingId', 'booking_id'): model.bookingId,
      _k(src, 'noteText', 'note_text'): model.noteText,
      _k(src, 'alertType', 'alert_type'): model.alertType,
      _k(src, 'alertUntil', 'alert_until'): model.alertUntil,
      _k(src, 'isActive', 'is_active'): model.isActive,
      _k(src, 'createdAt', 'created_at'): model.createdAt,
      _k(src, 'updatedAt', 'updated_at'): model.updatedAt,
      _k(src, 'deletedAt', 'deleted_at'): model.deletedAt,
      _k(src, 'lastModified', 'last_modified'): model.lastModified,
      _k(src, 'version', 'version'): model.version,
      _k(src, 'origin', 'origin'): model.origin,
      _k(src, 'vectorClock', 'vector_clock'): model.vectorClock,
    };
  }
}

d.Value<int?> _vInt(Map<String, dynamic> json, String key, Source src) {
  final v = _asInt(json, key, src);
  return v == null ? const d.Value.absent() : d.Value(v);
}

d.Value<String?> _vStr(Map<String, dynamic> json, String key, Source src) {
  final v = _asString(json, key, src);
  return v == null ? const d.Value.absent() : d.Value(v);
}

int? _epoch(Map<String, dynamic> json, String key, Source src) {
  final v = _asInt(json, key, src);
  if (v != null) return v;
  final s = _asString(json, key, src);
  if (s == null) return null;
  return int.tryParse(s);
}

int? _asInt(Map<String, dynamic> json, String key, Source src) {
  final v = _raw(json, key, src);
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

double? _asDouble(Map<String, dynamic> json, String key, Source src) {
  final v = _raw(json, key, src);
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
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
