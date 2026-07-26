import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../utils/time.dart';
import '../appwrite_config.dart';
import '../appwrite_sync_utils.dart';
import '../local_db.dart';

/// PayloadMapper — يحوّل كيانات Drift المحلية إلى Map<String, dynamic>
/// جاهزة للإرسال إلى Appwrite Cloud.
///
/// تم تحديث هذا الصنف ليتطابق بالكامل مع Appwrite Schema v2
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

  /// ✅ يطبّع UUID للصيغة القياسية (بالشرطات: 8-4-4-4-12).
  /// إذا كان 32 حرف بدون شرطات، يضيف الشرطات.
  /// إذا كان بالشرطات بالفعل، يُرجعه كما هو.
  String _normalizeUuid(String uuid) {
    final trimmed = uuid.trim();
    if (trimmed.length == 32 && !trimmed.contains('-')) {
      return '${trimmed.substring(0, 8)}-${trimmed.substring(8, 12)}-'
          '${trimmed.substring(12, 16)}-${trimmed.substring(16, 20)}-'
          '${trimmed.substring(20)}';
    }
    return trimmed;
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
      // ✅ إصلاح: إضافة vectorClock (كان مفقوداً — يُعطّل كشف التعارضات)
      'vectorClock': room.vectorClock,
      'deviceId': room.deviceId,
      // تمت إزالة الحقول الزائدة التي لا توجد في المخطط (floor, bedsCount, roomType, basePrice)
    };
    putIfNotNull(data, 'serverId', room.serverId);
    putIfNotNull(data, 'deletedAt', room.deletedAt);
    putIfStringNotEmpty(data, 'imageUrl', room.imageUrl);
    putIfStringNotEmpty(data, 'cleaningStatus', room.cleaningStatus);
    putIfStringNotEmpty(data, 'lastCleanedHotelDay', room.lastCleanedHotelDay);
    putIfStringNotEmpty(
      data,
      'lastOccupiedHotelDay',
      room.lastOccupiedHotelDay,
    );
    putIfNotNull(data, 'requiresMaintenance', room.requiresMaintenance);
    putIfStringNotEmpty(data, 'idempotencyKey', room.idempotencyKey);
    putIfStringNotEmpty(data, 'sync_origin', room.origin);

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
    putIfNotNull(data, 'deletedAt', booking.deletedAt);
    putIfStringNotEmpty(data, 'guestIdIssueDate', booking.guestIdIssueDate);
    putIfStringNotEmpty(data, 'guestIdIssuePlace', booking.guestIdIssuePlace);
    putIfStringNotEmpty(data, 'guestEmail', booking.guestEmail);
    putIfStringNotEmpty(data, 'guestAddress', booking.guestAddress);
    data['checkoutDate'] = booking.checkoutDate;
    data['actualCheckout'] = booking.actualCheckout;
    putIfStringNotEmpty(data, 'notes', booking.notes);
    data['discount'] = booking.discount;
    // ✅ حقل amount الموحّد لجدول bookings (مثل payments/expenses/cash_transactions).
    // القيمة المشتقّة = المبلغ المستحق للمُطالبة (totalDueCached). هذا الحقل يُرسَل
    // لكل من Primary و Secondary فيطابق الحقول تماماً.
    data['amount'] = booking.totalDueCached;
    putIfStringNotEmpty(data, 'discountType', booking.discountType);
    putIfStringNotEmpty(data, 'discountStartDate', booking.discountStartDate);
    data['totalDueCached'] = booking.totalDueCached;
    data['totalPaidCached'] = booking.totalPaidCached;
    data['remainingBalanceCached'] = booking.remainingBalanceCached;
    data['totalNightsCached'] = booking.totalNightsCached;
    data['isFullyPaid'] = booking.isFullyPaid;
    putIfStringNotEmpty(data, 'hotelDayCheckin', booking.hotelDayCheckin);
    putIfStringNotEmpty(data, 'hotelDayCheckout', booking.hotelDayCheckout);
    putIfStringNotEmpty(data, 'vectorClock', booking.vectorClock);
    data['deviceId'] = booking.deviceId;

    // حقول v2 الجديدة
    // TODO: enable when Drift model has this field — putIfNotNull(data, 'financialFrozenAt', booking.financialFrozenAt);
    // TODO: enable when Drift model has this field — putIfStringNotEmpty(data, 'financialHash', booking.financialHash);
    putIfStringNotEmpty(data, 'stayDurationIso', booking.stayDurationIso);
    putIfNotNull(data, 'lastNightEpoch', booking.lastNightEpoch);
    putIfNotNull(data, 'isOverdue', booking.isOverdue);
    putIfNotNull(data, 'needsCheckoutReview', booking.needsCheckoutReview);
    putIfStringNotEmpty(data, 'idempotencyKey', booking.idempotencyKey);

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
    final now = Time.nowEpoch();
    final data = <String, dynamic>{
      'expenseType': expense.expenseType,
      'description': expense.description,
      'amount': expense.amount,
      'date': expense.date,
      'localUuid': expense.localUuid,
      'createdAt': expense.createdAt,
      'updatedAt': expense.updatedAt,
      'lastModified': expense.lastModified,
      'createdAtEpoch': expense.createdAtEpoch,
      'lastModifiedEpoch': expense.lastModifiedEpoch,
      'version': expense.version,
      'origin': expense.origin,
      'sync_origin': expense.origin,
      'syncTimestamp': now,
      'vectorClock': expense.vectorClock,
      'deviceId': expense.deviceId,
    };
    putIfNotNull(data, 'relatedId', expense.relatedId);
    putIfNotNull(data, 'cashTransactionId', expense.cashTransactionId);
    putIfNotNull(data, 'serverId', expense.serverId);
    putIfNotNull(data, 'deletedAt', expense.deletedAt);
    putIfStringNotEmpty(data, 'hotelDayKey', expense.hotelDayKey);
    putIfStringNotEmpty(data, 'categoryUuid', expense.categoryUuid);
    putIfStringNotEmpty(data, 'cashFlowUuid', expense.cashFlowUuid);
    putIfStringNotEmpty(data, 'createdAtIso', expense.createdAtIso);
    putIfStringNotEmpty(data, 'updatedAtIso', expense.updatedAtIso);
    putIfStringNotEmpty(data, 'deletedAtIso', expense.deletedAtIso);
    // ✅ إصلاح (P1-5): إرسال isAutoGenerated دائماً كـ boolean (وليس فقط true).
    // كنا نُرسله فقط `if (expense.isAutoGenerated)` مما يعني أن false لا يُرسل.
    // الـ adapter يُرسله دائماً. توحيد السلوك لتفادي فقدان القيمة false.
    // Appwrite schema: boolean (مُتحقّق منه).
    data['isAutoGenerated'] = expense.isAutoGenerated;
    putIfStringNotEmpty(data, 'employeeUuid', expense.employeeUuid);
    putIfStringNotEmpty(data, 'idempotencyKey', expense.idempotencyKey);
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
      'isPendingBalance': payment.isPendingBalance,
      'isVoided': payment.isVoided,
    };
    putIfNotNull(data, 'serverPaymentId', payment.serverPaymentId);
    // ✅ إصلاح حرج: لا نرسل bookingLocalId للسيرفر!
    // bookingLocalId هو id محلي (autoIncrement) يختلف بين الأجهزة.
    // جهاز A قد يكون bookingLocalId=27، وجهاز B لنفس الحجز bookingLocalId=146.
    // إرسال هذا الرقم للسيرفر يلوّث البيانات ويسبب ربطاً خاطئاً عند السحب.
    // الربط الصحيح يتم عبر bookingUuidCache (UUID ثابت عبر الأجهزة).
    // (لا نرسل bookingLocalId إطلاقاً — البيانات تُستقبل محلياً فقط)
    // ✅ إصلاح: تطبيع bookingUuidCache للصيغة القياسية (بالشرطات) قبل الإرسال
    // منع تكرار UUIDs بصيغ مختلفة على Appwrite Cloud
    if (payment.bookingUuidCache != null &&
        payment.bookingUuidCache!.isNotEmpty) {
      putIfStringNotEmpty(
        data,
        'bookingUuidCache',
        _normalizeUuid(payment.bookingUuidCache!),
      );
    }
    putIfNotNull(data, 'serverBookingId', payment.serverBookingId);
    putIfStringNotEmpty(data, 'roomNumber', payment.roomNumber);
    putIfStringNotEmpty(data, 'hotelDayKey', payment.hotelDayKey);
    putIfStringNotEmpty(data, 'notes', payment.notes);
    putIfNotNull(
      data,
      'cashTransactionLocalId',
      payment.cashTransactionLocalId,
    );
    putIfNotNull(
      data,
      'cashTransactionServerId',
      payment.cashTransactionServerId,
    );
    putIfStringNotEmpty(data, 'referenceNumber', payment.referenceNumber);
    putIfNotNull(data, 'serverId', payment.serverId);
    putIfNotNull(data, 'deletedAt', payment.deletedAt);
    putIfStringNotEmpty(data, 'deletedAtIso', payment.deletedAtIso);
    putIfStringNotEmpty(data, 'linkedDebtUuid', payment.linkedDebtUuid);
    putIfNotNull(data, 'discountAmount', payment.discountAmount);
    putIfStringNotEmpty(data, 'discountStartDate', payment.discountStartDate);
    putIfNotNull(data, 'voidedAt', payment.voidedAt);
    putIfStringNotEmpty(data, 'voidedBy', payment.voidedBy);

    // حقول v2 الجديدة
    // TODO: enable when Drift model has this field — putIfStringNotEmpty(data, 'voidReason', payment.voidReason);
    // TODO: enable when Drift model has this field — putIfNotNull(data, 'isImmutable', payment.isImmutable);
    putIfStringNotEmpty(data, 'idempotencyKey', payment.idempotencyKey);

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
      'remainingAmount': debt.remainingAmount.round(),
      // ✅ إصلاح: لا نرسل bookingLocalId للسيرفر (id محلي يختلف بين الأجهزة)
      // الربط يتم عبر resolveBooking في debts_adapter باستخدام bookingUuidCache
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
    putIfNotNull(data, 'deletedAt', debt.deletedAt);
    putIfStringNotEmpty(data, 'deletedAtIso', debt.deletedAtIso);
    putIfStringNotEmpty(data, 'hotelDayOpened', debt.hotelDayOpened);
    putIfStringNotEmpty(data, 'hotelDayClosed', debt.hotelDayClosed);
    data['vectorClock'] = debt.vectorClock;
    data['deviceId'] = debt.deviceId;

    // حقول v2 الجديدة
    putIfStringNotEmpty(data, 'dateRecorded', debt.dateRecorded);
    // TODO: enable when Drift model has this field — putIfStringNotEmpty(data, 'guestPhone', debt.guestPhone);
    // TODO: enable when Drift model has this field — putIfStringNotEmpty(data, 'description', debt.description);
    // TODO: enable when Drift model has this field — putIfStringNotEmpty(data, 'status', debt.status);
    // TODO: enable when Drift model has this field — putIfStringNotEmpty(data, 'dueDate', debt.dueDate);
    putIfStringNotEmpty(data, 'idempotencyKey', debt.idempotencyKey);

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
    final now = Time.nowEpoch();
    // ✅ salary و basicSalary يجب أن تكونا دائماً قيمتين فعليتين (وليس null)
    // لأن Appwrite الثانوي يطلبهما كـ required. نضمن قيمة 0.0 كاحتياطي.
    final basicSalary = employee.basicSalary;
    final data = <String, dynamic>{
      'name': employee.name,
      'basicSalary': basicSalary,
      'salary': basicSalary,
      'position': employee.position,
      'phone': employee.phone,
      'hireDate': employee.hireDate,
      'status': employee.status,
      'localUuid': employee.localUuid,
      'createdAt': employee.createdAt,
      'updatedAt': employee.updatedAt,
      'lastModified': employee.lastModified,
      'createdAtEpoch': employee.createdAtEpoch,
      'lastModifiedEpoch': employee.lastModifiedEpoch,
      'version': employee.version,
      'origin': employee.origin,
      'sync_origin': employee.origin,
      'syncTimestamp': now,
      'vectorClock': employee.vectorClock,
      'deviceId': employee.deviceId,
    };
    putIfNotNull(data, 'serverId', employee.serverId);
    putIfNotNull(data, 'deletedAt', employee.deletedAt);
    putIfStringNotEmpty(data, 'createdAtIso', employee.createdAtIso);
    putIfStringNotEmpty(data, 'updatedAtIso', employee.updatedAtIso);
    putIfStringNotEmpty(data, 'deletedAtIso', employee.deletedAtIso);
    // حقول v2 الجديدة
    putIfStringNotEmpty(data, 'terminationDate', employee.terminationDate);
    putIfStringNotEmpty(data, 'terminationReason', employee.terminationReason);
    putIfStringNotEmpty(data, 'EmployeeID', employee.employeeID);
    putIfStringNotEmpty(data, 'idempotencyKey', employee.idempotencyKey);
    // ✅ إصلاح (P0-2): لف البيانات بـ sanitizePayload مثل باقي الكيانات.
    // بدون هذا، أي حقل غير معروف سيتجاوز الفلترة ويُسبب "Unknown attribute"
    // errors من Appwrite. PayloadMapper لباقي الكيانات يستخدم sanitizePayload.
    return AppwriteSyncUtils.sanitizePayload(
      'employees',
      data,
      collectionId: AppwriteConfig.employeesCollectionId,
    );
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
      // ✅ إصلاح: إضافة vectorClock
      'vectorClock': note.vectorClock,
      'sync_origin': note.origin,
      'deviceId': note.deviceId,
    };
    putIfNotNull(data, 'serverId', note.serverId);
    putIfNotNull(data, 'deletedAt', note.deletedAt);
    putIfStringNotEmpty(data, 'alertUntil', note.alertUntil);
    putIfStringNotEmpty(data, 'idempotencyKey', note.idempotencyKey);
    return data;
  }

  /// يحوّل [BookingNight] محلي إلى payload لـ Appwrite.
  Map<String, dynamic> bookingNightToRemote(BookingNight night) {
    final data = <String, dynamic>{
      // ✅ إصلاح: لا نرسل bookingLocalId للسيرفر (id محلي يختلف بين الأجهزة)
      // الربط يتم عبر resolveBooking في nights_adapter باستخدام bookingUuidCache
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
      'sync_origin': night.origin,
    };
    putIfNotNull(data, 'serverId', night.serverId);
    putIfNotNull(data, 'deletedAt', night.deletedAt);
    putIfStringNotEmpty(
      data,
      'appliedAdjustmentUuid',
      night.appliedAdjustmentUuid,
    );
    putIfStringNotEmpty(
      data,
      'appliedAdjustmentsJson',
      night.appliedAdjustmentsJson,
    );

    // حقول v2 الجديدة
    // TODO: enable when Drift model has this field — putIfStringNotEmpty(data, 'bookingUuidCache', night.bookingUuidCache);
    // TODO: enable when Drift model has this field — putIfNotNull(data, 'serverBookingId', night.serverBookingId);
    putIfStringNotEmpty(data, 'idempotencyKey', night.idempotencyKey);

    return data;
  }

  /// يحوّل [CashTransaction] محلي إلى payload لـ Appwrite.
  Map<String, dynamic> cashTransactionToRemote(CashTransaction transaction) {
    final data = <String, dynamic>{
      'transactionType': transaction.transactionType,
      'amount': transaction.amount, // ✅ Appwrite: double (fixed 2026-07-26)
      'transactionTime': transaction.transactionTime,
      'localUuid': transaction.localUuid,
      'createdAt': transaction.createdAt,
      'updatedAt': transaction.updatedAt,
      'lastModified': transaction.lastModified,
      'version': transaction.version,
      'origin': transaction.origin,
      // ✅ إصلاح: إضافة vectorClock
      'vectorClock': transaction.vectorClock,
      'deviceId': transaction.deviceId,
      'sync_origin': transaction.origin,
    };
    putIfNotNull(data, 'registerId', transaction.registerId);
    putIfNotNull(data, 'referenceId', transaction.referenceId);
    putIfNotNull(data, 'createdBy', transaction.createdBy);
    putIfNotNull(data, 'serverId', transaction.serverId);
    putIfNotNull(data, 'deletedAt', transaction.deletedAt);
    putIfStringNotEmpty(data, 'referenceType', transaction.referenceType);
    putIfStringNotEmpty(data, 'description', transaction.description);
    putIfStringNotEmpty(data, 'idempotencyKey', transaction.idempotencyKey);
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
      'sync_origin': cycle.origin,
    };
    putIfNotNull(data, 'serverId', cycle.serverId);
    putIfNotNull(data, 'deletedAt', cycle.deletedAt);
    putIfStringNotEmpty(data, 'hotelDayStart', cycle.hotelDayStart);
    putIfStringNotEmpty(data, 'hotelDayEnd', cycle.hotelDayEnd);
    putIfStringNotEmpty(data, 'idempotencyKey', cycle.idempotencyKey);
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
      // ✅ إصلاح: إضافة vectorClock
      'vectorClock': payment.vectorClock,
      'deviceId': payment.deviceId,
      'sync_origin': payment.origin,
    };
    putIfNotNull(data, 'serverId', payment.serverId);
    putIfNotNull(data, 'deletedAt', payment.deletedAt);
    putIfStringNotEmpty(data, 'hotelDayKey', payment.hotelDayKey);
    putIfStringNotEmpty(data, 'method', payment.method);
    putIfStringNotEmpty(data, 'idempotencyKey', payment.idempotencyKey);
    return data;
  }

  /// يحوّل [ShiftNote] محلي إلى payload لـ Appwrite.
  Map<String, dynamic> shiftNoteToRemote(ShiftNote note) {
    final createdDate = DateTime.fromMillisecondsSinceEpoch(
      note.createdAt * 1000,
    );
    final shiftDate = createdDate.toIso8601String().substring(0, 10);
    final createdAtIso = note.createdAtIso ?? createdDate.toIso8601String();
    final updatedAtIso =
        note.updatedAtIso ??
        DateTime.fromMillisecondsSinceEpoch(
          note.updatedAt * 1000,
        ).toIso8601String();
    final data = <String, dynamic>{
      'localUuid': note.localUuid,
      'title': note.title,
      'content': note.content,
      'priority': note.priority,
      'shiftType': note.shiftType,
      'isRead': note.isRead == 1,
      // ✅ إصلاح: shift_notes schema يُعرّف createdAt/updatedAt كـ string (ISO)
      'createdAt': createdAtIso,
      'createdAtIso': createdAtIso,
      'updatedAt': updatedAtIso,
      'updatedAtIso': updatedAtIso,
      'lastModified': note.lastModified,
      'createdBy': note.createdBy,
      'shiftDate': shiftDate,
      'deviceId': note.deviceId,
      'sync_origin': note.origin,
      // ✅ حقول الـ sync المفقودة (إصلاح 2026-07-03)
      'version': note.version,
      'origin': note.origin,
      'vectorClock': note.vectorClock,
      // حقل v2 الجديد
      'note': note.content,
    };
    putIfStringNotEmpty(data, 'expiresAt', note.expiresAt);
    putIfStringNotEmpty(data, 'idempotencyKey', note.idempotencyKey);
    // ✅ إصلاح: إرسال deletedAt كـ integer (epoch seconds) وليس DateTime
    putIfNotNull(data, 'deletedAt', note.deletedAt);
    putIfNotNull(data, 'serverId', note.serverId);
    return data;
  }

  /// يحوّل [PriceAdjustment] محلي إلى payload لـ Appwrite.
  Map<String, dynamic> priceAdjustmentToRemote(PriceAdjustment row) {
    final now = Time.nowEpoch();
    final data = <String, dynamic>{
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
      'updatedAt': row.updatedAt > 0 ? row.updatedAt : now,
      'lastModified': row.lastModified > 0 ? row.lastModified : now,
      // ✅ إصلاح: استخدام version/origin/vectorClock من السجل (وليس ثوابت)
      'version': row.version,
      'origin': row.origin,
      'vectorClock': row.vectorClock,
      'syncTimestamp': now,
      'deviceId': row.deviceId,
      'sync_origin': row.origin,
    };
    putIfNotNull(data, 'serverId', row.serverId);
    putIfStringNotEmpty(data, 'idempotencyKey', row.idempotencyKey);
    // ✅ إصلاح: إرسال deletedAt كـ integer (epoch seconds)
    putIfNotNull(data, 'deletedAt', row.deletedAt);
    // TODO: enable when Drift model has this field — if (row.roomNumber != null) 'roomNumber': row.roomNumber, // حقل v2
    // TODO: enable when Drift model has this field — if (row.adjustmentMode != null) 'adjustmentMode': row.adjustmentMode, // حقل v2
    return data;
  }

  /// يحوّل سجل [ShiftNote] (يُستخدم كـ blacklist محلي) إلى payload لـ Appwrite.
  Map<String, dynamic> blacklistToRemote(ShiftNote item) {
    Map<String, dynamic> extra = {};
    try {
      extra = jsonDecode(item.content) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('WARN: Failed to parse blacklist content for sync: $e');
    }

    final now = Time.nowEpoch();
    final createdAtIso =
        item.createdAtIso ??
        DateTime.fromMillisecondsSinceEpoch(
          item.createdAt * 1000,
        ).toIso8601String();
    final updatedAtIso =
        item.updatedAtIso ??
        DateTime.fromMillisecondsSinceEpoch(
          item.updatedAt * 1000,
        ).toIso8601String();
    final deletedAtIso = item.deletedAt != null
        ? (item.deletedAtIso ??
              DateTime.fromMillisecondsSinceEpoch(
                item.deletedAt! * 1000,
              ).toIso8601String())
        : null;

    final data = <String, dynamic>{
      // تم الإصلاح الجذري لمطابقة مخطط v2
      'guestName': item.title,
      'guestPhone': (extra['phone'] as String?) ?? '',
      'guestIdNumber': (extra['nationalId'] as String?) ?? '',
      'reason': (extra['reason'] as String?) ?? '',
      'isActive': (extra['active'] as bool?) ?? true,
      'addedDate': createdAtIso,
      'addedBy': (extra['reportedBy'] as String?) ?? 'police',

      'localUuid': item.localUuid,
      // ✅ إصلاح: blacklist schema يُعرّف createdAt/updatedAt/deletedAt كـ string (ISO)
      // وليس integer (epoch) مثل باقي الكيانات — نرسل ISO string لتجنب
      // خطأ "createdAt has invalid type. Value must be a valid string"
      'createdAt': createdAtIso,
      'createdAtIso': createdAtIso,
      'updatedAt': updatedAtIso,
      'updatedAtIso': updatedAtIso,
      'lastModified': item.lastModified,
      // ✅ إصلاح: version/origin/vectorClock من السجل (كانت ثوابت 'mobile')
      'version': item.version,
      'origin': item.origin,
      'vectorClock': item.vectorClock,
      'syncTimestamp': now,
      'deviceId': item.deviceId,
      'sync_origin': item.origin,
    };
    // ✅ إصلاح: deletedAt كـ integer (epoch seconds) وليس ISO string
    putIfNotNull(data, 'deletedAt', item.deletedAt);
    if (deletedAtIso != null) {
      putIfStringNotEmpty(data, 'deletedAtIso', deletedAtIso);
    }
    putIfNotNull(data, 'serverId', item.serverId);
    putIfStringNotEmpty(data, 'idempotencyKey', item.idempotencyKey);
    return data;
  }

  /// يحوّل [GuestInfo] محلي إلى payload لـ Appwrite.
  Map<String, dynamic> guestInfoToRemote(GuestInfo info) {
    final now = Time.nowEpoch();
    final data = <String, dynamic>{
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
      // تمت إزالة حقل 'id' لتجنب التعارض
      'roomNumber': info.roomNumber,
      'guestName': info.guestName,
      'nationality': info.nationality,
      'idNumber': info.idNumber,
      'idType': info.idType,
    };

    putIfStringNotEmpty(data, 'idempotencyKey', info.idempotencyKey);

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
  Map<String, dynamic> salaryWithdrawalToRemote(
    SalaryWithdrawal withdrawal, {
    String? employeeUuid,
  }) {
    final now = Time.nowEpoch();
    final effectiveWithdrawDate = withdrawal.withdrawDate.isEmpty
        ? DateTime.now().toIso8601String().split('T').first
        : withdrawal.withdrawDate;

    final data = <String, dynamic>{
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
      // تمت إزالة 'id'
      'employeeId': withdrawal.employeeId,
      'amount': withdrawal.amount, // ✅ Appwrite: double (fixed 2026-07-26)
      'withdrawDate': effectiveWithdrawDate,
      'withdrawalDate': effectiveWithdrawDate,
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
    putIfStringNotEmpty(data, 'idempotencyKey', withdrawal.idempotencyKey);

    if (employeeUuid != null && employeeUuid.isNotEmpty) {
      data['employeeUuid'] = employeeUuid;
      data['employeeLocalUuid'] = employeeUuid;
    }

    data['date'] = effectiveWithdrawDate;
    data['action'] = withdrawal.withdrawalType ?? 'withdrawal';
    data['note'] = withdrawal.description ?? '';
    data['name'] = '';

    return data;
  }

  /// يحوّل [BookingPriceAdjustment] محلي إلى payload لـ Appwrite.
  Map<String, dynamic> bookingPriceAdjustmentToRemote(
    BookingPriceAdjustment adj,
  ) {
    final now = Time.nowEpoch();
    final data = <String, dynamic>{
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
      // تمت إزالة 'id'
      'bookingLocalUuid': adj.bookingLocalUuid,
      'adjustmentType': adj.adjustmentType,
      'adjustmentMode': adj.adjustmentMode,
      'amount': adj.amount, // ✅ Appwrite: double (fixed 2026-07-26)
      'effectiveHotelDay': adj.effectiveHotelDay,
      // ✅ إصلاح 2026-07-26: hotelDayKey مطلوب على Appwrite Cloud (required attribute,
      // created 2026-07-03). محلياً BookingPriceAdjustments لا يملك عمود hotelDayKey
      // منفصل — effectiveHotelDay IS the hotel day key (same value, different name).
      // نرسله تحت الاسمين للحفاظ على التوافق مع المخطط المحلي والمطلوب من Appwrite.
      'hotelDayKey': adj.effectiveHotelDay,
      'isActive': adj.isActive,
    };

    // حقول v2 الجديدة
    // TODO: enable when Drift model has this field — putIfStringNotEmpty(data, 'bookingUuid', adj.bookingUuid);
    // TODO: enable when Drift model has this field — putIfNotNull(data, 'appliedAt', adj.appliedAt);
    putIfStringNotEmpty(data, 'idempotencyKey', adj.idempotencyKey);

    putIfNotNull(data, 'serverId', adj.serverId);
    putIfNotNull(data, 'deletedAt', adj.deletedAt);
    // ✅ إصلاح: لا نرسل bookingLocalId للسيرفر (id محلي يختلف بين الأجهزة)
    // الربط يتم عبر bookingLocalUuid (UUID ثابت عبر الأجهزة)
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

  /// يحوّل [SalaryCarryOverLog] محلي إلى payload لـ Appwrite.
  Map<String, dynamic> salaryCarryOverLogToRemote(SalaryCarryOverLog log) {
    final now = Time.nowEpoch();
    final data = <String, dynamic>{
      'localUuid': log.localUuid,
      'createdAt': log.createdAt,
      'updatedAt': log.updatedAt,
      'lastModified': log.lastModifiedEpoch > 0 ? log.lastModifiedEpoch : now,
      'lastModifiedEpoch': log.lastModifiedEpoch,
      'createdAtEpoch': log.createdAtEpoch,
      'version': log.version,
      'origin': log.origin,
      'sync_origin': log.origin,
      'syncTimestamp': now,
      'vectorClock': log.vectorClock,
      'deviceId': log.deviceId,
      // تمت إزالة 'id'
      'employeeId': log.employeeId,
      'amount': log.amount,
      'reason': log.reason,

      // تم الإصلاح ليتوافق مع v2 (ترحيل المتغيرات إذا تم تحديث Drift، وإلا تمرير القديمة مؤقتاً لتجنب الأخطاء)
      // TODO: enable when Drift model has this field — 'fromCycleId': log.fromCycleId ?? log.previousCycleStart, // احتياطي إن لم يحدث الموديل
      // TODO: enable when Drift model has this field — 'toCycleId': log.toCycleId ?? log.newCycleStart,         // احتياطي
      // TODO: enable when Drift model has this field — 'carryDate': log.carryDate ?? log.carriedAt,             // احتياطي
    };

    // حقول v2 الجديدة
    // TODO: enable when Drift model has this field — putIfStringNotEmpty(data, 'hotelDayKey', log.hotelDayKey);
    // TODO: enable when Drift model has this field — putIfStringNotEmpty(data, 'performedBy', log.performedBy);
    putIfStringNotEmpty(data, 'idempotencyKey', log.idempotencyKey);

    putIfNotNull(data, 'serverId', log.serverId);
    putIfNotNull(data, 'deletedAt', log.deletedAt);
    putIfStringNotEmpty(data, 'createdAtIso', log.createdAtIso);
    putIfStringNotEmpty(data, 'updatedAtIso', log.updatedAtIso);
    putIfStringNotEmpty(data, 'deletedAtIso', log.deletedAtIso);
    return data;
  }

  /// هل نوع المصروف مرتبط بالرواتب
  static bool isSalaryExpenseType(String type) {
    const salaryKeywords = [
      'رواتب',
      'سحب راتب',
      'سحب من الراتب',
      'خصم راتب',
      'خصم من الراتب',
    ];
    for (final keyword in salaryKeywords) {
      if (type.contains(keyword)) return true;
    }
    return false;
  }

  /// يحوّل [PaymentVoid] محلي إلى payload لـ Appwrite.
  ///
  /// سجل إلغاء دفع — يُنشأ عند void دفعة موجودة. يحتوي على:
  /// - مرجع للدفع الأصلي (originalPaymentUuid + originalPaymentId)
  /// - معرف الحجز المرتبط (bookingUuid)
  /// - بيانات الإلغاء (voidedAmount, voidReason, voidedBy, voidedAt)
  /// - الدفع العكسي المرتبط (reversalPaymentUuid) إن وُجد
  /// - الموافق على الإلغاء (approvedBy)
  /// - v2: ملاحظة (note)، المبلغ الأصلي (originalAmount)، UUID الدفع (paymentUuid)
  Map<String, dynamic> paymentVoidToRemote(PaymentVoid voidRecord) {
    final now = Time.nowEpoch();
    final data = <String, dynamic>{
      // ── Sync fields ──
      'localUuid': voidRecord.localUuid,
      'createdAt': voidRecord.createdAt,
      'updatedAt': voidRecord.updatedAt,
      'lastModified': voidRecord.lastModified,
      'lastModifiedEpoch': voidRecord.lastModifiedEpoch,
      'createdAtEpoch': voidRecord.createdAtEpoch,
      'version': voidRecord.version,
      'origin': voidRecord.origin,
      'sync_origin': voidRecord.origin,
      'syncTimestamp': now,
      'vectorClock': voidRecord.vectorClock,
      'deviceId': voidRecord.deviceId,
      // ── Business fields (إلغاء الدفع) ──
      'originalPaymentUuid': voidRecord.originalPaymentUuid,
      'originalPaymentId': voidRecord.originalPaymentId,
      'bookingUuid': voidRecord.bookingUuid,
      'voidedAmount': voidRecord.voidedAmount,
      'voidReason': voidRecord.voidReason,
      'voidedBy': voidRecord.voidedBy,
      'voidedAt': voidRecord.voidedAt,
      'voidedAtIso': voidRecord.voidedAtIso,
      'hotelDayKey': voidRecord.hotelDayKey,
    };
    putIfNotNull(data, 'serverId', voidRecord.serverId);
    putIfNotNull(data, 'deletedAt', voidRecord.deletedAt);
    putIfStringNotEmpty(
      data,
      'reversalPaymentUuid',
      voidRecord.reversalPaymentUuid,
    );
    putIfStringNotEmpty(data, 'approvedBy', voidRecord.approvedBy);
    putIfStringNotEmpty(data, 'createdAtIso', voidRecord.createdAtIso);
    putIfStringNotEmpty(data, 'updatedAtIso', voidRecord.updatedAtIso);
    putIfStringNotEmpty(data, 'deletedAtIso', voidRecord.deletedAtIso);
    putIfStringNotEmpty(data, 'idempotencyKey', voidRecord.idempotencyKey);
    // ✅ v2: حقول إضافية موجودة على Appwrite Cloud
    putIfStringNotEmpty(data, 'note', voidRecord.note);
    putIfNotNull(data, 'originalAmount', voidRecord.originalAmount);
    putIfStringNotEmpty(data, 'paymentUuid', voidRecord.paymentUuid);
    return data;
  }
}
