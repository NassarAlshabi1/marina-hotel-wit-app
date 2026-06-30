// ignore_for_file: prefer_const_declarations

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../utils/time.dart';
import '../appwrite_config.dart';
import '../appwrite_sync_utils.dart';
import '../local_db.dart';

/// PayloadMapper — يحوّل كيانات Drift المحلية إلى Map<String, dynamic>
/// جاهزة للإرسال إلى Appwrite Cloud.
///
/// تم استخراج هذا الصنف من AppwriteSyncManager (God Class 6,442 سطر)
/// لتقليل حجمه وتسهيل اختبار دوال التحويل بشكل مستقل.
///
/// كل دالة تُرجع Map نظيف بعد تطبيق sanitizePayload لإزالة الحقول غير
/// الموجودة في schema الـ collection الهدف.
class PayloadMapper {
  const PayloadMapper();

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// يضع القيمة في الـ Map فقط إذا كانت غير null.
  void putIfNotNull<T>(Map<String, dynamic> map, String key, T? value) {
    if (value != null) {
      map[key] = value;
    }
  }

  /// يضع السلسلة النصية في الـ Map فقط إذا كانت غير null وغير فارغة.
  void putIfStringNotEmpty(
    Map<String, dynamic> map,
    String key,
    String? value,
  ) {
    if (value != null && value.isNotEmpty) {
      map[key] = value;
    }
  }

  // ── Entity Mappers ───────────────────────────────────────────────────────

  /// يحوّل [Room] محلي إلى payload لـ Appwrite.
  Map<String, dynamic> roomToRemote(Room room) {
    final data = <String, dynamic>{
      'roomNumber': room.roomNumber,
      'type': room.type,
      'price': room.price,
      'status': room.status,
      'localUuid': room.localUuid,
      'createdAt': room.createdAt,
      'updatedAt': room.updatedAt,
      'lastModified': room.lastModified,
      'version': room.version,
      'origin': room.origin,
      'deviceId': room.deviceId,
      // حقول مطلوبة إضافية من Appwrite schema
      'roomType': room.type,
      'basePrice': room.price,
      'floor': 1,
      'bedsCount': 1,
    };
    putIfNotNull(data, 'serverId', room.serverId);
    data['deletedAt'] = room.deletedAt;
    putIfStringNotEmpty(data, 'imageUrl', room.imageUrl);
    return AppwriteSyncUtils.sanitizePayload(
      'rooms',
      data,
      collectionId: AppwriteConfig.roomsCollectionId,
    );
  }

