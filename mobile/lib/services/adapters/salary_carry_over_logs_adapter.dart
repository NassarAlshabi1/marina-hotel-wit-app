import 'package:drift/drift.dart' as d;

import '../../utils/id.dart';
import '../../utils/time.dart';
import '../local_db.dart';
import 'entity_adapter.dart';
import 'id_resolver.dart';
import 'resolve_result.dart';
import 'source.dart';

class SalaryCarryOverLogsAdapter
    extends EntityAdapter<SalaryCarryOverLog, SalaryCarryOverLogsCompanion> {
  SalaryCarryOverLogsAdapter(this.resolver);
  final IdResolver resolver;

  @override
  String get collectionId => 'salary_carry_over_logs';

  @override
  String get drivePath => 'salary_carry_over_logs.json';

  @override
  String get tableName => 'salary_carry_over_logs';

  @override
  Future<ResolveResult> resolveRefs(
    AppDatabase db,
    Map<String, dynamic> json, {
    required Source src,
  }) async {
    return ResolveResult.empty;
  }

  @override
  SalaryCarryOverLogsCompanion fromJson(
    Map<String, dynamic> json, {
    required Source src,
    required ResolveResult refs,
  }) {
    final now = Time.nowEpoch();
    return SalaryCarryOverLogsCompanion(
      id: _vInt(json, 'id', src),
      localUuid: d.Value(
        _asString(json, 'localUuid', src) ??
            _asString(json, 'local_uuid', src) ??
            IdGen.uuid(),
      ),
      employeeId: _vInt(json, 'employeeId', src, altKey: 'employee_id'),
      amount: d.Value(_asDouble(json, 'amount', src) ?? 0),
      previousCycleStart: d.Value(
          _asString(json, 'previousCycleStart', src) ??
          _asString(json, 'previous_cycle_start', src) ??
          ''),
      previousCycleEnd: d.Value(
          _asString(json, 'previousCycleEnd', src) ??
          _asString(json, 'previous_cycle_end', src) ??
          ''),
      newCycleStart: d.Value(
          _asString(json, 'newCycleStart', src) ??
          _asString(json, 'new_cycle_start', src) ??
          ''),
      newCycleEnd: d.Value(
          _asString(json, 'newCycleEnd', src) ??
          _asString(json, 'new_cycle_end', src) ??
          ''),
      reason: d.Value(_asString(json, 'reason', src) ?? ''),
      carriedAt: d.Value(_asInt(json, 'carriedAt', src) ?? now),
      createdAt: d.Value(_asInt(json, 'createdAt', src) ?? now),
      updatedAt: d.Value(_asInt(json, 'updatedAt', src) ?? now),
      deletedAt: _vInt(json, 'deletedAt', src),
      createdAtIso: _vStr(json, 'createdAtIso', src),
      updatedAtIso: _vStr(json, 'updatedAtIso', src),
      deletedAtIso: _vStr(json, 'deletedAtIso', src),
      createdAtEpoch: d.Value(_asInt(json, 'createdAtEpoch', src) ?? 0),
      lastModifiedEpoch:
          d.Value(_asInt(json, 'lastModifiedEpoch', src) ?? 0),
      version: _vInt(json, 'version', src, fallback: 1),
      origin: src == Source.appwrite || src == Source.drive
          ? const d.Value('server')
          : _vStr(json, 'origin', src, fallback: 'server'),
      vectorClock: _vStr(json, 'vectorClock', src,
          altKey: 'vector_clock', fallback: '{}'),
      idempotencyKey: _vStr(json, 'idempotencyKey', src, altKey: 'idempotency_key'),
      deviceId: _vStr(json, 'deviceId', src, altKey: 'device_id', fallback: ''),
    );
  }

  @override
  Map<String, dynamic> toJson(SalaryCarryOverLog model, {required Source src}) {
    return {
      _k(src, 'id', 'id'): model.id,
      _k(src, 'localUuid', 'local_uuid'): model.localUuid,
      _k(src, 'employeeId', 'employee_id'): model.employeeId,
      _k(src, 'amount', 'amount'): model.amount,
      _k(src, 'previousCycleStart', 'previous_cycle_start'):
          model.previousCycleStart,
      _k(src, 'previousCycleEnd', 'previous_cycle_end'):
          model.previousCycleEnd,
      _k(src, 'newCycleStart', 'new_cycle_start'): model.newCycleStart,
      _k(src, 'newCycleEnd', 'new_cycle_end'): model.newCycleEnd,
      _k(src, 'reason', 'reason'): model.reason,
      _k(src, 'carriedAt', 'carried_at'): model.carriedAt,
      _k(src, 'createdAt', 'created_at'): model.createdAt,
      _k(src, 'createdAtEpoch', 'created_at_epoch'): model.createdAtEpoch,
      _k(src, 'createdAtIso', 'created_at_iso'): model.createdAtIso,
      _k(src, 'updatedAt', 'updated_at'): model.updatedAt,
      _k(src, 'updatedAtIso', 'updated_at_iso'): model.updatedAtIso,
      _k(src, 'deletedAt', 'deleted_at'): model.deletedAt,
      _k(src, 'deletedAtIso', 'deleted_at_iso'): model.deletedAtIso,
      _k(src, 'lastModifiedEpoch', 'last_modified_epoch'):
          model.lastModifiedEpoch,
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
  final v = _asInt(json, key, src) ??
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
  final v = _asString(json, key, src) ??
      (altKey != null ? _asString(json, altKey, src) : null) ??
      fallback;
  return v == null ? const d.Value.absent() : d.Value(v);
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

double? _asDouble(Map<String, dynamic> json, String key, Source src) {
  final v = _raw(json, key, src);
  if (v is double) return v;
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
