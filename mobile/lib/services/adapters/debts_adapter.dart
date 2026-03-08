import 'package:drift/drift.dart' as d;

import '../local_db.dart';
import '../../utils/id.dart';
import '../../utils/time.dart';
import 'entity_adapter.dart';
import 'id_resolver.dart';
import 'resolve_result.dart';
import 'source.dart';

/// محول لتحويل بيانات الديون بين JSON المحلي/السحابي وكائنات Drift.
/// يدعم الحقول البديلة: camelCase, snake_case, sync_* prefix
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
    final bookingUuid = _asStringMulti(json, ['bookingUuidCache', 'booking_uuid_cache', 'booking_uuid'], src);
    final serverBookingId = _asIntMulti(json, ['serverBookingId', 'booking_id'], src);
    final localId = _asIntMulti(json, ['bookingLocalId', 'booking_local_id'], src);
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

  @override
  DebtsCompanion fromJson(
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
    return DebtsCompanion(
      id: _vInt(json, 'id', src),
      localUuid: d.Value(
        _asStringMulti(json, ['localUuid', 'local_uuid'], src) ?? IdGen.uuid(),
      ),
      serverId: _vIntMulti(json, ['serverId', 'server_id'], src),
      bookingLocalId: refs.bookingLocalId != null
          ? d.Value(refs.bookingLocalId)
          : _vIntMulti(json, ['bookingLocalId', 'booking_local_id'], src),
      guestName: _vStrMulti(json, ['guestName', 'guest_name'], src, fallback: ''),
      checkinDate: _vStrMulti(json, ['checkinDate', 'checkin_date'], src, fallback: ''),
      checkoutDate: _vStrMulti(json, ['checkoutDate', 'checkout_date'], src, fallback: ''),
      dateRecorded: _vStrMulti(json, ['dateRecorded', 'date_recorded'], src, fallback: ''),
      debtReason: _vStrMulti(json, ['debtReason', 'debt_reason'], src, fallback: ''),
      totalAmount: _vDoubleMulti(json, ['totalAmount', 'total_amount'], src, fallback: 0),
      paidAmount: _vDoubleMulti(json, ['paidAmount', 'paid_amount'], src, fallback: 0),
      remainingAmount: _vDoubleMulti(json, ['remainingAmount', 'remaining_amount'], src, fallback: 0),
      paymentDate: _vStrMulti(json, ['paymentDate', 'payment_date'], src, fallback: ''),
      isSettled: _vIntMulti(json, ['isSettled', 'is_settled'], src, fallback: 0),
      pledge: _vStr(json, 'pledge', src),
      pledgeType: _vStrMulti(json, ['pledgeType', 'pledge_type'], src),
      note: _vStr(json, 'note', src),
      debtUuid: _vStrMulti(json, ['debtUuid', 'debt_uuid'], src),
      hotelDayOpened: _vStrMulti(json, ['hotelDayOpened', 'hotel_day_opened'], src),
      hotelDayClosed: _vStrMulti(json, ['hotelDayClosed', 'hotel_day_closed'], src),
      isFromAutoFix: _vBoolMulti(json, ['isFromAutoFix', 'is_from_auto_fix'], src, fallback: false),
      settlementConfirmed: _vBoolMulti(json, ['settlementConfirmed', 'settlement_confirmed'], src, fallback: false),
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

  @override
  Map<String, dynamic> toJson(Debt model, {required Source src}) {
    return {
      // الحقول الأساسية للمزامنة
      'localUuid': model.localUuid,
      'serverId': model.serverId,
      'version': model.version,
      'origin': model.origin,
      
      // الحقول الأساسية للديون
      'bookingLocalId': model.bookingLocalId,
      'guestName': model.guestName,
      'checkinDate': model.checkinDate,
      'checkoutDate': model.checkoutDate,
      'dateRecorded': model.dateRecorded,
      'debtReason': model.debtReason,
      
      // المبالغ
      'totalAmount': model.totalAmount,
      'paidAmount': model.paidAmount,
      'remainingAmount': model.remainingAmount,
      
      // حالة السداد
      'paymentDate': model.paymentDate,
      'isSettled': model.isSettled,
      'settlementConfirmed': model.settlementConfirmed,
      
      // معلومات إضافية
      'pledge': model.pledge,
      'pledgeType': model.pledgeType,
      'note': model.note,
      'debtUuid': model.debtUuid,
      'hotelDayOpened': model.hotelDayOpened,
      'hotelDayClosed': model.hotelDayClosed,
      'isFromAutoFix': model.isFromAutoFix,
      
      // التواريخ المتزامنة (حقل واحد فقط بدون تكرار)
      'createdAt': model.createdAt,
      'updatedAt': model.updatedAt,
      'deletedAt': model.deletedAt,
      'lastModified': model.lastModified,
      
      // تم إزالة الحقول المكررة (sync_*) والحقول المحلية فقط
      // هذا يقلل حجم البيانات المرسلة بنسبة ~35%
    };
  }
  
  /// تحويل مختصر للمزامنة السريعة
  Map<String, dynamic> toJsonCompact(Debt model, {required Source src}) {
    return {
      'localUuid': model.localUuid,
      'serverId': model.serverId,
      'guestName': model.guestName,
      'totalAmount': model.totalAmount,
      'paidAmount': model.paidAmount,
      'remainingAmount': model.remainingAmount,
      'isSettled': model.isSettled,
      'lastModified': model.lastModified,
      'version': model.version,
      'origin': model.origin,
    };
  }
}

// ================== الدوال المساعدة ==================

d.Value<int> _vInt(
  Map<String, dynamic> json,
  String key,
  Source src, {
  int? fallback,
}) {
  final v = _asInt(json, key, src) ?? fallback;
  return v == null ? const d.Value.absent() : d.Value(v);
}

d.Value<int> _vIntMulti(
  Map<String, dynamic> json,
  List<String> keys,
  Source src, {
  int? fallback,
}) {
  final v = _asIntMulti(json, keys, src) ?? fallback;
  return v == null ? const d.Value.absent() : d.Value(v);
}

d.Value<String> _vStr(
  Map<String, dynamic> json,
  String key,
  Source src, {
  String? fallback,
}) {
  final v = _asString(json, key, src) ?? fallback;
  return v == null ? const d.Value.absent() : d.Value(v);
}

d.Value<String> _vStrMulti(
  Map<String, dynamic> json,
  List<String> keys,
  Source src, {
  String? fallback,
}) {
  final v = _asStringMulti(json, keys, src) ?? fallback;
  return v == null ? const d.Value.absent() : d.Value(v);
}

d.Value<double> _vDouble(
  Map<String, dynamic> json,
  String key,
  Source src, {
  double? fallback,
}) {
  final v = _asDouble(json, key, src) ?? fallback;
  return v == null ? const d.Value.absent() : d.Value(v);
}

d.Value<double> _vDoubleMulti(
  Map<String, dynamic> json,
  List<String> keys,
  Source src, {
  double? fallback,
}) {
  final v = _asDoubleMulti(json, keys, src) ?? fallback;
  return v == null ? const d.Value.absent() : d.Value(v);
}

d.Value<bool> _vBool(
  Map<String, dynamic> json,
  String key,
  Source src, {
  bool? fallback,
}) {
  final v = _asBool(json, key, src) ?? fallback;
  return v == null ? const d.Value.absent() : d.Value(v);
}

d.Value<bool> _vBoolMulti(
  Map<String, dynamic> json,
  List<String> keys,
  Source src, {
  bool? fallback,
}) {
  final v = _asBoolMulti(json, keys, src) ?? fallback;
  return v == null ? const d.Value.absent() : d.Value(v);
}

int? _epoch(Map<String, dynamic> json, String key, Source src) {
  final v = _asInt(json, key, src);
  if (v != null) return v;
  final s = _asString(json, key, src);
  if (s == null) return null;
  return int.tryParse(s);
}

int? _epochMulti(Map<String, dynamic> json, List<String> keys, Source src) {
  for (final key in keys) {
    final v = _epoch(json, key, src);
    if (v != null) return v;
  }
  return null;
}

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

int? _asIntMulti(Map<String, dynamic> json, List<String> keys, Source src) {
  for (final key in keys) {
    final v = _asInt(json, key, src);
    if (v != null) return v;
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

double? _asDoubleMulti(Map<String, dynamic> json, List<String> keys, Source src) {
  for (final key in keys) {
    final v = _asDouble(json, key, src);
    if (v != null) return v;
  }
  return null;
}

String? _asString(Map<String, dynamic> json, String key, Source src) {
  final v = _raw(json, key, src);
  if (v == null) return null;
  return v.toString();
}

String? _asStringMulti(Map<String, dynamic> json, List<String> keys, Source src) {
  for (final key in keys) {
    final v = _asString(json, key, src);
    if (v != null) return v;
  }
  return null;
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

bool? _asBoolMulti(Map<String, dynamic> json, List<String> keys, Source src) {
  for (final key in keys) {
    final v = _asBool(json, key, src);
    if (v != null) return v;
  }
  return null;
}

Object? _raw(Map<String, dynamic> json, String key, Source src) {
  if (json.containsKey(key)) return json[key];
  final alt = _altKey(key, src);
  if (alt != null && json.containsKey(alt)) return json[alt];
  return null;
}

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
