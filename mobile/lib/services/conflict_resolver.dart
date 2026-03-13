import 'package:flutter/foundation.dart';
import 'vector_clock.dart';

enum ConflictStrategy {
  lastWriteWins,
  firstWriteWins,
  manualResolve,
  fieldLevel,
  customPriority,
}

class ConflictResolution {
  const ConflictResolution({
    required this.winner,
    required this.strategy,
    this.mergedData,
    this.needsManualReview = false,
  });

  final Map<String, dynamic> winner;
  final ConflictStrategy strategy;
  final Map<String, dynamic>? mergedData;
  final bool needsManualReview;
}

class ConflictContext {
  const ConflictContext({
    required this.table,
    required this.uuid,
    required this.localData,
    required this.remoteData,
    this.localVectorClock,
    this.remoteVectorClock,
    required this.localTimestamp,
    required this.remoteTimestamp,
    required this.localDeviceId,
    required this.remoteDeviceId,
    this.localDevicePriority = 100,
    this.remoteDevicePriority = 100,
  });

  final String table;
  final String uuid;
  final Map<String, dynamic> localData;
  final Map<String, dynamic> remoteData;
  final VectorClock? localVectorClock;
  final VectorClock? remoteVectorClock;
  final DateTime localTimestamp;
  final DateTime remoteTimestamp;
  final String localDeviceId;
  final String remoteDeviceId;
  final int localDevicePriority;
  final int remoteDevicePriority;
}

/// محلل تعارضات متقدم مع استراتيجيات متعددة
class EnhancedConflictResolver {
  EnhancedConflictResolver({
    this.defaultStrategy = ConflictStrategy.lastWriteWins,
    this.tableStrategies = const {},
    this.tableHooks = const {},
    this.devicePriorityResolver,
    this.criticalFieldsOverrides = const {},
  });

  final ConflictStrategy defaultStrategy;
  final Map<String, ConflictStrategy> tableStrategies;
  final Map<String, ConflictResolution Function(ConflictContext)> tableHooks;
  final int Function(String deviceId)? devicePriorityResolver;
  final Map<String, Set<String>> criticalFieldsOverrides;

  ConflictResolution resolve(ConflictContext context) {
    final hook = tableHooks[context.table];
    if (hook != null) {
      return hook(context);
    }

    final strategy = tableStrategies[context.table] ?? defaultStrategy;

    if (context.localVectorClock != null && context.remoteVectorClock != null) {
      final vectorResult = _resolveWithVectorClock(context);
      if (vectorResult != null) return vectorResult;
    }

    switch (strategy) {
      case ConflictStrategy.lastWriteWins:
        return _lastWriteWins(context);
      case ConflictStrategy.firstWriteWins:
        return _firstWriteWins(context);
      case ConflictStrategy.fieldLevel:
        return _fieldLevelMerge(context);
      case ConflictStrategy.customPriority:
        return _customPriority(context);
      case ConflictStrategy.manualResolve:
        return ConflictResolution(
          winner: context.localData,
          strategy: strategy,
          needsManualReview: true,
        );
    }
  }

  ConflictResolution? _resolveWithVectorClock(ConflictContext context) {
    final localClock = context.localVectorClock!;
    final remoteClock = context.remoteVectorClock!;

    final comparison = localClock.compare(remoteClock);

    switch (comparison) {
      case 'equal':
        return ConflictResolution(
          winner: context.remoteData,
          strategy: ConflictStrategy.lastWriteWins,
        );
      case 'before':
        return ConflictResolution(
          winner: context.remoteData,
          strategy: ConflictStrategy.lastWriteWins,
        );
      case 'after':
        return ConflictResolution(
          winner: context.localData,
          strategy: ConflictStrategy.lastWriteWins,
        );
      case 'concurrent':
        debugPrint('⚠️ تعارض حقيقي: ${context.table}/${context.uuid}');
        return _handleConcurrentConflict(context);
    }
    return null;
  }

  ConflictResolution _handleConcurrentConflict(ConflictContext context) {
    final timeDiff =
        context.localTimestamp.difference(context.remoteTimestamp).abs();

    if (timeDiff.inSeconds < 30) {
      debugPrint(
        '🔀 تعارض متزامن (${timeDiff.inSeconds}s) - استخدام field-level merge',
      );
      return _fieldLevelMerge(context);
    }

    debugPrint('🔀 تعارض متزامن - استخدام last-write-wins');
    return _lastWriteWins(context);
  }

  ConflictResolution _lastWriteWins(ConflictContext context) {
    final localNewer = context.localTimestamp.isAfter(context.remoteTimestamp);

    if (localNewer) {
      return ConflictResolution(
        winner: context.localData,
        strategy: ConflictStrategy.lastWriteWins,
      );
    } else if (context.remoteTimestamp.isAfter(context.localTimestamp)) {
      return ConflictResolution(
        winner: context.remoteData,
        strategy: ConflictStrategy.lastWriteWins,
      );
    }

    final localPriority = _priorityForDevice(
      context.localDeviceId,
      context.localDevicePriority,
    );
    final remotePriority = _priorityForDevice(
      context.remoteDeviceId,
      context.remoteDevicePriority,
    );

    if (localPriority >= remotePriority) {
      return ConflictResolution(
        winner: context.localData,
        strategy: ConflictStrategy.customPriority,
      );
    } else {
      return ConflictResolution(
        winner: context.remoteData,
        strategy: ConflictStrategy.customPriority,
      );
    }
  }