  /// يحوّل [Booking] محلي إلى payload لـ Appwrite.
  Map<String, dynamic> bookingToRemote(Booking booking) {
    final data = <String, dynamic>{
      'roomNumber': booking.roomNumber,
      'guestName': booking.guestName,
      'guestPhone': booking.guestPhone,
      'guestIdType': booking.guestIdType,
      'guestIdNumber': booking.guestIdNumber,
      'guestNationality': booking.guestNationality,
      'checkinDate': booking.checkinDate,
      'status': booking.status,
      'expectedNights': booking.expectedNights,
      'calculatedNights': booking.calculatedNights,
      'localUuid': booking.localUuid,
      'createdAt': booking.createdAt,
      'updatedAt': booking.updatedAt,
      'lastModified': booking.lastModified,
      'version': booking.version,
      'origin': booking.origin,
    };
    putIfNotNull(data, 'serverBookingId', booking.serverBookingId);
    putIfNotNull(data, 'serverId', booking.serverId);
    data['deletedAt'] = booking.deletedAt;
    putIfStringNotEmpty(data, 'guestIdIssueDate', booking.guestIdIssueDate);
    putIfStringNotEmpty(data, 'guestIdIssuePlace', booking.guestIdIssuePlace);
    putIfStringNotEmpty(data, 'guestEmail', booking.guestEmail);
    putIfStringNotEmpty(data, 'guestAddress', booking.guestAddress);
    // ✅ checkoutDate و actualCheckout يجب إرسالهما دائماً
    // حتى لو كانا null — لأن `_putIfStringNotEmpty` يحذف المفتاح إذا كان null،
    // مما يمنع Appwrite من تحديث الحقل عند تسجيل الخروج.
    data['checkoutDate'] = booking.checkoutDate;
    data['actualCheckout'] = booking.actualCheckout;
    putIfStringNotEmpty(data, 'notes', booking.notes);
    // حقول مالية
    data['discount'] = booking.discount;
    putIfStringNotEmpty(data, 'discountType', booking.discountType);
    putIfStringNotEmpty(data, 'discountStartDate', booking.discountStartDate);
    data['totalDueCached'] = booking.totalDueCached;
    data['totalPaidCached'] = booking.totalPaidCached;
    data['remainingBalanceCached'] = booking.remainingBalanceCached;
    // حقول تواريخ ومشتقات
    data['totalNightsCached'] = booking.totalNightsCached;
    data['isFullyPaid'] = booking.isFullyPaid;
    putIfStringNotEmpty(data, 'hotelDayCheckin', booking.hotelDayCheckin);
    putIfStringNotEmpty(data, 'hotelDayCheckout', booking.hotelDayCheckout);
    putIfStringNotEmpty(data, 'vectorClock', booking.vectorClock);
    data['deviceId'] = booking.deviceId;
    // حقول SyncFields المضافة حديثاً إلى Appwrite Cloud
    putIfStringNotEmpty(data, 'createdAtIso', booking.createdAtIso);
    putIfStringNotEmpty(data, 'updatedAtIso', booking.updatedAtIso);
    putIfStringNotEmpty(data, 'deletedAtIso', booking.deletedAtIso);
    putIfNotNull(data, 'createdAtEpoch', booking.createdAtEpoch);
    putIfNotNull(data, 'lastModifiedEpoch', booking.lastModifiedEpoch);
    putIfStringNotEmpty(data, 'sync_origin', booking.origin);
    putIfNotNull(data, 'syncTimestamp', booking.lastModified);
    return AppwriteSyncUtils.sanitizePayload(
      'bookings',
      data,
      collectionId: AppwriteConfig.bookingsCollectionId,
    );
  }

  /// يحوّل [Expense] محلي إلى payload لـ Appwrite.
  Map<String, dynamic> expenseToRemote(Expense expense) {
    final data = <String, dynamic>{
      'expenseType': expense.expenseType,
      'description': expense.description,
      'amount': expense.amount,
      'date': expense.date,
      'localUuid': expense.localUuid,
      'createdAt': expense.createdAt,
      'updatedAt': expense.updatedAt,
      'lastModified': expense.lastModified,
      'version': expense.version,
      'origin': expense.origin,
      'vectorClock': expense.vectorClock,
      'deviceId': expense.deviceId,
    };
    putIfNotNull(data, 'relatedId', expense.relatedId);
    putIfNotNull(data, 'cashTransactionId', expense.cashTransactionId);
    putIfNotNull(data, 'serverId', expense.serverId);
    data['deletedAt'] = expense.deletedAt;
    putIfStringNotEmpty(data, 'hotelDayKey', expense.hotelDayKey);
    putIfStringNotEmpty(data, 'categoryUuid', expense.categoryUuid);
    putIfStringNotEmpty(data, 'cashFlowUuid', expense.cashFlowUuid);
    if (expense.isAutoGenerated) data['isAutoGenerated'] = true;
    putIfNotNull(data, 'syncTimestamp', expense.lastModified);
    putIfStringNotEmpty(data, 'sync_origin', expense.origin);
    return AppwriteSyncUtils.sanitizePayload(
      'expenses',
      data,
      collectionId: AppwriteConfig.expensesCollectionId,
    );
  }

