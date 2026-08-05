import 'dart:async';

import 'package:drift/drift.dart' as d;
import 'package:flutter/foundation.dart';

import '../../utils/hotel_time_engine.dart';
import '../auto_backup_manager.dart';
import '../booking_derived_fields_service.dart';
import '../crashlytics_service.dart';
import '../daos/outbox_dao.dart';
import '../daos/payments_dao.dart';
import '../local_db.dart';
import '../telegram/telegram_notification_service.dart';
import '../telegram/whatsapp_notification_service.dart';

class PaymentsRepository {
  PaymentsRepository(this.db) {
    outbox = OutboxDao(db);
    dao = PaymentsDao(db, outbox);
    derivedFields = BookingDerivedFieldsService(db);
  }
  final AppDatabase db;
  late final OutboxDao outbox;
  late final PaymentsDao dao;
  late final BookingDerivedFieldsService derivedFields;

  Stream<List<Payment>> paymentsByBooking(int bookingLocalId) {
    final bookingStream = (db.select(
      db.bookings,
    )..where((b) => b.id.equals(bookingLocalId))).watchSingleOrNull();

    return bookingStream.asyncExpand((booking) {
      final q = db.select(db.payments);
      q.where((p) => p.deletedAt.isNull());

      if (booking == null) {
        q.where((p) => p.bookingLocalId.equals(bookingLocalId));
      } else {
        final byLocalId = db.payments.bookingLocalId.equals(bookingLocalId);
        final byUuid = db.payments.bookingUuidCache.equals(booking.localUuid);
        q.where((p) => byLocalId | byUuid);
      }

      q.orderBy([(p) => d.OrderingTerm.desc(p.paymentDate)]);
      return q.watch();
    });
  }

  Stream<List<Payment>> watchAll({bool includeDeleted = false}) =>
      dao.watchList(includeDeleted: includeDeleted);
  Stream<Payment?> watchOne(int id) => dao.watchById(id);

  /// مراقبة إجمالي المدفوعات ليوم فندقي محدد عبر SQL SUM() — أداء أفضل
  /// من تحميل جميع صفوف المدفوعات (38 عمود لكل صف) ثم جمعها في Dart.
  /// يُحدَّث تلقائياً عند أي تغيير في جدول المدفوعات بفضل Stream من Drift.
  /// يطابق المنطق السابق: hotelDayKey مطابق OR (hotelDayKey فارغ AND paymentDate ضمن النطاق).
  Stream<double> watchTotalByHotelDayKey(String hotelDayKey) {
    return db
        .customSelect(
          'SELECT COALESCE(SUM(amount), 0.0) AS total FROM payments '
          'WHERE deleted_at IS NULL AND is_voided = 0 AND '
          '(hotel_day_key = ? OR (hotel_day_key IS NULL AND payment_date LIKE ?))',
          variables: [
            d.Variable.withString(hotelDayKey),
            d.Variable.withString('$hotelDayKey%'),
          ],
          readsFrom: {db.payments},
        )
        .watchSingle()
        .map((result) => (result.data['total'] as num).toDouble());
  }

  /// مراقبة إجمالي المدفوعات لحجز محدد عبر SQL SUM() — بديل خفيف الوزن
  /// لـ [paymentsByBooking] عندما يحتاج المستهلك فقط للمجموع (مثل قائمة الحجوزات).
  /// يتجنب تحميل جميع صفوف المدفوعات (38 عمود) وفك تشفيرها فقط لجمع `amount`.
  Stream<double> watchTotalPaidForBooking(int bookingLocalId) {
    return db
        .customSelect(
          'SELECT COALESCE(SUM(amount), 0.0) AS total FROM payments '
          'WHERE deleted_at IS NULL AND is_voided = 0 AND booking_local_id = ?',
          variables: [d.Variable.withInt(bookingLocalId)],
          readsFrom: {db.payments},
        )
        .watchSingle()
        .map((result) => (result.data['total'] as num).toDouble());
  }

