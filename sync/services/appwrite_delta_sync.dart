// lib/services/appwrite_delta_sync.dart
//
// ╔═══════════════════════════════════════════════════════════════════════════╗
// ║       ⭐⭐⭐ نظام المزامنة التفاضلية على مستوى الحقول ⭐⭐⭐                    ║
// ║           Field-Level Delta Sync System - Professional Edition              ║
// ║                           [VERSION 2.0 - FIXED]                             ║
// ╚═══════════════════════════════════════════════════════════════════════════╝

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:appwrite/appwrite.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart' as d;
import 'package:uuid/uuid.dart';

import '../utils/time.dart';
import 'appwrite_logger.dart';
import 'appwrite_service.dart';
import 'daos/outbox_dao.dart';
import 'local_db.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// قسم 1: النماذج الأساسية (Core Models)
// ═══════════════════════════════════════════════════════════════════════════════

/// ⭐ أولوية المزامنة
enum SyncPriority {
  critical, // حجز، دفع - يجب مزامنته فوراً
  high, // ليالي الحجز، ملاحظات
  normal, // غرف، موظفين
  low, // سجلات التدقيق
}

/// ⭐ نوع العملية
enum OperationType {
  create,
  update,
  delete,
  noop;

  String get code => switch (this) {
        OperationType.create => 'C',
        OperationType.update => 'U',
        OperationType.delete => 'D',
        OperationType.noop => 'N',
      };

  static OperationType fromCode(String code) => switch (code) {
        'C' => OperationType.create,
        'U' => OperationType.update,
        'D' => OperationType.delete,
        _ => OperationType.noop,
      };
}

/// ⭐ حالة المزامنة
enum SyncStatus {
  pending,
  inProgress,
  completed,
  failed,
  conflicted,
  skipped,
}

/// ⭐ استراتيجية حل التعارضات
enum ConflictStrategy {
  lastWriteWins, // الأحدث يفوز
  localWins, // المحلي يفوز
  remoteWins, // البعيد يفوز
  fieldLevelMerge, // دمج على مستوى الحقول
  manual, // يدوي
}

// ═══════════════════════════════════════════════════════════════════════════════
// VectorClock – ساعة متجهة لحل التعارضات
// ═══════════════════════════════════════════════════════════════════════════════

/// ⭐ ساعة متجهة لحل التعارضات في الأنظمة الموزعة
class VectorClock {
  final Map<String, int> _counters;

  VectorClock([Map<String, int>? counters]) : _counters = Map.from(counters ?? {});

  factory VectorClock.fromJson(String? json) {
    if (json == null || json.isEmpty) return VectorClock();
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      return VectorClock(map.map((k, v) => MapEntry(k, v as int)));
    } catch (_) {
      return VectorClock();
    }
  }

  String toJson() => jsonEncode(_counters);

  /// زيادة العداد لجهاز معين
  VectorClock increment(String deviceId) {
    final newCounters = Map<String, int>.from(_counters);
    newCounters[deviceId] = (newCounters[deviceId] ?? 0) + 1;
    return VectorClock(newCounters);
  }

  /// هل هذه الساعة أحدث من الأخرى؟ (نظرية سببية)
  bool isAfter(VectorClock other) {
    // هذه الساعة أحدث إذا كان لكل جهاز عداد >= الآخر، وواحد على الأقل >.
    bool hasAnyGreater = false;
    for (final entry in _counters.entries) {
      final otherCount = other._counters[entry.key] ?? 0;
      if (entry.value < otherCount) return false;
      if (entry.value > otherCount) hasAnyGreater = true;
    }
    // التحقق من أن الأجهزة الموجودة في الأخرى فقط لا تحتوي على قيم أكبر
    for (final entry in other._counters.entries) {
      final thisCount = _counters[entry.key] ?? 0;
      if (thisCount < entry.value) return false;
      if (thisCount > entry.value) hasAnyGreater = true;
    }
    return hasAnyGreater;
  }

  /// دمج ساعتين (اتحاد)
  VectorClock merge(VectorClock other) {
    final newCounters = Map<String, int>.from(_counters);
    for (final entry in other._counters.entries) {
      final existing = newCounters[entry.key] ?? 0;
      newCounters[entry.key] = max(existing, entry.value);
    }
    return VectorClock(newCounters);
  }

  @override
  String toString() => toJson();
}

// ═══════════════════════════════════════════════════════════════════════════════
// FieldDelta - تغيير حقل واحد
// ═══════════════════════════════════════════════════════════════════════════════

/// ⭐ يمثل تغييراً في حقل واحد فقط
class FieldDelta {
  const FieldDelta({
    required this.fieldName,
    required this.newValue,
    required this.changedAt,
    this.oldValue,
    this.changedBy,
  });

  factory FieldDelta.fromJson(Map<String, dynamic> json) => FieldDelta(
        fieldName: json['f'] as String? ?? json['fieldName'] as String? ?? '',
        oldValue: json['o'] ?? json['oldValue'],
        newValue: json['n'] ?? json['newValue'],
        changedAt: json['t'] as int? ?? json['changedAt'] as int? ?? 0,
        changedBy: json['b'] as String? ?? json['changedBy'] as String?,
      );

  final String fieldName;
  final dynamic oldValue;
  final dynamic newValue;
  final int changedAt;
  final String? changedBy;

  Map<String, dynamic> toJson() => {
        'f': fieldName,
        'o': oldValue,
        'n': newValue,
        't': changedAt,
        if (changedBy != null) 'b': changedBy,
      };

  bool get isSignificant {
    if (newValue == null && oldValue == null) return false;
    if (newValue == null || oldValue == null) return true;
    if (newValue is num && oldValue is num) {
      return (newValue - oldValue).abs() > 0.001;
    }
    return newValue.toString() != oldValue.toString();
  }

  @override
  String toString() => 'FieldDelta($fieldName: $oldValue → $newValue)';
}

// ═══════════════════════════════════════════════════════════════════════════════
// EntityDelta - دلتا كاملة لسجل
// ═══════════════════════════════════════════════════════════════════════════════

/// ⭐ يمثل دلتا كاملة لسجل واحد
class EntityDelta {
  const EntityDelta({
    required this.entity,
    required this.uuid,
    required this.operation,
    required this.fieldDeltas,
    required this.version,
    required this.timestamp,
    required this.deviceId,
    required this.vectorClock,
    this.parentUuid,
    this.priority = SyncPriority.normal,
  });

  /// ⭐ إنشاء دلتا من مقارنة قديم وجديد
  factory EntityDelta.fromComparison({
    required String entity,
    required String uuid,
    required Map<String, dynamic> oldData,
    required Map<String, dynamic> newData,
    required String deviceId,
    required VectorClock vectorClock,
    String? parentUuid,
    SyncPriority priority = SyncPriority.normal,
    Set<String>? ignoreFields,
  }) {
    final fieldDeltas = <FieldDelta>[];
    final now = Time.nowEpoch();

    final ignored = ignoreFields ?? {
      'localUuid',
      'version',
      'lastModified',
      'createdAt',
      'updatedAt',
      'origin',
      'syncTimestamp',
      'deviceId',
      'id',
      'vectorClock',
    };

    for (final key in newData.keys) {
      if (ignored.contains(key)) continue;

      final oldVal = oldData[key];
      final newVal = newData[key];

      if (!_valuesEqual(oldVal, newVal)) {
        fieldDeltas.add(FieldDelta(
          fieldName: key,
          oldValue: oldVal,
          newValue: newVal,
          changedAt: now,
          changedBy: deviceId,
        ));
      }
    }

    final operation = fieldDeltas.isEmpty
        ? OperationType.noop
        : (oldData.isEmpty ? OperationType.create : OperationType.update);

    final oldVersion = oldData['version'] as int? ?? 0;

    // زيادة ساعة المتجه للجهاز الحالي
    final newVectorClock = vectorClock.increment(deviceId);

    return EntityDelta(
      entity: entity,
      uuid: uuid,
      operation: operation,
      fieldDeltas: fieldDeltas,
      version: oldVersion + 1,
      timestamp: now,
      parentUuid: parentUuid,
      deviceId: deviceId,
      priority: priority,
      vectorClock: newVectorClock,
    );
  }

  /// ⭐ إنشاء دلتا حذف
  factory EntityDelta.forDelete({
    required String entity,
    required String uuid,
    required int lastVersion,
    required String deviceId,
    required VectorClock vectorClock,
    String? parentUuid,
  }) {
    final newVectorClock = vectorClock.increment(deviceId);
    return EntityDelta(
      entity: entity,
      uuid: uuid,
      operation: OperationType.delete,
      fieldDeltas: [],
      version: lastVersion + 1,
      timestamp: Time.nowEpoch(),
      parentUuid: parentUuid,
      deviceId: deviceId,
      priority: SyncPriority.high,
      vectorClock: newVectorClock,
    );
  }

  factory EntityDelta.fromJson(Map<String, dynamic> json) {
    final deltaList = json['d'] as List<dynamic>? ?? json['fieldDeltas'] as List<dynamic>?;
    final deltas = deltaList?.map((d) => FieldDelta.fromJson(d as Map<String, dynamic>)).toList() ?? <FieldDelta>[];
    final vectorClock = VectorClock.fromJson(json['vc'] as String? ?? json['vectorClock'] as String?);

    return EntityDelta(
      entity: json['e'] as String? ?? json['entity'] as String? ?? '',
      uuid: json['u'] as String? ?? json['uuid'] as String? ?? '',
      operation: OperationType.fromCode(json['o'] as String? ?? json['operation'] as String? ?? 'U'),
      fieldDeltas: deltas,
      version: json['v'] as int? ?? json['version'] as int? ?? 1,
      timestamp: json['t'] as int? ?? json['timestamp'] as int? ?? 0,
      parentUuid: json['p'] as String? ?? json['parentUuid'] as String?,
      deviceId: json['b'] as String? ?? json['deviceId'] as String? ?? '',
      priority: SyncPriority.values.firstWhere(
        (p) => p.name == (json['pr'] as String? ?? json['priority'] as String?),
        orElse: () => SyncPriority.normal,
      ),
      vectorClock: vectorClock,
    );
  }

  final String entity;
  final String uuid;
  final OperationType operation;
  final List<FieldDelta> fieldDeltas;
  final int version;
  final int timestamp;
  final String? parentUuid;
  final String deviceId;
  final SyncPriority priority;
  final VectorClock vectorClock;

  Map<String, dynamic> toPayload() => {
        'e': entity,
        'u': uuid,
        'o': operation.code,
        'd': fieldDeltas.map((f) => f.toJson()).toList(),
        'v': version,
        't': timestamp,
        if (parentUuid != null) 'p': parentUuid,
        'b': deviceId,
        'pr': priority.name,
        'vc': vectorClock.toJson(),
      };

  Map<String, dynamic> toJson() => {
        'entity': entity,
        'uuid': uuid,
        'operation': operation.code,
        'fieldDeltas': fieldDeltas.map((f) => f.toJson()).toList(),
        'version': version,
        'timestamp': timestamp,
        'parentUuid': parentUuid,
        'deviceId': deviceId,
        'priority': priority.name,
        'vectorClock': vectorClock.toJson(),
      };

  /// ⭐ تطبيق الدلتا على بيانات موجودة
  Map<String, dynamic> applyTo(Map<String, dynamic> existing) {
    if (operation == OperationType.delete) {
      return {'_deleted': true, 'deletedAt': timestamp};
    }

    final result = Map<String, dynamic>.from(existing);
    for (final delta in fieldDeltas) {
      result[delta.fieldName] = delta.newValue;
    }
    result['version'] = version;
    result['lastModified'] = timestamp;
    result['vectorClock'] = vectorClock.toJson();
    return result;
  }

  int get changedFieldsCount => fieldDeltas.length;
  bool get isEmpty => operation == OperationType.noop || fieldDeltas.isEmpty;
  bool get isDelete => operation == OperationType.delete;
  bool get isCreate => operation == OperationType.create;
  List<String> get changedFieldNames => fieldDeltas.map((d) => d.fieldName).toList();

  static bool _valuesEqual(dynamic a, dynamic b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a is num && b is num) return (a - b).abs() < 0.001;
    return a.toString() == b.toString();
  }

  @override
  String toString() =>
      'EntityDelta($entity/$uuid, ${operation.name}, ${fieldDeltas.length} fields, v$version)';
}

// ═══════════════════════════════════════════════════════════════════════════════
// ConflictInfo - معلومات التعارض
// ═══════════════════════════════════════════════════════════════════════════════

/// ⭐ معلومات التعارض
class ConflictInfo {
  const ConflictInfo({
    required this.entity,
    required this.uuid,
    required this.fieldName,
    required this.localTimestamp,
    required this.remoteTimestamp,
    required this.localDeviceId,
    required this.remoteDeviceId,
    this.localValue,
    this.remoteValue,
  });

