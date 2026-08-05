import 'package:drift/drift.dart' as d;
import 'package:flutter/foundation.dart';

import '../../utils/id.dart';
import '../../utils/time.dart';
import '../local_db.dart';
import 'entity_adapter.dart';
import 'id_resolver.dart';
import 'resolve_result.dart';
import 'source.dart';
import 'package:marina_hotel_mobile/utils/debug_log.dart';

class PaymentsAdapter extends EntityAdapter<Payment, PaymentsCompanion> {
  PaymentsAdapter(this.resolver);
  final IdResolver resolver;

  @override
  String get collectionId => 'payments';

  @override
  String get drivePath => 'payments.json';

  @override
  String get tableName => 'payments';

  @override
  Future<ResolveResult> resolveRefs(
    AppDatabase db,
    Map<String, dynamic> json, {
    required Source src,
  }) async {
    final bookingUuid =
        _asString(json, 'bookingUuidCache', src) ??
        _asString(json, 'booking_uuid_cache', src) ??
        _asString(json, 'booking_uuid', src);
    final serverBookingId =
        _asInt(json, 'serverBookingId', src) ?? _asInt(json, 'booking_id', src);
    final localId =
        _asInt(json, 'bookingLocalId', src) ??
        _asInt(json, 'booking_local_id', src);
    final resolvedId = await resolver.resolveBooking(
      localId: localId,
      serverId: serverBookingId,
      uuid: bookingUuid,
      // ✅ إصلاح حرج: عند المزامنة من السيرفر، لا نستخدم localId كـ fallback
      // لأن bookingLocalId من جهاز بعيد يختلف عن المحلي (autoIncrement مستقل)
      fromRemote: src == Source.appwrite || src == Source.drive,
    );

    // تحذير إذا كان لدينا booking_local_id لكن لم نتمكن من حل المرجع
    if (resolvedId == null && localId != null) {
      // تسجيل تحذير فقط، سيتم معالجة الخطأ في _syncPayments
      dlog(() => '[PaymentsAdapter] Warning: Could not resolve booking for localId: $localId');
    }

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
  PaymentsCompanion fromJson(
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
    return PaymentsCompanion(
      id: _vInt(json, 'id', src),
      localUuid: d.Value(
        _asString(json, 'localUuid', src) ??
            _asString(json, 'local_uuid', src) ??
            IdGen.uuid(),
      ),
      serverId: _vInt(json, 'serverId', src),
      serverPaymentId: _vInt(
        json,
        'serverPaymentId',
        src,
        altKey: 'payment_id',
      ),
      // ✅ إصلاح حرج: لا نستخدم bookingLocalId الخام من الجهاز البعيد
      // معرّف الزيادة التلقائية يختلف بين الأجهزة — bookingLocalId=5 على جهاز A ≠ جهاز B
      // إذا فشل resolveBooking، نترك الحقل فارغاً و bookingUuidCache يُحفظ لإعادة الربط لاحقاً
      bookingLocalId: refs.bookingLocalId != null
          ? d.Value(refs.bookingLocalId)
          : (src == Source.appwrite || src == Source.drive)
          ? const d.Value.absent()
          : _vInt(json, 'bookingLocalId', src, altKey: 'booking_local_id'),
      serverBookingId: _vInt(
        json,
        'serverBookingId',
        src,
        altKey: 'booking_id',
      ),
      roomNumber: _vStr(json, 'roomNumber', src, altKey: 'room_number'),
      amount: _vDouble(json, 'amount', src),
      paymentDate: _vStr(
        json,
        'paymentDate',
        src,
        altKey: 'payment_date',
        fallback: '',
      ),
      notes: _vStr(json, 'notes', src),
      paymentMethod: _vStr(
        json,
        'paymentMethod',
        src,
        altKey: 'payment_method',
        fallback: '',
      ),
      revenueType: _vStr(
        json,
        'revenueType',
        src,
        altKey: 'revenue_type',
        fallback: '',
      ),
      cashTransactionLocalId: _vInt(
        json,
        'cashTransactionLocalId',
        src,
        altKey: 'cash_transaction_local_id',
      ),
      cashTransactionServerId: _vInt(
        json,
        'cashTransactionServerId',
        src,
        altKey: 'cash_transaction_id',
      ),
      referenceNumber: _vStr(json, 'referenceNumber', src),
      hotelDayKey: _vStr(json, 'hotelDayKey', src, altKey: 'hotel_day_key'),
      isPendingBalance: _vBool(json, 'isPendingBalance', src, fallback: false),
      linkedDebtUuid: _vStr(
        json,
        'linkedDebtUuid',
        src,
        altKey: 'linked_debt_uuid',
      ),
      bookingUuidCache: refs.bookingUuidCache != null
          ? d.Value(refs.bookingUuidCache)
          : _vStr(json, 'bookingUuidCache', src, altKey: 'booking_uuid_cache'),
      createdAt: d.Value(createdAt),
      updatedAt: d.Value(_epoch(json, 'updatedAt', src) ?? createdAt),
      deletedAt: _vInt(json, 'deletedAt', src),
      lastModified: d.Value(lastModified),
      createdAtEpoch: d.Value(_asInt(json, 'createdAtEpoch', src) ?? createdAt),
      lastModifiedEpoch: d.Value(
        _asInt(json, 'lastModifiedEpoch', src) ?? lastModified,
      ),
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
      idempotencyKey: _vStr(
        json,
        'idempotencyKey',
        src,
        altKey: 'idempotency_key',
      ),
      deviceId: _vStr(json, 'deviceId', src, altKey: 'device_id', fallback: ''),
      discountAmount: _vDouble(json, 'discountAmount', src),
      discountStartDate: _vStr(json, 'discountStartDate', src),
      isVoided: _vBool(json, 'isVoided', src, fallback: false),
      voidedAt: _vInt(json, 'voidedAt', src),
      voidedBy: _vStr(json, 'voidedBy', src),
    );
  }

  @override
  Map<String, dynamic> toJson(Payment model, {required Source src}) {
    return {
      _k(src, 'id', 'id'): model.id,
      _k(src, 'localUuid', 'local_uuid'): model.localUuid,
      _k(src, 'serverId', 'server_id'): model.serverId,
      _k(src, 'serverPaymentId', 'payment_id'): model.serverPaymentId,
      _k(src, 'bookingLocalId', 'booking_local_id'): model.bookingLocalId,
      _k(src, 'bookingUuidCache', 'booking_uuid_cache'): model.bookingUuidCache,
      _k(src, 'serverBookingId', 'booking_id'): model.serverBookingId,
      _k(src, 'roomNumber', 'room_number'): model.roomNumber,
      _k(src, 'amount', 'amount'): model.amount,
      _k(src, 'paymentDate', 'payment_date'): model.paymentDate,
      _k(src, 'notes', 'notes'): model.notes,
      _k(src, 'paymentMethod', 'payment_method'): model.paymentMethod,
      _k(src, 'revenueType', 'revenue_type'): model.revenueType,
      _k(src, 'cashTransactionLocalId', 'cash_transaction_local_id'):
          model.cashTransactionLocalId,
      _k(src, 'cashTransactionServerId', 'cash_transaction_id'):
          model.cashTransactionServerId,
      _k(src, 'referenceNumber', 'reference_number'): model.referenceNumber,
      _k(src, 'hotelDayKey', 'hotel_day_key'): model.hotelDayKey,
      _k(src, 'isPendingBalance', 'is_pending_balance'): model.isPendingBalance,
      _k(src, 'linkedDebtUuid', 'linked_debt_uuid'): model.linkedDebtUuid,
      _k(src, 'createdAt', 'created_at'): model.createdAt,
      _k(src, 'createdAtEpoch', 'created_at_epoch'): model.createdAtEpoch,
      _k(src, 'createdAtIso', 'created_at_iso'): model.createdAtIso,
      _k(src, 'updatedAt', 'updated_at'): model.updatedAt,
      _k(src, 'updatedAtIso', 'updated_at_iso'): model.updatedAtIso,
      _k(src, 'deletedAt', 'deleted_at'): model.deletedAt,
      _k(src, 'deletedAtIso', 'deleted_at_iso'): model.deletedAtIso,
      _k(src, 'lastModified', 'last_modified'): model.lastModified,
      _k(src, 'lastModifiedEpoch', 'last_modified_epoch'):
          model.lastModifiedEpoch,
      _k(src, 'version', 'version'): model.version,
      _k(src, 'origin', 'origin'): model.origin,
      _k(src, 'vectorClock', 'vector_clock'): model.vectorClock,
      'idempotencyKey': model.idempotencyKey,
      'deviceId': model.deviceId,
      // ✅ تم إضافة الحقول التالية إلى Appwrite Cloud (2026-05-15)
      _k(src, 'discountAmount', 'discount_amount'): model.discountAmount,
      // ⚠️ discountStartDate على Cloud هو datetime — نرسل ISO string وهو متوافق
      _k(src, 'discountStartDate', 'discount_start_date'):
          model.discountStartDate,
      _k(src, 'isVoided', 'is_voided'): model.isVoided,
      _k(src, 'voidedAt', 'voided_at'): model.voidedAt,
      _k(src, 'voidedBy', 'voided_by'): model.voidedBy,
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
  final parsed = int.tryParse(s);
  return parsed;
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
    // تجاهل UUID أو strings طويلة
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
