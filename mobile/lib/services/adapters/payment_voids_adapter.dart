import 'package:drift/drift.dart' as d;
import 'package:flutter/foundation.dart' show debugPrint;

import '../../utils/id.dart';
import '../../utils/time.dart';
import '../local_db.dart';
import 'entity_adapter.dart';
import 'id_resolver.dart';
import 'resolve_result.dart';
import 'source.dart';

class PaymentVoidsAdapter
    extends EntityAdapter<PaymentVoid, PaymentVoidsCompanion> {
  PaymentVoidsAdapter(this.resolver);
  final IdResolver resolver;

  @override
  String get collectionId => 'payment_voids';

  @override
  String get drivePath => 'payment_voids.json';

  @override
  String get tableName => 'payment_voids';

  @override
  Future<ResolveResult> resolveRefs(
    AppDatabase db,
    Map<String, dynamic> json, {
    required Source src,
  }) async {
    final bookingUuid =
        _asString(json, 'bookingUuid', src) ??
        _asString(json, 'booking_uuid', src);
    final createdAt = _epoch(json, 'createdAt', src);
    final lastModified = _epoch(json, 'lastModified', src);
    return ResolveResult(
      bookingUuidCache: bookingUuid,
      createdAtEpoch: createdAt,
      lastModifiedEpoch: lastModified,
    );
  }

  @override
  PaymentVoidsCompanion fromJson(
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
    final voidedAt = _epoch(json, 'voidedAt', src) ?? now;

    return PaymentVoidsCompanion(
      id: _vInt(json, 'id', src),
      localUuid: d.Value(
        _asString(json, 'localUuid', src) ??
            _asString(json, 'local_uuid', src) ??
            IdGen.uuid(),
      ),
      serverId: _vInt(json, 'serverId', src),
      originalPaymentUuid: _vStr(
        json,
        'originalPaymentUuid',
        src,
        altKey: 'original_payment_uuid',
        fallback: '',
      ),
      originalPaymentId: _vInt(
        json,
        'originalPaymentId',
        src,
        altKey: 'original_payment_id',
        fallback: 0,
      ),
      bookingUuid: refs.bookingUuidCache != null
          ? d.Value(refs.bookingUuidCache!)
          : _vStr(json, 'bookingUuid', src, altKey: 'booking_uuid', fallback: ''),
      voidedAmount: _vInt(json, 'voidedAmount', src, altKey: 'voided_amount', fallback: 0),
      voidReason: _vStr(json, 'voidReason', src, altKey: 'void_reason', fallback: ''),
      voidedBy: _vStr(json, 'voidedBy', src, altKey: 'voided_by', fallback: ''),
      voidedAt: d.Value(voidedAt),
      voidedAtIso: _vStr(
        json,
        'voidedAtIso',
        src,
        altKey: 'voided_at_iso',
        fallback: DateTime.fromMillisecondsSinceEpoch(voidedAt * 1000).toIso8601String(),
      ),
      hotelDayKey: _vStr(json, 'hotelDayKey', src, altKey: 'hotel_day_key', fallback: ''),
      reversalPaymentUuid: _vStr(
        json,
        'reversalPaymentUuid',
        src,
        altKey: 'reversal_payment_uuid',
      ),
      approvedBy: _vStr(json, 'approvedBy', src, altKey: 'approved_by'),
      createdAt: d.Value(createdAt),
      updatedAt: d.Value(_epoch(json, 'updatedAt', src) ?? createdAt),
      deletedAt: _vInt(json, 'deletedAt', src),
      lastModified: d.Value(lastModified),
      createdAtEpoch: d.Value(_asInt(json, 'createdAtEpoch', src) ?? createdAt),
      lastModifiedEpoch: d.Value(_asInt(json, 'lastModifiedEpoch', src) ?? lastModified),
      createdAtIso: _vStr(json, 'createdAtIso', src),
      updatedAtIso: _vStr(json, 'updatedAtIso', src),
      deletedAtIso: _vStr(json, 'deletedAtIso', src),
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
      note: _vStr(json, 'note', src),
      originalAmount: _vDoubleNullable(json, 'originalAmount', src, altKey: 'original_amount'),
      paymentUuid: _vStr(json, 'paymentUuid', src, altKey: 'payment_uuid'),
      deviceId: _vStr(json, 'deviceId', src, altKey: 'device_id', fallback: ''),
    );
  }

  @override
  Map<String, dynamic> toJson(PaymentVoid model, {required Source src}) {
    return {
      _k(src, 'id', 'id'): model.id,
      _k(src, 'localUuid', 'local_uuid'): model.localUuid,
      _k(src, 'serverId', 'server_id'): model.serverId,
      _k(src, 'originalPaymentUuid', 'original_payment_uuid'): model.originalPaymentUuid,
      _k(src, 'originalPaymentId', 'original_payment_id'): model.originalPaymentId,
      _k(src, 'bookingUuid', 'booking_uuid'): model.bookingUuid,
      _k(src, 'voidedAmount', 'voided_amount'): model.voidedAmount,
      _k(src, 'voidReason', 'void_reason'): model.voidReason,
      _k(src, 'voidedBy', 'voided_by'): model.voidedBy,
      _k(src, 'voidedAt', 'voided_at'): model.voidedAt,
      _k(src, 'voidedAtIso', 'voided_at_iso'): model.voidedAtIso,
      _k(src, 'hotelDayKey', 'hotel_day_key'): model.hotelDayKey,
      _k(src, 'reversalPaymentUuid', 'reversal_payment_uuid'): model.reversalPaymentUuid,
      _k(src, 'approvedBy', 'approved_by'): model.approvedBy,
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
      'note': model.note,
      'originalAmount': model.originalAmount,
      'paymentUuid': model.paymentUuid,
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

// ✅ Helpers إضافية للحقول الجديدة (v2)

d.Value<double?> _vDoubleNullable(
  Map<String, dynamic> json,
  String key,
  Source src, {
  String? altKey,
}) {
  final v = _asDouble(json, key, src) ??
      (altKey != null ? _asFloat(json, altKey, src) : null);
  return v == null ? const d.Value.absent() : d.Value(v);
}

double? _asFloat(Map<String, dynamic> json, String key, Source src) {
  return _asDouble(json, key, src);
}

double? _asDouble(Map<String, dynamic> json, String key, Source src) {
  final v = _raw(json, key, src);
  if (v == null) return null;
  if (v is double) return v;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  // ✅ تسجيل تحذيري للأنواع غير المتوقعة (bool, List, Map) — كان silent null
  // يصعّب التشخيص عند تلقي بيانات Appwrite/Drive بنوع خاطئ.
  debugPrint(
    '⚠️ payment_voids._asDouble: قيمة غير متوقعة لـ $key من $src — '
    'type=${v.runtimeType}, value=$v',
  );
  return null;
}