  final String entity;
  final String uuid;
  final String fieldName;
  final dynamic localValue;
  final dynamic remoteValue;
  final int localTimestamp;
  final int remoteTimestamp;
  final String localDeviceId;
  final String remoteDeviceId;

  bool get remoteIsNewer => remoteTimestamp > localTimestamp;
  bool get localIsNewer => localTimestamp > remoteTimestamp;

  @override
  String toString() =>
      'ConflictInfo($entity/$uuid.$fieldName: local=$localValue vs remote=$remoteValue)';
}

// ═══════════════════════════════════════════════════════════════════════════════
// SyncResult - نتيجة المزامنة
// ═══════════════════════════════════════════════════════════════════════════════

/// ⭐ نتيجة عملية المزامنة
class SyncResult {
  const SyncResult({
    required this.success,
    required this.message,
    this.pushedCount = 0,
    this.pulledCount = 0,
    this.fieldsCount = 0,
    this.conflictCount = 0,
    this.skippedCount = 0,
    this.errors = const [],
    this.conflicts = const [],
    this.timestamp,
    this.duration,
  });

  factory SyncResult.error(String message, {List<String>? errors}) => SyncResult(
        success: false,
        message: message,
        errors: errors ?? [message],
      );

  final bool success;
  final String message;
  final int pushedCount;
  final int pulledCount;
  final int fieldsCount;
  final int conflictCount;
  final int skippedCount;
  final List<String> errors;
  final List<ConflictInfo> conflicts;
  final DateTime? timestamp;
  final Duration? duration;

  static const SyncResult empty =
      SyncResult(success: true, message: 'لا توجد تغييرات للمزامنة');

  bool get hasErrors => errors.isNotEmpty || !success;
  bool get hasConflicts => conflicts.isNotEmpty;

  /// ⭐ هل يوجد فشل (اسم بديل)
  bool get hasFailures => hasErrors;

  /// ⭐ عدد الفشل (اسم بديل)
  int get failedCount => errors.length;

  /// ⭐ عدد السجلات المدفوعة (اسم بديل)
  int get recordsPushed => pushedCount;

  /// ⭐ عدد السجلات المسحوبة (اسم بديل)
  int get recordsPulled => pulledCount;

  @override
  String toString() =>
      'SyncResult(success: $success, pushed: $pushedCount, pulled: $pulledCount, fields: $fieldsCount)';
}

// ═══════════════════════════════════════════════════════════════════════════════
// SyncError - خطأ المزامنة
// ═══════════════════════════════════════════════════════════════════════════════

/// ⭐ خطأ المزامنة
class SyncError {
  const SyncError({
    required this.message,
    required this.timestamp,
    this.entity,
    this.uuid,
  });

  final String? entity;
  final String? uuid;
  final String message;
  final DateTime timestamp;
}

/// ⭐ سجل خطأ المزامنة (للعرض في الواجهة)
class SyncErrorRecord {
  const SyncErrorRecord({
    required this.entity,
    required this.localUuid,
    required this.operation,
    required this.errorMessage,
    required this.createdAt,
    this.retryCount = 0,
    this.lastAttemptAt,
  });

  factory SyncErrorRecord.fromJson(Map<String, dynamic> json) {
    return SyncErrorRecord(
      entity: json['entity'] as String? ?? '',
      localUuid: json['localUuid'] as String? ?? '',
      operation: json['operation'] as String? ?? '',
      errorMessage: json['errorMessage'] as String? ?? '',
      retryCount: json['retryCount'] as int? ?? 0,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      lastAttemptAt: json['lastAttemptAt'] != null
          ? DateTime.parse(json['lastAttemptAt'] as String)
          : null,
    );
  }

  final String entity;
  final String localUuid;
  final String operation;
  final String errorMessage;
  final int retryCount;
  final DateTime createdAt;
  final DateTime? lastAttemptAt;

  /// ⭐ أسماء بديلة للتوافق مع الواجهة
  DateTime get timestamp => createdAt;
  DateTime? get lastRetryAt => lastAttemptAt;

  Map<String, dynamic> toJson() => {
        'entity': entity,
        'localUuid': localUuid,
        'operation': operation,
        'errorMessage': errorMessage,
        'retryCount': retryCount,
        'createdAt': createdAt.toIso8601String(),
        if (lastAttemptAt != null) 'lastAttemptAt': lastAttemptAt!.toIso8601String(),
      };
}

// ═══════════════════════════════════════════════════════════════════════════════
// SyncProgress - تقدم المزامنة
// ═══════════════════════════════════════════════════════════════════════════════

/// ⭐ تقدم المزامنة
class SyncProgress {
  const SyncProgress({
    required this.phase,
    required this.message,
    this.current,
    this.total,
    this.currentEntity,
  });

  final String phase;
  final String message;
  final int? current;
  final int? total;
  final String? currentEntity;

  double? get progress => total != null && total! > 0 ? (current ?? 0) / total! : null;
}

// ═══════════════════════════════════════════════════════════════════════════════
// StateCache - ذاكرة الحالة
// ═══════════════════════════════════════════════════════════════════════════════

/// ⭐ إدخال في ذاكرة الحالة
class StateCacheEntry {
  const StateCacheEntry({
    required this.entity,
    required this.uuid,
    required this.data,
    required this.version,
    required this.timestamp,
    required this.vectorClock,
  });

  final String entity;
  final String uuid;
  final Map<String, dynamic> data;
  final int version;
  final int timestamp;
  final VectorClock vectorClock;
}

// ═══════════════════════════════════════════════════════════════════════════════
// قسم 2: سجل الكيانات (Entity Registry)
// ═══════════════════════════════════════════════════════════════════════════════

/// ⭐ إعدادات مزامنة الكيان
class SyncEntityConfig {
  const SyncEntityConfig({
    required this.entityName,
    required this.collectionId,
    this.defaultPriority = SyncPriority.normal,
    this.requiredFields = const [],
    this.ignoreFields = const [],
    this.parentEntity,
    this.parentForeignKey,
  });

  final String entityName;
  final String collectionId;
  final SyncPriority defaultPriority;
  final List<String> requiredFields;
  final List<String> ignoreFields;
  final String? parentEntity;
  final String? parentForeignKey;

  bool get hasParent => parentEntity != null;
}

/// ⭐ سجل جميع الكيانات المدعومة
class SyncEntityRegistry {
  /// ═══════════════════════════════════════════════════════════════════════════
  /// جداول غير قابلة للمزامنة (محلية فقط)
  /// ═══════════════════════════════════════════════════════════════════════════
  static const nonSyncableTables = [
    'hotel_day_ledger',
    'auto_fix_runs',
    'integrity_violations',
    'app_sessions',
    'outbox',
    'sync_state',
    'restore_fix_log',
    'sync_queue',
    'sync_log',
    'sync_conflicts',
    'guest_info',
  ];

  static bool isSyncable(String tableName) => !nonSyncableTables.contains(tableName);

  static const Map<String, SyncEntityConfig> _configs = {
    // ─────────── كيانات الغرف ───────────
    'rooms': SyncEntityConfig(
      entityName: 'rooms',
      collectionId: 'rooms',
      requiredFields: ['roomNumber', 'type', 'price'],
    ),

    // ─────────── كيانات الحجوزات ───────────
    'bookings': SyncEntityConfig(
      entityName: 'bookings',
      collectionId: 'bookings',
      defaultPriority: SyncPriority.critical,
      requiredFields: ['roomNumber', 'guestName', 'checkinDate', 'status'],
    ),

    'booking_nights': SyncEntityConfig(
      entityName: 'booking_nights',
      collectionId: 'booking_nights',
      defaultPriority: SyncPriority.high,
      requiredFields: ['bookingLocalId', 'hotelDayKey', 'nightlyRate'],
      parentEntity: 'bookings',
      parentForeignKey: 'bookingLocalId',
    ),

    'booking_notes': SyncEntityConfig(
      entityName: 'booking_notes',
      collectionId: 'booking_notes',
      defaultPriority: SyncPriority.high,
      requiredFields: ['bookingId', 'noteText'],
      parentEntity: 'bookings',
      parentForeignKey: 'bookingId',
    ),

    'booking_price_adjustments': SyncEntityConfig(
      entityName: 'booking_price_adjustments',
      collectionId: 'booking_price_adjustments',
      defaultPriority: SyncPriority.high,
      requiredFields: ['bookingLocalUuid', 'adjustmentType', 'amount'],
      parentEntity: 'bookings',
      parentForeignKey: 'bookingLocalUuid',
    ),

    // ─────────── كيانات المدفوعات ───────────
    'payments': SyncEntityConfig(
      entityName: 'payments',
      collectionId: 'payments',
      defaultPriority: SyncPriority.critical,
      requiredFields: ['amount', 'paymentDate', 'paymentMethod'],
      parentEntity: 'bookings',
      parentForeignKey: 'bookingLocalId',
    ),

    'payment_voids': SyncEntityConfig(
      entityName: 'payment_voids',
      collectionId: 'payment_voids',
      defaultPriority: SyncPriority.high,
      requiredFields: ['originalPaymentUuid', 'voidedAmount', 'voidReason'],
      parentEntity: 'payments',
      parentForeignKey: 'originalPaymentUuid',
    ),

    // ─────────── كيانات المصروفات والديون ───────────
    'expenses': SyncEntityConfig(
      entityName: 'expenses',
      collectionId: 'expenses',
      requiredFields: ['expenseType', 'amount', 'date'],
    ),

    'debts': SyncEntityConfig(
      entityName: 'debts',
      collectionId: 'debts',
      defaultPriority: SyncPriority.high,
      requiredFields: ['guestName', 'totalAmount', 'checkinDate'],
    ),

    // ─────────── كيانات الموظفين والرواتب ───────────
    'employees': SyncEntityConfig(
      entityName: 'employees',
      collectionId: 'employees',
      requiredFields: ['name', 'basicSalary', 'position'],
    ),

    'salary_cycles': SyncEntityConfig(
      entityName: 'salary_cycles',
      collectionId: 'salary_cycles',
      requiredFields: ['employeeId', 'cycleKey', 'expectedAmount'],
      parentEntity: 'employees',
      parentForeignKey: 'employeeId',
    ),

    'salary_payments': SyncEntityConfig(
      entityName: 'salary_payments',
      collectionId: 'salary_payments',
      requiredFields: ['cycleId', 'amount', 'paymentDateIso'],
      parentEntity: 'salary_cycles',
      parentForeignKey: 'cycleId',
    ),

    'salary_withdrawals': SyncEntityConfig(
      entityName: 'salary_withdrawals',
      collectionId: 'salary_withdrawals',
      requiredFields: ['employeeId', 'amount', 'date'],
      parentEntity: 'employees',
      parentForeignKey: 'employeeId',
    ),

    // ─────────── كيانات النقد ───────────
    'cash_transactions': SyncEntityConfig(
      entityName: 'cash_transactions',
      collectionId: 'cash_transactions',
      defaultPriority: SyncPriority.high,
      requiredFields: ['transactionType', 'amount', 'transactionTime'],
    ),

    // ─────────── كيانات أخرى ───────────
    'shift_notes': SyncEntityConfig(
      entityName: 'shift_notes',
      collectionId: 'shift_notes',
      defaultPriority: SyncPriority.low,
      requiredFields: ['title', 'content'],
    ),

    'price_adjustments': SyncEntityConfig(
      entityName: 'price_adjustments',
      collectionId: 'price_adjustments',
      requiredFields: ['targetType', 'targetUuid', 'adjustmentType', 'newValue'],
    ),

    'audit_logs': SyncEntityConfig(
      entityName: 'audit_logs',
      collectionId: 'audit_logs',
      defaultPriority: SyncPriority.low,
      requiredFields: ['operationType', 'entityType', 'entityUuid'],
    ),
  };

  static SyncEntityConfig? getConfig(String entityName) => _configs[entityName];
  static List<String> get allEntities => _configs.keys.toList();

  /// ⭐ الكيانات مرتبة حسب الاعتماديات (الأب قبل الابن)
  static List<String> get orderedEntities {
    final result = <String>[];
    final visited = <String>{};

    void visit(String entity) {
      if (visited.contains(entity)) return;
      visited.add(entity);

      final config = _configs[entity];
      if (config?.parentEntity != null) {
        visit(config!.parentEntity!);
      }
      result.add(entity);
    }

    for (final entity in _configs.keys) {
      visit(entity);
    }
    return result;
  }

  /// ⭐ الكيانات الأصلية (ليس لها أب)
  static List<String> get rootEntities => _configs.entries
      .where((e) => e.value.parentEntity == null)
      .map((e) => e.key)
      .toList();
}

// ═══════════════════════════════════════════════════════════════════════════════
// قسم 3: محلل التعارضات (Conflict Resolver)
// ═══════════════════════════════════════════════════════════════════════════════

