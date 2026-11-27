import 'package:drift/drift.dart' as d;

import '../utils/debug_log.dart';
import 'local_db.dart';

/// ✅ الربط الرجعي لـ bookingLocalId في الدفعات غير المرتبطة محلياً
/// (المرحلة 2.2 من خطة الإصلاح — نمط BookingChildUuidBackfillService).
///
/// نمط الإنتاج الموثق: الدفعات المسحوبة من السحابة عبر المزامنة ترتبط
/// بحجزها بـ bookingUuidCache فقط وربما بلا bookingLocalId (98/172 دفعة
/// لحجز غرفة 203). المسارات القديمة التي تستهلك بالمعرف المحلي وحده
/// كانت تُخفي هذه الدفعات من كشف الحساب وإجمالي قائمة الحجوزات.
///
/// القواعد:
///   • الحسم بالهوية العابرة: booking_uuid_cache (بصيغتيه) هو المصدر.
///   • تُربط فقط الدفعات ذات booking_local_id = NULL — لا يُلمس معرف
///     محلي موجود أبداً (قد يكون ثمرة نقلٍ محلي مقصود؛ تحديث الدفعة
///     القديم لا يزامن bookingUuidCache عند النقل فلا يُخمَّن مكانه).
///   • لا re-push: bookingLocalId محلي بطبيعته ولا يُرفع للسحابة إطلاقاً
///     (payload_mapper.paymentToRemote يستثنيه — UUID هو الرابط السحابي).
///   • لا كتابة lastModified: المحتوى المتزامن لم يتغير.
///   • العملية idempotent بطبيعتها (شرط IS NULL يخلوها بعد الربط).
class PaymentsBookingLinkBackfillService {
  PaymentsBookingLinkBackfillService._();
  static final PaymentsBookingLinkBackfillService instance =
      PaymentsBookingLinkBackfillService._();

  static const _chunkSize = 500;

  bool _applied = false;

  /// Runs at most once per session; idempotent.
  Future<int> runIfNeeded(AppDatabase db) async {
    if (_applied) return 0;
    _applied = true;
    try {
      return await backfillPayments(db);
    } catch (e) {
      dwarn(() => '⚠️ PaymentsBookingLinkBackfill: $e');
      return 0;
    }
  }

  /// Fills `bookingLocalId` on payments whose `bookingUuidCache` resolves to a
  /// local booking. Matching accepts both UUID formats (dashed and compact) —
  /// the normalization BaseRepository applies on upsert.
  Future<int> backfillPayments(AppDatabase db) async {
    final rows = await db
        .customSelect(
          'SELECT p.id AS payment_id, b.id AS booking_id, '
          'p.local_uuid AS payment_uuid '
          'FROM payments p '
          'JOIN bookings b '
          'ON replace(b.local_uuid, \'-\', \'\') '
          '= replace(p.booking_uuid_cache, \'-\', \'\') '
          'WHERE p.booking_local_id IS NULL '
          'AND p.deleted_at IS NULL '
          "AND p.booking_uuid_cache IS NOT NULL AND p.booking_uuid_cache <> '' "
          "AND b.local_uuid IS NOT NULL AND b.local_uuid <> '' "
          'AND b.deleted_at IS NULL',
          readsFrom: {db.payments, db.bookings},
        )
        .get();
    if (rows.isEmpty) return 0;

    var linked = 0;
    for (var i = 0; i < rows.length; i += _chunkSize) {
      final chunk = rows.sublist(
        i,
        i + _chunkSize < rows.length ? i + _chunkSize : rows.length,
      );
      await db.transaction(() async {
        for (final row in chunk) {
          await (db.update(
            db.payments,
          )..where((p) => p.id.equals(row.read<int>('payment_id')))).write(
            PaymentsCompanion(
              bookingLocalId: d.Value(row.read<int>('booking_id')),
              // لا lastModified: المحتوى المتزامن لم يتغير وbookingLocalId
              // محلي بطبيعته (لا يُرفع) — نفس عقيدة backfillNights.
            ),
          );
          linked++;
        }
      });
    }
    if (linked > 0) {
      dlog(
        () => '✅ PaymentsBookingLinkBackfill: ربط $linked دفعة '
            'غير مرتبطة محلياً بحجوزاتها (عبر UUID)',
      );
    }
    return linked;
  }
}