  /// يحوّل [Payment] محلي إلى payload لـ Appwrite.
  Map<String, dynamic> paymentToRemote(Payment payment) {
    final data = <String, dynamic>{
      'amount': payment.amount,
      'paymentDate': payment.paymentDate,
      'paymentMethod': payment.paymentMethod,
      'revenueType': payment.revenueType,
      'localUuid': payment.localUuid,
      'createdAt': payment.createdAt,
      'updatedAt': payment.updatedAt,
      'lastModified': payment.lastModified,
      'version': payment.version,
      'origin': payment.origin,
      'hotelDayKey': payment.hotelDayKey ?? '',
      'isPendingBalance': payment.isPendingBalance,
    };
    putIfNotNull(data, 'serverPaymentId', payment.serverPaymentId);
    putIfNotNull(data, 'bookingLocalId', payment.bookingLocalId);
    putIfStringNotEmpty(data, 'bookingUuidCache', payment.bookingUuidCache);
    putIfNotNull(data, 'serverBookingId', payment.serverBookingId);
    putIfStringNotEmpty(data, 'roomNumber', payment.roomNumber);
    putIfStringNotEmpty(data, 'notes', payment.notes);
    putIfNotNull(data, 'cashTransactionLocalId', payment.cashTransactionLocalId);
    putIfNotNull(data, 'cashTransactionServerId', payment.cashTransactionServerId);
    putIfStringNotEmpty(data, 'referenceNumber', payment.referenceNumber);
    putIfNotNull(data, 'serverId', payment.serverId);
    data['deletedAt'] = payment.deletedAt;
    putIfStringNotEmpty(data, 'deletedAtIso', payment.deletedAtIso);
    putIfStringNotEmpty(data, 'linkedDebtUuid', payment.linkedDebtUuid);
    putIfNotNull(data, 'discountAmount', payment.discountAmount);
    putIfStringNotEmpty(data, 'discountStartDate', payment.discountStartDate);
    // إرسال isVoided دائماً (حتى لو false) لضمان المزامنة الصحيحة
    data['isVoided'] = payment.isVoided;
    putIfNotNull(data, 'voidedAt', payment.voidedAt);
    putIfStringNotEmpty(data, 'voidedBy', payment.voidedBy);
    putIfNotNull(data, 'createdAtEpoch', payment.createdAtEpoch);
    putIfNotNull(data, 'lastModifiedEpoch', payment.lastModifiedEpoch);
    data['vectorClock'] = payment.vectorClock;
    data['deviceId'] = payment.deviceId;
    putIfStringNotEmpty(data, 'createdAtIso', payment.createdAtIso);
    putIfStringNotEmpty(data, 'updatedAtIso', payment.updatedAtIso);
    putIfNotNull(data, 'syncTimestamp', payment.lastModified);
    putIfStringNotEmpty(data, 'sync_origin', payment.origin);
    return AppwriteSyncUtils.sanitizePayload(
      'payments',
      data,
      collectionId: AppwriteConfig.paymentsCollectionId,
    );
  }

  /// يحوّل [Debt] محلي إلى payload لـ Appwrite.
  Map<String, dynamic> debtToRemote(Debt debt) {
    final data = <String, dynamic>{
      'localUuid': debt.localUuid,
      'guestName': debt.guestName,
      'checkinDate': debt.checkinDate,
      'totalAmount': debt.totalAmount,
      'paidAmount': debt.paidAmount,
      'remainingAmount': debt.remainingAmount.round(), // Appwrite: integer
      'bookingLocalId': debt.bookingLocalId,
      'checkoutDate': debt.checkoutDate,
      'paymentDate': debt.paymentDate,
      'isSettled': debt.isSettled,
      'debtReason': debt.debtReason,
      'note': debt.note,
      'debtUuid': debt.debtUuid,
      'pledge': debt.pledge,
      'pledgeType': debt.pledgeType,
      'isFromAutoFix': debt.isFromAutoFix,
      'settlementConfirmed': debt.settlementConfirmed,
      'createdAt': debt.createdAt,
      'updatedAt': debt.updatedAt,
      'lastModified': debt.lastModified,
      'version': debt.version,
      'origin': debt.origin,
    };
    putIfNotNull(data, 'serverId', debt.serverId);
    data['deletedAt'] = debt.deletedAt;
    putIfStringNotEmpty(data, 'deletedAtIso', debt.deletedAtIso);
    putIfStringNotEmpty(data, 'hotelDayOpened', debt.hotelDayOpened);
    putIfStringNotEmpty(data, 'hotelDayClosed', debt.hotelDayClosed);
    data['vectorClock'] = debt.vectorClock;
    data['deviceId'] = debt.deviceId;
    putIfNotNull(data, 'createdAtEpoch', debt.createdAtEpoch);
    putIfNotNull(data, 'lastModifiedEpoch', debt.lastModifiedEpoch);
    putIfNotNull(data, 'syncTimestamp', debt.lastModified);
    putIfStringNotEmpty(data, 'sync_origin', debt.origin);
    return AppwriteSyncUtils.sanitizePayload(
      'debts',
      data,
      collectionId: AppwriteConfig.debtsCollectionId,
    );
  }

