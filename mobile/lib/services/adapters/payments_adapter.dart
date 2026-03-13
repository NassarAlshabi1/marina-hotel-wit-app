import 'package:drift/drift.dart' as d;
import 'package:flutter/foundation.dart';
import '../local_db.dart';
import '../../utils/id.dart';
import '../../utils/time.dart';
import 'entity_adapter.dart';
import 'id_resolver.dart';
import 'resolve_result.dart';
import 'source.dart';

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
    final bookingUuid = _asString(json, 'bookingUuidCache', src) ??
        _asString(json, 'booking_uuid_cache', src) ??
        _asString(json, 'booking_uuid', src);
    final serverBookingId =
        _asInt(json, 'serverBookingId', src) ?? _asInt(json, 'booking_id', src);
    final localId = _asInt(json, 'bookingLocalId', src) ??
        _asInt(json, 'booking_local_id', src);
    final resolvedId = await resolver.resolveBooking(
      localId: localId,
      serverId: serverBookingId,
      uuid: bookingUuid,
    );

    // تحذير إذا كان لدينا booking_local_id لكن لم نتمكن من حل المرجع
    if (resolvedId == null && localId != null) {
      // تسجيل تحذير فقط، سيتم معالجة الخطأ في _syncPayments
      debugPrint(
        '[PaymentsAdapter] Warning: Could not resolve booking for localId: $localId',
      );
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
    final lastModified = refs.lastModifiedEpoch ??
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
      bookingLocalId: refs.bookingLocalId != null
          ? d.Value(refs.bookingLocalId)
          : _vInt(json, 'bookingLocalId', src, altKey: 'booking_local_id'),
      serverBookingId: _vInt(
        json,
        'serverBookingId',
        src,
        altKey: 'booking_id',
      ),
      roomNumber: _vStr(json, 'roomNumber', src, altKey: 'room_number'),
      amount: _vDouble(json, 'amount', src, fallback: 0),
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
      version: _vInt(json, 'version', src, fallback: 1),
      origin: _vStr(json, 'origin', src, fallback: 'server'),
      vectorClock: _vStr(
        json,
        'vectorClock',
        src,
        altKey: 'vector_clock',
        fallback: '{}',
      ),
    );
  }

  @override
  Map<String, dynamic> toJson(Payment model, {required Source src}) {
    return {
      _k(src, 'id'): model.id,
      _k(src, 'localUuid'): model.localUuid,
      _k(src, 'serverId'): model.serverId,
      _k(src, 'serverPaymentId'): model.serverPaymentId,
      _k(src, 'bookingLocalId'): model.bookingLocalId,
      _k(src, 'bookingUuidCache'): model.bookingUuidCache,
      _k(src, 'serverBookingId'): model.serverBookingId,
      _k(src, 'roomNumber'): model.roomNumber,
      _k(src, 'amount'): model.amount,
      _k(src, 'paymentDate'): model.paymentDate,
      _k(src, 'notes'): model.notes,
      _k(src, 'paymentMethod'): model.paymentMethod,
      _k(src, 'revenueType'): model.revenueType,
      _k(src, 'cashTransactionLocalId'):
          model.cashTransactionLocalId,
      _k(src, 'cashTransactionServerId'):
          model.cashTransactionServerId,
      _k(src, 'referenceNumber'): model.referenceNumber,
      _k(src, 'hotelDayKey'): model.hotelDayKey,
      _k(src, 'isPendingBalance'): model.isPendingBalance,
      _k(src, 'linkedDebtUuid'): model.linkedDebtUuid,
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

d.Value<double> _vDouble(
  Map<String, dynamic> json,
  String key,
  Source src, {
  String? altKey,
  double? fallback,
}) {
  final v = _asDouble(json, key, src) ??
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
  final v = _asBool(json, key, src) ??
      (altKey != null ? _asBool(json, altKey, src) : null) ??
      fallback;
  return v == null ? const d.Value.absent() : d.Value(v);
}

int? _epoch(Map<String, dynamic> json, String key, Source src) {
  final v = _asInt(json, key, src);
  if (v != null) return v;
  final s = _asString(json, key, src);
  if (s == null) return null;
  final parsed = int.tryParse(s);
  return parsed;
}

int? _asInt(Map<String, dynamic> json, String key, Source src) {
  final v = _raw(json, key, src);
  if (v is bool) return v ? 1 : 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) {
    // تجاهل UUID أو strings طويلة
    if (v.contains('-') || v.length > 20) return null;
    return int.tryParse(v);
  }
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
