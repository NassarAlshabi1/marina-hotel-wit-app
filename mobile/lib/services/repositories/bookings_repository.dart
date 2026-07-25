import 'dart:async';

import 'package:drift/drift.dart' as d;
import 'package:flutter/foundation.dart';

import '../../utils/status_utils.dart';
import '../../utils/time.dart';
import '../auto_backup_manager.dart';
import '../booking_derived_fields_service.dart';
import '../crashlytics_service.dart';
import '../daos/bookings_dao.dart';
import '../daos/outbox_dao.dart';
import '../local_db.dart';
import '../telegram/telegram_notification_service.dart';
import '../telegram/whatsapp_notification_service.dart';

class BookingsRepository {
  BookingsRepository(this.db) {
    outbox = OutboxDao(db);
    dao = BookingsDao(db, outbox);
    derivedFields = BookingDerivedFieldsService(db);
  }
  final AppDatabase db;
  late final OutboxDao outbox;
  late final BookingsDao dao;
  late final BookingDerivedFieldsService derivedFields;

  Stream<List<Booking>> watch({String? roomNumber, String? status}) =>
      dao.watchList(roomNumber: roomNumber, status: status);
  Stream<List<Booking>> watchList({String? roomNumber, String? status}) =>
      dao.watchList(roomNumber: roomNumber, status: status);
  Stream<Booking?> watchOne(int id) => dao.watchById(id);

  Future<int> create({      required String roomNumber,
      required String guestName,
      required String guestPhone,
      required String guestNationality,
      required String checkinDate,
      required String status,
      String guestIdType = 'بطاقة شخصية',
      String guestIdNumber = '',
      String? guestIdIssueDate,
      String? guestIdIssuePlace,
      String? guestEmail,
      String? guestAddress,
      String? checkoutDate,
      String? actualCheckout,
      String? notes,
      int expectedNights = 1,
      int? calculatedNights,
      double discount = 0,
      String discountType = 'per_night',
      String? discountStartDate,
  }) async {
    // ─── منع الحجز المزدوج: غرفة واحدة = حجز نشط واحد فقط ───
    if (StatusUtils.isActiveBooking(status)) {
      final existing = await getActiveBookingForRoom(roomNumber);
      if (existing != null) {
        throw StateError(
          'يوجد حجز نشط بالفعل للغرفة $roomNumber ' //
          '(الضيف: ${existing.guestName})',
        );
      }
    }

    try {
      // ✅ تغليف العملية في معاملة لضمان اتساق البيانات
      final result = await db.transaction(() async {
        final id = await dao.insertOne(
          BookingsCompanion(
            roomNumber: d.Value(roomNumber),
            guestName: d.Value(guestName),
            guestPhone: d.Value(guestPhone),
            guestIdType: d.Value(guestIdType),
            guestIdNumber: d.Value(guestIdNumber),
            guestIdIssueDate: d.Value(guestIdIssueDate),
            guestIdIssuePlace: d.Value(guestIdIssuePlace),
            guestNationality: d.Value(guestNationality),
            guestEmail: d.Value(guestEmail),
            guestAddress: d.Value(guestAddress),
            checkinDate: d.Value(checkinDate),
            checkoutDate: d.Value(checkoutDate),
            actualCheckout: d.Value(actualCheckout),
            status: d.Value(status),
            notes: d.Value(notes),
            expectedNights: d.Value(expectedNights),
            calculatedNights: calculatedNights != null ? d.Value(calculatedNights) : const d.Value.absent(),
            discount: d.Value(discount),
            discountType: d.Value(discountType),
            discountStartDate: d.Value(discountStartDate),
          ),
        );
        await syncLegacyDiscountToAdjustments(id);
        await derivedFields.refreshForBookingId(id);
        return id;
      });

      unawaited(AutoBackupManager.instance.onDataChange('bookings', 'INSERT', recordData: {'id': result}));
      // إشعارات فورية (fire-and-forget)
      unawaited(_notifyNewBooking(result));
      return result;
    } catch (e, stack) {
      await CrashlyticsService.instance.recordScreenError(
        screen: 'BookingsRepository',
        action: 'create',
        error: e,
        stackTrace: stack,
        severity: CrashlyticsSeverity.fatal,
        extra: {'room': roomNumber, 'guest': guestName, 'status': status},
      );
      rethrow;
    }
  }