  /// يحوّل [Employee] محلي إلى payload لـ Appwrite.
  Map<String, dynamic> employeeToRemote(Employee employee) {
    final data = <String, dynamic>{
      'name': employee.name,
      'basicSalary': employee.basicSalary,
      'position': employee.position,
      'phone': employee.phone,
      'hireDate': employee.hireDate,
      'status': employee.status,
      'localUuid': employee.localUuid,
      'createdAt': employee.createdAt,
      'updatedAt': employee.updatedAt,
      'lastModified': employee.lastModified,
      'version': employee.version,
      'origin': employee.origin,
      'deviceId': employee.deviceId,
    };
    putIfNotNull(data, 'serverId', employee.serverId);
    data['deletedAt'] = employee.deletedAt;
    return data;
  }

  /// يحوّل [BookingNote] محلي إلى payload لـ Appwrite.
  Map<String, dynamic> bookingNoteToRemote(BookingNote note) {
    final data = <String, dynamic>{
      'bookingId': note.bookingId,
      'noteText': note.noteText,
      'alertType': note.alertType,
      'isActive': note.isActive,
      'localUuid': note.localUuid,
      'createdAt': note.createdAt,
      'updatedAt': note.updatedAt,
      'lastModified': note.lastModified,
      'version': note.version,
      'origin': note.origin,
      'sync_origin': note.origin,
      'deviceId': note.deviceId,
    };
    putIfNotNull(data, 'serverId', note.serverId);
    data['deletedAt'] = note.deletedAt;
    putIfStringNotEmpty(data, 'alertUntil', note.alertUntil);
    return data;
  }

  /// يحوّل [BookingNight] محلي إلى payload لـ Appwrite.
  Map<String, dynamic> bookingNightToRemote(BookingNight night) {
    final data = <String, dynamic>{
      'bookingLocalId': night.bookingLocalId,
      'hotelDayKey': night.hotelDayKey,
      'nightStart': night.nightStart,
      'nightEnd': night.nightEnd,
      'nightlyRate': night.nightlyRate,
      'sequence': night.sequence,
      'isProcessedByAutoFix': night.isProcessedByAutoFix,
      'baseRate': night.baseRate,
      'adjustment': night.adjustment,
      'finalRate': night.finalRate,
      'localUuid': night.localUuid,
      'createdAt': night.createdAt,
      'updatedAt': night.updatedAt,
      'lastModified': night.lastModified,
      'version': night.version,
      'origin': night.origin,
      'vectorClock': night.vectorClock,
      'deviceId': night.deviceId,
    };
    putIfNotNull(data, 'serverId', night.serverId);
    data['deletedAt'] = night.deletedAt;
    putIfStringNotEmpty(data, 'appliedAdjustmentUuid', night.appliedAdjustmentUuid);
    putIfStringNotEmpty(data, 'appliedAdjustmentsJson', night.appliedAdjustmentsJson);
    return data;
  }

  /// يحوّل [CashTransaction] محلي إلى payload لـ Appwrite.
  Map<String, dynamic> cashTransactionToRemote(CashTransaction transaction) {
    final data = <String, dynamic>{
      'transactionType': transaction.transactionType,
      'amount': transaction.amount.round(), // Appwrite: integer
      'transactionTime': transaction.transactionTime,
      'localUuid': transaction.localUuid,
      'createdAt': transaction.createdAt,
      'updatedAt': transaction.updatedAt,
      'lastModified': transaction.lastModified,
      'version': transaction.version,
      'origin': transaction.origin,
      'deviceId': transaction.deviceId,
    };
    putIfNotNull(data, 'registerId', transaction.registerId);
    putIfNotNull(data, 'referenceId', transaction.referenceId);
    putIfNotNull(data, 'createdBy', transaction.createdBy);
    putIfNotNull(data, 'serverId', transaction.serverId);
    data['deletedAt'] = transaction.deletedAt;
    putIfStringNotEmpty(data, 'referenceType', transaction.referenceType);
    putIfStringNotEmpty(data, 'description', transaction.description);
    return data;
  }