/// ⭐ محلل التعارضات
class ConflictResolver {
  ConflictResolver({this.defaultStrategy = ConflictStrategy.lastWriteWins});
  final ConflictStrategy defaultStrategy;
  final Map<String, ConflictStrategy> _entityStrategies = {};

  void setEntityStrategy(String entity, ConflictStrategy strategy) {
    _entityStrategies[entity] = strategy;
  }

  ConflictStrategy getStrategy(String entity) {
    return _entityStrategies[entity] ?? defaultStrategy;
  }

  /// ⭐ حل التعارض بين دلتا محلية وبعيدة
  Map<String, dynamic> resolve({
    required String entity,
    required Map<String, dynamic> baseData,
    required EntityDelta localDelta,
    required EntityDelta remoteDelta,
  }) {
    final strategy = getStrategy(entity);

    switch (strategy) {
      case ConflictStrategy.lastWriteWins:
        return _resolveLastWriteWins(baseData, localDelta, remoteDelta);
      case ConflictStrategy.localWins:
        return localDelta.applyTo(baseData);
      case ConflictStrategy.remoteWins:
        return remoteDelta.applyTo(baseData);
      case ConflictStrategy.fieldLevelMerge:
        return _resolveFieldLevelMerge(baseData, localDelta, remoteDelta);
      case ConflictStrategy.manual:
        return localDelta.applyTo(baseData);
    }
  }

  Map<String, dynamic> _resolveLastWriteWins(
    Map<String, dynamic> baseData,
    EntityDelta local,
    EntityDelta remote,
  ) {
    final result = Map<String, dynamic>.from(baseData);
    final localIsNewer = local.timestamp >= remote.timestamp;

    final newer = localIsNewer ? local : remote;
    final older = localIsNewer ? remote : local;

    for (final delta in older.fieldDeltas) {
      result[delta.fieldName] = delta.newValue;
    }
    for (final delta in newer.fieldDeltas) {
      result[delta.fieldName] = delta.newValue;
    }

    result['version'] = local.version > remote.version ? local.version : remote.version;
    result['vectorClock'] = local.vectorClock.merge(remote.vectorClock).toJson();
    return result;
  }

