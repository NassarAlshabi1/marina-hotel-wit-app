// lib/services/field_level_sync.dart
/// Field-Level Delta Sync System
/// نظام مزامنة تفاضلية على مستوى الحقل
///
/// الميزات:
/// - تتبع تغييرات كل حقل على حدة
/// - دمج ذكي للتعارضات
/// - Vector Clock لكل حقل
/// - حل التعارضات بناءً على النسخة والوقت
library;

import 'package:drift/drift.dart';
import 'local_db.dart';
import 'vector_clock.dart';
import '../utils/time.dart';

// ============================================================================
// Part 1: Data Models - نماذج البيانات
// ============================================================================

/// تغيير حقل واحد
class FieldChange {
  const FieldChange({
    required this.fieldName,
    required this.oldValue,
    required this.newValue,
    required this.version,
    required this.timestamp,
    required this.deviceId,
    required this.vectorClock,
    this.fieldType = FieldType.text,
  });

  factory FieldChange.fromJson(Map<String, dynamic> json) => FieldChange(
    fieldName: json['fieldName'] as String,
    oldValue: _deserializeValue(json['oldValue'], json['fieldType']),
    newValue: _deserializeValue(json['newValue'], json['fieldType']),
    version: json['version'] as int,
    timestamp: json['timestamp'] as int,
    deviceId: json['deviceId'] as String,
    vectorClock: json['vectorClock'] as String? ?? '{}',
    fieldType: FieldType.values.firstWhere(
      (e) => e.name == json['fieldType'],
      orElse: () => FieldType.text,
    ),
  );

  final String fieldName;
  final dynamic oldValue;
  final dynamic newValue;
  final int version;
  final int timestamp;
  final String deviceId;
  final String vectorClock;
  final FieldType fieldType;

  Map<String, dynamic> toJson() => {
    'fieldName': fieldName,
    'oldValue': _serializeValue(oldValue),
    'newValue': _serializeValue(newValue),
    'version': version,
    'timestamp': timestamp,
    'deviceId': deviceId,
    'vectorClock': vectorClock,
    'fieldType': fieldType.name,
  };

  static dynamic _serializeValue(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value.toIso8601String();
    if (value is double) return value; // Keep as double
    if (value is num) return value;
    return value.toString();
  }

  static dynamic _deserializeValue(dynamic value, String? fieldType) {
    if (value == null) return null;
    switch (fieldType) {
      case 'integer':
        return value is int ? value : int.tryParse(value.toString());
      case 'real':
        return value is double ? value : double.tryParse(value.toString());
      case 'boolean':
        if (value is bool) return value;
        return value.toString().toLowerCase() == 'true';
      default:
        return value;
    }
  }
}

/// أنواع الحقول
enum FieldType { text, integer, real, boolean, datetime, json }

/// نتيجة حساب الفروقات على مستوى الحقل
class FieldLevelDiff {
  const FieldLevelDiff({
    required this.changedFields,
    required this.fieldVersions,
    required this.fieldTimestamps,
    required this.fieldVectorClocks,
    required this.fieldDevices,
  });

  final Map<String, dynamic> changedFields;
  final Map<String, int> fieldVersions;
  final Map<String, int> fieldTimestamps;
  final Map<String, String> fieldVectorClocks;
  final Map<String, String> fieldDevices;

  bool get isEmpty => changedFields.isEmpty;
  bool get isNotEmpty => changedFields.isNotEmpty;

  List<FieldChange> toFieldChanges(String deviceId) {
    return changedFields.entries
        .map(
          (e) => FieldChange(
            fieldName: e.key,
            oldValue: null, // لا نحتاج القيمة القديمة للإرسال
            newValue: e.value,
            version: fieldVersions[e.key] ?? 1,
            timestamp: fieldTimestamps[e.key] ?? 0,
            deviceId: fieldDevices[e.key] ?? deviceId,
            vectorClock: fieldVectorClocks[e.key] ?? '{}',
          ),
        )
        .toList();
  }
}

/// نتيجة دمج السجلات
class FieldMergeResult {
  const FieldMergeResult({
    required this.data,
    required this.fieldVersions,
    required this.fieldTimestamps,
    required this.fieldDevices,
    required this.fieldVectorClocks,
    this.conflicts = const [],
  });

  final Map<String, dynamic> data;
  final Map<String, int> fieldVersions;
  final Map<String, int> fieldTimestamps;
  final Map<String, String> fieldDevices;
  final Map<String, String> fieldVectorClocks;
  final List<FieldConflict> conflicts;

  bool get hasConflicts => conflicts.isNotEmpty;
}

/// تعارض حقل
class FieldConflict {
  const FieldConflict({
    required this.fieldName,
    required this.localValue,
    required this.remoteValue,
    required this.winner,
    required this.resolutionStrategy,
  });

