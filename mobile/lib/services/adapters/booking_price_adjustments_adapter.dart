import 'package:drift/drift.dart' as d;

import '../../utils/id.dart';
import '../../utils/time.dart';
import '../local_db.dart';
import 'entity_adapter.dart';
import 'id_resolver.dart';
import 'resolve_result.dart';
import 'source.dart';

class BookingPriceAdjustmentsAdapter
    extends EntityAdapter<BookingPriceAdjustment, BookingPriceAdjustmentsCompanion> {
  BookingPriceAdjustmentsAdapter(this.resolver);
  final IdResolver resolver;

  @override
  String get collectionId => 'booking_price_adjustments';

  @override
  String get drivePath => 'booking_price_adjustments.json';

  @override
  String get tableName => 'booking_price_adjustments';

  @override
  Future<ResolveResult> resolveRefs(
    AppDatabase db,
    Map<String, dynamic> json, {
    required Source src,
  }) async {
    final bookingUuid =
        _asString(json, 'bookingLocalUuid', src) ??
        _asString(json, 'booking_local_uuid', src) ??
        _asString(json, 'booking_uuid', src);
    final localId =
        _asInt(json, 'bookingLocalId', src) ??
        _asInt(json, 'booking_local_id', src);
    final resolvedId = await resolver.resolveBooking(
      localId: localId,
      uuid: bookingUuid,
    );
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
  BookingPriceAdjustmentsCompanion fromJson(
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
    return BookingPriceAdjustmentsCompanion(
      id: _vInt(json, 'id', src),
      localUuid: d.Value(
        _asString(json, 'localUuid', src) ??
            _asString(json, 'local_uuid', src) ??
            IdGen.uuid(),
      ),
      serverId: _vInt(json, 'serverId', src),
      bookingLocalUuid: _vStr(
        json,
        'bookingLocalUuid',
        src,
        altKey: 'booking_local_uuid',
        // ✅ إصلاح FK: لا نستخدم fallback فارغ لأن bookingLocalUuid هو FK NOT NULL
        // إذا لم يكن bookingUuidCache موجوداً، نستخدم القيمة الأصلية من JSON
        // وإذا لم تكن موجودة أيضاً، ستكون Value.absent() مما يسمح لـ Drift
        // برفع خطأ FK الذي يُعالج بنمط التأجيل في SyncManager
        fallback: refs.bookingUuidCache,
      ),
      // ✅ إصلاح حرج: لا نستخدم bookingLocalId الخام من الجهاز البعيد
      // معرّف الزيادة التلقائية يختلف بين الأجهزة — bookingLocalId=5 على جهاز A ≠ جهاز B
      // إذا فشل resolveBooking، نترك الحقل فارغاً و bookingUuidCache/bookingLocalUuid يُحفظ لإعادة الربط لاحقاً
      bookingLocalId: refs.bookingLocalId != null
          ? d.Value(refs.bookingLocalId)
          : (src == Source.appwrite || src == Source.drive)
              ? const d.Value.absent()
              : _vInt(json, 'bookingLocalId', src, altKey: 'booking_local_id'),
      roomNumber: _vStr(json, 'roomNumber', src, altKey: 'room_number'),
      adjustmentType: _vInt(
        json,
        'adjustmentType',
        src,
        altKey: 'adjustment_type',
        fallback: 0,
      ),
      adjustmentMode: _vStr(
        json,
        'adjustmentMode',
        src,
        altKey: 'adjustment_mode',
        fallback: 'per_night',
      ),
      // ✅ amount أُضيف إلى Appwrite Cloud (2026-05-15) كـ integer
      // نقرأه كـ double للمحلي (integer على Cloud → double محلياً)
      amount: _vDouble(json, 'amount', src, fallback: 0),
      effectiveHotelDay: _vStr(
        json,
        'effectiveHotelDay',
        src,
        altKey: 'effective_hotel_day',
        fallback: '',
      ),
      endHotelDay: _vStr(
        json,
        'endHotelDay',
        src,
        altKey: 'end_hotel_day',
      ),
      isActive: _vBool(json, 'isActive', src, altKey: 'is_active', fallback: true),
      reason: _vStr(json, 'reason', src),
      appliedBy: _vStr(json, 'appliedBy', src, altKey: 'applied_by'),
      cancelledAt: _vStr(json, 'cancelledAt', src, altKey: 'cancelled_at'),
      cancelledBy: _vStr(json, 'cancelledBy', src, altKey: 'cancelled_by'),
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
  Map<String, dynamic> toJson(BookingPriceAdjustment model, {required Source src}) {
    return {
      _k(src, 'id', 'id'): model.id,
      _k(src, 'localUuid', 'local_uuid'): model.localUuid,
      _k(src, 'serverId', 'server_id'): model.serverId,
      _k(src, 'bookingLocalUuid', 'booking_local_uuid'): model.bookingLocalUuid,
      _k(src, 'bookingLocalId', 'booking_local_id'): model.bookingLocalId,
      _k(src, 'roomNumber', 'room_number'): model.roomNumber,
      _k(src, 'adjustmentType', 'adjustment_type'): model.adjustmentType,
      _k(src, 'adjustmentMode', 'adjustment_mode'): model.adjustmentMode,
      // ✅ amount أُضيف إلى Appwrite Cloud (2026-05-15)
      // ⚠️ على Cloud هو integer — نحول من double إلى int عند الإرسال
      _k(src, 'amount', 'amount'): model.amount.round(),
      _k(src, 'effectiveHotelDay', 'effective_hotel_day'): model.effectiveHotelDay,
      _k(src, 'endHotelDay', 'end_hotel_day'): model.endHotelDay,
      _k(src, 'isActive', 'is_active'): model.isActive,
      _k(src, 'reason', 'reason'): model.reason,
      _k(src, 'appliedBy', 'applied_by'): model.appliedBy,
      _k(src, 'cancelledAt', 'cancelled_at'): model.cancelledAt,
      _k(src, 'cancelledBy', 'cancelled_by'): model.cancelledBy,
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

d.Value<double> _vDouble(
  Map<String, dynamic> json,
  String key,
  Source src, {
  String? altKey,
  double? fallback,
}) {
  final v =
      _asDouble(json, key, src) ??
      (altKey != null ? _asDouble(json, altKey, src) : null) ??
      fallback;
  return v == null ? const d.Value.absent() : d.Value(v);
}

d.Value<bool> _vBool(
  Map<String, dynamic> json,
  String key,
  Source src, {
  String? altKey,
  bool? fallback,
}) {
  final v =
      _asBool(json, key, src) ??
      (altKey != null ? _asBool(json, altKey, src) : null) ??
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

double? _asDouble(Map<String, dynamic> json, String key, Source src) {
  final v = _raw(json, key, src);
  if (v is double) {
    return v;
  }
  if (v is int) {
    return v.toDouble();
  }
  if (v is num) {
    return v.toDouble();
  }
  if (v is String) {
    return double.tryParse(v);
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