  Future<int> create({
    required double amount,
    required String paymentDate,
    required String paymentMethod,
    required String revenueType,
    int? bookingLocalId,
    int? serverBookingId,
    String? roomNumber,
    String? notes,
    bool isPendingBalance = false,
  }) async {
    try {
      final hotelDayKey = HotelTimeEngine.getHotelDayKeyFromIso(paymentDate);

      String? bookingUuidCache;
      if (bookingLocalId != null) {
        final booking = await (db.select(
          db.bookings,
        )..where((b) => b.id.equals(bookingLocalId))).getSingleOrNull();
        bookingUuidCache = booking?.localUuid;
      }

      // ✅ تغليف العملية في معاملة لضمان اتساق البيانات
      final result = await db.transaction(() async {
        final id = await dao.insertOne(
          PaymentsCompanion(
            bookingLocalId: d.Value(bookingLocalId),
            serverBookingId: d.Value(serverBookingId),
            roomNumber: d.Value(roomNumber),
            amount: d.Value(amount),
            paymentDate: d.Value(paymentDate),
            notes: d.Value(notes),
            paymentMethod: d.Value(paymentMethod),
            revenueType: d.Value(revenueType),
            hotelDayKey: d.Value(hotelDayKey),
            bookingUuidCache: d.Value(bookingUuidCache),
            isPendingBalance: d.Value(isPendingBalance),
          ),
        );
        if (bookingLocalId != null) {
          await derivedFields.refreshForBookingId(bookingLocalId);
        }
        return id;
      });

      unawaited(AutoBackupManager.instance.onDataChange(
          'payments',
          'INSERT',
          recordData: {'amount': amount},
        ),
      );
      // إشعارات فورية (fire-and-forget)
      unawaited(_notifyPaymentReceived(result));
      return result;
    } catch (e, stack) {
      await CrashlyticsService.instance.recordScreenError(
        screen: 'PaymentsRepository',
        action: 'create',
        error: e,
        stackTrace: stack,
        severity: CrashlyticsSeverity.fatal,
        extra: {
          'amount': '$amount',
          'method': paymentMethod,
          'bookingId': '$bookingLocalId',
        },
      );
      rethrow;
    }
  }

  Future<int> update(
    int id, {
    int? bookingLocalId,
    int? serverBookingId,
    String? roomNumber,
    double? amount,
    String? paymentDate,
    String? notes,
    String? paymentMethod,
    String? revenueType,
    bool? isPendingBalance,
  }) async {
    try {
      final before = await (db.select(
        db.payments,
      )..where((p) => p.id.equals(id))).getSingleOrNull();
      final oldBookingId = before?.bookingLocalId;

      final hotelDayKey = paymentDate != null
          ? HotelTimeEngine.getHotelDayKeyFromIso(paymentDate)
          : null;

      // ✅ تغليف العملية في معاملة لضمان اتساق البيانات
      final result = await db.transaction(() async {
        final updated = await dao.updateById(
          id,
          PaymentsCompanion(
            bookingLocalId: bookingLocalId != null
                ? d.Value(bookingLocalId)
                : const d.Value.absent(),
            serverBookingId: serverBookingId != null
                ? d.Value(serverBookingId)
                : const d.Value.absent(),
            roomNumber: roomNumber != null
                ? d.Value(roomNumber)
                : const d.Value.absent(),
            amount: amount != null ? d.Value(amount) : const d.Value.absent(),
            paymentDate: paymentDate != null
                ? d.Value(paymentDate)
                : const d.Value.absent(),
            notes: notes != null ? d.Value(notes) : const d.Value.absent(),
            paymentMethod: paymentMethod != null
                ? d.Value(paymentMethod)
                : const d.Value.absent(),
            revenueType: revenueType != null
                ? d.Value(revenueType)
                : const d.Value.absent(),
            hotelDayKey: hotelDayKey != null
                ? d.Value(hotelDayKey)
                : const d.Value.absent(),
            isPendingBalance: isPendingBalance != null
                ? d.Value(isPendingBalance)
                : const d.Value.absent(),
          ),
        );
        if (updated > 0) {
          final newBookingId = bookingLocalId ?? oldBookingId;
          final bookingIds = <int>{};
          if (oldBookingId != null) {
            bookingIds.add(oldBookingId);
          }
          if (newBookingId != null) {
            bookingIds.add(newBookingId);
          }
          for (final bId in bookingIds) {
            await derivedFields.refreshForBookingId(bId);
          }
        }
        return updated;
      });

      if (result > 0) {
        unawaited(AutoBackupManager.instance.onDataChange(
            'payments',
            'UPDATE',
            recordData: {'id': id},
          ),
        );
      }
      return result;
    } catch (e, stack) {
      await CrashlyticsService.instance.recordScreenError(
        screen: 'PaymentsRepository',
        action: 'update',
        error: e,
        stackTrace: stack,
        extra: {'id': '$id'},
      );
      rethrow;
    }
  }