  ConflictResolution _firstWriteWins(ConflictContext context) {
    final localOlder = context.localTimestamp.isBefore(context.remoteTimestamp);

    return ConflictResolution(
      winner: localOlder ? context.localData : context.remoteData,
      strategy: ConflictStrategy.firstWriteWins,
    );
  }

  ConflictResolution _fieldLevelMerge(ConflictContext context) {
    final merged = Map<String, dynamic>.from(context.localData);

    final criticalFields = _getCriticalFields(context.table);
    // ⭐ تم تحويل الحقول إلى camelCase للتوافق مع Appwrite
    final systemFields = {
      'localUuid',
      'serverId',
      'createdAt',
      'createdAtIso',
      'createdAtEpoch',
      'version',
      'origin',
      'vectorClock',
      // دعم snake_case للتوافق مع البيانات القديمة
      'localUuid',
      'serverId',
      'createdAt',
      'createdAtIso',
      'createdAtEpoch',
      'vectorClock',
    };

    for (final key in context.remoteData.keys) {
      if (systemFields.contains(key)) continue;

      final localValue = context.localData[key];
      final remoteValue = context.remoteData[key];

      if (localValue == remoteValue) continue;

      if (criticalFields.contains(key)) {
        if (context.remoteTimestamp.isAfter(context.localTimestamp)) {
          merged[key] = remoteValue;
        }
      } else {
        if (remoteValue != null &&
            (localValue == null ||
                context.remoteTimestamp.isAfter(context.localTimestamp))) {
          merged[key] = remoteValue;
        }
      }
    }

    // ⭐ استخدام camelCase للتوافق مع Appwrite
    merged['lastModified'] = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    merged['updatedAt'] = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    merged['updatedAtIso'] = DateTime.now().toUtc().toIso8601String();
    // دعم snake_case للتوافق مع البيانات القديمة
    merged['lastModified'] = merged['lastModified'];
    merged['updatedAt'] = merged['updatedAt'];
    merged['updatedAtIso'] = merged['updatedAtIso'];

    return ConflictResolution(
      winner: merged,
      strategy: ConflictStrategy.fieldLevel,
      mergedData: merged,
    );
  }

  ConflictResolution _customPriority(ConflictContext context) {
    final localPriority = _priorityForDevice(
      context.localDeviceId,
      context.localDevicePriority,
    );
    final remotePriority = _priorityForDevice(
      context.remoteDeviceId,
      context.remoteDevicePriority,
    );

    if (localPriority > remotePriority) {
      return ConflictResolution(
        winner: context.localData,
        strategy: ConflictStrategy.customPriority,
      );
    } else if (remotePriority > localPriority) {
      return ConflictResolution(
        winner: context.remoteData,
        strategy: ConflictStrategy.customPriority,
      );
    }

    return _lastWriteWins(context);
  }

  int _priorityForDevice(String deviceId, int fallback) {
    if (devicePriorityResolver == null) return fallback;
    return devicePriorityResolver!(deviceId);
  }

  Set<String> _getCriticalFields(String table) {
    final override = criticalFieldsOverrides[table];
    if (override != null) {
      return override;
    }

    // ⭐ تم تحويل جميع الحقول إلى camelCase للتوافق مع Appwrite
    const fieldsByTable = <String, Set<String>>{
      'bookings': {
        'status',
        'checkoutDate', 'checkout_date',
        'actualCheckout', 'actual_checkout',
        'roomNumber', 'room_number',
        'totalDueCached', 'total_due_cached',
        'totalPaidCached', 'total_paid_cached',
        'remainingBalanceCached', 'remaining_balance_cached',
        'guestName', 'guest_name',
        'isFullyPaid', 'is_fully_paid',
      },
      'payments': {
        'amount',
        'paymentDate', 'payment_date',
        'paymentMethod', 'payment_method',
        'bookingUuid', 'booking_uuid',
        'status',
        'revenueType', 'revenue_type',
      },
      'rooms': {
        'status',
        'price',
        'roomNumber', 'room_number',
        'floor',
        'type',
        'isActive', 'is_active',
        'cleaningStatus', 'cleaning_status',
      },
      'expenses': {
        'amount',
        'date',
        'category',
        'description',
        'status',
        'expenseType', 'expense_type',
      },
      'debts': {
        'amount',
        'status',
        'dueDate', 'due_date',
        'paidAmount', 'paid_amount',
        'guestName', 'guest_name',
        'remainingAmount', 'remaining_amount',
        'isSettled', 'is_settled',
      },
      'employees': {
        'name',
        'phone',
        'salary',
        'role',
        'status',
        'isActive', 'is_active',
        'basicSalary', 'basic_salary',
      },
      'guests': {'name', 'phone', 'idNumber', 'id_number', 'nationality', 'isBlacklisted', 'is_blacklisted'},
      'cash_transactions': {
        'amount',
        'type',
        'date',
        'status',
        'transactionType', 'transaction_type',
      },
      'shift_notes': {'content', 'isRead', 'is_read', 'priority', 'status'},
      'booking_notes': {
        'note',
        'isAlert', 'is_alert',
        'alertDate', 'alert_date',
        'status',
        'noteText', 'note_text',
      },
    };

    return fieldsByTable[table] ?? {};
  }
}