  final String fieldName;
  final dynamic localValue;
  final dynamic remoteValue;
  final dynamic winner;
  final String resolutionStrategy;
}

// ============================================================================
// Part 2: Field Configuration - إعدادات الحقول
// ============================================================================

/// إعدادات تتبع الحقول لكل جدول
class FieldSyncConfig {
  const FieldSyncConfig({
    required this.entityName,
    required this.trackableFields,
    required this.criticalFields,
    required this.ignoredFields,
    required this.fieldTypes,
    required this.mergeStrategies,
  });

  factory FieldSyncConfig.forEntity(String entityName) {
    switch (entityName) {
      case 'rooms':
        return const FieldSyncConfig(
          entityName: 'rooms',
          trackableFields: {
            'roomNumber',
            'type',
            'price',
            'status',
            'cleaningStatus',
            'lastCleanedHotelDay',
            'lastOccupiedHotelDay',
            'requiresMaintenance',
            'imageUrl',
            'floor',
          },
          criticalFields: {'status', 'price', 'roomNumber'},
          ignoredFields: systemFields,
          fieldTypes: {
            'price': FieldType.real,
            'requiresMaintenance': FieldType.boolean,
          },
          mergeStrategies: {
            'status': FieldMergeStrategy.lastWriteWins,
            'price': FieldMergeStrategy.lastWriteWins,
            'cleaningStatus': FieldMergeStrategy.lastWriteWins,
          },
        );

      case 'bookings':
        return const FieldSyncConfig(
          entityName: 'bookings',
          trackableFields: {
            'roomNumber',
            'guestName',
            'guestPhone',
            'guestNationality',
            'guestIdType',
            'guestIdNumber',
            'guestIdIssueDate',
            'guestIdIssuePlace',
            'checkinDate',
            'checkoutDate',
            'actualCheckout',
            'status',
            'notes',
            'discount',
            'discountType',
            'discountStartDate',
            'expectedNights',
            'calculatedNights',
            'totalNightsCached',
            'stayDurationIso',
            'totalDueCached',
            'totalPaidCached',
            'remainingBalanceCached',
            'isFullyPaid',
            'isOverdue',
            'hotelDayCheckin',
            'hotelDayCheckout',
          },
          criticalFields: {
            'status',
            'checkoutDate',
            'actualCheckout',
            'roomNumber',
            'totalDueCached',
            'totalPaidCached',
            'remainingBalanceCached',
            'isFullyPaid',
          },
          ignoredFields: systemFields,
          fieldTypes: {
            'discount': FieldType.real,
            'totalDueCached': FieldType.real,
            'totalPaidCached': FieldType.real,
            'remainingBalanceCached': FieldType.real,
            'expectedNights': FieldType.integer,
            'calculatedNights': FieldType.integer,
            'totalNightsCached': FieldType.integer,
            'isFullyPaid': FieldType.boolean,
            'isOverdue': FieldType.boolean,
          },
          mergeStrategies: {
            'status': FieldMergeStrategy.lastWriteWins,
            'checkoutDate': FieldMergeStrategy.lastWriteWins,
            'actualCheckout': FieldMergeStrategy.lastWriteWins,
            'guestName': FieldMergeStrategy.lastWriteWins,
            'totalDueCached': FieldMergeStrategy.lastWriteWins,
            'totalPaidCached': FieldMergeStrategy.lastWriteWins,
            'notes': FieldMergeStrategy.semanticMerge,
          },
        );

      case 'payments':
        return const FieldSyncConfig(
          entityName: 'payments',
          trackableFields: {
            'amount',
            'paymentDate',
            'notes',
            'paymentMethod',
            'revenueType',
            'roomNumber',
            'referenceNumber',
            'hotelDayKey',
            'isPendingBalance',
            'linkedDebtUuid',
          },
          criticalFields: {'amount', 'paymentDate', 'paymentMethod'},
          ignoredFields: systemFields,
          fieldTypes: {
            'amount': FieldType.real,
            'isPendingBalance': FieldType.boolean,
          },
          mergeStrategies: {
            'amount': FieldMergeStrategy.lastWriteWins,
            'paymentDate': FieldMergeStrategy.lastWriteWins,
          },
        );

      case 'employees':
        return const FieldSyncConfig(
          entityName: 'employees',
          trackableFields: {
            'name',
            'basicSalary',
            'position',
            'phone',
            'hireDate',
            'status',
          },
          criticalFields: {'basicSalary', 'status', 'name'},
          ignoredFields: systemFields,
          fieldTypes: {'basicSalary': FieldType.real},
          mergeStrategies: {
            'basicSalary': FieldMergeStrategy.lastWriteWins,
            'status': FieldMergeStrategy.lastWriteWins,
          },
        );

      case 'expenses':
        return const FieldSyncConfig(
          entityName: 'expenses',
          trackableFields: {
            'expenseType',
            'description',
            'amount',
            'date',
            'hotelDayKey',
            'categoryUuid',
            'isAutoGenerated',
          },
          criticalFields: {'amount', 'date', 'expenseType'},
          ignoredFields: systemFields,
          fieldTypes: {
            'amount': FieldType.real,
            'isAutoGenerated': FieldType.boolean,
          },
          mergeStrategies: {'amount': FieldMergeStrategy.lastWriteWins},
        );

      case 'debts':
        return const FieldSyncConfig(
          entityName: 'debts',
          trackableFields: {
            'guestName',
            'checkinDate',
            'checkoutDate',
            'dateRecorded',
            'debtReason',
            'totalAmount',
            'paidAmount',
            'remainingAmount',
            'paymentDate',
            'isSettled',
            'pledge',
            'pledgeType',
            'note',
          },
          criticalFields: {
            'totalAmount',
            'paidAmount',
            'remainingAmount',
            'isSettled',
          },
          ignoredFields: systemFields,
          fieldTypes: {
            'totalAmount': FieldType.real,
            'paidAmount': FieldType.real,
            'remainingAmount': FieldType.real,
            'isSettled': FieldType.integer,
          },
          mergeStrategies: {
            'totalAmount': FieldMergeStrategy.lastWriteWins,
            'paidAmount': FieldMergeStrategy.highestWins,
            'remainingAmount': FieldMergeStrategy.lastWriteWins,
          },
        );

      case 'shift_notes':
        return const FieldSyncConfig(
          entityName: 'shift_notes',
          trackableFields: {
            'title',
            'content',
            'priority',
            'shiftType',
            'isRead',
            'expiresAt',
            'createdBy',
            'shiftDate',
          },
          criticalFields: {'content', 'priority'},
          ignoredFields: systemFields,
          fieldTypes: {'isRead': FieldType.integer},
          mergeStrategies: {
            'content': FieldMergeStrategy.semanticMerge,
            'priority': FieldMergeStrategy.lastWriteWins,
          },
        );

      case 'booking_notes':
        return const FieldSyncConfig(
          entityName: 'booking_notes',
          trackableFields: {'noteText', 'alertType', 'alertUntil', 'isActive'},
          criticalFields: {'noteText', 'alertType'},
          ignoredFields: systemFields,
          fieldTypes: {'isActive': FieldType.integer},
          mergeStrategies: {'noteText': FieldMergeStrategy.semanticMerge},
        );

      case 'cash_transactions':
        return const FieldSyncConfig(
          entityName: 'cash_transactions',
          trackableFields: {
            'transactionType',
            'amount',
            'referenceType',
            'description',
            'transactionTime',
          },
          criticalFields: {'amount', 'transactionType'},
          ignoredFields: systemFields,
          fieldTypes: {'amount': FieldType.real},
          mergeStrategies: {'amount': FieldMergeStrategy.lastWriteWins},
        );

      case 'salary_cycles':
        return const FieldSyncConfig(
          entityName: 'salary_cycles',
          trackableFields: {
            'cycleKey', 'hotelDayStart', 'hotelDayEnd',
            // ❌ تم إزالة startDate و endDate - غير موجودة في Appwrite
            'expectedAmount',
            'actualPaid', 'remainingAmount', 'status',
          },
          criticalFields: {'expectedAmount', 'actualPaid', 'status'},
          ignoredFields: systemFields,
          fieldTypes: {
            'expectedAmount': FieldType.integer,
            'actualPaid': FieldType.integer,
            'remainingAmount': FieldType.integer,
          },
          mergeStrategies: {'actualPaid': FieldMergeStrategy.highestWins},
        );

      case 'salary_payments':
        return const FieldSyncConfig(
          entityName: 'salary_payments',
          trackableFields: {
            // ❌ تم إزالة amount - غير موجودة في Appwrite
            'paymentDateIso', 'method',
            'hotelDayKey', 'isAutoGenerated',
          },
          criticalFields: {'paymentDateIso'},
          ignoredFields: systemFields,
          fieldTypes: {'isAutoGenerated': FieldType.boolean},
          mergeStrategies: {'paymentDateIso': FieldMergeStrategy.lastWriteWins},
        );

      case 'salary_withdrawals':
        return const FieldSyncConfig(
          entityName: 'salary_withdrawals',
          trackableFields: {
            'action',
            'amount',
            'note',
            'date',
            'name',
            'employeeId',
          },
          criticalFields: {'amount', 'action', 'employeeId'},
          ignoredFields: systemFields,
          fieldTypes: {'amount': FieldType.real},
          mergeStrategies: {'amount': FieldMergeStrategy.lastWriteWins},
        );

      case 'booking_nights':
        return const FieldSyncConfig(
          entityName: 'booking_nights',
          trackableFields: {
            'hotelDayKey',
            'nightStart',
            'nightEnd',
            'nightlyRate',
            'sequence',
            'isProcessedByAutoFix',
            'baseRate',
            'adjustment',
            'finalRate',
          },
          criticalFields: {'nightlyRate', 'finalRate'},
          ignoredFields: systemFields,
          fieldTypes: {
            'nightlyRate': FieldType.real,
            'baseRate': FieldType.real,
            'adjustment': FieldType.real,
            'finalRate': FieldType.real,
            'sequence': FieldType.integer,
            'isProcessedByAutoFix': FieldType.boolean,
          },
          mergeStrategies: {
            'nightlyRate': FieldMergeStrategy.lastWriteWins,
            'finalRate': FieldMergeStrategy.lastWriteWins,
          },
        );

      case 'booking_price_adjustments':
        return const FieldSyncConfig(
          entityName: 'booking_price_adjustments',
          trackableFields: {
            'adjustmentType', 'adjustmentMode',
            // ❌ تم إزالة amount - غير موجودة في Appwrite
            'effectiveHotelDay', 'endHotelDay', 'isActive',
            'reason', 'appliedBy', 'cancelledAt', 'cancelledBy',
          },
          criticalFields: {'isActive'},
          ignoredFields: systemFields,
          fieldTypes: {
            'adjustmentType': FieldType.integer,
            'isActive': FieldType.boolean,
          },
          mergeStrategies: {'isActive': FieldMergeStrategy.lastWriteWins},
        );

      // ❌ hotel_day_ledger - محلي فقط، لا يتم مزامنته

      case 'price_adjustments':
        return const FieldSyncConfig(
          entityName: 'price_adjustments',
          trackableFields: {
            'targetType',
            'targetUuid',
            'adjustmentType',
            'previousValue',
            'newValue',
            'reason',
            'effectiveDate',
            'appliedBy',
            'hotelDayKey',
            'roomNumber',
            'isReversed',
            'reversedAt',
            'reversedBy',
          },
          criticalFields: {'previousValue', 'newValue', 'isReversed'},
          ignoredFields: systemFields,
          fieldTypes: {
            'previousValue': FieldType.integer,
            'newValue': FieldType.integer,
            'isReversed': FieldType.boolean,
          },
          mergeStrategies: {'isReversed': FieldMergeStrategy.lastWriteWins},
        );

      case 'payment_voids':
        return const FieldSyncConfig(
          entityName: 'payment_voids',
          trackableFields: {
            'originalPaymentUuid',
            'originalPaymentId',
            'bookingUuid',
            'voidedAmount',
            'voidReason',
            'voidedBy',
            'voidedAt',
            'voidedAtIso',
            'hotelDayKey',
            'reversalPaymentUuid',
            'approvedBy',
          },
          criticalFields: {'voidedAmount', 'voidReason', 'originalPaymentUuid'},
          ignoredFields: systemFields,
          fieldTypes: {
            'voidedAmount': FieldType.integer,
            'voidedAt': FieldType.integer,
            'originalPaymentId': FieldType.integer,
          },
          mergeStrategies: {'voidedAmount': FieldMergeStrategy.lastWriteWins},
        );

      case 'audit_logs':
        return const FieldSyncConfig(
          entityName: 'audit_logs',
          trackableFields: {
            'operationType',
            'entityType',
            'entityUuid',
            'entityId',
            'previousState',
            'newState',
            'changedFields',
            'performedBy',
            'deviceId',
            'ipAddress',
            'hotelDayKey',
            'timestamp',
            'timestampIso',
            'isFinancial',
            'amountImpact',
          },
          criticalFields: {'operationType', 'entityType', 'entityUuid'},
          ignoredFields: {'id', 'localUuid', 'createdAt'},
          fieldTypes: {
            'entityId': FieldType.integer,
            'timestamp': FieldType.integer,
            'isFinancial': FieldType.boolean,
            'amountImpact': FieldType.real,
          },
          mergeStrategies: {
            // Audit logs are append-only, no merging needed
          },
        );

      default:
        return FieldSyncConfig(
          entityName: entityName,
          trackableFields: {},
          criticalFields: {},
          ignoredFields: systemFields,
          fieldTypes: {},
          mergeStrategies: {},
        );
    }
  }