  /// يحوّل [SalaryCycle] محلي إلى payload لـ Appwrite.
  Map<String, dynamic> salaryCycleToRemote(SalaryCycle cycle) {
    final data = <String, dynamic>{
      'employeeId': cycle.employeeId,
      'cycleKey': cycle.cycleKey,
      'expectedAmount': cycle.expectedAmount,
      'actualPaid': cycle.actualPaid,
      'remainingAmount': cycle.remainingAmount,
      'status': cycle.status,
      'localUuid': cycle.localUuid,
      'createdAt': cycle.createdAt,
      'updatedAt': cycle.updatedAt,
      'lastModified': cycle.lastModified,
      'version': cycle.version,
      'origin': cycle.origin,
      'vectorClock': cycle.vectorClock,
      'deviceId': cycle.deviceId,
    };
    putIfNotNull(data, 'serverId', cycle.serverId);
    data['deletedAt'] = cycle.deletedAt;
    putIfStringNotEmpty(data, 'hotelDayStart', cycle.hotelDayStart);
    putIfStringNotEmpty(data, 'hotelDayEnd', cycle.hotelDayEnd);
    return data;
  }

  /// يحوّل [SalaryPayment] محلي إلى payload لـ Appwrite.
  Map<String, dynamic> salaryPaymentToRemote(SalaryPayment payment) {
    final data = <String, dynamic>{
      'cycleId': payment.cycleId,
      'amount': payment.amount,
      'paymentDateIso': payment.paymentDateIso,
      'isAutoGenerated': payment.isAutoGenerated,
      'localUuid': payment.localUuid,
      'createdAt': payment.createdAt,
      'updatedAt': payment.updatedAt,
      'lastModified': payment.lastModified,
      'version': payment.version,
      'origin': payment.origin,
      'deviceId': payment.deviceId,
    };
    putIfNotNull(data, 'serverId', payment.serverId);
    data['deletedAt'] = payment.deletedAt;
    putIfStringNotEmpty(data, 'hotelDayKey', payment.hotelDayKey);
    putIfStringNotEmpty(data, 'method', payment.method);
    return data;
  }

  /// يحوّل [ShiftNote] محلي إلى payload لـ Appwrite.
  Map<String, dynamic> shiftNoteToRemote(ShiftNote note) {
    final createdDate = DateTime.fromMillisecondsSinceEpoch(
      note.createdAt * 1000,
    );
    final shiftDate = createdDate.toIso8601String().substring(0, 10);
    final data = <String, dynamic>{
      'localUuid': note.localUuid,
      'title': note.title,
      'content': note.content,
      'priority': note.priority,
      'shiftType': note.shiftType,
      'isRead': note.isRead == 1, // Appwrite يتوقع boolean
      'createdAt': note.createdAt, // Appwrite يتوقع integer epoch
      'updatedAt': note.updatedAt, // integer epoch — مطلوب
      'lastModified': note.lastModified, // مطلوب للـ Delta Sync
      'createdBy': note.createdBy,
      'shiftDate': shiftDate, // مطلوب — مشتق من createdAt
      'deviceId': note.deviceId,
    };
    putIfStringNotEmpty(data, 'expiresAt', note.expiresAt);
    return data;
  }

