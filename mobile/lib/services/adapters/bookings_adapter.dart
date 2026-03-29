import 'dart:convert';

import 'package:drift/drift.dart' as d;

import '../local_db.dart';
import '../../utils/id.dart';
import '../../utils/time.dart';
import 'entity_adapter.dart';
import 'id_resolver.dart';
import 'resolve_result.dart';
import 'source.dart';

/// محول لتحويل بيانات الحجوزات بين JSON المحلي/السحابي وكائنات Drift.
/// تم تعديله ليتوافق مع تسميات camelCase في Appwrite Cloud.
class BookingsAdapter extends EntityAdapter<Booking, BookingsCompanion> {
  BookingsAdapter(this.resolver);
  final IdResolver resolver;

  @override
  String get collectionId => 'bookings';

  @override
  String get drivePath => 'bookings.json';

  @override
  String get tableName => 'bookings';

  /// يحل المراجع (UUID, serverId) ويعيد نتيجة تحتوي على المعرف المحلول والتواريخ.
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

  /// تحويل JSON إلى BookingsCompanion (جاهز للإدراج في Drift).
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
      totalDueCached: _vDouble(json, 'totalDueCached', src),
      totalPaidCached: _vDouble(json, 'totalPaidCached', src),
      remainingBalanceCached: _vDouble(json, 'remainingBalanceCached', src),
      isFullyPaid: _vBool(json, 'isFullyPaid', src),
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
      vectorClock: _vMapJson(
        json,
        'vectorClock',
        src,
        altKey: 'vector_clock',
        fallback: {},
      ),
    );
  }

  /// تحويل كائن Booking إلى JSON (لإرساله إلى Appwrite).
  /// يتم استخدام camelCase لجميع المفاتيح بفضل دالة _k.
  @override
  Map<String, dynamic> toJson(Booking model, {required Source src}) {
    return {
      _k(src, 'id'): model.id,
      _k(src, 'localUuid'): model.localUuid,
      _k(src, 'serverId'): model.serverId,
      _k(src, 'serverBookingId'): model.serverBookingId,
      _k(src, 'roomNumber'): model.roomNumber,
      _k(src, 'guestName'): model.guestName,
      _k(src, 'guestPhone'): model.guestPhone,
      _k(src, 'guestIdType'): model.guestIdType,
      _k(src, 'guestIdNumber'): model.guestIdNumber,
      _k(src, 'guestIdIssueDate'): model.guestIdIssueDate,
      _k(src, 'guestIdIssuePlace'): model.guestIdIssuePlace,
      _k(src, 'guestNationality'): model.guestNationality,
      _k(src, 'guestEmail'): model.guestEmail,
      _k(src, 'guestAddress'): model.guestAddress,
      _k(src, 'checkinDate'): model.checkinDate,
      _k(src, 'checkoutDate'): model.checkoutDate,
      _k(src, 'actualCheckout'): model.actualCheckout,
      _k(src, 'status'): model.status,
      _k(src, 'notes'): model.notes,
      _k(src, 'discount'): model.discount,
      _k(src, 'discountType'): model.discountType,
      _k(src, 'discountStartDate'): model.discountStartDate,
      _k(src, 'expectedNights'): model.expectedNights,
      _k(src, 'calculatedNights'): model.calculatedNights,
      _k(src, 'totalNightsCached'): model.totalNightsCached,
      _k(src, 'stayDurationIso'): model.stayDurationIso,
      _k(src, 'lastNightEpoch'): model.lastNightEpoch,
      _k(src, 'isOverdue'): model.isOverdue,
      _k(src, 'needsCheckoutReview'): model.needsCheckoutReview,
      _k(src, 'totalDueCached'): model.totalDueCached,
      _k(src, 'totalPaidCached'): model.totalPaidCached,
      _k(src, 'remainingBalanceCached'): model.remainingBalanceCached,
      _k(src, 'isFullyPaid'): model.isFullyPaid,
      _k(src, 'hotelDayCheckin'): model.hotelDayCheckin,
      _k(src, 'hotelDayCheckout'): model.hotelDayCheckout,
      _k(src, 'createdAt'): model.createdAt,
      _k(src, 'updatedAt'): model.updatedAt,
      _k(src, 'deletedAt'): model.deletedAt,
      _k(src, 'lastModified'): model.lastModified,
      _k(src, 'version'): model.version,
      _k(src, 'origin'): model.origin,
      _k(src, 'vectorClock'): jsonEncode(model.vectorClock),
    };
  }
}