  final String entityName;
  final Set<String> trackableFields;
  final Set<String> criticalFields;
  final Set<String> ignoredFields;
  final Map<String, FieldType> fieldTypes;
  final Map<String, FieldMergeStrategy> mergeStrategies;

  /// حقول النظام التي لا يتم تتبعها
  static const systemFields = {
    'id',
    'local_id',
    'localUuid',
    'serverId',
    'createdAt',
    'updatedAt',
    'deletedAt',
    'createdAtIso',
    'updatedAtIso',
    'deletedAtIso',
    'createdAtEpoch',
    'lastModifiedEpoch',
    'version',
    'origin',
    'vectorClock',
    'lastModified',
  };
}

/// استراتيجية دمج الحقول
enum FieldMergeStrategy {
  lastWriteWins, // آخر كتابة تفوز
  highestWins, // القيمة الأعلى تفوز
  lowestWins, // القيمة الأقل تفوز
  semanticMerge, // دمج دلالي (للنصوص والقوائم)
  vectorClockWins, // Vector Clock يقرر
}

// ============================================================================
// Part 3: Field-Level Tracker - متتبع الحقول
// ============================================================================

/// متتبع تغييرات الحقول
class FieldLevelTracker {
  FieldLevelTracker({required this.deviceId, this.onFieldChange});

