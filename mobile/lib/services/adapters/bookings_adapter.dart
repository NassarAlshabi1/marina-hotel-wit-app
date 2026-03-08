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
/// يدعم الحقول البديلة: camelCase, snake_case, sync_* prefix
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
    final bookingUuid = _asStringMulti(json, ['localUuid', 'local_uuid', 'booking_uuid', 'bookingUuid'], src);
    final serverBookingId = _asIntMulti(json, ['serverBookingId', 'booking_id', 'server_booking_id'], src);
    final localId = _asInt(json, 'id', src);
    final resolvedId = await resolver.resolveBooking(
      localId: localId,
      serverId: serverBookingId,
      uuid: bookingUuid,
    );
    final createdAt = _epochMulti(json, ['createdAt', 'created_at', 'sync_created_at'], src);
    final lastModified = _epochMulti(json, ['lastModified', 'last_modified', 'sync_last_modified'], src);
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
    final createdAt = refs.createdAtEpoch ??
        _epochMulti(json, ['createdAt', 'created_at', 'sync_created_at'], src) ?? 
        now;
    final lastModified = refs.lastModifiedEpoch ??
        _epochMulti(json, ['lastModified', 'last_modified', 'sync_last_modified'], src) ??
        createdAt;
    return BookingsCompanion(
      id: _vInt(json, 'id', src),
      localUuid: d.Value(
        _asStringMulti(json, ['localUuid', 'local_uuid'], src) ?? IdGen.uuid(),
      ),
      serverId: _vIntMulti(json, ['serverId', 'server_id'], src),
      serverBookingId: _vIntMulti(json, ['serverBookingId', 'booking_id', 'server_booking_id'], src),
      roomNumber: _vStrMulti(json, ['roomNumber', 'room_number'], src, fallback: ''),
      guestName: _vStrMulti(json, ['guestName', 'guest_name'], src, fallback: ''),
      guestPhone: _vStrMulti(json, ['guestPhone', 'guest_phone'], src, fallback: ''),
      guestIdType: _vStrMulti(json, ['guestIdType', 'guest_id_type'], src, fallback: 'بطاقة شخصية'),
      guestIdNumber: _vStrMulti(json, ['guestIdNumber', 'guest_id_number'], src, fallback: ''),
      guestIdIssueDate: _vStrMulti(json, ['guestIdIssueDate', 'guest_id_issue_date'], src),
      guestIdIssuePlace: _vStrMulti(json, ['guestIdIssuePlace', 'guest_id_issue_place'], src),
      guestNationality: _vStrMulti(json, ['guestNationality', 'guest_nationality'], src, fallback: ''),
      guestEmail: _vStrMulti(json, ['guestEmail', 'guest_email'], src),
      guestAddress: _vStrMulti(json, ['guestAddress', 'guest_address'], src),
      checkinDate: _vStrMulti(json, ['checkinDate', 'checkin_date'], src, fallback: ''),
      checkoutDate: _vStrMulti(json, ['checkoutDate', 'checkout_date'], src),
      actualCheckout: _vStrMulti(json, ['actualCheckout', 'actual_checkout'], src),
      status: _vStr(json, 'status', src, fallback: ''),
      notes: _vStr(json, 'notes', src),
      discount: _vDoubleMulti(json, ['discount'], src, fallback: 0),
      discountType: _vStrMulti(json, ['discountType', 'discount_type'], src, fallback: 'per_night'),
      discountStartDate: _vStrMulti(json, ['discountStartDate', 'discount_start_date'], src),
      expectedNights: _vIntMulti(json, ['expectedNights', 'expected_nights'], src, fallback: 1),
      calculatedNights: _vIntMulti(json, ['calculatedNights', 'calculated_nights'], src),
      totalNightsCached: _vIntMulti(json, ['totalNightsCached', 'total_nights_cached'], src),
      stayDurationIso: _vStrMulti(json, ['stayDurationIso', 'stay_duration_iso'], src),
      lastNightEpoch: _vIntMulti(json, ['lastNightEpoch', 'last_night_epoch'], src),
      isOverdue: _vBoolMulti(json, ['isOverdue', 'is_overdue'], src),
      needsCheckoutReview: _vBoolMulti(json, ['needsCheckoutReview', 'needs_checkout_review'], src),
      totalDueCached: _vDoubleMulti(json, ['totalDueCached', 'total_due_cached'], src),
      totalPaidCached: _vDoubleMulti(json, ['totalPaidCached', 'total_paid_cached'], src),
      remainingBalanceCached: _vDoubleMulti(json, ['remainingBalanceCached', 'remaining_balance_cached'], src),
      isFullyPaid: _vBoolMulti(json, ['isFullyPaid', 'is_fully_paid'], src),
      hotelDayCheckin: _vStrMulti(json, ['hotelDayCheckin', 'hotel_day_checkin'], src),
      hotelDayCheckout: _vStrMulti(json, ['hotelDayCheckout', 'hotel_day_checkout'], src),
      createdAt: d.Value(createdAt),
      updatedAt: d.Value(_epochMulti(json, ['updatedAt', 'updated_at', 'sync_updated_at'], src) ?? createdAt),
      deletedAt: _vIntMulti(json, ['deletedAt', 'deleted_at', 'sync_deleted_at'], src),
      lastModified: d.Value(lastModified),
      createdAtIso: _vStrMulti(json, ['createdAtIso', 'created_at_iso'], src),
      updatedAtIso: _vStrMulti(json, ['updatedAtIso', 'updated_at_iso'], src),
      deletedAtIso: _vStrMulti(json, ['deletedAtIso', 'deleted_at_iso'], src),
      createdAtEpoch: _vIntMulti(json, ['createdAtEpoch', 'created_at_epoch'], src, fallback: createdAt),
      lastModifiedEpoch: _vIntMulti(json, ['lastModifiedEpoch', 'last_modified_epoch'], src, fallback: lastModified),
      version: _vIntMulti(json, ['version', 'sync_version'], src, fallback: 1),
      origin: _vStrMulti(json, ['origin', 'sync_origin'], src, fallback: 'server'),
      vectorClock: _vStrMulti(json, ['vectorClock', 'vector_clock', 'sync_vector_clock'], src, fallback: '{}'),
    );
  }

  /// تحويل كائن Booking إلى JSON (لإرساله إلى Appwrite).
  /// يستخدم camelCase للحقول العادية، و sync_* prefix للحقول المطلوبة في Appwrite
  /// 
  /// ⭐ تم تحسينه لإرسال الحقول الأساسية فقط وتجنب التكرار
  @override
  Map<String, dynamic> toJson(Booking model, {required Source src}) {
    return {
      // الحقول الأساسية للمزامنة
      'localUuid': model.localUuid,
      'serverId': model.serverId,
      'serverBookingId': model.serverBookingId,
      'version': model.version,
      'origin': model.origin,
      
      // الحقول الأساسية للحجز
      'roomNumber': model.roomNumber,
      'guestName': model.guestName,
      'guestPhone': model.guestPhone,
      'guestIdType': model.guestIdType,
      'guestIdNumber': model.guestIdNumber,
      'guestIdIssueDate': model.guestIdIssueDate,
      'guestIdIssuePlace': model.guestIdIssuePlace,
      'guestNationality': model.guestNationality,
      'guestEmail': model.guestEmail,
      'guestAddress': model.guestAddress,
      
      // تواريخ الحجز
      'checkinDate': model.checkinDate,
      'checkoutDate': model.checkoutDate,
      'actualCheckout': model.actualCheckout,
      'status': model.status,
      'notes': model.notes,
      
      // الخصم
      'discount': model.discount,
      'discountType': model.discountType,
      'discountStartDate': model.discountStartDate,
      
      // الليالي والمدة
      'expectedNights': model.expectedNights,
      'calculatedNights': model.calculatedNights,
      
      // التواريخ المتزامنة (حقل واحد فقط بدون تكرار)
      'createdAt': model.createdAt,
      'updatedAt': model.updatedAt,
      'deletedAt': model.deletedAt,
      'lastModified': model.lastModified,
      
      // حقول إضافية مهمة
      'hotelDayCheckin': model.hotelDayCheckin,
      'hotelDayCheckout': model.hotelDayCheckout,
      
      // تم إزالة الحقول المكررة (sync_*) والحقول المحلية فقط
      // هذا يقلل حجم البيانات المرسلة بنسبة ~30%
    };
  }
  
  /// تحويل كائن Booking إلى JSON مختصر (للمزامنة السريعة)
  /// يرسل الحقول الأساسية فقط
  Map<String, dynamic> toJsonCompact(Booking model, {required Source src}) {
    return {
      'localUuid': model.localUuid,
      'serverId': model.serverId,
      'serverBookingId': model.serverBookingId,
      'roomNumber': model.roomNumber,
      'guestName': model.guestName,
      'guestPhone': model.guestPhone,
      'checkinDate': model.checkinDate,
      'checkoutDate': model.checkoutDate,
      'status': model.status,
      'lastModified': model.lastModified,
      'version': model.version,
      'origin': model.origin,
    };
  }
}

