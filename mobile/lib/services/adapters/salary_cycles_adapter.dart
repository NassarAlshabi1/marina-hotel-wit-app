import 'package:drift/drift.dart' as d;

import '../../utils/id.dart';
import '../../utils/time.dart';
import '../local_db.dart';
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
    // ✅ حل FK الموظف بالترتيب: UUID -> id -> serverId -> employeeId
    final remoteEmployeeUuid = _asString(json, 'employeeUuid', src) ?? 
                               _asString(json, 'employee_uuid', src) ??
                               _asString(json, 'employeeLocalUuid', src) ??
                               _asString(json, 'employee_local_uuid', src);
    final remoteEmployeeId = _asInt(json, 'employeeId', src) ?? _asInt(json, 'employee_id', src);
    final remoteServerId = _asInt(json, 'serverId', src) ?? _asInt(json, 'server_id', src);

    final resolvedEmployeeId = await resolver.resolveEmployee(
      uuid: remoteEmployeeUuid,
      localId: remoteEmployeeId,
      serverId: remoteServerId,
      employeeId: remoteEmployeeId,
    );

    final createdAt = _epoch(json, 'createdAt', src);
    final lastModified = _epoch(json, 'lastModified', src);

    // ✅ إصلاح حرج: إذا لم يتم العثور على الموظف المرتبط، نُعلم السجل للتخطي
    // لأن employeeId حقل مطلوب (NOT NULL FK) في جدول salary_cycles
    final shouldSkip = resolvedEmployeeId == null && (src == Source.appwrite || src == Source.drive);
    final skipReason = shouldSkip
        ? 'salary_cycle: لا يمكن العثور على الموظف المرتبط '
            '(uuid=$remoteEmployeeUuid, serverId=$remoteServerId, localId=$remoteEmployeeId) '
            '— تم التخطي لتجنب InvalidDataException'
        : null;

    return ResolveResult(
      employeeLocalId: resolvedEmployeeId,
      createdAtEpoch: createdAt,
      lastModifiedEpoch: lastModified,
      shouldSkip: shouldSkip,
      skipReason: skipReason,
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
    final lastModified =
        refs.lastModifiedEpoch ??
        _epoch(json, 'lastModified', src) ??
        createdAt;
    return SalaryCyclesCompanion(
      id: _vInt(json, 'id', src),
      localUuid: d.Value(
        _asString(json, 'localUuid', src) ??
            _asString(json, 'local_uuid', src) ??
            IdGen.uuid(),
      ),
      serverId: _vInt(json, 'serverId', src),
      // ✅ إصلاح دقيق: استخدام employeeLocalId المحلول بدل القيمة الخامة
      // إذا لم يتم حل الموظف (لا يوجد محلياً — يتيم)، نتخطى الحقل بـ absent()
      // لمنع إدراج قيمة FK غير صالحة (0 أو معرّف بعيد لا يتطابق محلياً)
      employeeId: refs.employeeLocalId != null
          ? d.Value(refs.employeeLocalId!)
          : (src == Source.appwrite || src == Source.drive)
              ? const d.Value.absent() // يتيم — لا نستخدم القيمة الخامة البعيدة
              : _vInt(json, 'employeeId', src, altKey: 'employee_id', fallback: 0),
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
      // ✅ إصلاح: عند src=Source.appwrite، نصر على origin='server' دائماً
      // لمنع مشكلة أن البيانات المسحوبة من السيرفر تحمل origin='mobile'
      // مما يمنع _cleanupOutboxAfterPull من تنظيف عناصر outbox بشكل صحيح
      origin: src == Source.appwrite || src == Source.drive
          ? const d.Value('server')
          : _vStr(json, 'origin', src, fallback: 'server'),
      vectorClock: _vStr(
        json,
        'vectorClock',
        src,
        altKey: 'vector_clock',
        fallback: '{}',
      ),
      idempotencyKey: _vStr(json, 'idempotencyKey', src, altKey: 'idempotency_key'),
      deviceId: _vStr(json, 'deviceId', src, altKey: 'device_id', fallback: ''),
    );
  }

  @override
  Map<String, dynamic> toJson(SalaryCycle model, {required Source src}) {
    return {
      _k(src, 'id', 'id'): model.id,
      _k(src, 'localUuid', 'local_uuid'): model.localUuid,
      _k(src, 'serverId', 'server_id'): model.serverId,
      _k(src, 'employeeId', 'employee_id'): model.employeeId,
      _k(src, 'cycleKey', 'cycle_key'): model.cycleKey,
      _k(src, 'hotelDayStart', 'hotel_day_start'): model.hotelDayStart,
      _k(src, 'hotelDayEnd', 'hotel_day_end'): model.hotelDayEnd,
      _k(src, 'expectedAmount', 'expected_amount'): model.expectedAmount,
      _k(src, 'actualPaid', 'actual_paid'): model.actualPaid,
      _k(src, 'remainingAmount', 'remaining_amount'): model.remainingAmount,
      _k(src, 'status', 'status'): model.status,
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
