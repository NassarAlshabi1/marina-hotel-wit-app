import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'appwrite_config_manager.dart';
import 'package:marina_hotel_mobile/utils/debug_log.dart';

/// سكريبت للتحقق من مطابقة جداول Appwrite Cloud
///
/// الاستخدام:
/// ```dart
/// await verifyAppwriteSchema();
/// ```
class AppwriteSchemaVerifier {
  static final _requiredCollections = {
    'inventory_items': {
      'name': 'Inventory Items',
      'includeSyncFields': true,
      'attributes': [
        {
          'key': 'localUuid',
          'type': 'string',
          'size': 36,
          'required': true,
          'unique': true,
        },
        {'key': 'name', 'type': 'string', 'size': 200, 'required': true},
        {'key': 'unit', 'type': 'string', 'size': 50, 'default': 'قطعة'},
        {'key': 'category', 'type': 'string', 'size': 100},
        {'key': 'quantity', 'type': 'integer', 'default': 0},
        {'key': 'minimumQuantity', 'type': 'integer', 'default': 0},
        {'key': 'isActive', 'type': 'boolean', 'default': true},
      ],
    },
    'inventory_transactions': {
      'name': 'Inventory Transactions',
      'includeSyncFields': true,
      'attributes': [
        {
          'key': 'localUuid',
          'type': 'string',
          'size': 36,
          'required': true,
          'unique': true,
        },
        {'key': 'itemLocalUuid', 'type': 'string', 'size': 36},
        {'key': 'itemId', 'type': 'integer', 'required': true},
        {'key': 'movementType', 'type': 'string', 'size': 20, 'required': true},
        {'key': 'quantity', 'type': 'integer', 'required': true},
        {'key': 'balanceAfter', 'type': 'integer', 'required': true},
        {'key': 'note', 'type': 'string', 'size': 500},
        {'key': 'userId', 'type': 'integer'},
        {'key': 'userName', 'type': 'string', 'size': 200},
      ],
    },
    'rooms': {
      'name': 'Rooms',
      'includeSyncFields': true,
      'attributes': [
        {
          'key': 'localUuid',
          'type': 'string',
          'size': 36,
          'required': true,
          'unique': true,
        },
        {
          'key': 'roomNumber',
          'type': 'string',
          'size': 50,
          'required': true,
          'unique': true,
        },
        {'key': 'type', 'type': 'string', 'size': 512, 'required': true},
        {'key': 'price', 'type': 'double', 'required': true},
        {'key': 'status', 'type': 'string', 'size': 512, 'required': true},
        {'key': 'imageUrl', 'type': 'string', 'size': 500},
        {
          'key': 'cleaningStatus',
          'type': 'string',
          'size': 20,
          'default': 'clean',
        },
        {'key': 'lastCleanedHotelDay', 'type': 'string', 'size': 50},
        {'key': 'lastOccupiedHotelDay', 'type': 'string', 'size': 50},
        {'key': 'requiresMaintenance', 'type': 'boolean', 'default': false},
      ],
    },
    'bookings': {
      'name': 'Bookings',
      'includeSyncFields': true,
      'attributes': [
        {
          'key': 'localUuid',
          'type': 'string',
          'size': 36,
          'required': true,
          'unique': true,
        },
        {'key': 'serverBookingId', 'type': 'integer'},
        {'key': 'roomNumber', 'type': 'string', 'size': 512, 'required': true},
        {'key': 'guestName', 'type': 'string', 'size': 512, 'required': true},
        {'key': 'guestPhone', 'type': 'string', 'size': 512, 'required': true},
        {
          'key': 'guestIdType',
          'type': 'string',
          'size': 50,
          'default': 'بطاقة شخصية',
        },
        {'key': 'guestIdNumber', 'type': 'string', 'size': 100, 'default': ''},
        {'key': 'guestIdIssueDate', 'type': 'string', 'size': 50},
        {'key': 'guestIdIssuePlace', 'type': 'string', 'size': 100},
        {
          'key': 'guestNationality',
          'type': 'string',
          'size': 512,
          'required': true,
        },
        {'key': 'guestEmail', 'type': 'string', 'size': 100},
        {'key': 'guestAddress', 'type': 'string', 'size': 200},
        {'key': 'checkinDate', 'type': 'string', 'size': 64, 'required': true},
        {'key': 'checkoutDate', 'type': 'string', 'size': 50},
        {'key': 'actualCheckout', 'type': 'string', 'size': 50},
        {'key': 'status', 'type': 'string', 'size': 512, 'required': true},
        {'key': 'notes', 'type': 'string', 'size': 1000},
        {'key': 'expectedNights', 'type': 'integer', 'default': 1},
        {'key': 'calculatedNights', 'type': 'integer', 'default': 1},
        {'key': 'totalNightsCached', 'type': 'integer', 'default': 0},
        {'key': 'stayDurationIso', 'type': 'string', 'size': 50},
        {'key': 'lastNightEpoch', 'type': 'integer'},
        {'key': 'isOverdue', 'type': 'boolean', 'default': false},
        {'key': 'needsCheckoutReview', 'type': 'boolean', 'default': false},
        {'key': 'totalDueCached', 'type': 'double', 'default': 0},
        {'key': 'totalPaidCached', 'type': 'double', 'default': 0},
        {'key': 'remainingBalanceCached', 'type': 'double', 'default': 0},
        {'key': 'isFullyPaid', 'type': 'boolean', 'default': false},
        {'key': 'discount', 'type': 'double', 'default': 0},
        {
          'key': 'discountType',
          'type': 'string',
          'size': 20,
          'default': 'per_night',
        },
        {'key': 'discountStartDate', 'type': 'string', 'size': 50},
        {'key': 'hotelDayCheckin', 'type': 'string', 'size': 50},
        {'key': 'hotelDayCheckout', 'type': 'string', 'size': 50},
        // ✅ حقول إضافية
        {'key': 'amount', 'type': 'double'},
        {'key': 'financialFrozenAt', 'type': 'integer'},
        {'key': 'financialHash', 'type': 'string', 'size': 64},
      ],
    },
    'booking_notes': {
      'name': 'Booking Notes',
      'includeSyncFields': true,
      'attributes': [
        {
          'key': 'localUuid',
          'type': 'string',
          'size': 36,
          'required': true,
          'unique': true,
        },
        {'key': 'bookingId', 'type': 'integer', 'required': true},
        {'key': 'noteText', 'type': 'string', 'size': 1000, 'required': true},
        {'key': 'alertType', 'type': 'string', 'size': 20, 'required': true},
        {'key': 'alertUntil', 'type': 'string', 'size': 50},
        {'key': 'isActive', 'type': 'integer', 'default': 1},
      ],
    },
    'booking_nights': {
      'name': 'Booking Nights',
      'includeSyncFields': true,
      'attributes': [
        {
          'key': 'localUuid',
          'type': 'string',
          'size': 36,
          'required': true,
          'unique': true,
        },
        {'key': 'bookingLocalId', 'type': 'integer'},
        {'key': 'hotelDayKey', 'type': 'string', 'size': 64, 'required': true},
        {'key': 'nightStart', 'type': 'string', 'size': 255, 'required': true},
        {'key': 'nightEnd', 'type': 'string', 'size': 255},
        {'key': 'nightlyRate', 'type': 'double', 'default': 0},
        {'key': 'sequence', 'type': 'integer', 'default': 0},
        {'key': 'isProcessedByAutoFix', 'type': 'boolean', 'default': false},
        // ✅ الحقول التالية أُضيفت إلى Appwrite Cloud (2026-05-15)
        {'key': 'baseRate', 'type': 'double', 'default': 0},
        {'key': 'adjustment', 'type': 'double', 'default': 0},
        {'key': 'finalRate', 'type': 'double', 'default': 0},
        {'key': 'appliedAdjustmentUuid', 'type': 'string', 'size': 36},
        {'key': 'appliedAdjustmentsJson', 'type': 'string', 'size': 5000},
      ],
    },
    'employees': {
      'name': 'Employees',
      'includeSyncFields': true,
      'attributes': [
        {
          'key': 'localUuid',
          'type': 'string',
          'size': 36,
          'required': true,
          'unique': true,
        },
        {'key': 'name', 'type': 'string', 'size': 255, 'required': true},
        {'key': 'basicSalary', 'type': 'double', 'required': true},
        {'key': 'position', 'type': 'string', 'size': 50, 'default': 'موظف'},
        {'key': 'phone', 'type': 'string', 'size': 50, 'default': ''},
        {'key': 'hireDate', 'type': 'string', 'size': 50, 'default': ''},
        {'key': 'status', 'type': 'string', 'size': 512, 'required': true},
        // ✅ حقول إنهاء الخدمة (Migration 39)
        {'key': 'terminationDate', 'type': 'string', 'size': 50},
        {'key': 'terminationReason', 'type': 'string', 'size': 500},
        // ✅ حقول إضافية
        {'key': 'EmployeeID', 'type': 'string', 'size': 50},
        {'key': 'salary', 'type': 'double'},
      ],
    },
    'expenses': {
      'name': 'Expenses',
      'includeSyncFields': true,
      'attributes': [
        {
          'key': 'localUuid',
          'type': 'string',
          'size': 36,
          'required': true,
          'unique': true,
        },
        {'key': 'expenseType', 'type': 'string', 'size': 255, 'required': true},
        {'key': 'relatedId', 'type': 'integer'},
        {'key': 'description', 'type': 'string', 'size': 255, 'required': true},
        {'key': 'amount', 'type': 'double', 'required': true},
        {'key': 'date', 'type': 'string', 'size': 64, 'required': true},
        {'key': 'cashTransactionId', 'type': 'integer'},
        {'key': 'hotelDayKey', 'type': 'string', 'size': 50},
        {'key': 'categoryUuid', 'type': 'string', 'size': 50},
        {'key': 'cashFlowUuid', 'type': 'string', 'size': 50},
        {'key': 'isAutoGenerated', 'type': 'boolean', 'default': false},
        // ✅ حقل employeeUuid لحل FK الموظف عبر الأجهزة لمصروفات الرواتب
        {'key': 'employeeUuid', 'type': 'string', 'size': 100},
      ],
    },
    'cash_transactions': {
      'name': 'Cash Transactions',
      'includeSyncFields': true,
      'attributes': [
        {'key': 'localUuid', 'type': 'string', 'size': 100, 'required': true},
        {'key': 'registerId', 'type': 'integer'},
        {
          'key': 'transactionType',
          'type': 'string',
          'size': 100,
          'required': true,
        },
        // ⚠️ amount على Appwrite Cloud هو integer (وليس double)
        // كود المزامنة يحول القيمة تلقائياً عبر AppwriteSyncUtils.convertAmountTypesForAppwrite
        {'key': 'amount', 'type': 'integer', 'required': false},
        {'key': 'referenceType', 'type': 'string', 'size': 100},
        {'key': 'referenceId', 'type': 'integer'},
        {'key': 'description', 'type': 'string', 'size': 500},
        {
          'key': 'transactionTime',
          'type': 'string',
          'size': 50,
          'required': true,
        },
        {'key': 'createdBy', 'type': 'integer'},
      ],
    },
    'payments': {
      'name': 'Payments',
      'includeSyncFields': true,
      'attributes': [
        {'key': 'localUuid', 'type': 'string', 'size': 36, 'required': true},
        {'key': 'serverPaymentId', 'type': 'integer'},
        {'key': 'bookingLocalId', 'type': 'integer'},
        {'key': 'serverBookingId', 'type': 'integer'},
        {'key': 'roomNumber', 'type': 'string', 'size': 50},
        {'key': 'amount', 'type': 'double', 'required': true},
        {'key': 'paymentDate', 'type': 'string', 'size': 64, 'required': true},
        {'key': 'notes', 'type': 'string', 'size': 500},
        {
          'key': 'paymentMethod',
          'type': 'string',
          'size': 255,
          'required': true,
        },
        {'key': 'revenueType', 'type': 'string', 'size': 255, 'required': true},
        {'key': 'cashTransactionLocalId', 'type': 'integer'},
        {'key': 'cashTransactionServerId', 'type': 'integer'},
        {'key': 'referenceNumber', 'type': 'string', 'size': 100},
        {'key': 'hotelDayKey', 'type': 'string', 'size': 50},
        {'key': 'isPendingBalance', 'type': 'boolean', 'default': false},
        {'key': 'linkedDebtUuid', 'type': 'string', 'size': 50},
        {'key': 'bookingUuidCache', 'type': 'string', 'size': 50},
        // ✅ تم إضافة الحقول التالية إلى Appwrite Cloud (2026-05-15)
        {'key': 'discountAmount', 'type': 'double'},
        {'key': 'discountStartDate', 'type': 'string', 'size': 50},
        {'key': 'isVoided', 'type': 'boolean', 'default': false},
        {'key': 'voidedAt', 'type': 'integer'},
        {'key': 'voidedBy', 'type': 'string', 'size': 100},
        {'key': 'voidReason', 'type': 'string', 'size': 500},
        {'key': 'isImmutable', 'type': 'boolean', 'default': false},
        {'key': 'receivedByUserId', 'type': 'integer'},
        {'key': 'receivedByName', 'type': 'string', 'size': 200},
        {'key': 'receivedSessionUuid', 'type': 'string', 'size': 36},
        {'key': 'receivedByCloudId', 'type': 'string', 'size': 100},
      ],
    },
    'debts': {
      'name': 'Debts',
      'includeSyncFields': true,
      'attributes': [
        {'key': 'localUuid', 'type': 'string', 'size': 36, 'required': true},
        {'key': 'bookingLocalId', 'type': 'integer'},
        {'key': 'guestName', 'type': 'string', 'size': 512, 'required': true},
        {'key': 'checkinDate', 'type': 'string', 'size': 64, 'required': true},
        {'key': 'checkoutDate', 'type': 'string', 'size': 64},
        {'key': 'dateRecorded', 'type': 'string', 'size': 50, 'default': ''},
        {'key': 'debtReason', 'type': 'string', 'size': 200, 'default': ''},
        {'key': 'totalAmount', 'type': 'double', 'required': true},
        {'key': 'paidAmount', 'type': 'double', 'required': true},
        {'key': 'remainingAmount', 'type': 'double', 'default': 0},
        {'key': 'paymentDate', 'type': 'string', 'size': 50},
        {'key': 'isSettled', 'type': 'boolean', 'default': false},
        {'key': 'pledge', 'type': 'string', 'size': 200},
        {'key': 'pledgeType', 'type': 'string', 'size': 50},
        {'key': 'note', 'type': 'string', 'size': 500},
        {'key': 'debtUuid', 'type': 'string', 'size': 100},
        {'key': 'hotelDayOpened', 'type': 'string', 'size': 50},
        {'key': 'hotelDayClosed', 'type': 'string', 'size': 50},
        {'key': 'isFromAutoFix', 'type': 'boolean', 'default': false},
        {'key': 'settlementConfirmed', 'type': 'boolean', 'default': false},
        // ✅ حقول إضافية
        {'key': 'guestPhone', 'type': 'string', 'size': 50},
        {'key': 'description', 'type': 'string', 'size': 500},
        {'key': 'status', 'type': 'string', 'size': 20},
        {'key': 'dueDate', 'type': 'string', 'size': 50},
        {'key': 'bookingUuidCache', 'type': 'string', 'size': 512},
        {'key': 'debtorName', 'type': 'string', 'size': 512},
        {'key': 'amount', 'type': 'double'},
        {'key': 'date', 'type': 'string', 'size': 64},
      ],
    },
    'salary_cycles': {
      'name': 'Salary Cycles',
      'includeSyncFields': true,
      'attributes': [
        {
          'key': 'localUuid',
          'type': 'string',
          'size': 36,
          'required': true,
          'unique': true,
        },
        {'key': 'employeeId', 'type': 'integer', 'required': true},
        {'key': 'cycleKey', 'type': 'string', 'size': 50, 'required': true},
        {'key': 'hotelDayStart', 'type': 'string', 'size': 50},
        {'key': 'hotelDayEnd', 'type': 'string', 'size': 50},
        {'key': 'expectedAmount', 'type': 'double', 'default': 0},
        {'key': 'actualPaid', 'type': 'double', 'default': 0},
        {'key': 'remainingAmount', 'type': 'double', 'default': 0},
        {'key': 'status', 'type': 'string', 'size': 20, 'default': 'draft'},
      ],
    },
    'salary_payments': {
      'name': 'Salary Payments',
      'includeSyncFields': true,
      'attributes': [
        {
          'key': 'localUuid',
          'type': 'string',
          'size': 36,
          'required': true,
          'unique': true,
        },
        {'key': 'cycleId', 'type': 'integer', 'required': true},
        // ✅ amount أُضيف إلى Appwrite Cloud (2026-05-15) كـ integer
        // المحلي يستخدم IntColumn لذلك النوع متطابق
        {'key': 'amount', 'type': 'integer', 'default': 0},
        {'key': 'hotelDayKey', 'type': 'string', 'size': 50},
        {
          'key': 'paymentDateIso',
          'type': 'string',
          'size': 50,
          'required': true,
        },
        {'key': 'method', 'type': 'string', 'size': 50},
        {'key': 'isAutoGenerated', 'type': 'boolean', 'default': false},
      ],
    },
    // ❌ hotel_day_ledger — جدول محلي فقط، لا يتم مزامنته أبداً
    // غير موجود على Appwrite Cloud ولن يُضاف لأنه بيانات محسوبة محلياً
    // البيانات تُعاد حسابها من خلال restore_fix_service.dart
    // 'hotel_day_ledger': { ... },
    'shift_notes': {
      'name': 'Shift Notes',
      'includeSyncFields': false,
      'attributes': [
        {'key': 'title', 'type': 'string', 'size': 200, 'required': true},
        {'key': 'content', 'type': 'string', 'size': 1000, 'required': true},
        {'key': 'priority', 'type': 'string', 'size': 20, 'default': 'medium'},
        {'key': 'shiftType', 'type': 'string', 'size': 20, 'default': 'all'},
        {'key': 'isRead', 'type': 'integer', 'default': 0},
        {'key': 'createdAt', 'type': 'string', 'size': 50, 'required': true},
        {'key': 'expiresAt', 'type': 'string', 'size': 50},
        {'key': 'createdBy', 'type': 'string', 'size': 50, 'default': 'user'},
      ],
    },
    'blacklist': {
      'name': 'Blacklist',
      'includeSyncFields': true,
      'attributes': [
        {
          'key': 'localUuid',
          'type': 'string',
          'size': 36,
          'required': true,
          'unique': true,
        },
        {'key': 'name', 'type': 'string', 'size': 200, 'required': true},
        {'key': 'nationality', 'type': 'string', 'size': 100},
        {'key': 'nationalId', 'type': 'string', 'size': 100},
        {'key': 'phone', 'type': 'string', 'size': 30},
        {'key': 'reason', 'type': 'string', 'size': 500},
        {'key': 'notes', 'type': 'string', 'size': 1000},
        {
          'key': 'reportedBy',
          'type': 'string',
          'size': 50,
          'default': 'police',
        },
        {'key': 'active', 'type': 'boolean', 'default': true},
      ],
    },
    'price_adjustments': {
      'name': 'Price Adjustments',
      'includeSyncFields': true,
      'attributes': [
        {
          'key': 'localUuid',
          'type': 'string',
          'size': 36,
          'required': true,
          'unique': true,
        },
        {'key': 'targetType', 'type': 'string', 'size': 20, 'required': true},
        {'key': 'targetUuid', 'type': 'string', 'size': 36, 'required': true},
        {
          'key': 'adjustmentType',
          'type': 'string',
          'size': 30,
          'required': true,
        },
        {'key': 'previousValue', 'type': 'double', 'required': true},
        {'key': 'newValue', 'type': 'double', 'required': true},
        {'key': 'reason', 'type': 'string', 'size': 500},
        {
          'key': 'effectiveDate',
          'type': 'string',
          'size': 30,
          'required': true,
        },
        {'key': 'appliedBy', 'type': 'string', 'size': 100, 'required': true},
        {'key': 'hotelDayKey', 'type': 'string', 'size': 10, 'required': true},
        {'key': 'isReversed', 'type': 'boolean', 'default': false},
        {'key': 'reversedAt', 'type': 'string', 'size': 30},
        {'key': 'reversedBy', 'type': 'string', 'size': 100},
      ],
    },
    'audit_logs': {
      'name': 'Audit Logs',
      'includeSyncFields': false,
      'attributes': [
        {
          'key': 'localUuid',
          'type': 'string',
          'size': 36,
          'required': true,
          'unique': true,
        },
        {
          'key': 'operationType',
          'type': 'string',
          'size': 30,
          'required': true,
        },
        {'key': 'entityType', 'type': 'string', 'size': 30, 'required': true},
        {'key': 'entityUuid', 'type': 'string', 'size': 36, 'required': true},
        {'key': 'entityId', 'type': 'integer'},
        {'key': 'previousState', 'type': 'string', 'size': 10000},
        {'key': 'newState', 'type': 'string', 'size': 10000},
        {'key': 'changedFields', 'type': 'string', 'size': 2000},
        {'key': 'performedBy', 'type': 'string', 'size': 100, 'required': true},
        {'key': 'deviceId', 'type': 'string', 'size': 100, 'required': true},
        {'key': 'ipAddress', 'type': 'string', 'size': 45},
        {'key': 'hotelDayKey', 'type': 'string', 'size': 10, 'required': true},
        {'key': 'timestamp', 'type': 'integer', 'required': true},
        {'key': 'timestampIso', 'type': 'string', 'size': 30, 'required': true},
        {'key': 'isFinancial', 'type': 'boolean', 'default': false},
        {'key': 'amountImpact', 'type': 'double'},
        {'key': 'createdAt', 'type': 'integer', 'required': true},
      ],
    },
    'payment_voids': {
      'name': 'Payment Voids',
      'includeSyncFields': true,
      'attributes': [
        {'key': 'localUuid', 'type': 'string', 'size': 100, 'required': true},
        {
          'key': 'originalPaymentUuid',
          'type': 'string',
          'size': 100,
          'required': true,
        },
        {'key': 'originalPaymentId', 'type': 'integer', 'required': true},
        {'key': 'bookingUuid', 'type': 'string', 'size': 100, 'required': true},
        // ⚠️ voidedAmount على Appwrite Cloud هو integer (وليس double)
        {'key': 'voidedAmount', 'type': 'integer', 'required': true},
        {'key': 'voidReason', 'type': 'string', 'size': 500, 'required': true},
        {'key': 'voidedBy', 'type': 'string', 'size': 100, 'required': true},
        {'key': 'voidedAt', 'type': 'integer', 'required': true},
        {'key': 'voidedAtIso', 'type': 'string', 'size': 50, 'required': true},
        {'key': 'hotelDayKey', 'type': 'string', 'size': 50, 'required': true},
        {'key': 'reversalPaymentUuid', 'type': 'string', 'size': 100},
        {'key': 'approvedBy', 'type': 'string', 'size': 100},
        // حقول إضافية على Cloud
        {'key': 'paymentUuid', 'type': 'string', 'size': 100},
        {'key': 'note', 'type': 'string', 'size': 500},
        {'key': 'originalAmount', 'type': 'integer'},
      ],
    },
    'booking_price_adjustments': {
      'name': 'Booking Price Adjustments',
      'includeSyncFields': true,
      'attributes': [
        {'key': 'localUuid', 'type': 'string', 'size': 100, 'required': true},
        {
          'key': 'bookingLocalUuid',
          'type': 'string',
          'size': 100,
          'required': true,
        },
        {'key': 'bookingLocalId', 'type': 'integer'},
        {
          'key': 'adjustmentType',
          'type': 'integer',
          'required': true,
        }, // 0=discount, 1=surcharge
        {
          'key': 'adjustmentMode',
          'type': 'string',
          'size': 20,
          'default': 'per_night',
        },
        // ✅ amount أُضيف إلى Appwrite Cloud (2026-05-15)
        // ⚠️ على Cloud هو integer (وليس double) — كود المزامنة يحول تلقائياً
        {'key': 'amount', 'type': 'integer', 'required': true},
        // ✅ roomNumber أُضيف إلى Appwrite Cloud (2026-05-15)
        {'key': 'roomNumber', 'type': 'string', 'size': 20},
        {
          'key': 'effectiveHotelDay',
          'type': 'string',
          'size': 50,
          'required': true,
        },
        {'key': 'endHotelDay', 'type': 'string', 'size': 50},
        {'key': 'adjustmentType', 'type': 'integer', 'required': true},
        {
          'key': 'adjustmentMode',
          'type': 'string',
          'size': 20,
          'default': 'per_night',
        },
        // ✅ amount: double (ليس integer)، optional، default 0
        {'key': 'amount', 'type': 'double', 'default': 0},
        {'key': 'roomNumber', 'type': 'string', 'size': 50},
        // ✅ effectiveHotelDay: size 255 (ليس 50)، optional (ليس required)
        {'key': 'effectiveHotelDay', 'type': 'string', 'size': 255},
        // ✅ hotelDayKey: size 50, REQUIRED (مطلوب على Appwrite)
        {'key': 'hotelDayKey', 'type': 'string', 'size': 50, 'required': true},
        // ✅ appliedDate: التاريخ الذي طُبِّق فيه التعديل (same as effectiveHotelDay)
        {'key': 'appliedDate', 'type': 'string', 'size': 50, 'required': true},
        {'key': 'endHotelDay', 'type': 'string', 'size': 10},
        {'key': 'isActive', 'type': 'boolean', 'default': true},
        {'key': 'reason', 'type': 'string', 'size': 500},
        {'key': 'appliedBy', 'type': 'string', 'size': 100},
        {'key': 'cancelledAt', 'type': 'string', 'size': 50},
        {'key': 'cancelledBy', 'type': 'string', 'size': 100},
      ],
    },
    'salary_withdrawals': {
      'name': 'Salary Withdrawals',
      'includeSyncFields': true,
      'attributes': [
        {'key': 'localUuid', 'type': 'string', 'size': 100, 'required': true},
        {'key': 'employeeId', 'type': 'integer', 'required': true},
        // ⚠️ amount على Appwrite Cloud هو double
        {'key': 'amount', 'type': 'double', 'required': true},
        // ✅ حقول المحلية المتوافقة مع Adapter (2026-05-17)
        {
          'key': 'withdrawDate',
          'type': 'string',
          'size': 255,
          'required': true,
        },
        {'key': 'reason', 'type': 'string', 'size': 500},
        {'key': 'hotelDayKey', 'type': 'string', 'size': 50},
        {
          'key': 'withdrawalType',
          'type': 'string',
          'size': 30,
          'default': 'withdrawal',
        },
        {'key': 'description', 'type': 'string', 'size': 500},
        // ✅ حقول employeeUuid لحل FK عبر الأجهزة
        {'key': 'employeeUuid', 'type': 'string', 'size': 36},
        // الحقول القديمة على Cloud (للتوافق العكسي) - nullable
        {'key': 'action', 'type': 'string', 'size': 50},
        {'key': 'date', 'type': 'string', 'size': 50},
        {'key': 'note', 'type': 'string', 'size': 500},
        {'key': 'expenseId', 'type': 'integer'},
        {'key': 'name', 'type': 'string', 'size': 100},
      ],
    },
    'guest_infos': {
      'name': 'Guest Infos',
      'includeSyncFields': true,
      'attributes': [
        {'key': 'localUuid', 'type': 'string', 'size': 100, 'required': true},
        {'key': 'roomNumber', 'type': 'string', 'required': true},
        {'key': 'guestName', 'type': 'string', 'required': true},
        {'key': 'nationality', 'type': 'string', 'required': true},
        {'key': 'idNumber', 'type': 'string', 'required': true},
        {'key': 'idType', 'type': 'string'},
        {'key': 'issueDate', 'type': 'string'},
        {'key': 'issuePlace', 'type': 'string'},
        {'key': 'governorate', 'type': 'string'},
        {'key': 'notes', 'type': 'string'},
      ],
    },
    'salary_carry_over_logs': {
      'name': 'Salary Carry Over Logs',
      'includeSyncFields': true,
      'attributes': [
        {'key': 'localUuid', 'type': 'string', 'size': 100, 'required': true},
        {'key': 'employeeId', 'type': 'integer', 'required': true},
        // ⚠️ amount على Appwrite Cloud هو integer (يُحوَّل تلقائياً عبر
        // AppwriteSyncUtils.convertAmountTypesForAppwrite)
        {'key': 'amount', 'type': 'integer', 'required': true},
        {'key': 'reason', 'type': 'string', 'size': 500},
      ],
    },
    'app_users': {
      'name': 'App Users',
      'includeSyncFields': true,
      'attributes': [
        {
          'key': 'localUuid',
          'type': 'string',
          'size': 36,
          'required': true,
          'unique': true,
        },
        {'key': 'userId', 'type': 'string', 'size': 100},
        {'key': 'username', 'type': 'string', 'size': 100, 'required': true},
        {'key': 'displayName', 'type': 'string', 'size': 100},
        {'key': 'email', 'type': 'string', 'size': 100},
        {'key': 'phone', 'type': 'string', 'size': 50},
        {'key': 'passwordHash', 'type': 'string', 'size': 256},
        {'key': 'role', 'type': 'string', 'size': 50, 'required': true},
        {'key': 'permissions', 'type': 'string', 'size': 2000},
        {'key': 'employeeUuid', 'type': 'string', 'size': 36},
        {'key': 'employeeId', 'type': 'integer'},
        {'key': 'isActive', 'type': 'boolean'},
        {'key': 'lastLoginAt', 'type': 'integer'},
        {'key': 'lastLoginIso', 'type': 'string', 'size': 50},
        {'key': 'lastLoginDeviceId', 'type': 'string', 'size': 100},
        {'key': 'failedLoginAttempts', 'type': 'integer'},
        {'key': 'isLocked', 'type': 'boolean'},
        {'key': 'lockedUntil', 'type': 'integer'},
        {'key': 'avatarUrl', 'type': 'string', 'size': 500},
        {'key': 'preferences', 'type': 'string', 'size': 2000},
        {'key': 'serverId', 'type': 'integer'},
        {'key': 'createdAt', 'type': 'integer', 'required': true},
        {'key': 'updatedAt', 'type': 'integer', 'required': true},
        {'key': 'deletedAt', 'type': 'integer'},
        {'key': 'lastModified', 'type': 'integer', 'required': true},
        {'key': 'createdAtIso', 'type': 'string', 'size': 50},
        {'key': 'updatedAtIso', 'type': 'string', 'size': 50},
        {'key': 'deletedAtIso', 'type': 'string', 'size': 50},
        {'key': 'createdAtEpoch', 'type': 'integer'},
        {'key': 'lastModifiedEpoch', 'type': 'integer', 'required': true},
        {'key': 'syncTimestamp', 'type': 'integer', 'required': true},
        {'key': 'deviceId', 'type': 'string', 'size': 100},
        {'key': 'version', 'type': 'integer', 'required': true},
        {'key': 'origin', 'type': 'string', 'size': 50},
        {'key': 'vectorClock', 'type': 'string', 'size': 1000},
        {'key': 'sync_origin', 'type': 'string', 'size': 50},
        {'key': 'idempotencyKey', 'type': 'string', 'size': 100},
        {'key': 'active', 'type': 'boolean'},
        {'key': 'credentials_version', 'type': 'integer'},
        {'key': 'fullName', 'type': 'string', 'size': 512},
        {'key': 'full_name', 'type': 'string', 'size': 512},
        {'key': 'lastLogin', 'type': 'integer'},
        {'key': 'last_login', 'type': 'integer'},
        {'key': 'password', 'type': 'string', 'size': 512},
        {'key': 'userType', 'type': 'string', 'size': 512, 'required': true},
        {'key': 'user_type', 'type': 'string', 'size': 512},
      ],
    },
  };