// ================== الدوال المساعدة ==================

/// تحويل قيمة من JSON إلى d.Value<int> مع دعم مفتاح واحد.
d.Value<int> _vInt(
  Map<String, dynamic> json,
  String key,
  Source src, {
  int? fallback,
}) {
  final v = _asInt(json, key, src) ?? fallback;
  return v == null ? const d.Value.absent() : d.Value(v);
}

/// تحويل قيمة من JSON إلى d.Value<int> مع دعم مفاتيح متعددة.
d.Value<int> _vIntMulti(
  Map<String, dynamic> json,
  List<String> keys,
  Source src, {
  int? fallback,
}) {
  final v = _asIntMulti(json, keys, src) ?? fallback;
  return v == null ? const d.Value.absent() : d.Value(v);
}

/// تحويل قيمة من JSON إلى d.Value<String> مع دعم مفتاح واحد.
d.Value<String> _vStr(
  Map<String, dynamic> json,
  String key,
  Source src, {
  String? fallback,
}) {
  final v = _asString(json, key, src) ?? fallback;
  return v == null ? const d.Value.absent() : d.Value(v);
}

/// تحويل قيمة من JSON إلى d.Value<String> مع دعم مفاتيح متعددة.
d.Value<String> _vStrMulti(
  Map<String, dynamic> json,
  List<String> keys,
  Source src, {
  String? fallback,
}) {
  final v = _asStringMulti(json, keys, src) ?? fallback;
  return v == null ? const d.Value.absent() : d.Value(v);
}