  final String deviceId;
  final void Function(String entity, String uuid, FieldChange change)?
  onFieldChange;

  /// تكوينات الحقول المخزنة مؤقتاً
  final Map<String, FieldSyncConfig> _configs = {};

  /// الحصول على تكوين الحقول لجدول معين
  FieldSyncConfig getConfig(String entityName) {
    return _configs.putIfAbsent(
      entityName,
      () => FieldSyncConfig.forEntity(entityName),
    );
  }

  /// حساب الفروقات على مستوى الحقل
  FieldLevelDiff computeDiff({
    required String entityName,
    required Map<String, dynamic> oldData,
    required Map<String, dynamic> newData,
    required Map<String, int> oldFieldVersions,
    required Map<String, int> oldFieldTimestamps,
    required Map<String, String> oldFieldVectorClocks,
    required Map<String, String> oldFieldDevices,
  }) {
    final config = getConfig(entityName);
    final changedFields = <String, dynamic>{};
    final fieldVersions = <String, int>{};
    final fieldTimestamps = <String, int>{};
    final fieldVectorClocks = <String, String>{};
    final fieldDevices = <String, String>{};
    final now = Time.nowEpoch();

    for (final key in newData.keys) {
      // تجاهل حقول النظام
      if (config.ignoredFields.contains(key)) continue;
      // تجاهل الحقول غير القابلة للتتبع
      if (config.trackableFields.isNotEmpty &&
          !config.trackableFields.contains(key)) {
        continue;
      }

      final oldValue = oldData[key];
      final newValue = newData[key];

      // إذا تغير الحقل
      if (!_valuesEqual(oldValue, newValue)) {
        changedFields[key] = newValue;

        final oldVersion = oldFieldVersions[key] ?? 0;
        fieldVersions[key] = oldVersion + 1;
        fieldTimestamps[key] = now;

        // تحديث Vector Clock
        final oldVc = VectorClock.fromJson(oldFieldVectorClocks[key] ?? '{}');
        final newVc = oldVc.increment(deviceId);
        fieldVectorClocks[key] = newVc.toJson();

        fieldDevices[key] = deviceId;
      }
    }

    return FieldLevelDiff(
      changedFields: changedFields,
      fieldVersions: fieldVersions,
      fieldTimestamps: fieldTimestamps,
      fieldVectorClocks: fieldVectorClocks,
      fieldDevices: fieldDevices,
    );
  }