  static final _syncFields = [
    {
      'key': 'localUuid',
      'type': 'string',
      'size': 36,
      'required': true,
      'unique': true,
    },
    {'key': 'serverId', 'type': 'integer'},
    {'key': 'createdAt', 'type': 'integer', 'required': true},
    {'key': 'updatedAt', 'type': 'integer', 'required': true},
    {'key': 'deletedAt', 'type': 'integer'},
    {'key': 'lastModified', 'type': 'integer', 'required': true},
    {'key': 'createdAtIso', 'type': 'string', 'size': 50},
    {'key': 'updatedAtIso', 'type': 'string', 'size': 50},
    {'key': 'deletedAtIso', 'type': 'string', 'size': 50},
    {'key': 'createdAtEpoch', 'type': 'integer', 'default': 0},
    {'key': 'lastModifiedEpoch', 'type': 'integer', 'default': 0},
    {'key': 'syncTimestamp', 'type': 'integer', 'default': 0},
    {'key': 'deviceId', 'type': 'string', 'size': 100, 'default': ''},
    {'key': 'version', 'type': 'integer', 'default': 1},
    {'key': 'origin', 'type': 'string', 'size': 20, 'default': 'local'},
    {'key': 'vectorClock', 'type': 'string', 'size': 500, 'default': '{}'},
    {'key': 'idempotencyKey', 'type': 'string', 'size': 100},
  ];

