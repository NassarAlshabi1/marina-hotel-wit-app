// ignore_for_file: avoid_print, sort_constructors_first

import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart';

import '../utils/id.dart';
import '../utils/time.dart';
import 'appwrite_sync_manager.dart';
import 'daos/outbox_dao.dart';
import 'local_db.dart';

/// خدمة إلغاء الدفعات (Payment Void)
///
/// عند إلغاء دفعة:
/// 1. تُنشأ سجل PaymentVoid يحوي تفاصيل الإلغاء (المبلغ، السبب، المُلغي، الوقت)
/// 2. تُحدَّث الدفعة الأصلية: isVoided=true, voidedAt, voidedBy, voidReason
/// 3. يُسجَّل PaymentVoid في outbox للمزامنة مع Appwrite Cloud
/// 4. تُحدَّث الدفعة في outbox أيضاً (لأن isVoided تغيّر)
class PaymentVoidService {
  final AppDatabase _db;
  final OutboxDao _outboxDao;

  PaymentVoidService(this._db) : _outboxDao = OutboxDao(_db);

  /// إلغاء دفعة موجودة
  ///
  /// [paymentUuid] — localUuid للدفعة المراد إلغاؤها
  /// [voidReason] — سبب الإلغاء
  /// [voidedBy] — اسم/معرف المستخدم الذي ألغى الدفعة
  /// [approvedBy] — اسم/معرف المستخدم الذي وافق على الإلغاء (اختياري)
  ///
  /// يُرجع true عند نجاح الإلغاء، false إذا الدفعة غير موجودة أو مُلغاة مسبقاً
  Future<bool> voidPayment({
    required String paymentUuid,
    required String voidReason,
    required String voidedBy,
    String? approvedBy,
  }) async {
    try {
      return await _db.transaction(() async {
        // 1) جلب الدفعة الأصلية
        final payment =
            await (_db.select(_db.payments)
                  ..where((t) => t.localUuid.equals(paymentUuid))
                  ..limit(1))
                .getSingleOrNull();

        if (payment == null) {
          debugPrint('⚠️ PaymentVoid: الدفعة $paymentUuid غير موجودة');
          return false;
        }

        if (payment.isVoided) {
          debugPrint('⚠️ PaymentVoid: الدفعة $paymentUuid مُلغاة مسبقاً');
          return false;
        }

        final nowEpoch = Time.nowEpoch();
        final nowIso = DateTime.now().toIso8601String();
        final voidUuid = IdGen.uuid();

        // 1.5) حل bookingUuid و hotelDayKey من الدفعة أو من الحجز المرتبط
        String bookingUuid = payment.bookingUuidCache ?? '';
        String hotelDayKey = payment.hotelDayKey ?? '';

        // إذا لم يكن bookingUuid متوفراً، نحاول حله من bookingLocalId
        if (bookingUuid.isEmpty && payment.bookingLocalId != null) {
          final booking =
              await (_db.select(_db.bookings)
                    ..where((t) => t.id.equals(payment.bookingLocalId!))
                    ..limit(1))
                  .getSingleOrNull();
          if (booking != null) {
            bookingUuid = booking.localUuid;
          }
        }

        // إذا لم يكن hotelDayKey متوفراً، نستمده من paymentDate
        if (hotelDayKey.isEmpty && payment.paymentDate.isNotEmpty) {
          hotelDayKey = payment.paymentDate;
        }

        // إذا لم نتمكن من حل bookingUuid، نرفض العملية
        if (bookingUuid.isEmpty) {
          debugPrint('⚠️ PaymentVoid: تعذر حل bookingUuid للدفعة $paymentUuid');
          return false;
        }

        // 2) إنشاء سجل PaymentVoid
        await _db
            .into(_db.paymentVoids)
            .insert(
              PaymentVoidsCompanion.insert(
                localUuid: voidUuid,
                originalPaymentUuid: paymentUuid,
                originalPaymentId: payment.id,
                bookingUuid: bookingUuid,
                voidedAmount: payment.amount.round(),
                voidReason: voidReason,
                voidedBy: voidedBy,
                voidedAt: nowEpoch,
                voidedAtIso: nowIso,
                hotelDayKey: hotelDayKey,
                createdAt: nowEpoch,
                updatedAt: nowEpoch,
                lastModified: nowEpoch,
                origin: const drift.Value('local'),
                deviceId: drift.Value(AppwriteSyncManager.currentDeviceIdStatic ?? ''),
                approvedBy: drift.Value(approvedBy),
              ),
            );

        // 3) تحديث الدفعة الأصلية: isVoided=true + voidedAt + voidedBy
        // ✅ bump version لتفعيل OCC عند الدفع لاحقاً
        await (_db.update(_db.payments)..where((t) => t.localUuid.equals(paymentUuid))).write(
          PaymentsCompanion(
            isVoided: const drift.Value(true),
            voidedAt: drift.Value(nowEpoch),
            voidedBy: drift.Value(voidedBy),
            updatedAt: drift.Value(nowEpoch),
            lastModified: drift.Value(nowEpoch),
            version: drift.Value(payment.version + 1),
          ),
        );

        // 4) تسجيل PaymentVoid في outbox للمزامنة
        await _outboxDao.merge(
          entity: 'payment_voids',
          op: 'create',
          localUuid: voidUuid,
          clientTs: nowEpoch,
          payload: {
            'originalPaymentUuid': paymentUuid,
            'originalPaymentId': payment.id,
            'bookingUuid': bookingUuid,
            'voidedAmount': payment.amount.round(),
            'voidReason': voidReason,
            'voidedBy': voidedBy,
            'voidedAt': nowEpoch,
            'voidedAtIso': nowIso,
            'hotelDayKey': hotelDayKey,
            if (approvedBy != null) 'approvedBy': approvedBy,
          },
        );

        // 5) تحديث outbox للدفعة المُلغاة (لأن isVoided تغيّر)
        await _outboxDao.merge(
          entity: 'payments',
          op: 'update',
          localUuid: paymentUuid,
          clientTs: nowEpoch,
          payload: {
            'isVoided': true,
            'voidedAt': nowEpoch,
            'voidedBy': voidedBy,
            'voidReason': voidReason,
            'isImmutable': true,
          },
        );

        debugPrint('✅ PaymentVoid: تم إلغاء الدفعة $paymentUuid بنجاح');
        return true;
      });
    } catch (e, st) {
      debugPrint('❌ PaymentVoid: فشل إلغاء الدفعة $paymentUuid: $e');
      debugPrint('Stack: $st');
      return false;
    }
  }

  /// التحقق هل الدفعة مُلغاة
  Future<bool> isPaymentVoided(String paymentUuid) async {
    final payment =
        await (_db.select(_db.payments)
              ..where((t) => t.localUuid.equals(paymentUuid))
              ..limit(1))
            .getSingleOrNull();
    return payment?.isVoided ?? false;
  }

  /// جلب سجل الإلغاء لدفعة معينة
  Future<PaymentVoid?> getVoidForPayment(String paymentUuid) async {
    return (_db.select(_db.paymentVoids)
          ..where((t) => t.originalPaymentUuid.equals(paymentUuid))
          ..limit(1))
        .getSingleOrNull();
  }

  /// جلب كل عمليات الإلغاء في يوم فندقي معين
  Future<List<PaymentVoid>> getVoidsForHotelDay(String hotelDayKey) async {
    return (_db.select(_db.paymentVoids)
          ..where((t) => t.hotelDayKey.equals(hotelDayKey))
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => drift.OrderingTerm.desc(t.voidedAt)]))
        .get();
  }
}