  /// يحوّل [PriceAdjustment] محلي إلى payload لـ Appwrite.
  Map<String, dynamic> priceAdjustmentToRemote(PriceAdjustment row) {
    final now = Time.nowEpoch();
    return {
      'localUuid': row.localUuid,
      'targetType': row.targetType,
      'targetUuid': row.targetUuid,
      'adjustmentType': row.adjustmentType,
      'previousValue': row.previousValue,
      'newValue': row.newValue,
      'reason': row.reason,
      'effectiveDate': row.effectiveDate,
      'appliedBy': row.appliedBy,
      'hotelDayKey': row.hotelDayKey,
      'isReversed': row.isReversed,
      'reversedAt': row.reversedAt,
      'reversedBy': row.reversedBy,
      'createdAt': row.createdAt,
      'updatedAt': now,
      'lastModified': now,
      'origin': 'mobile',
      'syncTimestamp': now,
      'deviceId': row.deviceId,
      if (row.serverId != null) 'serverId': row.serverId,
    };
  }

  /// يحوّل سجل [ShiftNote] (يُستخدم كـ blacklist محلي) إلى payload لـ Appwrite.
  /// ملاحظة: Blacklist مُخزَّن محليًا في جدول shift_notes مع content يحوي JSON
  /// ببيانات الضيف، وله mapping خاص إلى collection blacklist على Appwrite.
  Map<String, dynamic> blacklistToRemote(ShiftNote item) {
    Map<String, dynamic> extra = {};
    try {
      extra = jsonDecode(item.content) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('WARN: Failed to parse blacklist content for sync: $e');
    }

    final now = Time.nowEpoch();
    // Appwrite blacklist collection: createdAt/updatedAt/deletedAt are STRING (ISO)
    final createdAtIso = item.createdAtIso ??
        DateTime.fromMillisecondsSinceEpoch(item.createdAt * 1000)
            .toIso8601String();
    final updatedAtIso = DateTime.fromMillisecondsSinceEpoch(item.updatedAt * 1000)
        .toIso8601String();

    return {
      'name': item.title,
      'nationality': (extra['nationality'] as String?) ?? '',
      'nationalId': (extra['nationalId'] as String?) ?? '',
      'phone': (extra['phone'] as String?) ?? '',
      'reason': (extra['reason'] as String?) ?? '',
      'notes': (extra['notes'] as String?) ?? '',
      'reportedBy': (extra['reportedBy'] as String?) ?? 'police',
      'active': (extra['active'] as bool?) ?? true,
      'localUuid': item.localUuid,
      'createdAt': createdAtIso,
      'createdAtIso': createdAtIso,
      'updatedAt': updatedAtIso,
      'updatedAtIso': updatedAtIso,
      'deletedAt': item.deletedAt != null
          ? DateTime.fromMillisecondsSinceEpoch(item.deletedAt! * 1000)
              .toIso8601String()
          : null,
      'lastModified': item.lastModified,
      'origin': 'mobile',
      'syncTimestamp': now,
      'deviceId': item.deviceId,
      if (item.serverId != null) 'serverId': item.serverId,
    };
  }

  /// يحوّل [GuestInfo] محلي إلى payload لـ Appwrite.
  ///
  /// مطابق لـ GuestInfosAdapter.toJson(src: Source.appwrite) مع إضافة
  /// حقول sync الإضافية (syncTimestamp, sync_origin) المطلوبة لـ Appwrite Cloud.
  Map<String, dynamic> guestInfoToRemote(GuestInfo info) {
    final now = Time.nowEpoch();
    final data = <String, dynamic>{
      // ── Sync fields ──
      'localUuid': info.localUuid,
      'createdAt': info.createdAt,
      'updatedAt': info.updatedAt,
      'lastModified': info.lastModified,
      'lastModifiedEpoch': info.lastModifiedEpoch,
      'createdAtEpoch': info.createdAtEpoch,
      'version': info.version,
      'origin': info.origin,
      'sync_origin': info.origin,
      'syncTimestamp': now,
      'vectorClock': info.vectorClock,
      'deviceId': info.deviceId,
      // ── Business fields ──
      'id': info.id,
      'roomNumber': info.roomNumber,
      'guestName': info.guestName,
      'nationality': info.nationality,
      'idNumber': info.idNumber,
      'idType': info.idType,
    };
    putIfNotNull(data, 'serverId', info.serverId);
    putIfNotNull(data, 'deletedAt', info.deletedAt);
    putIfStringNotEmpty(data, 'createdAtIso', info.createdAtIso);
    putIfStringNotEmpty(data, 'updatedAtIso', info.updatedAtIso);
    putIfStringNotEmpty(data, 'deletedAtIso', info.deletedAtIso);
    putIfStringNotEmpty(data, 'issueDate', info.issueDate);
    putIfStringNotEmpty(data, 'issuePlace', info.issuePlace);
    putIfStringNotEmpty(data, 'governorate', info.governorate);
    putIfStringNotEmpty(data, 'notes', info.notes);
    return data;
  }

