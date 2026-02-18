import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'appwrite_config_manager.dart';

/// سكريبت للتحقق من مطابقة جداول Appwrite Cloud
///
/// الاستخدام:
/// ```dart
/// await verifyAppwriteSchema();
/// ```
class AppwriteSchemaVerifier {
  static final _requiredCollections = {
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
        {'key': 'type', 'type': 'string', 'size': 50, 'required': true},
        {'key': 'price', 'type': 'double', 'required': true},
        {'key': 'status', 'type': 'string', 'size': 20, 'required': true},
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
        {'key': 'roomNumber', 'type': 'string', 'size': 50, 'required': true},
        {'key': 'guestName', 'type': 'string', 'size': 100, 'required': true},
        {'key': 'guestPhone', 'type': 'string', 'size': 50, 'required': true},
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
          'size': 50,
          'required': true,
        },
        {'key': 'guestEmail', 'type': 'string', 'size': 100},
        {'key': 'guestAddress', 'type': 'string', 'size': 200},
        {'key': 'checkinDate', 'type': 'string', 'size': 50, 'required': true},
        {'key': 'checkoutDate', 'type': 'string', 'size': 50},
        {'key': 'actualCheckout', 'type': 'string', 'size': 50},
        {'key': 'status', 'type': 'string', 'size': 20, 'required': true},
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
        {'key': 'bookingLocalId', 'type': 'integer', 'required': true},
        {'key': 'hotelDayKey', 'type': 'string', 'size': 50, 'required': true},
        {'key': 'nightStart', 'type': 'string', 'size': 50, 'required': true},
        {'key': 'nightEnd', 'type': 'string', 'size': 50, 'required': true},
        {'key': 'nightlyRate', 'type': 'double', 'default': 0},
        {'key': 'sequence', 'type': 'integer', 'default': 0},
        {'key': 'isProcessedByAutoFix', 'type': 'boolean', 'default': false},
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
        {'key': 'name', 'type': 'string', 'size': 100, 'required': true},
        {'key': 'basicSalary', 'type': 'double', 'required': true},
        {'key': 'position', 'type': 'string', 'size': 50, 'default': 'موظف'},
        {'key': 'phone', 'type': 'string', 'size': 50, 'default': ''},
        {'key': 'hireDate', 'type': 'string', 'size': 50, 'default': ''},
        {'key': 'status', 'type': 'string', 'size': 20, 'required': true},
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
        {'key': 'expenseType', 'type': 'string', 'size': 50, 'required': true},
        {'key': 'relatedId', 'type': 'integer'},
        {'key': 'description', 'type': 'string', 'size': 500, 'required': true},
        {'key': 'amount', 'type': 'double', 'required': true},
        {'key': 'date', 'type': 'string', 'size': 50, 'required': true},
        {'key': 'cashTransactionId', 'type': 'integer'},
        {'key': 'hotelDayKey', 'type': 'string', 'size': 50},
        {'key': 'categoryUuid', 'type': 'string', 'size': 50},
        {'key': 'cashFlowUuid', 'type': 'string', 'size': 50},
        {'key': 'isAutoGenerated', 'type': 'boolean', 'default': false},
      ],
    },
    'cash_transactions': {
      'name': 'Cash Transactions',
      'includeSyncFields': true,
      'attributes': [
        {
          'key': 'localUuid',
          'type': 'string',
          'size': 36,
          'required': true,
          'unique': true,
        },
        {'key': 'registerId', 'type': 'integer'},
        {
          'key': 'transactionType',
          'type': 'string',
          'size': 20,
          'required': true,
        },
        {'key': 'amount', 'type': 'double', 'required': true},
        {'key': 'referenceType', 'type': 'string', 'size': 50},
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
        {
          'key': 'localUuid',
          'type': 'string',
          'size': 36,
          'required': true,
          'unique': true,
        },
        {'key': 'serverPaymentId', 'type': 'integer'},
        {'key': 'bookingLocalId', 'type': 'integer'},
        {'key': 'serverBookingId', 'type': 'integer'},
        {'key': 'roomNumber', 'type': 'string', 'size': 50},
        {'key': 'amount', 'type': 'double', 'required': true},
        {'key': 'paymentDate', 'type': 'string', 'size': 50, 'required': true},
        {'key': 'notes', 'type': 'string', 'size': 500},
        {
          'key': 'paymentMethod',
          'type': 'string',
          'size': 20,
          'required': true,
        },
        {'key': 'revenueType', 'type': 'string', 'size': 20, 'required': true},
        {'key': 'cashTransactionLocalId', 'type': 'integer'},
        {'key': 'cashTransactionServerId', 'type': 'integer'},
        {'key': 'referenceNumber', 'type': 'string', 'size': 100},
        {'key': 'hotelDayKey', 'type': 'string', 'size': 50},
        {'key': 'isPendingBalance', 'type': 'boolean', 'default': false},
        {'key': 'linkedDebtUuid', 'type': 'string', 'size': 50},
        {'key': 'bookingUuidCache', 'type': 'string', 'size': 50},
      ],
    },
    'debts': {
      'name': 'Debts',
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
        {'key': 'guestName', 'type': 'string', 'size': 100, 'required': true},
        {'key': 'checkinDate', 'type': 'string', 'size': 50, 'required': true},
        {'key': 'checkoutDate', 'type': 'string', 'size': 50, 'required': true},
        {'key': 'dateRecorded', 'type': 'string', 'size': 50, 'default': ''},
        {'key': 'debtReason', 'type': 'string', 'size': 200, 'default': ''},
        {'key': 'totalAmount', 'type': 'double', 'required': true},
        {'key': 'paidAmount', 'type': 'double', 'required': true},
        {'key': 'remainingAmount', 'type': 'double', 'required': true},
        {'key': 'paymentDate', 'type': 'string', 'size': 50, 'required': true},
        {'key': 'isSettled', 'type': 'integer', 'default': 0},
        {'key': 'pledge', 'type': 'string', 'size': 200},
        {'key': 'pledgeType', 'type': 'string', 'size': 50},
        {'key': 'note', 'type': 'string', 'size': 500},
        {'key': 'debtUuid', 'type': 'string', 'size': 50},
        {'key': 'hotelDayOpened', 'type': 'string', 'size': 50},
        {'key': 'hotelDayClosed', 'type': 'string', 'size': 50},
        {'key': 'isFromAutoFix', 'type': 'boolean', 'default': false},
        {'key': 'settlementConfirmed', 'type': 'boolean', 'default': false},
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
        {'key': 'amount', 'type': 'double', 'default': 0},
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
    'hotel_day_ledger': {
      'name': 'Hotel Day Ledger',
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
          'key': 'hotelDayKey',
          'type': 'string',
          'size': 50,
          'required': true,
          'unique': true,
        },
        {'key': 'totalIncome', 'type': 'double', 'default': 0},
        {'key': 'totalExpenses', 'type': 'double', 'default': 0},
        {'key': 'pendingBalances', 'type': 'double', 'default': 0},
        {'key': 'occupancyRate', 'type': 'double', 'default': 0},
        {'key': 'bookingsProcessed', 'type': 'integer', 'default': 0},
        {'key': 'paymentsProcessed', 'type': 'integer', 'default': 0},
        {'key': 'debtsProcessed', 'type': 'integer', 'default': 0},
        {'key': 'expensesProcessed', 'type': 'integer', 'default': 0},
        {'key': 'status', 'type': 'string', 'size': 20, 'default': 'draft'},
      ],
    },
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
    'price_adjustments': {
      'name': 'Price Adjustments',
      'includeSyncFields': true,
      'attributes': [
        {'key': 'localUuid', 'type': 'string', 'size': 36, 'required': true, 'unique': true},
        {'key': 'targetType', 'type': 'string', 'size': 20, 'required': true},
        {'key': 'targetUuid', 'type': 'string', 'size': 36, 'required': true},
        {'key': 'adjustmentType', 'type': 'string', 'size': 30, 'required': true},
        {'key': 'previousValue', 'type': 'double', 'required': true},
        {'key': 'newValue', 'type': 'double', 'required': true},
        {'key': 'reason', 'type': 'string', 'size': 500},
        {'key': 'effectiveDate', 'type': 'string', 'size': 30, 'required': true},
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
        {'key': 'localUuid', 'type': 'string', 'size': 36, 'required': true, 'unique': true},
        {'key': 'operationType', 'type': 'string', 'size': 30, 'required': true},
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
        {'key': 'localUuid', 'type': 'string', 'size': 36, 'required': true, 'unique': true},
        {'key': 'originalPaymentUuid', 'type': 'string', 'size': 36, 'required': true},
        {'key': 'originalPaymentId', 'type': 'integer', 'required': true},
        {'key': 'bookingUuid', 'type': 'string', 'size': 36, 'required': true},
        {'key': 'voidedAmount', 'type': 'double', 'required': true},
        {'key': 'voidReason', 'type': 'string', 'size': 500, 'required': true},
        {'key': 'voidedBy', 'type': 'string', 'size': 100, 'required': true},
        {'key': 'voidedAt', 'type': 'integer', 'required': true},
        {'key': 'voidedAtIso', 'type': 'string', 'size': 30, 'required': true},
        {'key': 'hotelDayKey', 'type': 'string', 'size': 10, 'required': true},
        {'key': 'reversalPaymentUuid', 'type': 'string', 'size': 36},
        {'key': 'approvedBy', 'type': 'string', 'size': 100},
      ],
    },
    'booking_price_adjustments': {
      'name': 'Booking Price Adjustments',
      'includeSyncFields': true,
      'attributes': [
        {'key': 'localUuid', 'type': 'string', 'size': 36, 'required': true, 'unique': true},
        {'key': 'bookingLocalUuid', 'type': 'string', 'size': 36, 'required': true},
        {'key': 'bookingLocalId', 'type': 'integer'},
        {'key': 'adjustmentType', 'type': 'integer', 'required': true}, // 0=discount, 1=surcharge
        {'key': 'adjustmentMode', 'type': 'string', 'size': 20, 'default': 'per_night'}, // per_night, total, percentage
        {'key': 'amount', 'type': 'double', 'required': true},
        {'key': 'effectiveHotelDay', 'type': 'string', 'size': 10, 'required': true},
        {'key': 'endHotelDay', 'type': 'string', 'size': 10},
        {'key': 'isActive', 'type': 'boolean', 'default': true},
        {'key': 'reason', 'type': 'string', 'size': 500},
        {'key': 'appliedBy', 'type': 'string', 'size': 100},
        {'key': 'cancelledAt', 'type': 'string', 'size': 30},
        {'key': 'cancelledBy', 'type': 'string', 'size': 100},
      ],
    },
  };

  static final _syncFields = [
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
  ];

  /// التحقق من جميع Collections والـ Attributes
  static Future<Map<String, dynamic>> verifySchema() async {
    debugPrint('🔍 بدء التحقق من مطابقة جداول Appwrite Cloud...\n');

    final endpoint = AppwriteConfigManager.endpoint;
    final projectId = AppwriteConfigManager.projectId;
    final apiKey = AppwriteConfigManager.apiKey;

    final client = Client().setEndpoint(endpoint).setProject(projectId);
    if (apiKey.isNotEmpty) {
      client.addHeader('X-Appwrite-Key', apiKey);
    }

    final databases = Databases(client);
    final results = <String, dynamic>{
      'collections': {},
      'missing': [],
      'errors': [],
      'summary': {},
    };

    int totalCollections = 0;
    int foundCollections = 0;
    int missingCollections = 0;

    for (final entry in _requiredCollections.entries) {
      final collectionId = entry.key;
      final schema = entry.value;
      totalCollections++;

      debugPrint('📋 التحقق من: $collectionId (${schema['name']})');

      try {
        final response = await databases.listDocuments(
          databaseId: AppwriteConfigManager.databaseId,
          collectionId: collectionId,
          queries: [],
        );

        foundCollections++;
        debugPrint('   ✅ موجود: ${schema['name']}');

        results['collections'][collectionId] = {
          'found': true,
          'name': schema['name'],
          'total_documents': response.total,
        };

        debugPrint('   📄 عدد المستندات: ${response.total}');
      } catch (e) {
        missingCollections++;
        debugPrint('   ❌ غير موجود: $collectionId');
        results['missing'].add(collectionId);
        results['collections'][collectionId] = {
          'found': false,
          'error': e.toString(),
        };
      }

      debugPrint('');
    }

    results['summary'] = {
      'total': totalCollections,
      'found': foundCollections,
      'missing': missingCollections,
      'percentage': ((foundCollections / totalCollections) * 100)
          .toStringAsFixed(1),
    };

    debugPrint('═══════════════════════════════════════');
    debugPrint('📊 ملخص التحقق');
    debugPrint('═══════════════════════════════════════');
    debugPrint('إجمالي الجداول المطلوبة: $totalCollections');
    debugPrint('✅ موجود: $foundCollections');
    debugPrint('❌ ناقص: $missingCollections');
    debugPrint('📈 نسبة الاكتمال: ${results['summary']['percentage']}%');
    debugPrint('═══════════════════════════════════════\n');

    if (missingCollections > 0) {
      debugPrint('⚠️  الجداول الناقصة:');
      for (final missing in results['missing']) {
        debugPrint('   - $missing');
      }
      debugPrint('\n💡 يرجى إنشاء الجداول الناقصة في Appwrite Console');
      debugPrint('   راجع: mobile/APPWRITE_SCHEMA_VERIFICATION.md\n');
    } else {
      debugPrint('🎉 جميع الجداول موجودة! التطابق كامل.\n');
    }

    return results;
  }

  /// طباعة سكريبت CLI لإنشاء Collection ناقص
  static void printCreateCollectionScript(String collectionId) {
    final schema = _requiredCollections[collectionId];
    if (schema == null) return;

    debugPrint('# إنشاء Collection: $collectionId');
    debugPrint('appwrite databases createCollection \\');
    debugPrint('  --databaseId ${AppwriteConfigManager.databaseId} \\');
    debugPrint('  --collectionId $collectionId \\');
    debugPrint('  --name "${schema['name']}"');
    debugPrint('');

    debugPrint('# إنشاء Attributes:');
    final includeSyncFields = schema['includeSyncFields'] != false;
    final allAttributes = [
      ...(schema['attributes'] as List),
      if (includeSyncFields) ..._syncFields,
    ];

    for (final attr in allAttributes) {
      final key = attr['key'];
      final type = attr['type'];
      final required = attr['required'] == true ? 'true' : 'false';

      if (type == 'string') {
        final size = attr['size'] ?? 255;
        debugPrint('appwrite databases createStringAttribute \\');
        debugPrint('  --databaseId ${AppwriteConfigManager.databaseId} \\');
        debugPrint('  --collectionId $collectionId \\');
        debugPrint('  --key $key \\');
        debugPrint('  --size $size \\');
        debugPrint('  --required $required');
      } else if (type == 'integer') {
        debugPrint('appwrite databases createIntegerAttribute \\');
        debugPrint('  --databaseId ${AppwriteConfigManager.databaseId} \\');
        debugPrint('  --collectionId $collectionId \\');
        debugPrint('  --key $key \\');
        debugPrint('  --required $required');
      } else if (type == 'double') {
        debugPrint('appwrite databases createFloatAttribute \\');
        debugPrint('  --databaseId ${AppwriteConfigManager.databaseId} \\');
        debugPrint('  --collectionId $collectionId \\');
        debugPrint('  --key $key \\');
        debugPrint('  --required $required');
      } else if (type == 'boolean') {
        debugPrint('appwrite databases createBooleanAttribute \\');
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
