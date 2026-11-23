// ══════════════════════════════════════════════════════════════════
//  booking_night_payload.dart — لقطة صف ليلة كاملة لحمولة D1
//
//  العقد (outbox_dao.dart:283-286): «الصانع الجزئي يجب أن يرسل لقطة صف
//  كاملة». الحمولات الرقيقة `{'localUuid': ...}` كانت تُترجم على الخادم
//  إلى create بقيم NOT NULL الافتراضية (booking_local_id=0,
//  hotel_day_key='') لأن worker يعيد تنفيذ update الغائب كـ create
//  (worker/src/database.ts:1446-1453 + :1282-1302) — وهذا أحد جذور
//  الليالي اليتيمة والمكررة.
//
//  هذا الملف يجعل لكل منتج لحمولة ليلة نقطة واحدة تُنتج فيها اللقطة
//  الكاملة، فلا يعود أي مسار يرسل `{localUuid}` وحده.
// ══════════════════════════════════════════════════════════════════

import '../adapters/id_resolver.dart';
import '../adapters/nights_adapter.dart';
import '../adapters/source.dart';
import '../daos/outbox_dao.dart';
import '../local_db.dart';

/// باني حمولة `booking_nights` — لقطة صف كاملة بأسماء camelCase
/// (يُحوّلها PayloadNormalizer إلى snake_case عند نقطة الرفع).
class BookingNightPayloadBuilder {
  BookingNightPayloadBuilder(AppDatabase db)
    : _adapter = NightsAdapter(IdResolver(db));

  final NightsAdapter _adapter;

  /// لقطة صف كاملة. `id` المحلي يُحذف: هوية السلك هي `local_uuid`
  /// (worker/src/sync.ts: resolvePushEntityId) ولا معنى لرقم جهاز آخر.
  Map<String, dynamic> build(BookingNight row) {
    final json = _adapter.toJson(row, src: Source.appwrite);
    json.remove('id');
    return json;
  }

  /// إدراج/تحديث عنصر outbox بحمولة كاملة للصف [row].
  ///
  /// [tombstonedAt] (ثواني epoch) يحوّل العنصر إلى إعلان موت: تُضاف حقول
  /// `deletedAt` ويرتفع `lastModified/version` كي يفوز الإخفاء على أي نسخة
  /// أحدث محلياً على جهاز آخر (عقد LWW على worker). بدون هذه اللقطة
  /// الكاملة كان الصف الميت يُنشأ على D1 من جديد بقيم 0/'' — أصل اليتامى.
  Future<void> enqueue({
    required OutboxDao outboxDao,
    required BookingNight row,
    required String op,
    required int clientTs,
    int? tombstonedAt,
    String? tombstonedAtIso,
  }) async {
    final payload = build(row);
    if (tombstonedAt != null) {
      payload
        ..['deletedAt'] = tombstonedAt
        ..['deletedAtIso'] = tombstonedAtIso
        ..['updatedAt'] = tombstonedAt
        ..['updatedAtIso'] = tombstonedAtIso
        ..['lastModified'] = tombstonedAt
        ..['lastModifiedEpoch'] = tombstonedAt
        ..['version'] = row.version + 1;
    }
    await outboxDao.merge(
      entity: 'booking_nights',
      op: op,
      localUuid: row.localUuid,
      payload: payload,
      clientTs: clientTs,
    );
  }
}
