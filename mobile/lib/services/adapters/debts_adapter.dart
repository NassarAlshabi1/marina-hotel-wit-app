import 'package:drift/drift.dart' as d;

import '../local_db.dart';
import '../../utils/id.dart';
import '../../utils/time.dart';
import 'entity_adapter.dart';
import 'id_resolver.dart';
import 'resolve_result.dart';
import 'source.dart';

class DebtsAdapter extends EntityAdapter<Debt, DebtsCompanion> {
  DebtsAdapter(this.resolver);
  final IdResolver resolver;

  @override
  String get collectionId => 'debts';

  @override
  String get drivePath => 'debts.json';

  @override
  String get tableName => 'debts';

  @override
  Future<ResolveResult> resolveRefs(AppDatabase db, Map<String, dynamic> json,
      {required Source src}) async {
    final bookingUuid = _asString(json, 'bookingUuidCache', src) ??
        _asString(json, 'booking_uuid_cache', src) ??
        _asString(json, 'booking_uuid', src);
    final serverBookingId =
        _asInt(json, 'serverBookingId', src) ?? _asInt(json, 'booking_id', src);
    final localId = _asInt(json, 'bookingLocalId', src) ??
        _asInt(json, 'booking_local_id', src);
    final resolvedId = await resolver.resolveBooking(
        localId: localId, serverId: serverBookingId, uuid: bookingUuid);
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
  DebtsCompanion fromJson(Map<String, dynamic> json,
      {required Source src, required ResolveResult refs}) {
    final now = Time.nowEpoch();
    final createdAt =
        refs.createdAtEpoch ?? _epoch(json, 'createdAt', src) ?? now;
    final lastModified = refs.lastModifiedEpoch ??
        _epoch(json, 'lastModified', src) ??
        createdAt;
    return DebtsCompanion(
      id: _vInt(json, 'id', src),
      localUuid: d.Value(_asString(json, 'localUuid', src) ??
          _asString(json, 'local_uuid', src) ??
          IdGen.uuid()),
      serverId: _vInt(json, 'serverId', src),
      bookingLocalId: refs.bookingLocalId != null
          ? d.Value(refs.bookingLocalId)
          : _vInt(json, 'bookingLocalId', src) ??
              _vInt(json, 'booking_local_id', src),
      guestName: _vStr(json, 'guestName', src, fallback: '') ?? const d.Value(''),
      checkinDate: _vStr(json, 'checkinDate', src, fallback: '') ??
          _vStr(json, 'checkin_date', src, fallback: '') ??
          const d.Value(''),
      checkoutDate: _vStr(json, 'checkoutDate', src, fallback: '') ??
          _vStr(json, 'checkout_date', src, fallback: '') ??
          const d.Value(''),
      dateRecorded: _vStr(json, 'dateRecorded', src) ??
          _vStr(json, 'date_recorded', src) ??
          const d.Value(''),
      debtReason: _vStr(json, 'debtReason', src) ??
          _vStr(json, 'debt_reason', src) ??
          const d.Value(''),
      totalAmount: _vDouble(json, 'totalAmount', src, fallback: 0.0) ??
          _vDouble(json, 'total_amount', src, fallback: 0.0) ??
          const d.Value(0.0),
      paidAmount: _vDouble(json, 'paidAmount', src, fallback: 0.0) ??
          _vDouble(json, 'paid_amount', src, fallback: 0.0) ??
          const d.Value(0.0),
      remainingAmount: _vDouble(json, 'remainingAmount', src, fallback: 0.0) ??
          _vDouble(json, 'remaining_amount', src, fallback: 0.0) ??
          const d.Value(0.0),
      paymentDate: _vStr(json, 'paymentDate', src) ??
          _vStr(json, 'payment_date', src) ??
          const d.Value(''),
      isSettled: _vInt(json, 'isSettled', src) ?? const d.Value(0),
      pledge: _vStr(json, 'pledge', src),
      pledgeType:
          _vStr(json, 'pledgeType', src) ?? _vStr(json, 'pledge_type', src),
      note: _vStr(json, 'note', src),
      debtUuid: _vStr(json, 'debtUuid', src) ?? _vStr(json, 'debt_uuid', src),
      hotelDayOpened: _vStr(json, 'hotelDayOpened', src) ??
          _vStr(json, 'hotel_day_opened', src),
      hotelDayClosed: _vStr(json, 'hotelDayClosed', src) ??
          _vStr(json, 'hotel_day_closed', src),
      isFromAutoFix: _vBool(json, 'isFromAutoFix', src) ?? const d.Value(false),
      settlementConfirmed:
          _vBool(json, 'settlementConfirmed', src) ?? const d.Value(false),
      createdAt: d.Value(createdAt),
      updatedAt: d.Value(_epoch(json, 'updatedAt', src) ?? createdAt),
      deletedAt: _vInt(json, 'deletedAt', src),
      lastModified: d.Value(lastModified),
      createdAtIso: _vStr(json, 'createdAtIso', src),
      updatedAtIso: _vStr(json, 'updatedAtIso', src),
      deletedAtIso: _vStr(json, 'deletedAtIso', src),
      createdAtEpoch: _vInt(json, 'createdAtEpoch', src) ?? d.Value(createdAt),
      lastModifiedEpoch:
          _vInt(json, 'lastModifiedEpoch', src) ?? d.Value(lastModified),
      version: _vInt(json, 'version', src) ?? const d.Value(1),
      origin: _vStr(json, 'origin', src) ?? const d.Value('server'),
      vectorClock: _vStr(json, 'vectorClock', src) ??
          _vStr(json, 'vector_clock', src) ??
          const d.Value('{}'),
    );
  }

  @override
  Map<String, dynamic> toJson(Debt model, {required Source src}) {
    return {
      _k(src, 'id', 'id'): model.id,
      _k(src, 'localUuid', 'local_uuid'): model.localUuid,
      _k(src, 'serverId', 'server_id'): model.serverId,
      _k(src, 'bookingLocalId', 'booking_local_id'): model.bookingLocalId,
      _k(src, 'guestName', 'guest_name'): model.guestName,
      _k(src, 'checkinDate', 'checkin_date'): model.checkinDate,
      _k(src, 'checkoutDate', 'checkout_date'): model.checkoutDate,
      _k(src, 'dateRecorded', 'date_recorded'): model.dateRecorded,
      _k(src, 'debtReason', 'debt_reason'): model.debtReason,
      _k(src, 'totalAmount', 'total_amount'): model.totalAmount,
      _k(src, 'paidAmount', 'paid_amount'): model.paidAmount,
      _k(src, 'remainingAmount', 'remaining_amount'): model.remainingAmount,
      _k(src, 'paymentDate', 'payment_date'): model.paymentDate,
      _k(src, 'isSettled', 'is_settled'): model.isSettled,
      _k(src, 'pledge', 'pledge'): model.pledge,
      _k(src, 'pledgeType', 'pledge_type'): model.pledgeType,
      _k(src, 'note', 'note'): model.note,
      _k(src, 'debtUuid', 'debt_uuid'): model.debtUuid,
      _k(src, 'hotelDayOpened', 'hotel_day_opened'): model.hotelDayOpened,
      _k(src, 'hotelDayClosed', 'hotel_day_closed'): model.hotelDayClosed,
      _k(src, 'isFromAutoFix', 'is_from_auto_fix'): model.isFromAutoFix,
      _k(src, 'settlementConfirmed', 'settlement_confirmed'):
          model.settlementConfirmed,
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

d.Value<int> _vInt(Map<String, dynamic> json, String key, Source src) {
  final v = _asInt(json, key, src);
  return v == null ? const d.Value.absent() : d.Value(v);
}

d.Value<String> _vStr(Map<String, dynamic> json, String key, Source src,
    {String? fallback}) {
  final v = _asString(json, key, src) ?? fallback;
  return v == null ? const d.Value.absent() : d.Value(v);
}

d.Value<double> _vDouble(Map<String, dynamic> json, String key, Source src,
    {double? fallback}) {
  final v = _asDouble(json, key, src) ?? fallback;
  return v == null ? const d.Value.absent() : d.Value(v);
}

d.Value<bool> _vBool(Map<String, dynamic> json, String key, Source src,
    {bool? fallback}) {
  final v = _asBool(json, key, src) ?? fallback;
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

String _k(Source src, String camel, String snake) =>
    src == Source.drive ? snake : camel;

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
