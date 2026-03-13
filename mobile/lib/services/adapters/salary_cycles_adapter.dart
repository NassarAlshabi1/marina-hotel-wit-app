import 'package:drift/drift.dart' as d;

import '../local_db.dart';
import '../../utils/id.dart';
import '../../utils/time.dart';
import 'entity_adapter.dart';
import 'id_resolver.dart';
import 'resolve_result.dart';
import 'source.dart';

class SalaryCyclesAdapter
    extends EntityAdapter<SalaryCycle, SalaryCyclesCompanion> {
  SalaryCyclesAdapter(this.resolver);
  final IdResolver resolver;

  @override
  String get collectionId => 'salary_cycles';

  @override
  String get drivePath => 'salary_cycles.json';

  @override
  String get tableName => 'salary_cycles';

  @override
  Future<ResolveResult> resolveRefs(
    AppDatabase db,
    Map<String, dynamic> json, {
    required Source src,
  }) async {
    final createdAt = _epoch(json, 'createdAt', src);
    final lastModified = _epoch(json, 'lastModified', src);
    return ResolveResult(
      createdAtEpoch: createdAt,
      lastModifiedEpoch: lastModified,
    );
  }

  @override
  SalaryCyclesCompanion fromJson(
    Map<String, dynamic> json, {
    required Source src,
    required ResolveResult refs,
  }) {
    final now = Time.nowEpoch();
    final createdAt =
        refs.createdAtEpoch ?? _epoch(json, 'createdAt', src) ?? now;
    final lastModified = refs.lastModifiedEpoch ??
        _epoch(json, 'lastModified', src) ??
        createdAt;
    return SalaryCyclesCompanion(
      id: _vInt(json, 'id', src),
      localUuid: d.Value(
        _asString(json, 'localUuid', src) ??
            _asString(json, 'localUuid', src) ??
            IdGen.uuid(),
      ),
      serverId: _vInt(json, 'serverId', src),
      employeeId: _vInt(
        json,
        'employeeId',
        src,
        altKey: 'employee_id',
        fallback: 0,
      ),
      cycleKey: _vStr(json, 'cycleKey', src, altKey: 'cycle_key', fallback: ''),
      hotelDayStart: _vStr(
        json,
        'hotelDayStart',
        src,
        altKey: 'hotel_day_start',
        fallback: '',
      ),
      hotelDayEnd: _vStr(
        json,
        'hotelDayEnd',
        src,
        altKey: 'hotel_day_end',
        fallback: '',
      ),
      expectedAmount: _vInt(
        json,
        'expectedAmount',
        src,
        altKey: 'expected_amount',
        fallback: 0,
      ),
      actualPaid: _vInt(
        json,
        'actualPaid',
        src,
        altKey: 'actual_paid',
        fallback: 0,
      ),
      remainingAmount: _vInt(
        json,
        'remainingAmount',
        src,
        altKey: 'remaining_amount',
        fallback: 0,
      ),
      status: _vStr(json, 'status', src, fallback: 'draft'),
      createdAt: d.Value(createdAt),
      updatedAt: d.Value(_epoch(json, 'updatedAt', src) ?? createdAt),
      deletedAt: _vInt(json, 'deletedAt', src),
      lastModified: d.Value(lastModified),
      createdAtIso: _vStr(json, 'createdAtIso', src),
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
      vectorClock: _vStr(
        json,
        'vectorClock',
        src,
        altKey: 'vectorClock',
        fallback: '{}',
      ),
    );
  }

  @override
  Map<String, dynamic> toJson(SalaryCycle model, {required Source src}) {
    return {
      _k(src, 'id'): model.id,
      _k(src, 'localUuid'): model.localUuid,
      _k(src, 'serverId'): model.serverId,
      _k(src, 'employeeId'): model.employeeId,
      _k(src, 'cycleKey'): model.cycleKey,
      _k(src, 'hotelDayStart'): model.hotelDayStart,
      _k(src, 'hotelDayEnd'): model.hotelDayEnd,
      _k(src, 'expectedAmount'): model.expectedAmount,
      _k(src, 'actualPaid'): model.actualPaid,
      _k(src, 'remainingAmount'): model.remainingAmount,
      _k(src, 'status'): model.status,
      _k(src, 'createdAt'): model.createdAt,
      _k(src, 'updatedAt'): model.updatedAt,
      _k(src, 'deletedAt'): model.deletedAt,
      _k(src, 'lastModified'): model.lastModified,
      _k(src, 'version'): model.version,
      _k(src, 'origin'): model.origin,
      _k(src, 'vectorClock'): model.vectorClock,
    };
  }
}

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

int? _epoch(Map<String, dynamic> json, String key, Source src) {
  final v = _asInt(json, key, src);
  if (v != null) return v;
  final s = _asString(json, key, src);
  if (s == null) return null;
  return int.tryParse(s);
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

String _k(Source src, String camel) => camel; // camelCase only
// removed:

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