  Future<int> update(
    int id, {
    String? roomNumber,
    String? guestName,
    String? guestPhone,
    String? guestIdType,
    String? guestIdNumber,
    String? guestIdIssueDate,
    String? guestIdIssuePlace,
    String? guestNationality,
    String? guestEmail,
    String? guestAddress,
    String? checkinDate,
    String? checkoutDate,
    String? actualCheckout,
    String? status,
    String? notes,
    int? expectedNights,
    int? calculatedNights,
    double? discount,
    String? discountType,
    String? discountStartDate,
  }) async {
    // ✅ فحص الحجز المزدوج عند تغيير الغرفة
    if (roomNumber != null) {
      final existing = await getActiveBookingForRoom(roomNumber);
      if (existing != null && existing.id != id) {
        throw StateError(
          'يوجد حجز نشط بالفعل للغرفة $roomNumber '
          '(الضيف: ${existing.guestName})',
        );
      }
    }

    try {
      // ✅ تغليف العملية في معاملة لضمان اتساق البيانات
      final result = await db.transaction(() async {
        final updated = await dao.updateById(
          id,
          BookingsCompanion(
            roomNumber: roomNumber != null ? d.Value(roomNumber) : const d.Value.absent(),
            guestName: guestName != null ? d.Value(guestName) : const d.Value.absent(),
            guestPhone: guestPhone != null ? d.Value(guestPhone) : const d.Value.absent(),
            guestIdType: guestIdType != null ? d.Value(guestIdType) : const d.Value.absent(),
            guestIdNumber: guestIdNumber != null ? d.Value(guestIdNumber) : const d.Value.absent(),
            guestIdIssueDate: guestIdIssueDate != null ? d.Value(guestIdIssueDate) : const d.Value.absent(),
            guestIdIssuePlace: guestIdIssuePlace != null ? d.Value(guestIdIssuePlace) : const d.Value.absent(),
            guestNationality: guestNationality != null ? d.Value(guestNationality) : const d.Value.absent(),
            guestEmail: guestEmail != null ? d.Value(guestEmail) : const d.Value.absent(),
            guestAddress: guestAddress != null ? d.Value(guestAddress) : const d.Value.absent(),
            checkinDate: checkinDate != null ? d.Value(checkinDate) : const d.Value.absent(),
            checkoutDate: checkoutDate != null ? d.Value(checkoutDate) : const d.Value.absent(),
            actualCheckout: actualCheckout != null ? d.Value(actualCheckout) : const d.Value.absent(),
            status: status != null ? d.Value(status) : const d.Value.absent(),
            notes: notes != null ? d.Value(notes) : const d.Value.absent(),
            expectedNights: expectedNights != null ? d.Value(expectedNights) : const d.Value.absent(),
            calculatedNights: calculatedNights != null ? d.Value(calculatedNights) : const d.Value.absent(),
            discount: discount != null ? d.Value(discount) : const d.Value.absent(),
            discountType: discountType != null ? d.Value(discountType) : const d.Value.absent(),
            discountStartDate: discountStartDate != null ? d.Value(discountStartDate) : const d.Value.absent(),
          ),
        );
        if (updated > 0) {
          await syncLegacyDiscountToAdjustments(id);
          await derivedFields.refreshForBookingId(id);
        }
        return updated;
      });

      if (result > 0) {
        unawaited(AutoBackupManager.instance.onDataChange('bookings', 'UPDATE', recordData: {'id': id}));
        if (status != null) {
          unawaited(_notifyBookingUpdate(id, status));
        }
      }
      return result;
    } catch (e, stack) {
      await CrashlyticsService.instance.recordScreenError(
        screen: 'BookingsRepository',
        action: 'update',
        error: e,
        stackTrace: stack,
        extra: {'id': '$id', 'newStatus': status ?? '', 'newRoom': roomNumber ?? ''},
      );
      rethrow;
    }
  }

  Future<int> delete(int id) async {
    try {
      final result = await dao.softDelete(id);
      if (result > 0) {
        unawaited(AutoBackupManager.instance.onDataChange('bookings', 'DELETE', recordData: {'id': id}));
      }
      return result;
    } catch (e, stack) {
      await CrashlyticsService.instance.recordScreenError(
        screen: 'BookingsRepository',
        action: 'delete',
        error: e,
        stackTrace: stack,
        extra: {'id': '$id'},
      );
      rethrow;
    }
  }

  // دوال النسخ الاحتياطي

