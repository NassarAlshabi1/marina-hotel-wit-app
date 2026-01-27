import 'package:drift/drift.dart' as d;

import '../local_db.dart';
import '../../utils/id.dart';
import '../../utils/time.dart';
import 'entity_adapter.dart';
import 'id_resolver.dart';
import 'resolve_result.dart';
import 'source.dart';

class RoomsAdapter extends EntityAdapter<Room, RoomsCompanion> {
  RoomsAdapter(this.resolver);
  final IdResolver resolver;

  @override
  String get collectionId => 'rooms';

  @override
  String get drivePath => 'rooms.json';

  @override
  String get tableName => 'rooms';

  @override
  Future<ResolveResult> resolveRefs(AppDatabase db, Map<String, dynamic> json,
      {required Source src}) async {
    final createdAt = _epoch(json, 'createdAt', src);
    final lastModified = _epoch(json, 'lastModified', src);
    return ResolveResult(
        createdAtEpoch: createdAt, lastModifiedEpoch: lastModified);
  }

  @override
  RoomsCompanion fromJson(Map<String, dynamic> json,
      {required Source src, required ResolveResult refs}) {
    final now = Time.nowEpoch();
    final createdAt =
        refs.createdAtEpoch ?? _epoch(json, 'createdAt', src) ?? now;
    final lastModified = refs.lastModifiedEpoch ??
        _epoch(json, 'lastModified', src) ??
        createdAt;
    return RoomsCompanion(
      id: _vInt(json, 'id', src),
      localUuid: d.Value(_asString(json, 'localUuid', src) ??
          _asString(json, 'local_uuid', src) ??
          IdGen.uuid()),
      serverId: _vInt(json, 'serverId', src),
      roomNumber: _vStr(json, 'roomNumber', src) ??
          _vStr(json, 'room_number', src) ??
          const d.Value.absent(),
      type: _vStr(json, 'type', src) ?? const d.Value.absent(),
      price: _vDouble(json, 'price', src) ?? const d.Value(0.0),
      status: _vStr(json, 'status', src) ?? const d.Value.absent(),
      imageUrl: _vStr(json, 'imageUrl', src) ?? _vStr(json, 'image_url', src),
      cleaningStatus: _vStr(json, 'cleaningStatus', src) ??
          _vStr(json, 'cleaning_status', src) ??
          const d.Value('clean'),
      lastCleanedHotelDay: _vStr(json, 'lastCleanedHotelDay', src) ??
          _vStr(json, 'last_cleaned_hotel_day', src),
      lastOccupiedHotelDay: _vStr(json, 'lastOccupiedHotelDay', src) ??
          _vStr(json, 'last_occupied_hotel_day', src),
      requiresMaintenance:
          _vBool(json, 'requiresMaintenance', src) ?? const d.Value(false),
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
  Map<String, dynamic> toJson(Room model, {required Source src}) {
    return {
      _k(src, 'id', 'id'): model.id,
      _k(src, 'localUuid', 'local_uuid'): model.localUuid,
      _k(src, 'serverId', 'server_id'): model.serverId,
      _k(src, 'roomNumber', 'room_number'): model.roomNumber,
      _k(src, 'type', 'type'): model.type,
      _k(src, 'price', 'price'): model.price,
      _k(src, 'status', 'status'): model.status,
      _k(src, 'imageUrl', 'image_url'): model.imageUrl,
      _k(src, 'cleaningStatus', 'cleaning_status'): model.cleaningStatus,
      _k(src, 'lastCleanedHotelDay', 'last_cleaned_hotel_day'):
          model.lastCleanedHotelDay,
      _k(src, 'lastOccupiedHotelDay', 'last_occupied_hotel_day'):
          model.lastOccupiedHotelDay,
      _k(src, 'requiresMaintenance', 'requires_maintenance'):
          model.requiresMaintenance,
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

d.Value<double?> _vDouble(Map<String, dynamic> json, String key, Source src) {
  final v = _asDouble(json, key, src);
  return v == null ? const d.Value.absent() : d.Value(v);
}

d.Value<bool?> _vBool(Map<String, dynamic> json, String key, Source src) {
  final v = _asBool(json, key, src);
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

bool? _asBool(Map<String, dynamic> json, String key, Source src) {
  final v = _raw(json, key, src);
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final t = v.toLowerCase();
    if (t == 'true' || t == '1') return true;
    if (t == 'false' || t == '0') return false;
  }
  return null;
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
