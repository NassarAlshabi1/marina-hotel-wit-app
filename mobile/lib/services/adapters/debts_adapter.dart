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
  DebtsCompanion fromJson(
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
    return DebtsCompanion(
      id: _vInt(json, 'id', src),
      localUuid: d.Value(
        _asString(json, 'localUuid', src) ??
            _asString(json, 'local_uuid', src) ??
            IdGen.uuid(),
      ),
      serverId: _vInt(json, 'serverId', src),
      bookingLocalId: refs.bookingLocalId != null
          ? d.Value(refs.bookingLocalId)
          : _vInt(json, 'bookingLocalId', src, altKey: 'booking_local_id'),
      guestName: _vStr(json, 'guestName', src, fallback: ''),
      checkinDate: _vStr(
        json,
        'checkinDate',
        src,
        altKey: 'checkin_date',
        fallback: '',
      ),
      checkoutDate: _vStr(
        json,
        'checkoutDate',
        src,
        altKey: 'checkout_date',
        fallback: '',
      ),
      dateRecorded: _vStr(
        json,
        'dateRecorded',
        src,
        altKey: 'date_recorded',
        fallback: '',
      ),
      debtReason: _vStr(
        json,
        'debtReason',
        src,
        altKey: 'debt_reason',
        fallback: '',
      ),
      totalAmount: _vDouble(
        json,
        'totalAmount',
        src,
        altKey: 'total_amount',
        fallback: 0.0,
      ),
      paidAmount: _vDouble(
        json,
        'paidAmount',
        src,
        altKey: 'paid_amount',
        fallback: 0.0,
      ),
      remainingAmount: _vDouble(
        json,
        'remainingAmount',
        src,
        altKey: 'remaining_amount',
        fallback: 0.0,
      ),
      paymentDate: _vStr(
        json,
        'paymentDate',
        src,
        altKey: 'payment_date',
        fallback: '',
      ),
      isSettled: _vInt(json, 'isSettled', src, fallback: 0),
      pledge: _vStr(json, 'pledge', src),
      pledgeType: _vStr(json, 'pledgeType', src, altKey: 'pledge_type'),
      note: _vStr(json, 'note', src),
      debtUuid: _vStr(json, 'debtUuid', src, altKey: 'debt_uuid'),
      hotelDayOpened: _vStr(
        json,
        'hotelDayOpened',
        src,
        altKey: 'hotel_day_opened',
      ),
      hotelDayClosed: _vStr(
        json,
        'hotelDayClosed',
        src,
        altKey: 'hotel_day_closed',
      ),
      isFromAutoFix: _vBool(json, 'isFromAutoFix', src, fallback: false),
      settlementConfirmed: _vBool(
        json,
        'settlementConfirmed',
        src,
        fallback: false,
      ),
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
        altKey: 'vector_clock',
        fallback: '{}',
      ),
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
  return int.tryParse(s);
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
