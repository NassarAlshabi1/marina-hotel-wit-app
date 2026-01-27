import 'package:drift/drift.dart' as d;

import '../local_db.dart';
import '../../utils/id.dart';
import '../../utils/time.dart';
import 'entity_adapter.dart';
import 'id_resolver.dart';
import 'resolve_result.dart';
import 'source.dart';

class EmployeesAdapter extends EntityAdapter<Employee, EmployeesCompanion> {
  EmployeesAdapter(this.resolver);
  final IdResolver resolver;

  @override
  String get collectionId => 'employees';

  @override
  String get drivePath => 'employees.json';

  @override
  String get tableName => 'employees';

  @override
  Future<ResolveResult> resolveRefs(AppDatabase db, Map<String, dynamic> json, {required Source src}) async {
    final createdAt = _epoch(json, 'createdAt', src);
    final lastModified = _epoch(json, 'lastModified', src);
    return ResolveResult(createdAtEpoch: createdAt, lastModifiedEpoch: lastModified);
  }

  @override
  EmployeesCompanion fromJson(Map<String, dynamic> json, {required Source src, required ResolveResult refs}) {
    final now = Time.nowEpoch();
    final createdAt = refs.createdAtEpoch ?? _epoch(json, 'createdAt', src) ?? now;
    final lastModified = refs.lastModifiedEpoch ?? _epoch(json, 'lastModified', src) ?? createdAt;
    return EmployeesCompanion(
      id: _vInt(json, 'id', src),
      localUuid: d.Value(_asString(json, 'localUuid', src) ?? _asString(json, 'local_uuid', src) ?? IdGen.uuid()),
      serverId: _vInt(json, 'serverId', src),
      name: _vStr(json, 'name', src) ?? const d.Value.absent(),
      basicSalary: _vDouble(json, 'basicSalary', src) ?? _vDouble(json, 'basic_salary', src) ?? const d.Value(0.0),
      position: _vStr(json, 'position', src) ?? const d.Value(''),
      phone: _vStr(json, 'phone', src) ?? const d.Value(''),
      hireDate: _vStr(json, 'hireDate', src) ?? _vStr(json, 'hire_date', src) ?? const d.Value(''),
      status: _vStr(json, 'status', src) ?? const d.Value(''),
      createdAt: d.Value(createdAt),
      updatedAt: d.Value(_epoch(json, 'updatedAt', src) ?? createdAt),
      deletedAt: _vInt(json, 'deletedAt', src),
      lastModified: d.Value(lastModified),
      createdAtIso: _vStr(json, 'createdAtIso', src),
      updatedAtIso: _vStr(json, 'updatedAtIso', src),
      deletedAtIso: _vStr(json, 'deletedAtIso', src),
      createdAtEpoch: _vInt(json, 'createdAtEpoch', src) ?? d.Value(createdAt),
      lastModifiedEpoch: _vInt(json, 'lastModifiedEpoch', src) ?? d.Value(lastModified),
      version: _vInt(json, 'version', src) ?? const d.Value(1),
      origin: _vStr(json, 'origin', src) ?? const d.Value('server'),
      vectorClock: _vStr(json, 'vectorClock', src) ?? _vStr(json, 'vector_clock', src) ?? const d.Value('{}'),
    );
  }

  @override
  Map<String, dynamic> toJson(Employee model, {required Source src}) {
    return {
      _k(src, 'id', 'id'): model.id,
      _k(src, 'localUuid', 'local_uuid'): model.localUuid,
      _k(src, 'serverId', 'server_id'): model.serverId,
      _k(src, 'name', 'name'): model.name,
      _k(src, 'basicSalary', 'basic_salary'): model.basicSalary,
      _k(src, 'position', 'position'): model.position,
      _k(src, 'phone', 'phone'): model.phone,
      _k(src, 'hireDate', 'hire_date'): model.hireDate,
      _k(src, 'status', 'status'): model.status,
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

String _k(Source src, String camel, String snake) => src == Source.drive ? snake : camel;

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