  /// تصدير بيانات الحجوزات
  Future<Map<String, dynamic>> exportData() async {
    final bookingsData = await dao.exportToJson();
    final recordCount = await dao.getRecordCount();

    return {'data': bookingsData, 'count': recordCount, 'entity': 'bookings'};
  }

  /// استيراد بيانات الحجوزات
  Future<void> importData(Map<String, dynamic> data) async {
    if (data.containsKey('data') && data['data'] is List) {
      await dao.importFromJson(List<Map<String, dynamic>>.from(data['data'] as List));
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

  /// مزامنة التخفيض القديم (legacy discount) مع جدول التعديلات.
  ///
  /// ─── ملاحظة مهمة (BUG #2 + #3): ───
  /// سجلات legacy_discount في booking_price_adjustments هي سجلات ميتة لا تُستخدم
  /// في الحساب الفعلي. EnhancedBookingCalculationService يستبعدها دائماً في
  /// _fetchActiveAdjustments ويطبق التخفيض القديم مباشرة عبر booking.discount.
  ///
  /// لذلك هذه الدالة تقوم بـ:
  /// 1. إلغاء أي سجلات legacy_discount يتيمة (عند عدم وجود تخفيض)
  /// 2. عدم إنشاء سجلات جديدة (كانت ميتة ولا فائدة منها)
  Future<void> syncLegacyDiscountToAdjustments(int bookingId) async {
    final booking = await (db.select(db.bookings)..where((b) => b.id.equals(bookingId))).getSingleOrNull();
    if (booking == null) {
      return;
    }

    final discount = booking.discount;
    if (discount <= 0 || booking.discountType == 'total') {
      // لا يوجد تخفيض — ألغِ أي سجلات يتيمة
      await _cancelLegacyDiscountAdjustments(bookingId);
      return;
    }

    // التخفيض موجود — لا حاجة لإنشاء سجل legacy_discount لأن:
    // 1. EnhancedBookingCalculationService يستبعدها دائماً
    // 2. التخفيض يُطبق مباشرة عبر booking.discount في المسار القديم
    // فقط تأكد من تنظيف أي سجلات يتيمة بمبلغ مختلف
    await _cancelLegacyDiscountAdjustments(bookingId);
  }

  /// إلغاء جميع سجلات legacy_discount النشطة لحجز معين.
  /// تُستدعى عندما يُزال التخفيض من الحجز (discount <= 0) لمنع سجلات يتيمة.
  Future<void> _cancelLegacyDiscountAdjustments(int bookingId) async {
    final now = Time.nowEpoch();
    final nowIso = DateTime.now().toUtc().toIso8601String();

    // جلب السجلات قبل التحديث لإنشاء outbox entries
    final orphans =
        await (db.select(db.bookingPriceAdjustments)
              ..where((a) => a.bookingLocalId.equals(bookingId))
              ..where((a) => a.isActive.equals(true))
              ..where((a) => a.deletedAt.isNull())
              ..where((a) => a.reason.equals('legacy_discount')))
            .get();

    if (orphans.isEmpty) return;

    await (db.update(db.bookingPriceAdjustments)
          ..where((a) => a.bookingLocalId.equals(bookingId))
          ..where((a) => a.isActive.equals(true))
          ..where((a) => a.deletedAt.isNull())
          ..where((a) => a.reason.equals('legacy_discount')))
        .write(
          BookingPriceAdjustmentsCompanion(
            isActive: const d.Value(false),
            cancelledAt: d.Value(nowIso),
            cancelledBy: const d.Value('auto_cleanup'),
            updatedAt: d.Value(now),
            lastModified: d.Value(now),
            updatedAtIso: d.Value(nowIso),
            lastModifiedEpoch: d.Value(now),
          ),
        );

    // ─── إنشاء outbox entries لمزامنة التعديلات المُلغاة ───
    // ✅ تحسين أداء: استبدال N × merge() بـ mergeBatch() — معاملة واحدة بدل N
    // بدون هذا، إلغاء legacy_discount لن يُزامن إلى الأجهزة الأخرى
<<<<<<< HEAD
    if (orphans.isNotEmpty) {
      final outboxDao = OutboxDao(db);
      await outboxDao.mergeBatch(
        orphans.map((orphan) => <String, dynamic>{
          'entity': 'booking_price_adjustments',
          'op': 'update',
          'localUuid': orphan.localUuid,
          'payload': <String, dynamic>{'isActive': false, 'cancelledAt': nowIso, 'cancelledBy': 'auto_cleanup'},
          'clientTs': now,
        }).toList(),
=======
    final outboxDao = OutboxDao(db);
    for (final orphan in orphans) {
      await outboxDao.merge(
        entity: 'booking_price_adjustments',
        op: 'update',
        localUuid: orphan.localUuid,
        payload: {'isActive': false, 'cancelledAt': nowIso, 'cancelledBy': 'auto_cleanup'},
        clientTs: now,
>>>>>>> origin/refactor/clean-v2
      );
    }
  }

  /// الحصول على أي حجز نشط للغرفة (التحقق من جميع حالات الحجز النشط)
  Future<Booking?> getActiveBookingForRoom(String roomNumber) async {
    return (db.select(db.bookings)
          ..where((b) => b.roomNumber.equals(roomNumber))
          ..where((b) => b.deletedAt.isNull())
          ..where((b) => b.status.isIn(StatusUtils.activeBookingStatuses))
          ..orderBy([(b) => d.OrderingTerm.desc(b.checkinDate)])
          ..limit(1))
        .getSingleOrNull();
  }

  /// إرسال إشعارات (WhatsApp + Telegram) لحجز جديد
  Future<void> _notifyNewBooking(int id) async {
    try {
      final booking = await (db.select(db.bookings)..where((b) => b.id.equals(id))).getSingleOrNull();
      if (booking == null) return;

      final roomNumber = booking.roomNumber;
      final guestName = booking.guestName;
      final guestPhone = booking.guestPhone;
      final checkinDate = booking.checkinDate;
      final checkoutDate = booking.checkoutDate;
      final nights = booking.expectedNights;

      unawaited(
        WhatsAppNotificationService.instance.notifyNewBooking(
          roomNumber: roomNumber,
          guestName: guestName,
          guestPhone: guestPhone,
          checkinDate: checkinDate,
          checkoutDate: checkoutDate,
          nights: nights,
        ),
      );
      unawaited(
        TelegramNotificationService.instance.notifyNewBooking(
          roomNumber: roomNumber,
          guestName: guestName,
          guestPhone: guestPhone,
          checkinDate: checkinDate,
          checkoutDate: checkoutDate,
          nights: nights,
        ),
      );
    } catch (e) {
      debugPrint('⚠️ فشل إرسال إشعار الحجز الجديد: $e');
    }
  }

  /// إرسال إشعارات (WhatsApp + Telegram) عند تغيير حالة الحجز
  Future<void> _notifyBookingUpdate(int id, String newStatus) async {
    try {
      final booking = await (db.select(db.bookings)..where((b) => b.id.equals(id))).getSingleOrNull();
      if (booking == null) return;

      final roomNumber = booking.roomNumber;
      final guestName = booking.guestName;

      // حالة تسجيل دخول (check-in): نشط/active/confirmed
      if (newStatus == 'نشط' || newStatus == 'active' || newStatus == 'confirmed') {
        unawaited(
          WhatsAppNotificationService.instance.notifyCheckIn(
            roomNumber: roomNumber,
            guestName: guestName,
            guestPhone: booking.guestPhone,
            expectedNights: booking.expectedNights,
          ),
        );
        unawaited(
          TelegramNotificationService.instance.notifyCheckIn(
            roomNumber: roomNumber,
            guestName: guestName,
            guestPhone: booking.guestPhone,
            expectedNights: booking.expectedNights,
          ),
        );
      } else if (newStatus == 'مكتمل') {
        final totalPaid = booking.totalPaidCached;
        final remaining = booking.remainingBalanceCached;

        unawaited(
          WhatsAppNotificationService.instance.notifyCheckOut(
            roomNumber: roomNumber,
            guestName: guestName,
            actualNights: booking.calculatedNights,
            totalPaid: totalPaid,
            remaining: remaining > 0 ? remaining : null,
          ),
        );
        unawaited(
          TelegramNotificationService.instance.notifyCheckOut(
            roomNumber: roomNumber,
            guestName: guestName,
            actualNights: booking.calculatedNights,
            totalPaid: totalPaid,
            remaining: remaining > 0 ? remaining : null,
          ),
        );
      }
    } catch (e) {
      debugPrint('⚠️ فشل إرسال إشعار تحديث الحجز: $e');
    }
  }
}