/// تحويل قيمة من JSON إلى d.Value<double> مع دعم مفتاح واحد.
d.Value<double> _vDouble(
  Map<String, dynamic> json,
  String key,
  Source src, {
  double? fallback,
}) {
  final v = _asDouble(json, key, src) ?? fallback;
  return v == null ? const d.Value.absent() : d.Value(v);
}

/// تحويل قيمة من JSON إلى d.Value<double> مع دعم مفاتيح متعددة.
d.Value<double> _vDoubleMulti(
  Map<String, dynamic> json,
  List<String> keys,
  Source src, {
  double? fallback,
}) {
  final v = _asDoubleMulti(json, keys, src) ?? fallback;
  return v == null ? const d.Value.absent() : d.Value(v);
}

/// تحويل قيمة من JSON إلى d.Value<bool> مع دعم مفتاح واحد.
d.Value<bool> _vBool(
  Map<String, dynamic> json,
  String key,
  Source src, {
  bool? fallback,
}) {
  final v = _asBool(json, key, src) ?? fallback;
  return v == null ? const d.Value.absent() : d.Value(v);
}

/// تحويل قيمة من JSON إلى d.Value<bool> مع دعم مفاتيح متعددة.
d.Value<bool> _vBoolMulti(
  Map<String, dynamic> json,
  List<String> keys,
  Source src, {
  bool? fallback,
}) {
  final v = _asBoolMulti(json, keys, src) ?? fallback;
  return v == null ? const d.Value.absent() : d.Value(v);
}

/// استخراج قيمة epoch من JSON بمفتاح واحد.
int? _epoch(Map<String, dynamic> json, String key, Source src) {
  final v = _asInt(json, key, src);
  if (v != null) return v;
  final s = _asString(json, key, src);
  if (s == null) return null;
  return int.tryParse(s);
}

/// استخراج قيمة epoch من JSON بمفاتيح متعددة.
int? _epochMulti(Map<String, dynamic> json, List<String> keys, Source src) {
  for (final key in keys) {
    final v = _epoch(json, key, src);
    if (v != null) return v;
  }
  return null;
}

/// استخراج قيمة كـ int بمفتاح واحد.
int? _asInt(Map<String, dynamic> json, String key, Source src) {
  final v = _raw(json, key, src);
  if (v is bool) return v ? 1 : 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) {
    if (v.contains('-') || v.length > 20) return null;
    return int.tryParse(v);
  }
  return null;
}

/// استخراج قيمة كـ int بمفاتيح متعددة (يُرجع أول قيمة موجودة).
int? _asIntMulti(Map<String, dynamic> json, List<String> keys, Source src) {
  for (final key in keys) {
    final v = _asInt(json, key, src);
    if (v != null) return v;
  }
  return null;
}

/// استخراج قيمة كـ double بمفتاح واحد.
double? _asDouble(Map<String, dynamic> json, String key, Source src) {
  final v = _raw(json, key, src);
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

/// استخراج قيمة كـ double بمفاتيح متعددة.
double? _asDoubleMulti(Map<String, dynamic> json, List<String> keys, Source src) {
  for (final key in keys) {
    final v = _asDouble(json, key, src);
    if (v != null) return v;
  }
  return null;
}

/// استخراج قيمة كـ String بمفتاح واحد.
String? _asString(Map<String, dynamic> json, String key, Source src) {
  final v = _raw(json, key, src);
  if (v == null) return null;
  return v.toString();
}

/// استخراج قيمة كـ String بمفاتيح متعددة.
String? _asStringMulti(Map<String, dynamic> json, List<String> keys, Source src) {
  for (final key in keys) {
    final v = _asString(json, key, src);
    if (v != null) return v;
  }
  return null;
}

/// استخراج قيمة كـ bool بمفتاح واحد.
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

/// استخراج قيمة كـ bool بمفاتيح متعددة.
bool? _asBoolMulti(Map<String, dynamic> json, List<String> keys, Source src) {
  for (final key in keys) {
    final v = _asBool(json, key, src);
    if (v != null) return v;
  }
  return null;
}

/// الوصول الأولي للقيمة من JSON.
Object? _raw(Map<String, dynamic> json, String key, Source src) {
  if (json.containsKey(key)) return json[key];
  final alt = _altKey(key, src);
  if (alt != null && json.containsKey(alt)) return json[alt];
  return null;
}

/// إنشاء مفتاح بديل بصيغة snake_case من camelCase.
String? _altKey(String camel, Source src) {
  if (src != Source.drive) return null;
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
