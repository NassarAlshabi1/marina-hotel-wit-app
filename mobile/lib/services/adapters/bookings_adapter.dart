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
  Future<ResolveResult> resolveRefs(
    AppDatabase db,
    Map<String, dynamic> json, {
    required Source src,
  }) async {
    final bookingUuid =
        _asString(json, 'localUuid', src) ??
        _asString(json, 'booking_uuid', src) ??
        _asString(json, 'bookingUuid', src);
    final serverBookingId =
        _asInt(json, 'serverBookingId', src) ?? _asInt(json, 'booking_id', src);
    final localId = _asInt(json, 'id', src);
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
  BookingsCompanion fromJson(
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
    return BookingsCompanion(
      id: _vInt(json, 'id', src),
      localUuid: d.Value(
        _asString(json, 'localUuid', src) ??
            _asString(json, 'local_uuid', src) ??
            IdGen.uuid(),
      ),
      serverId: _vInt(json, 'serverId', src),
      serverBookingId: _vInt(
        json,
        'serverBookingId',
        src,
        altKey: 'booking_id',
      ),
      roomNumber: _vStr(
        json,
        'roomNumber',
        src,
        altKey: 'room_number',
        fallback: '',
      ),
      guestName: _vStr(
        json,
        'guestName',
        src,
        altKey: 'guest_name',
        fallback: '',
      ),
      guestPhone: _vStr(
        json,
        'guestPhone',
        src,
        altKey: 'guest_phone',
        fallback: '',
      ),
      guestIdType: _vStr(
        json,
        'guestIdType',
        src,
        altKey: 'guest_id_type',
        fallback: 'بطاقة شخصية',
      ),
      guestIdNumber: _vStr(
        json,
        'guestIdNumber',
        src,
        altKey: 'guest_id_number',
        fallback: '',
      ),
      guestIdIssueDate: _vStr(
        json,
        'guestIdIssueDate',
        src,
        altKey: 'guest_id_issue_date',
      ),
      guestIdIssuePlace: _vStr(
        json,
        'guestIdIssuePlace',
        src,
        altKey: 'guest_id_issue_place',
      ),
      guestNationality: _vStr(
        json,
        'guestNationality',
        src,
        altKey: 'guest_nationality',
        fallback: '',
      ),
      guestEmail: _vStr(json, 'guestEmail', src, altKey: 'guest_email'),
      guestAddress: _vStr(json, 'guestAddress', src, altKey: 'guest_address'),
      checkinDate: _vStr(
        json,
        'checkinDate',
        src,
        altKey: 'checkin_date',
        fallback: '',
      ),
      checkoutDate: _vStr(json, 'checkoutDate', src, altKey: 'checkout_date'),
      actualCheckout: _vStr(
        json,
        'actualCheckout',
        src,
        altKey: 'actual_checkout',
      ),
      status: _vStr(json, 'status', src, fallback: ''),
      notes: _vStr(json, 'notes', src),
      discount: _vDouble(
        json,
        'discount',
        src,
        altKey: 'discount',
        fallback: 0,
      ),
      discountType: _vStr(
        json,
        'discountType',
        src,
        altKey: 'discount_type',
        fallback: 'per_night',
      ),
      discountStartDate: _vStr(
        json,
        'discountStartDate',
        src,
        altKey: 'discount_start_date',
      ),
      expectedNights: _vInt(
        json,
        'expectedNights',
        src,
        altKey: 'expected_nights',
        fallback: 1,
      ),
      calculatedNights: _vInt(
        json,
        'calculatedNights',
        src,
        altKey: 'calculated_nights',
      ),
      totalNightsCached: _vInt(json, 'totalNightsCached', src),
      stayDurationIso: _vStr(
        json,
        'stayDurationIso',
        src,
        altKey: 'stay_duration_iso',
      ),
      lastNightEpoch: _vInt(json, 'lastNightEpoch', src),
      isOverdue: _vBool(json, 'isOverdue', src),
      needsCheckoutReview: _vBool(json, 'needsCheckoutReview', src),
      // لا نقرأ الحقول المحسوبة من Appwrite/Drive — تُعاد حسابها محلياً
      // عبر BookingDerivedFieldsService لضمان دقة الأرقام
      // totalDueCached, totalPaidCached, remainingBalanceCached, isFullyPaid
      // تُترك كـ Value.absent() حتى يُعاد حسابها
      hotelDayCheckin: _vStr(
        json,
        'hotelDayCheckin',
        src,
        altKey: 'hotel_day_checkin',
      ),
      hotelDayCheckout: _vStr(
        json,
        'hotelDayCheckout',
        src,
        altKey: 'hotel_day_checkout',
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
      _k(src, 'discount', 'discount'): model.discount,
      _k(src, 'discountType', 'discount_type'): model.discountType,
      _k(src, 'discountStartDate', 'discount_start_date'):
          model.discountStartDate,
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

/// تحويل اسم الحقل بين camelCase و snake_case حسب المصدر.
/// يدعم استدعاء باراميترين (camel فقط) أو ثلاثة (camel + snake).
String _k(Source src, String camel, [String? snake]) =>
    src == Source.drive ? (snake ?? camel) : camel;

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
