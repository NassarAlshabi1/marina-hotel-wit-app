import 'package:drift/drift.dart' as d;

import '../local_db.dart';
import '../../utils/id.dart';
import '../../utils/time.dart';
import 'entity_adapter.dart';
import 'id_resolver.dart';
import 'resolve_result.dart';
import 'source.dart';

class BookingsAdapter extends EntityAdapter<Booking, BookingsCompanion> {
  BookingsAdapter(this.resolver);
  final IdResolver resolver;

  @override
  String get collectionId => 'bookings';

  @override
  String get drivePath => 'bookings.json';

  @override
  String get tableName => 'bookings';

  @override
  Future<ResolveResult> resolveRefs(AppDatabase db, Map<String, dynamic> json,
      {required Source src}) async {
    final bookingUuid = _asString(json, 'localUuid', src) ??
        _asString(json, 'booking_uuid', src) ??
        _asString(json, 'bookingUuid', src);
    final serverBookingId =
        _asInt(json, 'serverBookingId', src) ?? _asInt(json, 'booking_id', src);
    final localId = _asInt(json, 'id', src);
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
  BookingsCompanion fromJson(Map<String, dynamic> json,
      {required Source src, required ResolveResult refs}) {
    final now = Time.nowEpoch();
    final createdAt =
        refs.createdAtEpoch ?? _epoch(json, 'createdAt', src) ?? now;
    final lastModified = refs.lastModifiedEpoch ??
        _epoch(json, 'lastModified', src) ??
        createdAt;
    return BookingsCompanion(
      id: _vInt(json, 'id', src),
      localUuid: d.Value(_asString(json, 'localUuid', src) ??
          _asString(json, 'local_uuid', src) ??
          IdGen.uuid()),
      serverId: _vInt(json, 'serverId', src),
      serverBookingId:
          _vInt(json, 'serverBookingId', src) ?? _vInt(json, 'booking_id', src),
      roomNumber: _vStr(json, 'roomNumber', src, fallback: '') ??
          _vStr(json, 'room_number', src, fallback: '') ??
          const d.Value(''),
      guestName: _vStr(json, 'guestName', src, fallback: '') ??
          _vStr(json, 'guest_name', src, fallback: '') ??
          const d.Value(''),
      guestPhone: _vStr(json, 'guestPhone', src, fallback: '') ??
          _vStr(json, 'guest_phone', src, fallback: '') ??
          const d.Value(''),
      guestIdType: _vStr(json, 'guestIdType', src, fallback: 'بطاقة شخصية') ??
          _vStr(json, 'guest_id_type', src, fallback: 'بطاقة شخصية') ??
          const d.Value('بطاقة شخصية'),
      guestIdNumber: _vStr(json, 'guestIdNumber', src, fallback: '') ??
          _vStr(json, 'guest_id_number', src, fallback: '') ??
          const d.Value(''),
      guestIdIssueDate: _vStr(json, 'guestIdIssueDate', src) ??
          _vStr(json, 'guest_id_issue_date', src),
      guestIdIssuePlace: _vStr(json, 'guestIdIssuePlace', src) ??
          _vStr(json, 'guest_id_issue_place', src),
      guestNationality: _vStr(json, 'guestNationality', src, fallback: '') ??
          _vStr(json, 'guest_nationality', src, fallback: '') ??
          const d.Value(''),
      guestEmail:
          _vStr(json, 'guestEmail', src) ?? _vStr(json, 'guest_email', src),
      guestAddress:
          _vStr(json, 'guestAddress', src) ?? _vStr(json, 'guest_address', src),
      checkinDate: _vStr(json, 'checkinDate', src, fallback: '') ??
          _vStr(json, 'checkin_date', src, fallback: '') ??
          const d.Value(''),
      checkoutDate:
          _vStr(json, 'checkoutDate', src) ?? _vStr(json, 'checkout_date', src),
      actualCheckout: _vStr(json, 'actualCheckout', src) ??
          _vStr(json, 'actual_checkout', src),
      status: _vStr(json, 'status', src, fallback: '') ?? const d.Value(''),
      notes: _vStr(json, 'notes', src),
      expectedNights: _vInt(json, 'expectedNights', src) ??
          _vInt(json, 'expected_nights', src) ??
          const d.Value.absent(),
      calculatedNights: _vInt(json, 'calculatedNights', src) ??
          _vInt(json, 'calculated_nights', src),
      totalNightsCached: _vInt(json, 'totalNightsCached', src),
      stayDurationIso: _vStr(json, 'stayDurationIso', src) ??
          _vStr(json, 'stay_duration_iso', src),
      lastNightEpoch: _vInt(json, 'lastNightEpoch', src),
      isOverdue: _vBool(json, 'isOverdue', src),
      needsCheckoutReview: _vBool(json, 'needsCheckoutReview', src),
      totalDueCached: _vDouble(json, 'totalDueCached', src),
      totalPaidCached: _vDouble(json, 'totalPaidCached', src),
      remainingBalanceCached: _vDouble(json, 'remainingBalanceCached', src),
      isFullyPaid: _vBool(json, 'isFullyPaid', src),
      hotelDayCheckin: _vStr(json, 'hotelDayCheckin', src) ??
          _vStr(json, 'hotel_day_checkin', src),
      hotelDayCheckout: _vStr(json, 'hotelDayCheckout', src) ??
          _vStr(json, 'hotel_day_checkout', src),
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
  Map<String, dynamic> toJson(Booking model, {required Source src}) {
    return {
      _k(src, 'id', 'id'): model.id,
      _k(src, 'localUuid', 'local_uuid'): model.localUuid,
      _k(src, 'serverId', 'server_id'): model.serverId,
      _k(src, 'serverBookingId', 'booking_id'): model.serverBookingId,
      _k(src, 'roomNumber', 'room_number'): model.roomNumber,
      _k(src, 'guestName', 'guest_name'): model.guestName,
      _k(src, 'guestPhone', 'guest_phone'): model.guestPhone,
      _k(src, 'guestIdType', 'guest_id_type'): model.guestIdType,
      _k(src, 'guestIdNumber', 'guest_id_number'): model.guestIdNumber,
      _k(src, 'guestIdIssueDate', 'guest_id_issue_date'):
          model.guestIdIssueDate,
      _k(src, 'guestIdIssuePlace', 'guest_id_issue_place'):
          model.guestIdIssuePlace,
      _k(src, 'guestNationality', 'guest_nationality'): model.guestNationality,
      _k(src, 'guestEmail', 'guest_email'): model.guestEmail,
      _k(src, 'guestAddress', 'guest_address'): model.guestAddress,
      _k(src, 'checkinDate', 'checkin_date'): model.checkinDate,
      _k(src, 'checkoutDate', 'checkout_date'): model.checkoutDate,
      _k(src, 'actualCheckout', 'actual_checkout'): model.actualCheckout,
      _k(src, 'status', 'status'): model.status,
      _k(src, 'notes', 'notes'): model.notes,
      _k(src, 'expectedNights', 'expected_nights'): model.expectedNights,
      _k(src, 'calculatedNights', 'calculated_nights'): model.calculatedNights,
      _k(src, 'totalNightsCached', 'total_nights_cached'):
          model.totalNightsCached,
      _k(src, 'stayDurationIso', 'stay_duration_iso'): model.stayDurationIso,
      _k(src, 'lastNightEpoch', 'last_night_epoch'): model.lastNightEpoch,
      _k(src, 'isOverdue', 'is_overdue'): model.isOverdue,
      _k(src, 'needsCheckoutReview', 'needs_checkout_review'):
          model.needsCheckoutReview,
      _k(src, 'totalDueCached', 'total_due_cached'): model.totalDueCached,
      _k(src, 'totalPaidCached', 'total_paid_cached'): model.totalPaidCached,
      _k(src, 'remainingBalanceCached', 'remaining_balance_cached'):
          model.remainingBalanceCached,
      _k(src, 'isFullyPaid', 'is_fully_paid'): model.isFullyPaid,
      _k(src, 'hotelDayCheckin', 'hotel_day_checkin'): model.hotelDayCheckin,
      _k(src, 'hotelDayCheckout', 'hotel_day_checkout'): model.hotelDayCheckout,
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