  /// التحقق من جميع Collections والـ Attributes
  static Future<Map<String, dynamic>> verifySchema() async {
    dlog('🔍 بدء التحقق من مطابقة جداول Appwrite Cloud...\n');

    final endpoint = AppwriteConfigManager.endpoint;
    final projectId = AppwriteConfigManager.projectId;
    final apiKey = AppwriteConfigManager.apiKey;

    final client = Client().setEndpoint(endpoint).setProject(projectId);
    if (apiKey.isNotEmpty) {
      client.addHeader('X-Appwrite-Key', apiKey);
    }

    final databases = Databases(client);
    final results = <String, dynamic>{
      'collections': <String, dynamic>{},
      'missing': <Map<String, dynamic>>[],
      'errors': <String>[],
      'summary': <String, dynamic>{},
    };

    int totalCollections = 0;
    int foundCollections = 0;
    int missingCollections = 0;

    for (final entry in _requiredCollections.entries) {
      final collectionId = entry.key;
      final schema = entry.value;
      totalCollections++;

      dlog(() => '📋 التحقق من: $collectionId (${schema['name']})');

      try {
        // ignore: deprecated_member_use
        final response = await databases.listDocuments(
          databaseId: AppwriteConfigManager.databaseId,
          collectionId: collectionId,
          // التحقق يستهلك response.total فقط (عدد المطابقات على الخادم،
          // لا يتأثر بـ limit) — select($id)+limit(1) تقلّص الحمولة من
          // 25 صفاً كاملاً لكل كولكشن إلى صف واحد بمعرّفه فقط.
          queries: [
            Query.select([r'$id']),
            Query.limit(1),
          ],
        );

        foundCollections++;
        dlog(() => '   ✅ موجود: ${schema['name']}');

        results['collections'][collectionId] = {
          'found': true,
          'name': schema['name'],
          'total_documents': response.total,
        };

        dlog(() => '   📄 عدد المستندات: ${response.total}');
      } catch (e) {
        missingCollections++;
        dlog(() => '   ❌ غير موجود: $collectionId');
        results['missing'].add(collectionId);
        results['collections'][collectionId] = {
          'found': false,
          'error': e.toString(),
        };
      }

      dlog('');
    }

    results['summary'] = {
      'total': totalCollections,
      'found': foundCollections,
      'missing': missingCollections,
      'percentage': ((foundCollections / totalCollections) * 100)
          .toStringAsFixed(1),
    };

    dlog('═══════════════════════════════════════');
    dlog('📊 ملخص التحقق');
    dlog('═══════════════════════════════════════');
    dlog(() => 'إجمالي الجداول المطلوبة: $totalCollections');
    dlog(() => '✅ موجود: $foundCollections');
    dlog(() => '❌ ناقص: $missingCollections');
    dlog(() => '📈 نسبة الاكتمال: ${results['summary']['percentage']}%');
    dlog('═══════════════════════════════════════\n');

    if (missingCollections > 0) {
      dlog('⚠️  الجداول الناقصة:');
      for (final missing in (results['missing'] as List)) {
        dlog(() => '   - $missing');
      }
      dlog('\n💡 يرجى إنشاء الجداول الناقصة في Appwrite Console');
      dlog('   راجع: mobile/APPWRITE_SCHEMA_VERIFICATION.md\n');
    } else {
      dlog('🎉 جميع الجداول موجودة! التطابق كامل.\n');
    }

    return results;
  }