  /// مقارنة قيمتين مع الأخذ بالاعتبار أنواع البيانات
  bool _valuesEqual(dynamic a, dynamic b) {
    if (a == b) return true;
    if (a == null || b == null) return false;

    // مقارنة الأرقام
    if (a is num && b is num) {
      return a.toDouble() == b.toDouble();
    }

    // مقارنة النصوص
    return a.toString() == b.toString();
  }

  /// دمج سجلين على مستوى الحقل
  FieldMergeResult mergeRecords({
    required String entityName,
    required Map<String, dynamic> localData,
    required Map<String, dynamic> remoteData,
    required Map<String, int> localFieldVersions,
    required Map<String, int> remoteFieldVersions,
    required Map<String, int> localFieldTimestamps,
    required Map<String, int> remoteFieldTimestamps,
    required Map<String, String> localFieldVectorClocks,
    required Map<String, String> remoteFieldVectorClocks,
    required Map<String, String> localFieldDevices,
    required Map<String, String> remoteFieldDevices,
  }) {
    final config = getConfig(entityName);
    final merged = <String, dynamic>{};
    final mergedVersions = <String, int>{};
    final mergedTimestamps = <String, int>{};
    final mergedDevices = <String, String>{};
    final mergedVectorClocks = <String, String>{};
    final conflicts = <FieldConflict>[];

    final allKeys = <String>{...localData.keys, ...remoteData.keys};

    for (final key in allKeys) {
      // تجاهل حقول النظام - نستخدم القيمة المحلية
      if (config.ignoredFields.contains(key)) {
        merged[key] = localData[key] ?? remoteData[key];
        continue;
      }

      // تجاهل الحقول غير القابلة للتتبع
      if (config.trackableFields.isNotEmpty &&
          !config.trackableFields.contains(key)) {
        merged[key] = localData[key] ?? remoteData[key];
        continue;
      }

      final localValue = localData[key];
      final remoteValue = remoteData[key];

      // نفس القيمة
      if (_valuesEqual(localValue, remoteValue)) {
        merged[key] = localValue;
        mergedVersions[key] = localFieldVersions[key] ?? 1;
        mergedTimestamps[key] = localFieldTimestamps[key] ?? 0;
        mergedDevices[key] = localFieldDevices[key] ?? deviceId;
        mergedVectorClocks[key] = localFieldVectorClocks[key] ?? '{}';
        continue;
      }

      // قيمة محلية فقط
      if (remoteValue == null) {
        merged[key] = localValue;
        mergedVersions[key] = localFieldVersions[key] ?? 1;
        mergedTimestamps[key] = localFieldTimestamps[key] ?? 0;
        mergedDevices[key] = localFieldDevices[key] ?? deviceId;
        mergedVectorClocks[key] = localFieldVectorClocks[key] ?? '{}';
        continue;
      }

      // قيمة بعيدة فقط
      if (localValue == null) {
        merged[key] = remoteValue;
        mergedVersions[key] = remoteFieldVersions[key] ?? 1;
        mergedTimestamps[key] = remoteFieldTimestamps[key] ?? 0;
        mergedDevices[key] = remoteFieldDevices[key] ?? deviceId;
        mergedVectorClocks[key] = remoteFieldVectorClocks[key] ?? '{}';
        continue;
      }

      // تعارض حقيقي - حل باستخدام الاستراتيجية
      final strategy =
          config.mergeStrategies[key] ?? FieldMergeStrategy.lastWriteWins;
      final resolution = _resolveFieldConflict(
        key: key,
        localValue: localValue,
        remoteValue: remoteValue,
        localVersion: localFieldVersions[key] ?? 0,
        remoteVersion: remoteFieldVersions[key] ?? 0,
        localTimestamp: localFieldTimestamps[key] ?? 0,
        remoteTimestamp: remoteFieldTimestamps[key] ?? 0,
        localVectorClock: localFieldVectorClocks[key] ?? '{}',
        remoteVectorClock: remoteFieldVectorClocks[key] ?? '{}',
        localDeviceId: localFieldDevices[key] ?? '',
        remoteDeviceId: remoteFieldDevices[key] ?? '',
        strategy: strategy,
        isCritical: config.criticalFields.contains(key),
      );

      merged[key] = resolution.winner;
      mergedVersions[key] = resolution.version;
      mergedTimestamps[key] = resolution.timestamp;
      mergedDevices[key] = resolution.deviceId;
      mergedVectorClocks[key] = resolution.vectorClock;

      if (resolution.hadConflict) {
        conflicts.add(
          FieldConflict(
            fieldName: key,
            localValue: localValue,
            remoteValue: remoteValue,
            winner: resolution.winner,
            resolutionStrategy: strategy.name,
          ),
        );
      }
    }

    return FieldMergeResult(
      data: merged,
      fieldVersions: mergedVersions,
      fieldTimestamps: mergedTimestamps,
      fieldDevices: mergedDevices,
      fieldVectorClocks: mergedVectorClocks,
      conflicts: conflicts,
    );
  }