  /// يحوّل [SalaryWithdrawal] محلي إلى payload لـ Appwrite.
  ///
  /// مطابق لـ SalaryWithdrawalsAdapter.toJson(src: Source.appwrite) مع:
  /// - حقول legacy (date, action, note, name) للتوافق مع كل إصدارات المخطط
  /// - employeeUuid / employeeLocalUuid (تمرَّر كمعاملات لأنهما يُحلَّان خارج الـ model)
  /// - sync_origin و syncTimestamp المطلوبة لـ Appwrite Cloud
  ///
  /// [employeeUuid] هو localUuid للموظف المرتبط — يُستخدم لربط السلف
  /// بالموظف عبر الأجهزة. مرّره من AppwriteSyncManager._processSalaryWithdrawalEntry.
  Map<String, dynamic> salaryWithdrawalToRemote(
    SalaryWithdrawal withdrawal, {
    String? employeeUuid,
  }) {
    final now = Time.nowEpoch();

    // إذا كان withdrawDate فارغاً (سجل قديم)، نستخدم تاريخ اليوم كاحتياطي
    final effectiveWithdrawDate = withdrawal.withdrawDate.isEmpty
        ? DateTime.now().toIso8601String().split('T').first // YYYY-MM-DD
        : withdrawal.withdrawDate;

    final data = <String, dynamic>{
      // ── Sync fields ──
      'localUuid': withdrawal.localUuid,
      'createdAt': withdrawal.createdAt,
      'updatedAt': withdrawal.updatedAt,
      'lastModified': withdrawal.lastModified,
      'lastModifiedEpoch': withdrawal.lastModifiedEpoch,
      'createdAtEpoch': withdrawal.createdAtEpoch,
      'version': withdrawal.version,
      'origin': withdrawal.origin,
      'sync_origin': withdrawal.origin,
      'syncTimestamp': now,
      'vectorClock': withdrawal.vectorClock,
      'deviceId': withdrawal.deviceId,
      // ── Business fields ──
      'id': withdrawal.id,
      'employeeId': withdrawal.employeeId,
      'amount': withdrawal.amount.round(), // Appwrite: integer
      'withdrawDate': effectiveWithdrawDate,
    };
    putIfNotNull(data, 'serverId', withdrawal.serverId);
    putIfNotNull(data, 'deletedAt', withdrawal.deletedAt);
    putIfStringNotEmpty(data, 'createdAtIso', withdrawal.createdAtIso);
    putIfStringNotEmpty(data, 'updatedAtIso', withdrawal.updatedAtIso);
    putIfStringNotEmpty(data, 'deletedAtIso', withdrawal.deletedAtIso);
    putIfStringNotEmpty(data, 'reason', withdrawal.reason);
    putIfStringNotEmpty(data, 'hotelDayKey', withdrawal.hotelDayKey);
    putIfStringNotEmpty(data, 'withdrawalType', withdrawal.withdrawalType);
    putIfStringNotEmpty(data, 'description', withdrawal.description);
    putIfNotNull(data, 'expenseId', withdrawal.expenseId);

    // ✅ حقول الربط بالموضف عبر الأجهزة
    if (employeeUuid != null && employeeUuid.isNotEmpty) {
      data['employeeUuid'] = employeeUuid;
      data['employeeLocalUuid'] = employeeUuid;
    }

    // ✅ حقول احتياطية (legacy) — تُرسل دائماً لضمان التوافق مع جميع إصدارات
    // مخطط Appwrite Cloud (القديم والجديد).
    //
    // 'date' يُرسل دائماً كاحتياطي لـ 'withdrawDate' — بعض إصدارات المخطط
    // تطلب 'date' كـ REQUIRED بدلاً من 'withdrawDate'.
    //
    // 'note' = ملاحظة المستخدم فقط (من description) — لا تخلطه مع reason.
    // 'reason' = سبب السحب (مثل "exp_629" للربط مع المصروف) — مستقل.
    data['date'] = effectiveWithdrawDate;
    data['action'] = withdrawal.withdrawalType ?? 'withdrawal';
    data['note'] = withdrawal.description ?? '';
    // ✅ إضافة name فارغ (optional لكن بعض إصدارات المخطط تتوقعه)
    data['name'] = '';

    return data;
  }