  /// طباعة سكريبت CLI لإنشاء Collection ناقص
  static void printCreateCollectionScript(String collectionId) {
    final schema = _requiredCollections[collectionId];
    if (schema == null) {
      return;
    }

    dlog(() => '# إنشاء Collection: $collectionId');
    debugPrint(r'appwrite databases createCollection \');
    debugPrint('  --databaseId ${AppwriteConfigManager.databaseId} \\');
    debugPrint('  --collectionId $collectionId \\');
    debugPrint('  --name "${schema['name']}"');
    debugPrint('');

    debugPrint('# إنشاء Attributes:');
    final includeSyncFields = schema['includeSyncFields'] != false;
    final allAttributes = [
      ...(schema['attributes']! as List),
      if (includeSyncFields) ..._syncFields,
    ];

    for (final attr in allAttributes) {
      final key = attr['key'];
      final type = attr['type'];
      final required = attr['required'] == true ? 'true' : 'false';

      if (type == 'string') {
        final size = attr['size'] ?? 255;
        debugPrint(r'appwrite databases createStringAttribute \');
        debugPrint('  --databaseId ${AppwriteConfigManager.databaseId} \\');
        debugPrint('  --collectionId $collectionId \\');
        debugPrint('  --key $key \\');
        debugPrint('  --size $size \\');
        debugPrint('  --required $required');
      } else if (type == 'integer') {
        debugPrint(r'appwrite databases createIntegerAttribute \');
        debugPrint('  --databaseId ${AppwriteConfigManager.databaseId} \\');
        debugPrint('  --collectionId $collectionId \\');
        debugPrint('  --key $key \\');
        debugPrint('  --required $required');
      } else if (type == 'double') {
        debugPrint(r'appwrite databases createFloatAttribute \');
        debugPrint('  --databaseId ${AppwriteConfigManager.databaseId} \\');
        debugPrint('  --collectionId $collectionId \\');
        debugPrint('  --key $key \\');
        debugPrint('  --required $required');
      } else if (type == 'boolean') {
        debugPrint(r'appwrite databases createBooleanAttribute \');
        debugPrint('  --databaseId ${AppwriteConfigManager.databaseId} \\');
        debugPrint('  --collectionId $collectionId \\');
        debugPrint('  --key $key \\');
        debugPrint('  --required $required');
      }
      debugPrint('');
    }
  }
}

/// مثال على الاستخدام:
///
/// ```dart
/// void main() async {
///   final results = await AppwriteSchemaVerifier.verifySchema();
///
///   // طباعة سكريبت لإنشاء collection ناقص
///   if (results['missing'].isNotEmpty) {
///     for (final collectionId in results['missing']) {
///       AppwriteSchemaVerifier.printCreateCollectionScript(collectionId);
///     }
///   }
/// }
/// ```
