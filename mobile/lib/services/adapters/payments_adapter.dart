import 'package:drift/drift.dart' as d;

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
  Future<ResolveResult> resolveRefs(AppDatabase db, Map<String, dynamic> json, {required Source src}) async {
    final bookingUuid = _asString(json, 'bookingUuidCache', src) ?? _asString(json, 'booking_uuid_cache', src) ?? _asString(json, 'booking_uuid', src);
    final serverBookingId = _asInt(json, 'serverBookingId', src) ?? _asInt(json, 'booking_id', src);
    final localId = _asInt(json, 'bookingLocalId', src) ?? _asInt(json, 'booking_local_id', src);
    final resolvedId = await resolver.resolveBooking(localId: localId, serverId: serverBookingId, uuid: bookingUuid);
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
  PaymentsCompanion fromJson(Map<String, dynamic> json, {required Source src, required ResolveResult refs}) {
    final now = Time.nowEpoch();
    final createdAt = refs.createdAtEpoch ?? _epoch(json, 'createdAt', src) ?? now;
    final lastModified = refs.lastModifiedEpoch ?? _epoch(json, 'lastModified', src) ?? createdAt;
    return PaymentsCompanion(
      id: _vInt(json, 'id', src),
      localUuid: d.Value(_asString(json, 'localUuid', src) ?? _asString(json, 'local_uuid', src) ?? IdGen.uuid()),
      serverId: _vInt(json, 'serverId', src),
      serverPaymentId: _vInt(json, 'serverPaymentId', src) ?? _vInt(json, 'payment_id', src),
      bookingLocalId: refs.bookingLocalId != null ? d.Value(refs.bookingLocalId) : _vInt(json, 'bookingLocalId', src) ?? _vInt(json, 'booking_local_id', src),
      serverBookingId: _vInt(json, 'serverBookingId', src) ?? _vInt(json, 'booking_id', src),
      roomNumber: _vStr(json, 'roomNumber', src) ?? _vStr(json, 'room_number', src),
      amount: _vDouble(json, 'amount', src) ?? const d.Value(0.0),
      paymentDate: _vStr(json, 'paymentDate', src) ?? _vStr(json, 'payment_date', src) ?? const d.Value(''),
      notes: _vStr(json, 'notes', src),
      paymentMethod: _vStr(json, 'paymentMethod', src) ?? _vStr(json, 'payment_method', src) ?? const d.Value(''),
      revenueType: _vStr(json, 'revenueType', src) ?? _vStr(json, 'revenue_type', src) ?? const d.Value(''),
      cashTransactionLocalId: _vInt(json, 'cashTransactionLocalId', src) ?? _vInt(json, 'cash_transaction_local_id', src),
      cashTransactionServerId: _vInt(json, 'cashTransactionServerId', src) ?? _vInt(json, 'cash_transaction_id', src),
      referenceNumber: _vStr(json, 'referenceNumber', src),
      hotelDayKey: _vStr(json, 'hotelDayKey', src) ?? _vStr(json, 'hotel_day_key', src),
      isPendingBalance: _vBool(json, 'isPendingBalance', src) ?? const d.Value(false),
      linkedDebtUuid: _vStr(json, 'linkedDebtUuid', src) ?? _vStr(json, 'linked_debt_uuid', src),
      bookingUuidCache: refs.bookingUuidCache != null ? d.Value(refs.bookingUuidCache) : _vStr(json, 'bookingUuidCache', src) ?? _vStr(json, 'booking_uuid_cache', src),
      createdAt: d.Value(createdAt),
      updatedAt: d.Value(_epoch(json, 'updatedAt', src) ?? createdAt),
      deletedAt: _vInt(json, 'deletedAt', src),
      lastModified: d.Value(lastModified),
      version: _vInt(json, 'version', src) ?? const d.Value(1),
      origin: _vStr(json, 'origin', src) ?? const d.Value('server'),
      vectorClock: _vStr(json, 'vectorClock', src) ?? _vStr(json, 'vector_clock', src) ?? const d.Value('{}'),
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
      _k(src, 'cashTransactionLocalId', 'cash_transaction_local_id'): model.cashTransactionLocalId,
      _k(src, 'cashTransactionServerId', 'cash_transaction_id'): model.cashTransactionServerId,
      _k(src, 'referenceNumber', 'reference_number'): model.referenceNumber,
      _k(src, 'hotelDayKey', 'hotel_day_key'): model.hotelDayKey,
      _k(src, 'isPendingBalance', 'is_pending_balance'): model.isPendingBalance,
      _k(src, 'linkedDebtUuid', 'linked_debt_uuid'): model.linkedDebtUuid,
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
  final parsed = int.tryParse(s);
  return parsed;
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