  /// يحوّل [BookingPriceAdjustment] محلي إلى payload لـ Appwrite.
  ///
  /// هذا الكيان هو **الأساس** لتطبيق التخفيضات والزيادات على الحجوزات.
  /// كل تعديل سعر (discount, surcharge, override) يُمثَّل كسجل في هذا الجدول
  /// ويُزامَن عبر هذه الدالة.
  ///
  /// مطابق لـ BookingPriceAdjustmentsAdapter.toJson(src: Source.appwrite) مع
  /// إضافة حقول sync الإضافية (syncTimestamp, sync_origin) المطلوبة لـ Appwrite Cloud.
  ///
  /// ملاحظة: amount على Appwrite Cloud هو integer — نُحوّل من double إلى int
  /// عبر `.round()` عند الإرسال.
  Map<String, dynamic> bookingPriceAdjustmentToRemote(BookingPriceAdjustment adj) {
    final now = Time.nowEpoch();
    final data = <String, dynamic>{
      // ── Sync fields ──
      'localUuid': adj.localUuid,
      'createdAt': adj.createdAt,
      'updatedAt': adj.updatedAt,
      'lastModified': adj.lastModified,
      'lastModifiedEpoch': adj.lastModifiedEpoch,
      'createdAtEpoch': adj.createdAtEpoch,
      'version': adj.version,
      'origin': adj.origin,
      'sync_origin': adj.origin,
      'syncTimestamp': now,
      'vectorClock': adj.vectorClock,
      'deviceId': adj.deviceId,
      // ── Business fields (تخفيضات/زيادات الحجوزات) ──
      'id': adj.id,
      'bookingLocalUuid': adj.bookingLocalUuid,
      'adjustmentType': adj.adjustmentType,
      'adjustmentMode': adj.adjustmentMode,
      'amount': adj.amount.round(), // Appwrite: integer
      'effectiveHotelDay': adj.effectiveHotelDay,
      'isActive': adj.isActive,
    };
    putIfNotNull(data, 'serverId', adj.serverId);
    putIfNotNull(data, 'deletedAt', adj.deletedAt);
    putIfNotNull(data, 'bookingLocalId', adj.bookingLocalId);
    putIfStringNotEmpty(data, 'roomNumber', adj.roomNumber);
    putIfStringNotEmpty(data, 'endHotelDay', adj.endHotelDay);
    putIfStringNotEmpty(data, 'reason', adj.reason);
    putIfStringNotEmpty(data, 'appliedBy', adj.appliedBy);
    putIfStringNotEmpty(data, 'cancelledAt', adj.cancelledAt);
    putIfStringNotEmpty(data, 'cancelledBy', adj.cancelledBy);
    putIfStringNotEmpty(data, 'createdAtIso', adj.createdAtIso);
    putIfStringNotEmpty(data, 'updatedAtIso', adj.updatedAtIso);
    putIfStringNotEmpty(data, 'deletedAtIso', adj.deletedAtIso);
    return data;
  }

  /// هل نوع المصروف مرتبط بالرواتب
  static bool isSalaryExpenseType(String type) {
    const salaryKeywords = [
      'رواتب',
      'سحب راتب',
      'سحب من الراتب',
      'خصم راتب',
      'خصم من الراتب'
    ];
    for (final keyword in salaryKeywords) {
      if (type.contains(keyword)) return true;
    }
    return false;
  }
}