  Future<int> delete(int id) async {
    try {
      final payment = await (db.select(
        db.payments,
      )..where((p) => p.id.equals(id))).getSingleOrNull();
      final bookingId = payment?.bookingLocalId;

      // ✅ تغليف العملية في معاملة لضمان اتساق البيانات
      final result = await db.transaction(() async {
        final deleted = await dao.softDelete(id);
        if (deleted > 0 && bookingId != null) {
          await derivedFields.refreshForBookingId(bookingId);
        }
        return deleted;
      });

      if (result > 0) {
        unawaited(AutoBackupManager.instance.onDataChange(
            'payments',
            'DELETE',
            recordData: {'id': id},
          ),
        );
      }
      return result;
    } catch (e, stack) {
      await CrashlyticsService.instance.recordScreenError(
        screen: 'PaymentsRepository',
        action: 'delete',
        error: e,
        stackTrace: stack,
        extra: {'id': '$id'},
      );
      rethrow;
    }
  }

  // دوال النسخ الاحتياطي

  /// تصدير بيانات المدفوعات
  Future<Map<String, dynamic>> exportData() async {
    final paymentsData = await dao.exportToJson();
    final recordCount = await dao.getRecordCount();

    return {'data': paymentsData, 'count': recordCount, 'entity': 'payments'};
  }

  /// استيراد بيانات المدفوعات
  Future<void> importData(Map<String, dynamic> data) async {
    if (data.containsKey('data') && data['data'] is List) {
      await dao.importFromJson(
        List<Map<String, dynamic>>.from(data['data'] as List),
      );
    }
  }

  /// مسح جميع البيانات
  Future<void> clearAllData() async {
    await dao.clearAllData();
  }

  /// الحصول على إجمالي عدد السجلات
  Future<int> getRecordCount() async {
    return dao.getRecordCount();
  }

  /// الحصول على إجمالي المدفوعات لتاريخ محدد
  Future<double> getTotalByDate(String date) async {
    final result = await db
        .customSelect(
          'SELECT COALESCE(SUM(amount), 0.0) AS total FROM payments '
          'WHERE payment_date LIKE ? AND deleted_at IS NULL AND is_voided = 0',
          variables: [d.Variable.withString('$date%')],
          readsFrom: {db.payments},
        )
        .getSingle();
    return (result.data['total'] as num).toDouble();
  }

  Future<double> getTotalByHotelDayKey(
    String hotelDayKey, {
    String? revenueType,
  }) async {
    final variables = <d.Variable<Object>>[
      d.Variable.withString(hotelDayKey),
      d.Variable.withString('$hotelDayKey%'),
    ];
    var revenueFilter = '';
    if (revenueType != null && revenueType.isNotEmpty) {
      revenueFilter = ' AND revenue_type = ?';
      variables.add(d.Variable.withString(revenueType));
    }
    final result = await db
        .customSelect(
          'SELECT COALESCE(SUM(amount), 0.0) AS total FROM payments '
          'WHERE deleted_at IS NULL AND is_voided = 0'
          '  AND (hotel_day_key = ? OR (hotel_day_key IS NULL AND payment_date LIKE ?))'
          '$revenueFilter',
          variables: variables,
          readsFrom: {db.payments},
        )
        .getSingle();
    return (result.data['total'] as num).toDouble();
  }

  /// إرسال إشعارات (WhatsApp + Telegram) عند استلام دفعة
  Future<void> _notifyPaymentReceived(int paymentId) async {
    try {
      final payment = await (db.select(
        db.payments,
      )..where((p) => p.id.equals(paymentId))).getSingleOrNull();
      if (payment == null) return;

      // الحصول على معلومات الحجز إن وجد
      String roomNumber = payment.roomNumber ?? '-';
      String guestName = '-';
      if (payment.bookingLocalId != null) {
        try {
          final booking =
              await (db.select(
                    db.bookings,
                  )..where((b) => b.id.equals(payment.bookingLocalId!)))
                  .getSingleOrNull();
          if (booking != null) {
            roomNumber = booking.roomNumber;
            guestName = booking.guestName;
          }
        } catch (e) {
      debugPrint('⚠️ Swallowed error in payments_repository.dart: ');}
      }

      unawaited(
        WhatsAppNotificationService.instance.notifyPayment(
          roomNumber: roomNumber,
          guestName: guestName,
          amount: payment.amount,
          paymentMethod: payment.paymentMethod,
        ),
      );
      unawaited(TelegramNotificationService.instance.notifyPayment(
          roomNumber: roomNumber,
          guestName: guestName,
          amount: payment.amount,
          paymentMethod: payment.paymentMethod,
        ),
      );
    } catch (e) {
      debugPrint('⚠️ فشل إرسال إشعار الدفعة: $e');
    }
  }
}