  /// حل تعارض حقل واحد
  _FieldResolution _resolveFieldConflict({
    required String key,
    required dynamic localValue,
    required dynamic remoteValue,
    required int localVersion,
    required int remoteVersion,
    required int localTimestamp,
    required int remoteTimestamp,
    required String localVectorClock,
    required String remoteVectorClock,
    required String localDeviceId,
    required String remoteDeviceId,
    required FieldMergeStrategy strategy,
    required bool isCritical,
  }) {
    const bool hadConflict = true;

    // 1. محاولة Vector Clock أولاً
    final localVC = VectorClock.fromJson(localVectorClock);
    final remoteVC = VectorClock.fromJson(remoteVectorClock);
    final comparison = localVC.compare(remoteVC);

    if (comparison == 'after') {
      return _FieldResolution(
        winner: localValue,
        version: localVersion,
        timestamp: localTimestamp,
        deviceId: localDeviceId,
        vectorClock: localVectorClock,
        hadConflict: false,
      );
    }

    if (comparison == 'before') {
      return _FieldResolution(
        winner: remoteValue,
        version: remoteVersion,
        timestamp: remoteTimestamp,
        deviceId: remoteDeviceId,
        vectorClock: remoteVectorClock,
        hadConflict: false,
      );
    }

    // 2. تعارض متزامن - استخدام الاستراتيجية
    switch (strategy) {
      case FieldMergeStrategy.lastWriteWins:
        if (localTimestamp >= remoteTimestamp) {
          return _FieldResolution(
            winner: localValue,
            version: localVersion + 1,
            timestamp: localTimestamp,
            deviceId: localDeviceId,
            vectorClock: localVC.merge(remoteVC).increment(deviceId).toJson(),
            hadConflict: hadConflict,
          );
        } else {
          return _FieldResolution(
            winner: remoteValue,
            version: remoteVersion + 1,
            timestamp: remoteTimestamp,
            deviceId: remoteDeviceId,
            vectorClock: remoteVC.merge(localVC).increment(deviceId).toJson(),
            hadConflict: hadConflict,
          );
        }

      case FieldMergeStrategy.highestWins:
        final localNum = _toNumber(localValue);
        final remoteNum = _toNumber(remoteValue);
        if (localNum >= remoteNum) {
          return _FieldResolution(
            winner: localValue,
            version: localVersion + 1,
            timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            deviceId: deviceId,
            vectorClock: localVC.merge(remoteVC).increment(deviceId).toJson(),
            hadConflict: hadConflict,
          );
        } else {
          return _FieldResolution(
            winner: remoteValue,
            version: remoteVersion + 1,
            timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            deviceId: deviceId,
            vectorClock: remoteVC.merge(localVC).increment(deviceId).toJson(),
            hadConflict: hadConflict,
          );
        }

      case FieldMergeStrategy.lowestWins:
        final localNum = _toNumber(localValue);
        final remoteNum = _toNumber(remoteValue);
        if (localNum <= remoteNum) {
          return _FieldResolution(
            winner: localValue,
            version: localVersion + 1,
            timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            deviceId: deviceId,
            vectorClock: localVC.merge(remoteVC).increment(deviceId).toJson(),
            hadConflict: hadConflict,
          );
        } else {
          return _FieldResolution(
            winner: remoteValue,
            version: remoteVersion + 1,
            timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            deviceId: deviceId,
            vectorClock: remoteVC.merge(localVC).increment(deviceId).toJson(),
            hadConflict: hadConflict,
          );
        }

      case FieldMergeStrategy.semanticMerge:
        final merged = _trySemanticMerge(localValue, remoteValue);
        return _FieldResolution(
          winner: merged,
          version:
              (localVersion > remoteVersion ? localVersion : remoteVersion) + 1,
          timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          deviceId: deviceId,
          vectorClock: localVC.merge(remoteVC).increment(deviceId).toJson(),
          hadConflict: hadConflict,
        );

      case FieldMergeStrategy.vectorClockWins:
        // Vector Clock قرر بالفعل أعلاه، استخدام LWW كـ fallback
        return _resolveFieldConflict(
          key: key,
          localValue: localValue,
          remoteValue: remoteValue,
          localVersion: localVersion,
          remoteVersion: remoteVersion,
          localTimestamp: localTimestamp,
          remoteTimestamp: remoteTimestamp,
          localVectorClock: localVectorClock,
          remoteVectorClock: remoteVectorClock,
          localDeviceId: localDeviceId,
          remoteDeviceId: remoteDeviceId,
          strategy: FieldMergeStrategy.lastWriteWins,
          isCritical: isCritical,
        );
    }
  }