  Map<String, dynamic> _resolveFieldLevelMerge(
    Map<String, dynamic> baseData,
    EntityDelta local,
    EntityDelta remote,
  ) {
    final result = Map<String, dynamic>.from(baseData);
    final localFields = {for (final d in local.fieldDeltas) d.fieldName: d};
    final remoteFields = {for (final d in remote.fieldDeltas) d.fieldName: d};

    for (final entry in {...localFields, ...remoteFields}.entries) {
      final localDelta = localFields[entry.key];
      final remoteDelta = remoteFields[entry.key];

      if (localDelta != null && remoteDelta != null) {
        result[entry.key] = localDelta.changedAt >= remoteDelta.changedAt
            ? localDelta.newValue
            : remoteDelta.newValue;
      } else if (localDelta != null) {
        result[entry.key] = localDelta.newValue;
      } else if (remoteDelta != null) {
        result[entry.key] = remoteDelta.newValue;
      }
    }

    result['version'] = local.version > remote.version ? local.version : remote.version;
    result['vectorClock'] = local.vectorClock.merge(remote.vectorClock).toJson();
    return result;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// قسم 4: الخدمة الرئيسية (Main Service)
// ═══════════════════════════════════════════════════════════════════════════════

/// ⭐⭐⭐ خدمة المزامنة التفاضلية على مستوى الحقول ⭐⭐⭐
class AppwriteDeltaSync {
  AppwriteDeltaSync._();
  static final instance = AppwriteDeltaSync._();

  // ─────────── Dependencies ───────────
  AppwriteService? _appwriteService;
  AppDatabase? _database;
  OutboxDao? _outboxDao;
  String? _deviceId;

  final _logger = AppwriteLogger();
  final _uuid = const Uuid();
  final _connectivity = Connectivity();

  // ─────────── Components ───────────
  late final ConflictResolver _conflictResolver;

  // ─────────── State ───────────
  final Map<String, StateCacheEntry> _stateCache = {};
  final List<SyncErrorRecord> _syncErrors = [];
  bool _isInitialized = false;
  bool _isSyncing = false;
  int _lastSyncTimestamp = 0;
  VectorClock _lastSyncVectorClock = VectorClock(); // آخر ساعة متجهة معروفة

  // ─────────── Streams ───────────
  final _syncStateController = StreamController<SyncStatus>.broadcast();
  final _progressController = StreamController<SyncProgress>.broadcast();
  final _errorsController = StreamController<SyncError>.broadcast();

  // ─────────── Constants ───────────
  static const int _maxRetries = 5;
  static const int _batchSize = 50;
  static const int _syncSafetyBufferSeconds = 60;
  static const int _maxCacheSize = 10000;

  // ═══════════════════════════════════════════════════════════════════════════
  // التهيئة (Initialization)
  // ═══════════════════════════════════════════════════════════════════════════

  /// ⭐ تهيئة الخدمة
  Future<void> initialize({
    required AppwriteService appwriteService,
    required AppDatabase database,
    OutboxDao? outboxDao,
    String? deviceId,
    ConflictStrategy conflictStrategy = ConflictStrategy.lastWriteWins,
  }) async {
    _appwriteService = appwriteService;
    _database = database;
    _outboxDao = outboxDao ?? OutboxDao(database);
    _deviceId = deviceId ?? _uuid.v4();

    _conflictResolver = ConflictResolver(defaultStrategy: conflictStrategy);
    _isInitialized = true;

    // تحميل آخر ساعة متجهة من قاعدة البيانات (إذا وُجدت)
    await _loadLastVectorClock();

    _logger.info('✅ AppwriteDeltaSync initialized (deviceId: $_deviceId)', tag: 'DELTA_SYNC');
  }

  Future<void> _loadLastVectorClock() async {
    // يمكن تحميلها من sync_state أو من أعلى version في outbox
    // تبسيطاً، نبدأ بساعة فارغة
    _lastSyncVectorClock = VectorClock();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Getters
  // ═══════════════════════════════════════════════════════════════════════════

  bool get isInitialized => _isInitialized;
  bool get isSyncing => _isSyncing;
  String? get deviceId => _deviceId;

  /// ⭐ قائمة الأخطاء الفاشلة
  List<SyncErrorRecord> get syncErrors => List.unmodifiable(_syncErrors);

  Stream<SyncStatus> get syncState => _syncStateController.stream;
  Stream<SyncProgress> get progress => _progressController.stream;
  Stream<SyncError> get errors => _errorsController.stream;

  /// ⭐ بث الأخطاء (اسم بديل للتوافق)
  Stream<SyncError> get errorsStream => _errorsController.stream;

  // ═══════════════════════════════════════════════════════════════════════════
  // واجهة برمجة التطبيقات للتتبع (Tracking API)
  // ═══════════════════════════════════════════════════════════════════════════

  /// ⭐ تتبع إنشاء سجل جديد
  Future<void> trackCreate({
    required String entity,
    required String uuid,
    required Map<String, dynamic> data,
    String? parentUuid,
    SyncPriority? priority,
  }) async {
    _ensureInitialized();

    final now = Time.nowEpoch();
    final config = SyncEntityRegistry.getConfig(entity);

    final fieldDeltas = data.entries
        .where((e) =>
            !['localUuid', 'version', 'lastModified', 'createdAt', 'origin', 'vectorClock']
                .contains(e.key))
        .map((e) => FieldDelta(
              fieldName: e.key,
              newValue: e.value,
              changedAt: now,
              changedBy: _deviceId,
            ))
        .toList();

    final delta = EntityDelta(
      entity: entity,
      uuid: uuid,
      operation: OperationType.create,
      fieldDeltas: fieldDeltas,
      version: 1,
      timestamp: now,
      parentUuid: parentUuid,
      deviceId: _deviceId!,
      priority: priority ?? config?.defaultPriority ?? SyncPriority.normal,
      vectorClock: _lastSyncVectorClock.increment(_deviceId!),
    );

    _saveToCache(entity, uuid, data, 1, delta.vectorClock);
    await _saveDeltaToOutbox(delta);

    _logger.info('🆕 Tracked CREATE $entity/$uuid (${fieldDeltas.length} fields)',
        tag: 'DELTA_SYNC');
  }

  /// ⭐ تتبع تحديث
  Future<void> trackUpdate({
    required String entity,
    required String uuid,
    required Map<String, dynamic> changes,
    String? parentUuid,
    SyncPriority? priority,
  }) async {
    _ensureInitialized();

    final oldState = _getFromCache(entity, uuid) ?? await _fetchFromDatabase(entity, uuid) ?? {};
    final newState = {...oldState, ...changes, 'lastModified': Time.nowEpoch()};

    final config = SyncEntityRegistry.getConfig(entity);
    final ignoreFields = config?.ignoreFields.toSet();

    final delta = EntityDelta.fromComparison(
      entity: entity,
      uuid: uuid,
      oldData: oldState,
      newData: newState,
      deviceId: _deviceId!,
      vectorClock: _lastSyncVectorClock,
      parentUuid: parentUuid,
      priority: priority ?? config?.defaultPriority ?? SyncPriority.normal,
      ignoreFields: ignoreFields,
    );

    if (delta.isEmpty) {
      _logger.info('⏭️ No actual changes for $entity/$uuid', tag: 'DELTA_SYNC');
      return;
    }

    _saveToCache(entity, uuid, newState, delta.version, delta.vectorClock);
    await _saveDeltaToOutbox(delta);

    _logger.info(
      '✏️ Tracked UPDATE $entity/$uuid: ${delta.changedFieldNames.join(', ')}',
      tag: 'DELTA_SYNC',
    );
  }

  /// ⭐ تتبع حذف
  Future<void> trackDelete({
    required String entity,
    required String uuid,
    String? parentUuid,
  }) async {
    _ensureInitialized();

    final oldState = _getFromCache(entity, uuid) ?? await _fetchFromDatabase(entity, uuid);
    final lastVersion = oldState?['version'] as int? ?? 0;

    final delta = EntityDelta.forDelete(
      entity: entity,
      uuid: uuid,
      lastVersion: lastVersion,
      deviceId: _deviceId!,
      vectorClock: _lastSyncVectorClock,
      parentUuid: parentUuid,
    );

    _removeFromCache(entity, uuid);
    await _saveDeltaToOutbox(delta);

    _logger.info('🗑️ Tracked DELETE $entity/$uuid', tag: 'DELTA_SYNC');
  }

  /// ⭐ تتبع تغيير عام
  Future<void> trackChange({
    required String entity,
    required String uuid,
    required OperationType operation,
    Map<String, dynamic>? data,
    Map<String, dynamic>? changes,
    String? parentUuid,
    SyncPriority? priority,
  }) async {
    switch (operation) {
      case OperationType.create:
        if (data != null) {
          await trackCreate(
              entity: entity,
              uuid: uuid,
              data: data,
              parentUuid: parentUuid,
              priority: priority);
        }
      case OperationType.update:
        if (changes != null) {
          await trackUpdate(
              entity: entity,
              uuid: uuid,
              changes: changes,
              parentUuid: parentUuid,
              priority: priority);
        }
      case OperationType.delete:
        await trackDelete(entity: entity, uuid: uuid, parentUuid: parentUuid);
      case OperationType.noop:
        break;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // واجهة برمجة التطبيقات للمزامنة (Sync API)
  // ═══════════════════════════════════════════════════════════════════════════

  /// ⭐ مزامنة كاملة (Push + Pull)
  Future<SyncResult> sync({bool force = false}) async {
    if (!_checkReady()) {
      return SyncResult.error('الخدمة غير مهيأة');
    }

    if (!force && !await _isOnline()) {
      return SyncResult.error('لا يوجد اتصال بالإنترنت');
    }

    if (_isSyncing) {
      return SyncResult.error('المزامنة جارية بالفعل');
    }

    _isSyncing = true;
    _syncStateController.add(SyncStatus.inProgress);

    final startTime = DateTime.now();
    _logger.info('🔄 Starting FIELD-LEVEL delta sync', tag: 'DELTA_SYNC');

    try {
      // 1. Push
      _progressController.add(const SyncProgress(phase: 'pushing', message: 'دفع التغييرات...'));
      final pushResult = await _processOutbox();

      // 2. Pull
      _progressController.add(const SyncProgress(phase: 'pulling', message: 'سحب التغييرات...'));
      final pullResult = await _pullChanges();

      final duration = DateTime.now().difference(startTime);
      final success = pushResult.success && pullResult.success;

      final result = SyncResult(
        success: success,
        message: success
            ? 'تمت المزامنة: دفع ${pushResult.pushedCount}، سحب ${pullResult.pulledCount}'
            : 'فشلت المزامنة',
        pushedCount: pushResult.pushedCount,
        pulledCount: pullResult.pulledCount,
        fieldsCount: pushResult.fieldsCount,
        conflictCount: pushResult.conflictCount + pullResult.conflictCount,
        skippedCount: pullResult.skippedCount,
        errors: [...pushResult.errors, ...pullResult.errors],
        conflicts: [...pushResult.conflicts, ...pullResult.conflicts],
        timestamp: DateTime.now(),
        duration: duration,
      );

      _syncStateController.add(success ? SyncStatus.completed : SyncStatus.failed);
      if (success) {
        _lastSyncTimestamp = Time.nowEpoch();
        // تحديث الساعة المتجهة بعد المزامنة الناجحة (أعلى ساعة من كل العناصر)
        await _updateLastVectorClockAfterSync();
      }

      _logger.info(
        '✅ Sync completed: pushed=${pushResult.pushedCount}, pulled=${pullResult.pulledCount}, '
        'fields=${pushResult.fieldsCount}, duration=${duration.inSeconds}s',
        tag: 'DELTA_SYNC',
      );

      return result;
    } catch (e, stack) {
      _logger.error('❌ Sync failed', tag: 'DELTA_SYNC', error: e, stackTrace: stack);
      _syncStateController.add(SyncStatus.failed);
      _errorsController.add(SyncError(message: e.toString(), timestamp: DateTime.now()));
      return SyncResult.error(e.toString());
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _updateLastVectorClockAfterSync() async {
    // يمكن جلب أعلى ساعة من جميع الجداول المحلية وتخزينها
    // تبسيطاً، نقوم بدمج الساعات المخزنة في الذاكرة
    VectorClock merged = VectorClock();
    for (final entry in _stateCache.values) {
      merged = merged.merge(entry.vectorClock);
    }
    _lastSyncVectorClock = merged;
  }

  /// ⭐ دفع فقط
  Future<SyncResult> pushOnly({bool force = false}) async {
    if (!force && !await _isOnline()) {
      return SyncResult.error('لا يوجد اتصال');
    }
    return _processOutbox();
  }

  /// ⭐ سحب فقط
  Future<SyncResult> pullOnly({bool fullSync = false}) async {
    return _pullChanges(forceFullSync: fullSync);
  }

  /// ⭐ إعادة محاولة الفاشلة
  Future<SyncResult> retryFailed() async {
    await _outboxDao?.resetErrors();
    return sync(force: true);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // تنفيذ الدفع (Push Implementation)
  // ═══════════════════════════════════════════════════════════════════════════

  Future<SyncResult> _processOutbox() async {
    final errors = <String>[];
    final conflicts = <ConflictInfo>[];
    int pushedCount = 0;
    int fieldsCount = 0;
    int conflictCount = 0;

    await _outboxDao!.cleanupStuckEntries();

    while (true) {
      final batch = await _outboxDao!.takeBatch(_batchSize);
      if (batch.isEmpty) break;

      _logger.info('📦 Processing batch of ${batch.length}', tag: 'DELTA_SYNC');

      final completedIds = <int>[];
      final failedItems = <OutboxData>[];

      for (final item in batch) {
        // ⭐ التحقق من الحد الأقصى للمحاولات
        if (item.attempts >= _maxRetries) {
          _logger.error(
              '❌ Permanent failure for ${item.entity}/${item.localUuid} after ${item.attempts} attempts',
              tag: 'DELTA_SYNC');
          completedIds.add(item.id); // حذفها من outbox
          continue;
        }

        try {
          final delta = _parseOutboxItem(item);
          final remoteDoc = await _pushSingleDelta(delta);

          // ⭐ تحديث البيانات المحلية بعد النجاح (لتطابق الخادم)
          await _updateLocalAfterPush(delta, remoteDoc);

          completedIds.add(item.id);
          pushedCount++;
          fieldsCount += delta.changedFieldsCount;

          _logger.info(
            '📤 Pushed ${item.entity}/${item.localUuid}: ${delta.changedFieldNames.join(', ')}',
            tag: 'DELTA_SYNC',
          );
        } on AppwriteException catch (e) {
          if (e.code == 409) {
            // تعارض - نحاول حله باستخدام البيانات البعيدة
            conflictCount++;
            try {
              final remoteDoc = await _appwriteService!.getDocument(
                collectionId: SyncEntityRegistry.getConfig(item.entity)!.collectionId,
                documentId: item.localUuid,
              );
              final remoteData = remoteDoc.data;
              final localData = await _fetchFromDatabase(item.entity, item.localUuid) ?? {};
              final resolved = await _resolveConflictWithRemote(
                item.entity,
                item.localUuid,
                localData,
                remoteData,
              );
              await _upsertLocalData(item.entity, item.localUuid, resolved);
              completedIds.add(item.id);
              _logger.warning('⚠️ Conflict resolved: ${item.entity}/${item.localUuid}',
                  tag: 'DELTA_SYNC');
            } catch (resolveError) {
              failedItems.add(item);
              final errorMsg = 'Conflict resolution failed: $resolveError';
              errors.add('${item.entity}/${item.localUuid}: $errorMsg');
              _addErrorRecord(item.entity, item.localUuid, item.op, errorMsg, item.attempts);
            }
          } else {
            failedItems.add(item);
            final errorMsg = e.message ?? 'Unknown error';
            errors.add('${item.entity}/${item.localUuid}: $errorMsg');

            _addErrorRecord(item.entity, item.localUuid, item.op, errorMsg, item.attempts);

            _errorsController.add(SyncError(
              entity: item.entity,
              uuid: item.localUuid,
              message: errorMsg,
              timestamp: DateTime.now(),
            ));
          }
        } catch (e) {
          failedItems.add(item);
          final errorMsg = e.toString();
          errors.add('${item.entity}/${item.localUuid}: $errorMsg');

          _addErrorRecord(item.entity, item.localUuid, item.op, errorMsg, item.attempts);
        }
      }

      if (completedIds.isNotEmpty) {
        await _outboxDao!.removeByIds(completedIds);
      }

      for (final item in failedItems) {
        await _outboxDao!.setError(
          item.id,
          'Failed after ${item.attempts + 1} attempts',
          item.attempts + 1,
        );
      }
    }

    return SyncResult(
      success: errors.isEmpty,
      message: 'Pushed $pushedCount deltas',
      pushedCount: pushedCount,
      fieldsCount: fieldsCount,
      conflictCount: conflictCount,
      errors: errors,
      conflicts: conflicts,
    );
  }

  Future<models.Document> _pushSingleDelta(EntityDelta delta) async {
    final collectionId = SyncEntityRegistry.getConfig(delta.entity)?.collectionId;
    if (collectionId == null) {
      throw Exception('Unknown entity: ${delta.entity}');
    }

    final payload = <String, dynamic>{
      'id': delta.uuid,
      'localUuid': delta.uuid,
      'version': delta.version,
      'lastModified': delta.timestamp,
      'deviceId': _deviceId,
      'syncTimestamp': Time.nowEpoch(),
      'vectorClock': delta.vectorClock.toJson(),
    };

    for (final fieldDelta in delta.fieldDeltas) {
      payload[fieldDelta.fieldName] = fieldDelta.newValue;
    }

    switch (delta.operation) {
      case OperationType.create:
        return await _appwriteService!.createDocument(
          collectionId: collectionId,
          documentId: delta.uuid,
          data: _sanitizePayload(payload),
        );

      case OperationType.update:
        return await _appwriteService!.updateDocument(
          collectionId: collectionId,
          documentId: delta.uuid,
          data: _sanitizePayload(payload),
        );

      case OperationType.delete:
        try {
          await _appwriteService!.deleteDocument(
            collectionId: collectionId,
            documentId: delta.uuid,
          );
          return models.Document(
            $id: delta.uuid,
            $collectionId: collectionId,
            $databaseId: _appwriteService!.client.project,
            $createdAt: '',
            $updatedAt: '',
            $permissions: [],
            data: {'_deleted': true},
          );
        } on AppwriteException catch (e) {
          if (e.code != 404) rethrow;
          return models.Document(
            $id: delta.uuid,
            $collectionId: collectionId,
            $databaseId: _appwriteService!.client.project,
            $createdAt: '',
            $updatedAt: '',
            $permissions: [],
            data: {},
          );
        }

      case OperationType.noop:
        throw Exception('Cannot push noop delta');
    }
  }

  Future<void> _updateLocalAfterPush(EntityDelta delta, models.Document remoteDoc) async {
    final localData = await _fetchFromDatabase(delta.entity, delta.uuid) ?? {};
    final mergedData = delta.applyTo(localData);
    // تحديث بالبيانات البعيدة (قد تحتوي على حقول إضافية)
    mergedData.addAll(remoteDoc.data);
    mergedData['version'] = remoteDoc.data['version'] ?? delta.version;
    mergedData['lastModified'] = remoteDoc.data['lastModified'] ?? delta.timestamp;
    mergedData['vectorClock'] = remoteDoc.data['vectorClock'] ?? delta.vectorClock.toJson();
    await _upsertLocalData(delta.entity, delta.uuid, mergedData);
    _saveToCache(
        delta.entity,
        delta.uuid,
        mergedData,
        mergedData['version'] as int? ?? 1,
        VectorClock.fromJson(mergedData['vectorClock'] as String?));
  }

  Future<Map<String, dynamic>> _resolveConflictWithRemote(
    String entity,
    String uuid,
    Map<String, dynamic> localData,
    Map<String, dynamic> remoteData,
  ) async {
    final localClock = VectorClock.fromJson(localData['vectorClock'] as String?);
    final remoteClock = VectorClock.fromJson(remoteData['vectorClock'] as String?);

    if (remoteClock.isAfter(localClock)) {
      return remoteData;
    } else if (localClock.isAfter(remoteClock)) {
      return localData;
    } else {
      // تعارض حقيقي – استخدم استراتيجية التكوين
      final localDelta = EntityDelta.fromComparison(
        entity: entity,
        uuid: uuid,
        oldData: localData,
        newData: localData, // ملاحظة: لسنا بحاجة لتوليد دلتا كاملة هنا
        deviceId: _deviceId!,
        vectorClock: localClock,
      );
      final remoteDelta = EntityDelta.fromComparison(
        entity: entity,
        uuid: uuid,
        oldData: remoteData,
        newData: remoteData,
        deviceId: remoteData['deviceId'] ?? 'remote',
        vectorClock: remoteClock,
      );
      return _conflictResolver.resolve(
        entity: entity,
        baseData: localData,
        localDelta: localDelta,
        remoteDelta: remoteDelta,
      );
    }
  }

  /// ⭐⭐⭐ تصحيح: إضافة entity و uuid من OutboxData إلى payload قبل التحليل
  /// هذا يضمن أن EntityDelta.fromJson سيحصل على entity الصحيح
  EntityDelta _parseOutboxItem(OutboxData item) {
    final payload = jsonDecode(item.payload) as Map<String, dynamic>;
    
    // ⭐⭐⭐ التصحيح: إضافة entity من OutboxData إلى payload
    // هذا يحل مشكلة "Unknown entity:" عندما يكون payload لا يحتوي على entity
    payload['entity'] = item.entity;
    payload['e'] = item.entity;
    
    // ⭐ إضافة uuid أيضاً إذا لم يكن موجوداً
    payload['uuid'] ??= item.localUuid;
    payload['u'] ??= item.localUuid;
    
    return EntityDelta.fromJson(payload);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // تنفيذ السحب (Pull Implementation)
  // ═══════════════════════════════════════════════════════════════════════════

  Future<SyncResult> _pullChanges({bool forceFullSync = false}) async {
    int pulledCount = 0;
    int skippedCount = 0;
    final errors = <String>[];
    final conflicts = <ConflictInfo>[];

    final lastSync = _lastSyncTimestamp;
    final safeLastSync = forceFullSync ? 0 : lastSync - _syncSafetyBufferSeconds;

    final entities = SyncEntityRegistry.orderedEntities;
    final total = entities.length;

    for (var i = 0; i < entities.length; i++) {
      final entity = entities[i];

      _progressController.add(SyncProgress(
        phase: 'pulling',
        message: 'سحب $entity...',
        current: i + 1,
        total: total,
        currentEntity: entity,
      ));

      try {
        final result = await _pullEntity(entity, safeLastSync);
        pulledCount += result.applied;
        skippedCount += result.skipped;
        conflicts.addAll(result.conflicts);
      } catch (e) {
        errors.add('Failed to pull $entity: $e');
        _logger.warning('⚠️ Failed to pull $entity: $e', tag: 'DELTA_SYNC');
      }
    }

    return SyncResult(
      success: errors.isEmpty,
      message: 'Pulled $pulledCount items',
      pulledCount: pulledCount,
      skippedCount: skippedCount,
      conflicts: conflicts,
      errors: errors,
    );
  }

  Future<_PullResult> _pullEntity(String entity, int lastSync) async {
    final collectionId = SyncEntityRegistry.getConfig(entity)?.collectionId;
    if (collectionId == null) return _PullResult();

    final queries = <String>[];
    if (lastSync > 0) {
      queries.add(Query.greaterThan('lastModified', lastSync));
    }
    queries.add(Query.notEqual('deviceId', _deviceId));

    final docs = await _appwriteService!.listDocuments(
      collectionId: collectionId,
      queries: queries.isEmpty ? null : queries,
    );

    int applied = 0;
    int skipped = 0;
    final conflicts = <ConflictInfo>[];

    for (final doc in docs) {
      final data = Map<String, dynamic>.from(doc.data);

      if (data['deviceId'] == _deviceId) continue;

      try {
        final result = await _applyRemoteChange(entity, doc.$id, data);
        if (result.applied) {
          applied++;
        } else if (result.skipped) {
          skipped++;
        }
        conflicts.addAll(result.conflicts);
      } catch (e) {
        _logger.warning('⚠️ Failed to apply $entity/${doc.$id}: $e', tag: 'DELTA_SYNC');
        skipped++;
      }
    }

    return _PullResult(applied: applied, skipped: skipped, conflicts: conflicts);
  }

  Future<_ApplyResult> _applyRemoteChange(
      String entity, String docId, Map<String, dynamic> data) async {
    final incomingModified = data['lastModified'] as int? ?? 0;
    final incomingClock = VectorClock.fromJson(data['vectorClock'] as String?);

    final localData = _getFromCache(entity, docId) ?? await _fetchFromDatabase(entity, docId);

    if (localData != null) {
      final localClock = VectorClock.fromJson(localData['vectorClock'] as String?);

      // مقارنة الساعات المتجهة
      if (incomingClock.isAfter(localClock)) {
        // البعيد أحدث – استبدل المحلي
        await _upsertLocalData(entity, docId, data);
        _saveToCache(entity, docId, data, data['version'] as int? ?? 1, incomingClock);
        return _ApplyResult(applied: true);
      } else if (localClock.isAfter(incomingClock)) {
        // المحلي أحدث – تجاهل البعيد
        _logger.info('⏭️ Skipping old change: $docId (local newer)', tag: 'DELTA_SYNC');
        return _ApplyResult(skipped: true);
      } else {
        // تعارض – دمج
        final localDelta = EntityDelta.fromComparison(
          entity: entity,
          uuid: docId,
          oldData: localData,
          newData: localData,
          deviceId: _deviceId!,
          vectorClock: localClock,
        );
        final remoteDelta = EntityDelta.fromComparison(
          entity: entity,
          uuid: docId,
          oldData: data,
          newData: data,
          deviceId: data['deviceId'] ?? 'remote',
          vectorClock: incomingClock,
        );
        final resolved = _conflictResolver.resolve(
          entity: entity,
          baseData: localData,
          localDelta: localDelta,
          remoteDelta: remoteDelta,
        );
        await _upsertLocalData(entity, docId, resolved);
        _saveToCache(entity, docId, resolved, resolved['version'] as int? ?? 1,
            VectorClock.fromJson(resolved['vectorClock'] as String?));
        return _ApplyResult(applied: true);
      }
    } else {
      // لا يوجد محلي – أدخل البعيد
      await _upsertLocalData(entity, docId, data);
      _saveToCache(entity, docId, data, data['version'] as int? ?? 1, incomingClock);
      return _ApplyResult(applied: true);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // إدارة الذاكرة المؤقتة (Cache Management)
  // ═══════════════════════════════════════════════════════════════════════════

  String _cacheKey(String entity, String uuid) => '$entity:$uuid';

  void _saveToCache(String entity, String uuid, Map<String, dynamic> data, int version,
      VectorClock vectorClock) {
    final key = _cacheKey(entity, uuid);
    _stateCache[key] = StateCacheEntry(
      entity: entity,
      uuid: uuid,
      data: Map.from(data),
      version: version,
      timestamp: Time.nowEpoch(),
      vectorClock: vectorClock,
    );
    _evictIfNeeded();
  }

  Map<String, dynamic>? _getFromCache(String entity, String uuid) {
    return _stateCache[_cacheKey(entity, uuid)]?.data;
  }

  void _removeFromCache(String entity, String uuid) {
    _stateCache.remove(_cacheKey(entity, uuid));
  }

  void _evictIfNeeded() {
    if (_stateCache.length <= _maxCacheSize) return;

    final entries = _stateCache.entries.toList()
      ..sort((a, b) => a.value.timestamp.compareTo(b.value.timestamp));

    final toRemove = (entries.length * 0.1).round();
    for (var i = 0; i < toRemove && i < entries.length; i++) {
      _stateCache.remove(entries[i].key);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // عمليات قاعدة البيانات (Database Operations)
  // ═══════════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>?> _fetchFromDatabase(String entity, String uuid) async {
    final db = _database!;

    switch (entity) {
      case 'rooms':
        final r = await (db.select(db.rooms)..where((t) => t.localUuid.equals(uuid)))
            .getSingleOrNull();
        return r?.toJson();
      case 'bookings':
        final r = await (db.select(db.bookings)..where((t) => t.localUuid.equals(uuid)))
            .getSingleOrNull();
        return r?.toJson();
      case 'booking_nights':
        final r = await (db.select(db.bookingNights)..where((t) => t.localUuid.equals(uuid)))
            .getSingleOrNull();
        return r?.toJson();
      case 'booking_notes':
        final r = await (db.select(db.bookingNotes)..where((t) => t.localUuid.equals(uuid)))
            .getSingleOrNull();
        return r?.toJson();
      case 'payments':
        final r = await (db.select(db.payments)..where((t) => t.localUuid.equals(uuid)))
            .getSingleOrNull();
        return r?.toJson();
      case 'expenses':
        final r = await (db.select(db.expenses)..where((t) => t.localUuid.equals(uuid)))
            .getSingleOrNull();
        return r?.toJson();
      case 'debts':
        final r = await (db.select(db.debts)..where((t) => t.localUuid.equals(uuid)))
            .getSingleOrNull();
        return r?.toJson();
      case 'employees':
        final r = await (db.select(db.employees)..where((t) => t.localUuid.equals(uuid)))
            .getSingleOrNull();
        return r?.toJson();
      case 'cash_transactions':
        final r = await (db.select(db.cashTransactions)..where((t) => t.localUuid.equals(uuid)))
            .getSingleOrNull();
        return r?.toJson();
      case 'salary_cycles':
        final r = await (db.select(db.salaryCycles)..where((t) => t.localUuid.equals(uuid)))
            .getSingleOrNull();
        return r?.toJson();
      case 'salary_payments':
        final r = await (db.select(db.salaryPayments)..where((t) => t.localUuid.equals(uuid)))
            .getSingleOrNull();
        return r?.toJson();
      case 'salary_withdrawals':
        final r = await (db.select(db.salaryWithdrawals)..where((t) => t.localUuid.equals(uuid)))
            .getSingleOrNull();
        return r?.toJson();
      case 'shift_notes':
        final r = await (db.select(db.shiftNotes)..where((t) => t.localUuid.equals(uuid)))
            .getSingleOrNull();
        return r?.toJson();
      case 'price_adjustments':
        final r = await (db.select(db.priceAdjustments)..where((t) => t.localUuid.equals(uuid)))
            .getSingleOrNull();
        return r?.toJson();
      case 'booking_price_adjustments':
        final r = await (db.select(db.bookingPriceAdjustments)
              ..where((t) => t.localUuid.equals(uuid)))
            .getSingleOrNull();
        return r?.toJson();
      case 'audit_logs':
        final r = await (db.select(db.auditLogs)..where((t) => t.localUuid.equals(uuid)))
            .getSingleOrNull();
        return r?.toJson();
      case 'payment_voids':
        final r = await (db.select(db.paymentVoids)..where((t) => t.localUuid.equals(uuid)))
            .getSingleOrNull();
        return r?.toJson();
      default:
        return null;
    }
  }

  Future<void> _upsertLocalData(String entity, String uuid, Map<String, dynamic> data) async {
    final db = _database!;

    switch (entity) {
      case 'rooms':
        await _upsertRoom(db, uuid, data);
      case 'bookings':
        await _upsertBooking(db, uuid, data);
      case 'booking_nights':
        await _upsertBookingNight(db, uuid, data);
      case 'booking_notes':
        await _upsertBookingNote(db, uuid, data);
      case 'payments':
        await _upsertPayment(db, uuid, data);
      case 'expenses':
        await _upsertExpense(db, uuid, data);
      case 'debts':
        await _upsertDebt(db, uuid, data);
      case 'employees':
        await _upsertEmployee(db, uuid, data);
      case 'cash_transactions':
        await _upsertCashTransaction(db, uuid, data);
      case 'salary_cycles':
        await _upsertSalaryCycle(db, uuid, data);
      case 'salary_payments':
        await _upsertSalaryPayment(db, uuid, data);
      case 'salary_withdrawals':
        await _upsertSalaryWithdrawal(db, uuid, data);
      case 'shift_notes':
        await _upsertShiftNote(db, uuid, data);
      case 'price_adjustments':
        await _upsertPriceAdjustment(db, uuid, data);
      case 'booking_price_adjustments':
        await _upsertBookingPriceAdjustment(db, uuid, data);
      case 'audit_logs':
        await _upsertAuditLog(db, uuid, data);
      case 'payment_voids':
        await _upsertPaymentVoid(db, uuid, data);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // معالجات الكيانات (Entity Handlers)
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _upsertRoom(AppDatabase db, String uuid, Map<String, dynamic> data) async {
    final companion = RoomsCompanion(
      localUuid: d.Value(_asString(data['localUuid']) ?? uuid),
      roomNumber: d.Value(_asString(data['roomNumber']) ?? ''),
      type: d.Value(_asString(data['type']) ?? ''),
      price: d.Value(_asDouble(data['price'])),
      status: d.Value(_asString(data['status']) ?? 'available'),
      floor: _nullableValue(_asInt(data['floor'])),
      imageUrl: _nullableValue(_asString(data['imageUrl'])),
      serverId: _nullableValue(_asInt(data['serverId'])),
      createdAt: d.Value(_asInt(data['createdAt']) ?? Time.nowEpoch()),
      updatedAt: d.Value(_asInt(data['updatedAt']) ?? Time.nowEpoch()),
      lastModified: d.Value(_asInt(data['lastModified']) ?? Time.nowEpoch()),
      version: d.Value(_asInt(data['version']) ?? 1),
      origin: d.Value(_asString(data['origin']) ?? 'appwrite_delta'),
      deletedAt: _nullableValue(_asInt(data['deletedAt'])),
      vectorClock: _nullableValue(_asString(data['vectorClock'])),
    );
    await db.into(db.rooms).insertOnConflictUpdate(companion);
  }

  Future<void> _upsertBooking(AppDatabase db, String uuid, Map<String, dynamic> data) async {
    final companion = BookingsCompanion(
      localUuid: d.Value(_asString(data['localUuid']) ?? uuid),
      roomNumber: d.Value(_asString(data['roomNumber']) ?? ''),
      guestName: d.Value(_asString(data['guestName']) ?? ''),
      guestPhone: d.Value(_asString(data['guestPhone']) ?? ''),
      guestIdType: d.Value(_asString(data['guestIdType']) ?? ''),
      guestIdNumber: d.Value(_asString(data['guestIdNumber']) ?? ''),
      guestIdIssueDate: _nullableValue(_asString(data['guestIdIssueDate'])),
      guestIdIssuePlace: _nullableValue(_asString(data['guestIdIssuePlace'])),
      guestNationality: d.Value(_asString(data['guestNationality']) ?? ''),
      guestEmail: _nullableValue(_asString(data['guestEmail'])),
      guestAddress: _nullableValue(_asString(data['guestAddress'])),
      checkinDate: d.Value(_asString(data['checkinDate']) ?? ''),
      checkoutDate: _nullableValue(_asString(data['checkoutDate'])),
      actualCheckout: _nullableValue(_asString(data['actualCheckout'])),
      status: d.Value(_asString(data['status']) ?? ''),
      notes: _nullableValue(_asString(data['notes'])),
      expectedNights: d.Value(_asInt(data['expectedNights']) ?? 1),
      calculatedNights: d.Value(_asInt(data['calculatedNights']) ?? 1),
      serverId: _nullableValue(_asInt(data['serverId'])),
      serverBookingId: _nullableValue(_asInt(data['serverBookingId'])),
      createdAt: d.Value(_asInt(data['createdAt']) ?? Time.nowEpoch()),
      updatedAt: d.Value(_asInt(data['updatedAt']) ?? Time.nowEpoch()),
      lastModified: d.Value(_asInt(data['lastModified']) ?? Time.nowEpoch()),
      version: d.Value(_asInt(data['version']) ?? 1),
      origin: d.Value(_asString(data['origin']) ?? 'appwrite_delta'),
      deletedAt: _nullableValue(_asInt(data['deletedAt'])),
      vectorClock: _nullableValue(_asString(data['vectorClock'])),
    );
    await db.into(db.bookings).insertOnConflictUpdate(companion);
  }

  Future<void> _upsertBookingNight(AppDatabase db, String uuid, Map<String, dynamic> data) async {
    final bookingId = await _resolveBookingId(db, data);
    final companion = BookingNightsCompanion(
      localUuid: d.Value(_asString(data['localUuid']) ?? uuid),
      bookingLocalId: _nullableValue(bookingId),
      hotelDayKey: d.Value(_asString(data['hotelDayKey']) ?? ''),
      nightDate: d.Value(_asString(data['nightDate']) ?? ''),
      nightlyRate: d.Value(_asDouble(data['nightlyRate'])),
      isWeekend: d.Value(_asBool(data['isWeekend'])),
      isHoliday: d.Value(_asBool(data['isHoliday'])),
      createdAt: d.Value(_asInt(data['createdAt']) ?? Time.nowEpoch()),
      updatedAt: d.Value(_asInt(data['updatedAt']) ?? Time.nowEpoch()),
      lastModified: d.Value(_asInt(data['lastModified']) ?? Time.nowEpoch()),
      version: d.Value(_asInt(data['version']) ?? 1),
      origin: d.Value(_asString(data['origin']) ?? 'appwrite_delta'),
      vectorClock: _nullableValue(_asString(data['vectorClock'])),
    );
    await db.into(db.bookingNights).insertOnConflictUpdate(companion);
  }

  Future<void> _upsertBookingNote(AppDatabase db, String uuid, Map<String, dynamic> data) async {
    final bookingId = await _resolveBookingId(db, data);
    final companion = BookingNotesCompanion(
      localUuid: d.Value(_asString(data['localUuid']) ?? uuid),
      bookingId: _nullableValue(bookingId),
      noteText: d.Value(_asString(data['noteText']) ?? ''),
      noteType: d.Value(_asString(data['noteType']) ?? 'general'),
      createdBy: d.Value(_asString(data['createdBy']) ?? ''),
      createdAt: d.Value(_asInt(data['createdAt']) ?? Time.nowEpoch()),
      updatedAt: d.Value(_asInt(data['updatedAt']) ?? Time.nowEpoch()),
      lastModified: d.Value(_asInt(data['lastModified']) ?? Time.nowEpoch()),
      version: d.Value(_asInt(data['version']) ?? 1),
      origin: d.Value(_asString(data['origin']) ?? 'appwrite_delta'),
      vectorClock: _nullableValue(_asString(data['vectorClock'])),
    );
    await db.into(db.bookingNotes).insertOnConflictUpdate(companion);
  }

  Future<void> _upsertPayment(AppDatabase db, String uuid, Map<String, dynamic> data) async {
    final bookingId = await _resolveBookingId(db, data);
    final companion = PaymentsCompanion(
      localUuid: d.Value(_asString(data['localUuid']) ?? uuid),
      bookingLocalId: _nullableValue(bookingId),
      serverBookingId: _nullableValue(_asInt(data['serverBookingId'])),
      roomNumber: _nullableValue(_asString(data['roomNumber'])),
      amount: d.Value(_asDouble(data['amount'])),
      paymentDate: d.Value(_asString(data['paymentDate']) ?? ''),
      paymentMethod: d.Value(_asString(data['paymentMethod']) ?? ''),
      revenueType: d.Value(_asString(data['revenueType']) ?? 'room'),
      notes: _nullableValue(_asString(data['notes'])),
      referenceNumber: _nullableValue(_asString(data['referenceNumber'])),
      cashTransactionLocalId: _nullableValue(_asInt(data['cashTransactionLocalId'])),
      cashTransactionServerId: _nullableValue(_asInt(data['cashTransactionServerId'])),
      serverId: _nullableValue(_asInt(data['serverId'])),
      serverPaymentId: _nullableValue(_asInt(data['serverPaymentId'])),
      createdAt: d.Value(_asInt(data['createdAt']) ?? Time.nowEpoch()),
      updatedAt: d.Value(_asInt(data['updatedAt']) ?? Time.nowEpoch()),
      lastModified: d.Value(_asInt(data['lastModified']) ?? Time.nowEpoch()),
      version: d.Value(_asInt(data['version']) ?? 1),
      origin: d.Value(_asString(data['origin']) ?? 'appwrite_delta'),
      deletedAt: _nullableValue(_asInt(data['deletedAt'])),
      vectorClock: _nullableValue(_asString(data['vectorClock'])),
    );
    await db.into(db.payments).insertOnConflictUpdate(companion);
  }

  Future<void> _upsertExpense(AppDatabase db, String uuid, Map<String, dynamic> data) async {
    final companion = ExpensesCompanion(
      localUuid: d.Value(_asString(data['localUuid']) ?? uuid),
      expenseType: d.Value(_asString(data['expenseType']) ?? ''),
      description: d.Value(_asString(data['description']) ?? ''),
      amount: d.Value(_asDouble(data['amount'])),
      date: d.Value(_asString(data['date']) ?? ''),
      relatedId: _nullableValue(_asInt(data['relatedId'])),
      cashTransactionId: _nullableValue(_asInt(data['cashTransactionId'])),
      serverId: _nullableValue(_asInt(data['serverId'])),
      createdAt: d.Value(_asInt(data['createdAt']) ?? Time.nowEpoch()),
      updatedAt: d.Value(_asInt(data['updatedAt']) ?? Time.nowEpoch()),
      lastModified: d.Value(_asInt(data['lastModified']) ?? Time.nowEpoch()),
      version: d.Value(_asInt(data['version']) ?? 1),
      origin: d.Value(_asString(data['origin']) ?? 'appwrite_delta'),
      deletedAt: _nullableValue(_asInt(data['deletedAt'])),
      vectorClock: _nullableValue(_asString(data['vectorClock'])),
    );
    await db.into(db.expenses).insertOnConflictUpdate(companion);
  }

  Future<void> _upsertDebt(AppDatabase db, String uuid, Map<String, dynamic> data) async {
    final bookingId = await _resolveBookingId(db, data);
    final companion = DebtsCompanion(
      localUuid: d.Value(_asString(data['localUuid']) ?? uuid),
      bookingLocalId: _nullableValue(bookingId),
      guestName: d.Value(_asString(data['guestName']) ?? _asString(data['debtorName']) ?? ''),
      checkinDate: d.Value(_asString(data['checkinDate']) ?? ''),
      checkoutDate: d.Value(_asString(data['checkoutDate']) ?? ''),
      dateRecorded: d.Value(_asString(data['dateRecorded']) ?? ''),
      debtReason: d.Value(_asString(data['debtReason']) ?? ''),
      totalAmount: d.Value(_asDouble(data['totalAmount'] ?? data['amount'])),
      paidAmount: d.Value(_asDouble(data['paidAmount'])),
      remainingAmount: d.Value(_asDouble(data['remainingAmount'])),
      paymentDate: d.Value(_asString(data['paymentDate']) ?? ''),
      isSettled: d.Value(_asInt(data['isSettled']) ?? (data['status'] == 'settled' ? 1 : 0)),
      pledge: _nullableValue(_asString(data['pledge'])),
      pledgeType: _nullableValue(_asString(data['pledgeType'])),
      note: _nullableValue(_asString(data['note'])),
      serverId: _nullableValue(_asInt(data['serverId'])),
      createdAt: d.Value(_asInt(data['createdAt']) ?? Time.nowEpoch()),
      updatedAt: d.Value(_asInt(data['updatedAt']) ?? Time.nowEpoch()),
      lastModified: d.Value(_asInt(data['lastModified']) ?? Time.nowEpoch()),
      version: d.Value(_asInt(data['version']) ?? 1),
      origin: d.Value(_asString(data['origin']) ?? 'appwrite_delta'),
      deletedAt: _nullableValue(_asInt(data['deletedAt'])),
      vectorClock: _nullableValue(_asString(data['vectorClock'])),
    );
    await db.into(db.debts).insertOnConflictUpdate(companion);
  }

  Future<void> _upsertEmployee(AppDatabase db, String uuid, Map<String, dynamic> data) async {
    final companion = EmployeesCompanion(
      localUuid: d.Value(_asString(data['localUuid']) ?? uuid),
      name: d.Value(_asString(data['name']) ?? ''),
      basicSalary: d.Value(_asDouble(data['basicSalary'])),
      position: d.Value(_asString(data['position']) ?? ''),
      phone: d.Value(_asString(data['phone']) ?? ''),
      hireDate: d.Value(_asString(data['hireDate']) ?? ''),
      status: d.Value(_asString(data['status']) ?? 'active'),
      serverId: _nullableValue(_asInt(data['serverId'])),
      createdAt: d.Value(_asInt(data['createdAt']) ?? Time.nowEpoch()),
      updatedAt: d.Value(_asInt(data['updatedAt']) ?? Time.nowEpoch()),
      lastModified: d.Value(_asInt(data['lastModified']) ?? Time.nowEpoch()),
      version: d.Value(_asInt(data['version']) ?? 1),
      origin: d.Value(_asString(data['origin']) ?? 'appwrite_delta'),
      deletedAt: _nullableValue(_asInt(data['deletedAt'])),
      vectorClock: _nullableValue(_asString(data['vectorClock'])),
    );
    await db.into(db.employees).insertOnConflictUpdate(companion);
  }

  Future<void> _upsertCashTransaction(AppDatabase db, String uuid, Map<String, dynamic> data) async {
    final companion = CashTransactionsCompanion(
      localUuid: d.Value(_asString(data['localUuid']) ?? uuid),
      transactionType: d.Value(_asString(data['transactionType']) ?? ''),
      amount: d.Value(_asDouble(data['amount'])),
      transactionTime: d.Value(_asString(data['transactionTime']) ?? ''),
      description: _nullableValue(_asString(data['description'])),
      relatedEntityType: _nullableValue(_asString(data['relatedEntityType'])),
      relatedEntityId: _nullableValue(_asString(data['relatedEntityId'])),
      shiftDate: d.Value(_asString(data['shiftDate']) ?? ''),
      serverId: _nullableValue(_asInt(data['serverId'])),
      createdAt: d.Value(_asInt(data['createdAt']) ?? Time.nowEpoch()),
      updatedAt: d.Value(_asInt(data['updatedAt']) ?? Time.nowEpoch()),
      lastModified: d.Value(_asInt(data['lastModified']) ?? Time.nowEpoch()),
      version: d.Value(_asInt(data['version']) ?? 1),
      origin: d.Value(_asString(data['origin']) ?? 'appwrite_delta'),
      deletedAt: _nullableValue(_asInt(data['deletedAt'])),
      vectorClock: _nullableValue(_asString(data['vectorClock'])),
    );
    await db.into(db.cashTransactions).insertOnConflictUpdate(companion);
  }

  Future<void> _upsertSalaryCycle(AppDatabase db, String uuid, Map<String, dynamic> data) async {
    final companion = SalaryCyclesCompanion(
      localUuid: d.Value(_asString(data['localUuid']) ?? uuid),
      employeeId: d.Value(_asInt(data['employeeId']) ?? 0),
      cycleKey: d.Value(_asString(data['cycleKey']) ?? ''),
      expectedAmount: d.Value(_asDouble(data['expectedAmount'])),
      paidAmount: d.Value(_asDouble(data['paidAmount'])),
      startDate: d.Value(_asString(data['startDate']) ?? ''),
      endDate: d.Value(_asString(data['endDate']) ?? ''),
      status: d.Value(_asString(data['status']) ?? 'pending'),
      serverId: _nullableValue(_asInt(data['serverId'])),
      createdAt: d.Value(_asInt(data['createdAt']) ?? Time.nowEpoch()),
      updatedAt: d.Value(_asInt(data['updatedAt']) ?? Time.nowEpoch()),
      lastModified: d.Value(_asInt(data['lastModified']) ?? Time.nowEpoch()),
      version: d.Value(_asInt(data['version']) ?? 1),
      origin: d.Value(_asString(data['origin']) ?? 'appwrite_delta'),
      vectorClock: _nullableValue(_asString(data['vectorClock'])),
    );
    await db.into(db.salaryCycles).insertOnConflictUpdate(companion);
  }

  Future<void> _upsertSalaryPayment(AppDatabase db, String uuid, Map<String, dynamic> data) async {
    final companion = SalaryPaymentsCompanion(
      localUuid: d.Value(_asString(data['localUuid']) ?? uuid),
      cycleId: d.Value(_asInt(data['cycleId']) ?? 0),
      amount: d.Value(_asDouble(data['amount'])),
      paymentDateIso: d.Value(_asString(data['paymentDateIso']) ?? ''),
      notes: _nullableValue(_asString(data['notes'])),
      serverId: _nullableValue(_asInt(data['serverId'])),
      createdAt: d.Value(_asInt(data['createdAt']) ?? Time.nowEpoch()),
      updatedAt: d.Value(_asInt(data['updatedAt']) ?? Time.nowEpoch()),
      lastModified: d.Value(_asInt(data['lastModified']) ?? Time.nowEpoch()),
      version: d.Value(_asInt(data['version']) ?? 1),
      origin: d.Value(_asString(data['origin']) ?? 'appwrite_delta'),
      vectorClock: _nullableValue(_asString(data['vectorClock'])),
    );
    await db.into(db.salaryPayments).insertOnConflictUpdate(companion);
  }

  Future<void> _upsertSalaryWithdrawal(AppDatabase db, String uuid, Map<String, dynamic> data) async {
    final companion = SalaryWithdrawalsCompanion(
      localUuid: d.Value(_asString(data['localUuid']) ?? uuid),
      employeeId: d.Value(_asInt(data['employeeId']) ?? 0),
      amount: d.Value(_asDouble(data['amount'])),
      date: d.Value(_asString(data['date']) ?? ''),
      reason: _nullableValue(_asString(data['reason'])),
      serverId: _nullableValue(_asInt(data['serverId'])),
      createdAt: d.Value(_asInt(data['createdAt']) ?? Time.nowEpoch()),
      updatedAt: d.Value(_asInt(data['updatedAt']) ?? Time.nowEpoch()),
      lastModified: d.Value(_asInt(data['lastModified']) ?? Time.nowEpoch()),
      version: d.Value(_asInt(data['version']) ?? 1),
      origin: d.Value(_asString(data['origin']) ?? 'appwrite_delta'),
      vectorClock: _nullableValue(_asString(data['vectorClock'])),
    );
    await db.into(db.salaryWithdrawals).insertOnConflictUpdate(companion);
  }

  Future<void> _upsertShiftNote(AppDatabase db, String uuid, Map<String, dynamic> data) async {
    final companion = ShiftNotesCompanion(
      localUuid: d.Value(_asString(data['localUuid']) ?? uuid),
      title: d.Value(_asString(data['title']) ?? ''),
      content: d.Value(_asString(data['content']) ?? ''),
      noteType: d.Value(_asString(data['noteType']) ?? 'general'),
      shiftDate: d.Value(_asString(data['shiftDate']) ?? ''),
      createdBy: d.Value(_asString(data['createdBy']) ?? ''),
      serverId: _nullableValue(_asInt(data['serverId'])),
      createdAt: d.Value(_asInt(data['createdAt']) ?? Time.nowEpoch()),
      updatedAt: d.Value(_asInt(data['updatedAt']) ?? Time.nowEpoch()),
      lastModified: d.Value(_asInt(data['lastModified']) ?? Time.nowEpoch()),
      version: d.Value(_asInt(data['version']) ?? 1),
      origin: d.Value(_asString(data['origin']) ?? 'appwrite_delta'),
      vectorClock: _nullableValue(_asString(data['vectorClock'])),
    );
    await db.into(db.shiftNotes).insertOnConflictUpdate(companion);
  }

  Future<void> _upsertPriceAdjustment(AppDatabase db, String uuid, Map<String, dynamic> data) async {
    final companion = PriceAdjustmentsCompanion(
      localUuid: d.Value(_asString(data['localUuid']) ?? uuid),
      targetType: d.Value(_asString(data['targetType']) ?? ''),
      targetUuid: d.Value(_asString(data['targetUuid']) ?? ''),
      adjustmentType: d.Value(_asString(data['adjustmentType']) ?? ''),
      newValue: d.Value(_asDouble(data['newValue'])),
      reason: _nullableValue(_asString(data['reason'])),
      serverId: _nullableValue(_asInt(data['serverId'])),
      createdAt: d.Value(_asInt(data['createdAt']) ?? Time.nowEpoch()),
      updatedAt: d.Value(_asInt(data['updatedAt']) ?? Time.nowEpoch()),
      lastModified: d.Value(_asInt(data['lastModified']) ?? Time.nowEpoch()),
      version: d.Value(_asInt(data['version']) ?? 1),
      origin: d.Value(_asString(data['origin']) ?? 'appwrite_delta'),
      vectorClock: _nullableValue(_asString(data['vectorClock'])),
    );
    await db.into(db.priceAdjustments).insertOnConflictUpdate(companion);
  }

  Future<void> _upsertBookingPriceAdjustment(AppDatabase db, String uuid, Map<String, dynamic> data) async {
    final companion = BookingPriceAdjustmentsCompanion(
      localUuid: d.Value(_asString(data['localUuid']) ?? uuid),
      bookingLocalUuid: d.Value(_asString(data['bookingLocalUuid']) ?? ''),
      adjustmentType: d.Value(_asString(data['adjustmentType']) ?? ''),
      amount: d.Value(_asDouble(data['amount'])),
      reason: _nullableValue(_asString(data['reason'])),
      serverId: _nullableValue(_asInt(data['serverId'])),
      createdAt: d.Value(_asInt(data['createdAt']) ?? Time.nowEpoch()),
      updatedAt: d.Value(_asInt(data['updatedAt']) ?? Time.nowEpoch()),
      lastModified: d.Value(_asInt(data['lastModified']) ?? Time.nowEpoch()),
      version: d.Value(_asInt(data['version']) ?? 1),
      origin: d.Value(_asString(data['origin']) ?? 'appwrite_delta'),
      vectorClock: _nullableValue(_asString(data['vectorClock'])),
    );
    await db.into(db.bookingPriceAdjustments).insertOnConflictUpdate(companion);
  }

  Future<void> _upsertAuditLog(AppDatabase db, String uuid, Map<String, dynamic> data) async {
    final companion = AuditLogsCompanion(
      localUuid: d.Value(_asString(data['localUuid']) ?? uuid),
      operationType: d.Value(_asString(data['operationType']) ?? ''),
      entityType: d.Value(_asString(data['entityType']) ?? ''),
      entityUuid: d.Value(_asString(data['entityUuid']) ?? ''),
      oldValues: _nullableValue(_asString(data['oldValues'])),
      newValues: _nullableValue(_asString(data['newValues'])),
      changedBy: d.Value(_asString(data['changedBy']) ?? ''),
      changedAt: d.Value(_asInt(data['changedAt']) ?? Time.nowEpoch()),
      serverId: _nullableValue(_asInt(data['serverId'])),
      createdAt: d.Value(_asInt(data['createdAt']) ?? Time.nowEpoch()),
      updatedAt: d.Value(_asInt(data['updatedAt']) ?? Time.nowEpoch()),
      lastModified: d.Value(_asInt(data['lastModified']) ?? Time.nowEpoch()),
      version: d.Value(_asInt(data['version']) ?? 1),
      origin: d.Value(_asString(data['origin']) ?? 'appwrite_delta'),
      vectorClock: _nullableValue(_asString(data['vectorClock'])),
    );
    await db.into(db.auditLogs).insertOnConflictUpdate(companion);
  }

  Future<void> _upsertPaymentVoid(AppDatabase db, String uuid, Map<String, dynamic> data) async {
    final companion = PaymentVoidsCompanion(
      localUuid: d.Value(_asString(data['localUuid']) ?? uuid),
      originalPaymentUuid: d.Value(_asString(data['originalPaymentUuid']) ?? ''),
      voidedAmount: d.Value(_asDouble(data['voidedAmount'])),
      voidReason: d.Value(_asString(data['voidReason']) ?? ''),
      voidedBy: d.Value(_asString(data['voidedBy']) ?? ''),
      voidedAt: d.Value(_asInt(data['voidedAt']) ?? Time.nowEpoch()),
      serverId: _nullableValue(_asInt(data['serverId'])),
      createdAt: d.Value(_asInt(data['createdAt']) ?? Time.nowEpoch()),
      updatedAt: d.Value(_asInt(data['updatedAt']) ?? Time.nowEpoch()),
      lastModified: d.Value(_asInt(data['lastModified']) ?? Time.nowEpoch()),
      version: d.Value(_asInt(data['version']) ?? 1),
      origin: d.Value(_asString(data['origin']) ?? 'appwrite_delta'),
      vectorClock: _nullableValue(_asString(data['vectorClock'])),
    );
    await db.into(db.paymentVoids).insertOnConflictUpdate(companion);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // حل FK (Foreign Key Resolution)
  // ═══════════════════════════════════════════════════════════════════════════

  Future<int?> _resolveBookingId(AppDatabase db, Map<String, dynamic> data) async {
    final bookingUuid = _asString(data['bookingLocalUuid'] ?? data['bookingUuid']);
    if (bookingUuid != null && bookingUuid.isNotEmpty) {
      final booking = await (db.select(db.bookings)..where((t) => t.localUuid.equals(bookingUuid)))
          .getSingleOrNull();
      if (booking != null) return booking.id;
    }

    final bookingId = _asInt(data['bookingLocalId'] ?? data['bookingId']);
    if (bookingId != null && bookingId > 0) {
      final booking = await (db.select(db.bookings)..where((t) => t.id.equals(bookingId)))
          .getSingleOrNull();
      if (booking != null) return bookingId;
    }

    final serverBookingId = _asInt(data['serverBookingId'] ?? data['bookingServerId']);
    if (serverBookingId != null && serverBookingId > 0) {
      final booking = await (db.select(db.bookings)..where((t) => t.serverId.equals(serverBookingId)))
          .getSingleOrNull();
      if (booking != null) return booking.id;
    }

    final roomNumber = _asString(data['roomNumber']);
    if (roomNumber != null && roomNumber.isNotEmpty) {
      final booking = await (db.select(db.bookings)
            ..where((t) =>
                t.roomNumber.equals(roomNumber) & t.status.equals('checked_in')))
          .getSingleOrNull();
      if (booking != null) return booking.id;
    }

    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // المساعدات (Helpers)
  // ═══════════════════════════════════════════════════════════════════════════

  void _ensureInitialized() {
    if (!_isInitialized) throw StateError('AppwriteDeltaSync not initialized');
  }

  bool _checkReady() => _isInitialized && _appwriteService != null && _outboxDao != null;

  Future<bool> _isOnline() async {
    final result = await _connectivity.checkConnectivity();
    return !result.contains(ConnectivityResult.none);
  }

  Future<void> _saveDeltaToOutbox(EntityDelta delta) async {
    await _outboxDao!.merge(
      entity: delta.entity,
      op: delta.operation.name,
      localUuid: delta.uuid,
      payload: delta.toJson(),
      clientTs: delta.timestamp,
    );
  }

  Map<String, dynamic> _sanitizePayload(Map<String, dynamic> payload) {
    return payload.map((key, value) {
      if (value == null) return MapEntry(key, null);
      return MapEntry(key, value);
    });
  }

  void _addErrorRecord(String entity, String localUuid, String operation, String errorMessage,
      int retryCount) {
    final existingIndex = _syncErrors.indexWhere(
        (e) => e.entity == entity && e.localUuid == localUuid);

    if (existingIndex >= 0) {
      _syncErrors[existingIndex] = SyncErrorRecord(
        entity: entity,
        localUuid: localUuid,
        operation: operation,
        errorMessage: errorMessage,
        retryCount: retryCount,
        createdAt: _syncErrors[existingIndex].createdAt,
        lastAttemptAt: DateTime.now(),
      );
    } else {
      _syncErrors.add(SyncErrorRecord(
        entity: entity,
        localUuid: localUuid,
        operation: operation,
        errorMessage: errorMessage,
        retryCount: retryCount,
        createdAt: DateTime.now(),
        lastAttemptAt: DateTime.now(),
      ));
    }

    final isPushOperation = operation.toLowerCase().contains('push') ||
        operation.toLowerCase().contains('create') ||
        operation.toLowerCase().contains('update') ||
        operation.toLowerCase().contains('delete');

    if (isPushOperation) {
      _logger.pushError(
        'خطأ مزامنة تفاضلية: $entity ($operation) - $errorMessage',
        error: errorMessage,
        entity: entity,
        recordId: localUuid,
        retryCount: retryCount,
      );
    } else {
      _logger.pullError(
        'خطأ مزامنة تفاضلية: $entity ($operation) - $errorMessage',
        error: errorMessage,
        entity: entity,
        recordId: localUuid,
        retryCount: retryCount,
      );
    }

    while (_syncErrors.length > 100) {
      _syncErrors.removeAt(0);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // مساعدات الأنواع (Type Helpers)
  // ═══════════════════════════════════════════════════════════════════════════

  d.Value<T?> _nullableValue<T>(T? value) =>
      value == null ? const d.Value.absent() : d.Value(value);

  int? _asInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? double.tryParse(value)?.toInt();
    return null;
  }

  double _asDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  String? _asString(dynamic value) {
    if (value == null) return null;
    final s = value.toString();
    return s.isEmpty ? null : s;
  }

  bool _asBool(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is int) return value != 0;
    if (value is String) return value.toLowerCase() == 'true' || value == '1';
    return false;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // الحالة والإحصائيات (Status & Stats)
  // ═══════════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> getStatus() async {
    final pending = await _outboxDao?.count() ?? 0;

    return {
      'initialized': _isInitialized,
      'is_syncing': _isSyncing,
      'device_id': _deviceId,
      'outbox_pending': pending,
      'is_online': await _isOnline(),
      'last_sync': _lastSyncTimestamp,
      'cache_size': _stateCache.length,
      'supported_entities': SyncEntityRegistry.allEntities.length,
    };
  }

  Future<void> clearErrors() async {
    await _outboxDao?.resetErrors();
  }

  void dispose() {
    _syncStateController.close();
    _progressController.close();
    _errorsController.close();
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// فئات مساعدة (Helper Classes)
// ═══════════════════════════════════════════════════════════════════════════════

/// ⭐ نتيجة السحب
class _PullResult {
  _PullResult({this.applied = 0, this.skipped = 0, this.conflicts = const []});
  final int applied;
  final int skipped;
  final List<ConflictInfo> conflicts;
}

/// ⭐ نتيجة التطبيق
class _ApplyResult {
  _ApplyResult({this.applied = false, this.skipped = false, this.conflicts = const []});
  final bool applied;
  final bool skipped;
  final List<ConflictInfo> conflicts;
}

// ═══════════════════════════════════════════════════════════════════════════════
// قسم 5: Offline Queue المحسّن (Enhanced Offline Queue)
// ═══════════════════════════════════════════════════════════════════════════════

/// ⭐ عنصر الطابور المحسّن
class OfflineQueueItem {
  const OfflineQueueItem({
    required this.id,
    required this.delta,
    required this.status,
    required this.createdAt,
    required this.priorityScore,
    this.retryCount = 0,
    this.lastAttemptAt,
    this.nextRetryAt,
    this.lastError,
  });

  factory OfflineQueueItem.fromJson(Map<String, dynamic> json) {
    return OfflineQueueItem(
      id: json['id'] as String,
      delta: EntityDelta.fromJson(json['delta'] as Map<String, dynamic>),
      status: OfflineQueueStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => OfflineQueueStatus.pending,
      ),
      retryCount: json['retryCount'] as int? ?? 0,
      createdAt: json['createdAt'] as int? ?? 0,
      lastAttemptAt: json['lastAttemptAt'] as int?,
      nextRetryAt: json['nextRetryAt'] as int?,
      lastError: json['lastError'] as String?,
      priorityScore: json['priorityScore'] as int? ?? 0,
    );
  }

  final String id;
  final EntityDelta delta;
  final OfflineQueueStatus status;
  final int retryCount;
  final int createdAt;
  final int? lastAttemptAt;
  final int? nextRetryAt;
  final String? lastError;
  final int priorityScore;

  static int calculatePriorityScore(EntityDelta delta) {
    int score = 0;

    score += switch (delta.priority) {
      SyncPriority.critical => 1000,
      SyncPriority.high => 500,
      SyncPriority.normal => 100,
      SyncPriority.low => 10,
    };

    score += switch (delta.operation) {
      OperationType.create => 50,
      OperationType.update => 30,
      OperationType.delete => 40,
      OperationType.noop => 0,
    };

    return score;
  }

  int getBackoffDelay() {
    const baseDelay = 5;
    const maxDelay = 300;
    final delay = baseDelay * (1 << retryCount.clamp(0, 8));
    return delay.clamp(baseDelay, maxDelay);
  }

  OfflineQueueItem copyWith({
    OfflineQueueStatus? status,
    int? retryCount,
    int? lastAttemptAt,
    int? nextRetryAt,
    String? lastError,
  }) {
    return OfflineQueueItem(
      id: id,
      delta: delta,
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
      createdAt: createdAt,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      nextRetryAt: nextRetryAt ?? this.nextRetryAt,
      lastError: lastError ?? this.lastError,
      priorityScore: priorityScore,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'delta': delta.toJson(),
        'status': status.name,
        'retryCount': retryCount,
        'createdAt': createdAt,
        'lastAttemptAt': lastAttemptAt,
        'nextRetryAt': nextRetryAt,
        'lastError': lastError,
        'priorityScore': priorityScore,
      };
}

enum OfflineQueueStatus {
  pending,
  processing,
  completed,
  failed,
  waitingRetry,
}

class OfflineQueueManager {
  final _items = <OfflineQueueItem>[];
  final _logger = AppwriteLogger();

  static const int maxRetries = 5;
  static const int maxQueueSize = 1000;
  static const int itemExpirySeconds = 86400;

  Future<void> enqueue(EntityDelta delta) async {
    if (_items.length >= maxQueueSize) {
      _purgeOldItems();
    }

    final item = OfflineQueueItem(
      id: const Uuid().v4(),
      delta: delta,
      status: OfflineQueueStatus.pending,
      createdAt: Time.nowEpoch(),
      priorityScore: OfflineQueueItem.calculatePriorityScore(delta),
    );

    final insertIndex = _items.indexWhere((i) => i.priorityScore < item.priorityScore);
    if (insertIndex == -1) {
      _items.add(item);
    } else {
      _items.insert(insertIndex, item);
    }

    _logger.info('📥 Queued: ${delta.entity}/${delta.uuid} (priority: ${item.priorityScore})',
        tag: 'OFFLINE_QUEUE');
  }

  List<OfflineQueueItem> getReadyItems({int limit = 50}) {
    final now = Time.nowEpoch();

    return _items
        .where((item) =>
            item.status == OfflineQueueStatus.pending ||
            (item.status == OfflineQueueStatus.waitingRetry &&
                (item.nextRetryAt == null || item.nextRetryAt! <= now)))
        .take(limit)
        .toList();
  }

  void updateItem(OfflineQueueItem updatedItem) {
    final index = _items.indexWhere((i) => i.id == updatedItem.id);
    if (index != -1) {
      _items[index] = updatedItem;
    }
  }

  void markCompleted(String id) {
    final index = _items.indexWhere((i) => i.id == id);
    if (index != -1) {
      _items.removeAt(index);
      _logger.info('✅ Queue item completed: $id', tag: 'OFFLINE_QUEUE');
    }
  }

  void markFailed(String id, String error) {
    final index = _items.indexWhere((i) => i.id == id);
    if (index != -1) {
      final item = _items[index];
      final newRetryCount = item.retryCount + 1;

      if (newRetryCount >= maxRetries) {
        _items.removeAt(index);
        _logger.error('❌ Queue item failed permanently: $id - $error', tag: 'OFFLINE_QUEUE');
      } else {
        final now = Time.nowEpoch();
        _items[index] = item.copyWith(
          status: OfflineQueueStatus.waitingRetry,
          retryCount: newRetryCount,
          lastAttemptAt: now,
          nextRetryAt: now + item.getBackoffDelay(),
          lastError: error,
        );
        _logger.warning(
            '⚠️ Queue item failed, will retry: $id (attempt $newRetryCount/$maxRetries)',
            tag: 'OFFLINE_QUEUE');
      }
    }
  }

  void _purgeOldItems() {
    final now = Time.nowEpoch();
    final cutoff = now - itemExpirySeconds;

    _items.removeWhere(
        (item) => item.createdAt < cutoff && item.status != OfflineQueueStatus.pending);

    _logger.info('🧹 Purged old queue items', tag: 'OFFLINE_QUEUE');
  }

  Map<String, int> getStats() {
    return {
      'total': _items.length,
      'pending': _items.where((i) => i.status == OfflineQueueStatus.pending).length,
      'processing': _items.where((i) => i.status == OfflineQueueStatus.processing).length,
      'waitingRetry': _items.where((i) => i.status == OfflineQueueStatus.waitingRetry).length,
      'failed': _items.where((i) => i.status == OfflineQueueStatus.failed).length,
    };
  }

  void clear() {
    _items.clear();
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// قسم 6: ضغط البيانات (Data Compression)
// ═══════════════════════════════════════════════════════════════════════════════

class SyncDataCompressor {
  static Map<String, dynamic> compress(EntityDelta delta) {
    final compressed = <String, dynamic>{
      'e': delta.entity,
      'u': delta.uuid,
      'o': delta.operation.code,
      'v': delta.version,
      't': delta.timestamp,
    };

    if (delta.fieldDeltas.isNotEmpty) {
      compressed['d'] = _compressFieldDeltas(delta.fieldDeltas);
    }

    if (delta.parentUuid != null) {
      compressed['p'] = delta.parentUuid;
    }

    compressed['b'] = delta.deviceId;
    compressed['pr'] = delta.priority.index;
    compressed['vc'] = delta.vectorClock.toJson();

    return compressed;
  }

  static List<Map<String, dynamic>> _compressFieldDeltas(List<FieldDelta> deltas) {
    return deltas.map((d) => {
          'f': d.fieldName,
          'n': d.newValue,
          't': d.changedAt,
          if (d.oldValue != null) 'o': d.oldValue,
        }).toList();
  }

  static EntityDelta decompress(Map<String, dynamic> compressed) {
    final fieldDeltas = (compressed['d'] as List<dynamic>?)
            ?.map((d) => FieldDelta(
                  fieldName: d['f'] as String,
                  newValue: d['n'],
                  changedAt: d['t'] as int? ?? 0,
                  oldValue: d['o'],
                ))
            .toList() ??
        [];

    return EntityDelta(
      entity: compressed['e'] as String,
      uuid: compressed['u'] as String,
      operation: OperationType.fromCode(compressed['o'] as String? ?? 'U'),
      fieldDeltas: fieldDeltas,
      version: compressed['v'] as int? ?? 1,
      timestamp: compressed['t'] as int? ?? 0,
      parentUuid: compressed['p'] as String?,
      deviceId: compressed['b'] as String? ?? '',
      priority: SyncPriority.values[compressed['pr'] as int? ?? 2],
      vectorClock: VectorClock.fromJson(compressed['vc'] as String?),
    );
  }

  static double calculateCompressionRatio(
      Map<String, dynamic> original, Map<String, dynamic> compressed) {
    final originalSize = jsonEncode(original).length;
    final compressedSize = jsonEncode(compressed).length;

    if (originalSize == 0) return 0;
    return ((originalSize - compressedSize) / originalSize) * 100;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// قسم 7: ملحقات الخدمة (Service Extensions)
// ═══════════════════════════════════════════════════════════════════════════════

extension AppwriteDeltaSyncExtensions on AppwriteDeltaSync {
  Future<SyncResult> syncCritical() async {
    return sync();
  }

  Future<int> getPendingChangesCount() async {
    final status = await getStatus();
    return status['outbox_pending'] as int? ?? 0;
  }

  Future<bool> hasPendingChanges() async {
    return await getPendingChangesCount() > 0;
  }

  void syncInBackground() {
    sync().then((result) {
      if (result.success) {
        AppwriteLogger().info('🔄 Background sync completed', tag: 'BG_SYNC');
      } else {
        AppwriteLogger().warning('⚠️ Background sync failed: ${result.message}', tag: 'BG_SYNC');
      }
    }).catchError((e) {
      AppwriteLogger().error('❌ Background sync error: $e', tag: 'BG_SYNC');
    });
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// قسم 8: مراقب المزامنة (Sync Monitor)
// ═══════════════════════════════════════════════════════════════════════════════

class SyncMonitor {
  factory SyncMonitor() => _instance;
  SyncMonitor._internal();
  static final SyncMonitor _instance = SyncMonitor._internal();

  final _metrics = <String, dynamic>{};
  final _events = <SyncEvent>[];
  final _logger = AppwriteLogger();

  static const int maxEvents = 100;

  void recordEvent(SyncEvent event) {
    _events.add(event);
    if (_events.length > maxEvents) {
      _events.removeAt(0);
    }

    _updateMetrics(event);
  }

  void _updateMetrics(SyncEvent event) {
    _metrics['last_sync_time'] = event.timestamp;
    _metrics['total_syncs'] = (_metrics['total_syncs'] as int? ?? 0) + 1;

    if (event.success) {
      _metrics['successful_syncs'] = (_metrics['successful_syncs'] as int? ?? 0) + 1;
    } else {
      _metrics['failed_syncs'] = (_metrics['failed_syncs'] as int? ?? 0) + 1;
    }

    _metrics['total_records_synced'] =
        (_metrics['total_records_synced'] as int? ?? 0) + event.recordsCount;
  }

  Map<String, dynamic> getMetrics() => Map.from(_metrics);

  List<SyncEvent> getRecentEvents({int limit = 20}) {
    return _events.reversed.take(limit).toList();
  }

  double get successRate {
    final total = _metrics['total_syncs'] as int? ?? 0;
    if (total == 0) return 0;

    final successful = _metrics['successful_syncs'] as int? ?? 0;
    return (successful / total) * 100;
  }
}

class SyncEvent {
  const SyncEvent({
    required this.type,
    required this.success,
    required this.timestamp,
    this.recordsCount = 0,
    this.duration,
    this.error,
  });

  final String type;
  final bool success;
  final int recordsCount;
  final Duration? duration;
  final String? error;
  final DateTime timestamp;
}
