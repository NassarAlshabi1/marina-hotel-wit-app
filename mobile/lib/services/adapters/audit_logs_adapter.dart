import 'package:drift/drift.dart' as d;

import '../../utils/id.dart';
import '../../utils/time.dart';
import '../local_db.dart';
import 'entity_adapter.dart';
import 'id_resolver.dart';
import 'resolve_result.dart';
import 'source.dart';

class AuditLogsAdapter extends EntityAdapter<AuditLog, AuditLogsCompanion> {
  AuditLogsAdapter(this.resolver);
  final IdResolver resolver;

  @override
  String get collectionId => 'audit_logs';

  @override
  String get drivePath => 'audit_logs.json';

  @override
  String get tableName => 'audit_logs';

  @override
  Future<ResolveResult> resolveRefs(AppDatabase db, Map<String, dynamic> json, {required Source src}) async {
    final createdAt = _epoch(json, 'createdAt', src);
    return ResolveResult(createdAtEpoch: createdAt);
  }

  @override
  AuditLogsCompanion fromJson(Map<String, dynamic> json, {required Source src, required ResolveResult refs}) {
    final now = Time.nowEpoch();
    final createdAt = refs.createdAtEpoch ?? _epoch(json, 'createdAt', src) ?? now;
    final timestamp = _epoch(json, 'timestamp', src) ?? createdAt;

    return AuditLogsCompanion(
      id: _vInt(json, 'id', src),
      localUuid: d.Value(_asString(json, 'localUuid', src) ?? _asString(json, 'local_uuid', src) ?? IdGen.uuid()),
      operationType: _vStr(json, 'operationType', src, altKey: 'operation_type', fallback: ''),
      entityType: _vStr(json, 'entityType', src, altKey: 'entity_type', fallback: ''),
      entityUuid: _vStr(json, 'entityUuid', src, altKey: 'entity_uuid', fallback: ''),
      entityId: _vInt(json, 'entityId', src, altKey: 'entity_id'),
      previousState: _vStr(json, 'previousState', src, altKey: 'previous_state'),
      newState: _vStr(json, 'newState', src, altKey: 'new_state'),
      changedFields: _vStr(json, 'changedFields', src, altKey: 'changed_fields'),
      performedBy: _vStr(json, 'performedBy', src, altKey: 'performed_by', fallback: ''),
      deviceId: _vStr(json, 'deviceId', src, altKey: 'device_id', fallback: ''),
      ipAddress: _vStr(json, 'ipAddress', src, altKey: 'ip_address'),
      hotelDayKey: _vStr(json, 'hotelDayKey', src, altKey: 'hotel_day_key', fallback: ''),
      timestamp: d.Value(timestamp),
      timestampIso: _vStr(
        json,
        'timestampIso',
        src,
        altKey: 'timestamp_iso',
        fallback: DateTime.fromMillisecondsSinceEpoch(timestamp * 1000).toIso8601String(),
      ),
      isFinancial: _vBool(json, 'isFinancial', src, altKey: 'is_financial', fallback: false),
      amountImpact: _vInt(json, 'amountImpact', src, altKey: 'amount_impact'),
      createdAt: d.Value(createdAt),
    );
  }

  @override
  Map<String, dynamic> toJson(AuditLog model, {required Source src}) {
    return {
      _k(src, 'id', 'id'): model.id,
      _k(src, 'localUuid', 'local_uuid'): model.localUuid,
      _k(src, 'operationType', 'operation_type'): model.operationType,
      _k(src, 'entityType', 'entity_type'): model.entityType,
      _k(src, 'entityUuid', 'entity_uuid'): model.entityUuid,
      _k(src, 'entityId', 'entity_id'): model.entityId,
      _k(src, 'previousState', 'previous_state'): model.previousState,
      _k(src, 'newState', 'new_state'): model.newState,
      _k(src, 'changedFields', 'changed_fields'): model.changedFields,
      _k(src, 'performedBy', 'performed_by'): model.performedBy,
      _k(src, 'deviceId', 'device_id'): model.deviceId,
      _k(src, 'ipAddress', 'ip_address'): model.ipAddress,
      _k(src, 'hotelDayKey', 'hotel_day_key'): model.hotelDayKey,
      _k(src, 'timestamp', 'timestamp'): model.timestamp,
      _k(src, 'timestampIso', 'timestamp_iso'): model.timestampIso,
      _k(src, 'isFinancial', 'is_financial'): model.isFinancial,
      _k(src, 'amountImpact', 'amount_impact'): model.amountImpact,
      _k(src, 'createdAt', 'created_at'): model.createdAt,
    };
  }
}

d.Value<int> _vInt(Map<String, dynamic> json, String key, Source src, {String? altKey, int? fallback}) {
  final v = _asInt(json, key, src) ?? (altKey != null ? _asInt(json, altKey, src) : null) ?? fallback;
  return v == null ? const d.Value.absent() : d.Value(v);
}

d.Value<String> _vStr(Map<String, dynamic> json, String key, Source src, {String? altKey, String? fallback}) {
  final v = _asString(json, key, src) ?? (altKey != null ? _asString(json, altKey, src) : null) ?? fallback;
  return v == null ? const d.Value.absent() : d.Value(v);
}

d.Value<bool> _vBool(Map<String, dynamic> json, String key, Source src, {String? altKey, bool? fallback}) {
  final v = _asBool(json, key, src) ?? (altKey != null ? _asBool(json, altKey, src) : null) ?? fallback;
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
  return int.tryParse(s);
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

bool? _asBool(Map<String, dynamic> json, String key, Source src) {
  final v = _raw(json, key, src);
  if (v is bool) {
    return v;
  }
  if (v is num) {
    return v != 0;
  }
  if (v is String) {
    final t = v.toLowerCase();
    if (t == 'true' || t == '1') {
      return true;
    }
    if (t == 'false' || t == '0') {
      return false;
    }
  }
  return null;
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

String _k(Source src, String camel, String snake) => src == Source.drive ? snake : camel;

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