  double _toNumber(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  dynamic _trySemanticMerge(dynamic local, dynamic remote) {
    // دمج القوائم
    if (local is List && remote is List) {
      return [...local, ...remote.where((e) => !local.contains(e))];
    }

    // دمج الخرائط
    if (local is Map && remote is Map) {
      return {...remote, ...local}; // المحلي يفوز في التضارب
    }

    // دمج النصوص (للملاحظات)
    if (local is String && remote is String) {
      if (local.contains(remote)) return local;
      if (remote.contains(local)) return remote;
      // دمج مع فاصل
      return '$local\n---\n$remote';
    }

    // لا يمكن الدمج - نستخدم المحلي
    return local;
  }
}

class _FieldResolution {
  const _FieldResolution({
    required this.winner,
    required this.version,
    required this.timestamp,
    required this.deviceId,
    required this.vectorClock,
    required this.hadConflict,
  });

  final dynamic winner;
  final int version;
  final int timestamp;
  final String deviceId;
  final String vectorClock;
  final bool hadConflict;
}

// ============================================================================
// Part 4: Field Versions DAO - الوصول لبيانات نسخ الحقول
// ============================================================================

/// للوصول لبيانات نسخ الحقول (يُستخدم مع جدول FieldVersions)
class FieldVersionsDao {
  FieldVersionsDao(this.db);

  final AppDatabase db;

  /// الحصول على نسخ جميع حقول سجل معين
  Future<Map<String, int>> getFieldVersions(
    String entityName,
    String recordUuid,
  ) async {
    final query = db.customSelect(
      'SELECT field_name, version FROM field_versions WHERE entity_name = ? AND record_uuid = ?',
      variables: [
        Variable.withString(entityName),
        Variable.withString(recordUuid),
      ],
    );

    final rows = await query.get();
    return Map.fromEntries(
      rows.map(
        (row) =>
            MapEntry(row.read<String>('field_name'), row.read<int>('version')),
      ),
    );
  }