// ================== الدوال المساعدة ==================

/// تحويل قيمة من JSON إلى d.Value<int> مع دعم القيم البديلة والافتراضية.
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

/// تحويل قيمة من JSON إلى d.Value<String> مع دعم القيم البديلة والافتراضية.
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

/// تحويل قيمة من JSON إلى d.Value<double> مع دعم القيم البديلة والافتراضية.
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

/// تحويل قيمة من JSON إلى d.Value<bool> مع دعم القيم البديلة والافتراضية.
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

/// استخراج قيمة epoch (عدد صحيح) من JSON، سواء كانت int أو String رقمية.
int? _epoch(Map<String, dynamic> json, String key, Source src) {
  final v = _asInt(json, key, src);
  if (v != null) return v;
  final s = _asString(json, key, src);
  if (s == null) return null;
  final parsed = int.tryParse(s);
  return parsed;
}

/// استخراج قيمة كـ int مع محاولة التحويل من bool/num/String.
int? _asInt(Map<String, dynamic> json, String key, Source src) {
  final v = _raw(json, key, src);
  if (v is bool) return v ? 1 : 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) {
    // تجاهل النصوص التي تشبه UUID أو طويلة جداً (ليست أرقام)
    if (v.contains('-') || v.length > 20) return null;
    return int.tryParse(v);
  }
  return null;
}

/// استخراج قيمة كـ double مع محاولة التحويل.
double? _asDouble(Map<String, dynamic> json, String key, Source src) {
  final v = _raw(json, key, src);
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

/// استخراج قيمة كـ String (تحويل أي شيء إلى String).
String? _asString(Map<String, dynamic> json, String key, Source src) {
  final v = _raw(json, key, src);
  if (v == null) return null;
  return v.toString();
}

/// استخراج قيمة كـ bool مع محاولة التحويل من String/num.
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

/// تحويل قيمة من JSON إلى d.Value<Map<String, dynamic>> مع دعم القيم البديلة والافتراضية.
d.Value<Map<String, dynamic>> _vMapJson(
  Map<String, dynamic> json,
  String key,
  Source src, {
  String? altKey,
  Map<String, dynamic>? fallback,
}) {
  final v =
      _asMap(json, key, src) ??
      (altKey != null ? _asMap(json, altKey, src) : null) ??
      fallback;
  return v == null ? const d.Value.absent() : d.Value(v);
}

/// استخراج قيمة كـ Map<String, dynamic> مع محاولة التحويل من String JSON.
Map<String, dynamic>? _asMap(
  Map<String, dynamic> json,
  String key,
  Source src,
) {
  final v = _raw(json, key, src);
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return Map<String, dynamic>.from(v);
  if (v is String) {
    try {
      final decoded = jsonDecode(v);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
  }
  return null;
}

/// الوصول الأولي للقيمة من JSON مع مراعاة الاسم البديل (إذا كان المصدر drive).
Object? _raw(Map<String, dynamic> json, String key, Source src) {
  if (json.containsKey(key)) return json[key];
  final alt = _altKey(key, src);
  if (alt != null && json.containsKey(alt)) return json[alt];
  return null;
}

/// اختيار اسم المفتاح المناسب عند إنشاء JSON للإرسال.
/// تم تعديلها لإرجاع camelCase دائماً ليتوافق مع Appwrite.
String _k(Source src, String camel) => camel;

/// إنشاء مفتاح بديل بصيغة snake_case من camelCase (للبحث في JSON القديم).
/// يُستخدم فقط عند القراءة من مصدر drive (Appwrite) للتوافق مع البيانات القديمة.
String? _altKey(String camel, Source src) {
  if (src != Source.drive) return null; // فقط drive يحتاج بديلاً
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