  /// الحصول على طوابع زمنية للحقول
  Future<Map<String, int>> getFieldTimestamps(
    String entityName,
    String recordUuid,
  ) async {
    final query = db.customSelect(
      'SELECT field_name, timestamp FROM field_versions WHERE entity_name = ? AND record_uuid = ?',
      variables: [
        Variable.withString(entityName),
        Variable.withString(recordUuid),
      ],
    );

    final rows = await query.get();
    return Map.fromEntries(
      rows.map(
        (row) => MapEntry(
          row.read<String>('field_name'),
          row.read<int>('timestamp'),
        ),
      ),
    );
  }

  /// الحصول على Vector Clocks للحقول
  Future<Map<String, String>> getFieldVectorClocks(
    String entityName,
    String recordUuid,
  ) async {
    final query = db.customSelect(
      'SELECT field_name, vector_clock FROM field_versions WHERE entity_name = ? AND record_uuid = ?',
      variables: [
        Variable.withString(entityName),
        Variable.withString(recordUuid),
      ],
    );

    final rows = await query.get();
    return Map.fromEntries(
      rows.map(
        (row) => MapEntry(
          row.read<String>('field_name'),
          row.read<String>('vector_clock'),
        ),
      ),
    );
  }

  /// الحصول على أجهزة الحقول
  Future<Map<String, String>> getFieldDevices(
    String entityName,
    String recordUuid,
  ) async {
    final query = db.customSelect(
      'SELECT field_name, device_id FROM field_versions WHERE entity_name = ? AND record_uuid = ?',
      variables: [
        Variable.withString(entityName),
        Variable.withString(recordUuid),
      ],
    );

    final rows = await query.get();
    return Map.fromEntries(
      rows.map(
        (row) => MapEntry(
          row.read<String>('field_name'),
          row.read<String>('device_id'),
        ),
      ),
    );
  }

  /// حفظ نسخ الحقول
  Future<void> saveFieldVersions({
    required String entityName,
    required String recordUuid,
    required Map<String, int> versions,
    required Map<String, int> timestamps,
    required Map<String, String> vectorClocks,
    required Map<String, String> devices,
  }) async {
    for (final entry in versions.entries) {
      final fieldName = entry.key;
      final version = entry.value;
      final timestamp = timestamps[fieldName] ?? 0;
      final vectorClock = vectorClocks[fieldName] ?? '{}';
      final deviceId = devices[fieldName] ?? '';

      await db.customStatement(
        '''
INSERT OR REPLACE INTO field_versions 
           (entity_name, record_uuid, field_name, version, timestamp, vector_clock, device_id)
           VALUES (?, ?, ?, ?, ?, ?, ?)''',
        [
          entityName,
          recordUuid,
          fieldName,
          version,
          timestamp,
          vectorClock,
          deviceId,
        ],
      );
    }
  }

  /// حذف نسخ حقول سجل معين
  Future<void> deleteFieldVersions(String entityName, String recordUuid) async {
    await db.customStatement(
      'DELETE FROM field_versions WHERE entity_name = ? AND record_uuid = ?',
      [entityName, recordUuid],
    );
  }

  /// الحصول على كل metadata لسجل
  Future<FieldMetadata> getFieldMetadata(
    String entityName,
    String recordUuid,
  ) async {
    final versions = await getFieldVersions(entityName, recordUuid);
    final timestamps = await getFieldTimestamps(entityName, recordUuid);
    final vectorClocks = await getFieldVectorClocks(entityName, recordUuid);
    final devices = await getFieldDevices(entityName, recordUuid);

    return FieldMetadata(
      versions: versions,
      timestamps: timestamps,
      vectorClocks: vectorClocks,
      devices: devices,
    );
  }
}

/// metadata للحقول
class FieldMetadata {
  const FieldMetadata({
    required this.versions,
    required this.timestamps,
    required this.vectorClocks,
    required this.devices,
  });

  /// إنشاء metadata فارغ
  factory FieldMetadata.empty() => const FieldMetadata(
    versions: {},
    timestamps: {},
    vectorClocks: {},
    devices: {},
  );

  /// إنشاء من JSON
  factory FieldMetadata.fromJson(Map<String, dynamic> json) => FieldMetadata(
    versions: Map<String, int>.from(json['versions'] ?? {}),
    timestamps: Map<String, int>.from(json['timestamps'] ?? {}),
    vectorClocks: Map<String, String>.from(json['vectorClocks'] ?? {}),
    devices: Map<String, String>.from(json['devices'] ?? {}),
  );

  final Map<String, int> versions;
  final Map<String, int> timestamps;
  final Map<String, String> vectorClocks;
  final Map<String, String> devices;

  /// تحويل إلى JSON للحفظ
  Map<String, dynamic> toJson() => {
    'versions': versions,
    'timestamps': timestamps,
    'vectorClocks': vectorClocks,
    'devices': devices,
  };
}
