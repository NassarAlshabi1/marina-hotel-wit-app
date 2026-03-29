/// Conflict Resolution Strategies
/// استراتيجيات حل التعارضات المختلفة
library;

import '../models/sync_models.dart';
import '../vector_clock.dart';

/// محلل التعارضات الرئيسي
/// يختار الاستراتيجية المناسبة ويطبقها
class ConflictResolver {
  ConflictResolver({
    ConflictStrategy defaultStrategy = ConflictStrategy.newerWins,
    Map<String, ConflictStrategy>? tableStrategies,
    SmartMergeResolver? smartMergeResolver,
  }) : _defaultStrategy = defaultStrategy,
       _tableStrategies = tableStrategies ?? {},
       _smartMergeResolver = smartMergeResolver;
  final ConflictStrategy _defaultStrategy;
  final Map<String, ConflictStrategy> _tableStrategies;
  final SmartMergeResolver? _smartMergeResolver;

  /// حل تعارض باستخدام الاستراتيجية المحددة
  ConflictResolutionResult resolve(SyncConflict conflict) {
    final strategy = _tableStrategies[conflict.table] ?? _defaultStrategy;

    switch (strategy) {
      case ConflictStrategy.newerWins:
        return _newerWinsStrategy(conflict);
      case ConflictStrategy.lastWriterWins:
        return _lastWriterWinsStrategy(conflict);
      case ConflictStrategy.devicePriority:
        return _devicePriorityStrategy(conflict);
      case ConflictStrategy.smartMerge:
        return _smartMergeStrategy(conflict);
      case ConflictStrategy.manualResolve:
        return _manualResolveStrategy(conflict);
    }
  }

  /// استراتيجية: الأحدث يفوز (بناءً على Vector Clock)
  ConflictResolutionResult _newerWinsStrategy(SyncConflict conflict) {
    final localClock = VectorClock.fromJson(
      conflict.localRecord['vector_clock'] as String? ?? '{}',
    );
    final remoteClock = conflict.remoteChange.vectorClockObject;

    final comparison = localClock.compare(remoteClock);

    switch (comparison) {
      case VectorClockComparison.localNewer:
        return ConflictResolutionResult(
          winner: Winner.local,
          data: conflict.localRecord,
          requiresReview: false,
        );
      case VectorClockComparison.remoteNewer:
        return ConflictResolutionResult(
          winner: Winner.remote,
          data: conflict.remoteChange.payload,
          requiresReview: false,
        );
      case VectorClockComparison.concurrent:
      case VectorClockComparison.equal:
        // في حالة التزامن، نستخدم الوقت كحل بديل
        return _timestampFallback(conflict);
    }
  }

  /// استراتيجية: آخر كاتب يفوز (بناءً على الطابع الزمني)
  ConflictResolutionResult _lastWriterWinsStrategy(SyncConflict conflict) {
    return _timestampFallback(conflict);
  }

  /// استراتيجية: أولوية الجهاز
  /// الجهاز ذو الأولوية الأعلى يفوز
  ConflictResolutionResult _devicePriorityStrategy(SyncConflict conflict) {
    final localDeviceId = conflict.localRecord['device_id'] as String?;
    final remoteDeviceId = conflict.remoteChange.deviceId;

    // إذا لم يكن لدينا أجهزة محددة، نستخدم الوقت
    if (localDeviceId == null || remoteDeviceId == null) {
      return _timestampFallback(conflict);
    }

    // هنا يمكن إضافة منطق أولوية الجهاز
    // مثلاً: الأجهزة الرئيسية (master) لها أولوية أعلى
    final localPriority = _getDevicePriority(localDeviceId);
    final remotePriority = _getDevicePriority(remoteDeviceId);

    if (localPriority > remotePriority) {
      return ConflictResolutionResult(
        winner: Winner.local,
        data: conflict.localRecord,
        requiresReview: false,
      );
    } else if (remotePriority > localPriority) {
      return ConflictResolutionResult(
        winner: Winner.remote,
        data: conflict.remoteChange.payload,
        requiresReview: false,
      );
    } else {
      // أولوية متساوية - استخدام الوقت
      return _timestampFallback(conflict);
    }
  }

  /// استراتيجية: دمج ذكي
  /// يحاول دمج البيانات من المصدرين
  ConflictResolutionResult _smartMergeStrategy(SyncConflict conflict) {
    if (_smartMergeResolver != null) {
      final result = _smartMergeResolver.tryMerge(
        table: conflict.table,
        local: conflict.localRecord,
        remote: conflict.remoteChange.payload,
      );

      if (result != null) {
        return ConflictResolutionResult(
          winner: Winner.merged,
          data: result,
          requiresReview: false,
        );
      }
    }

    // إذا فشل الدمج الذكي، نعود للحل اليدوي
    return _manualResolveStrategy(conflict);
  }

  /// استراتيجية: حل يدوي
  /// يتطلب تدخل المستخدم
  ConflictResolutionResult _manualResolveStrategy(SyncConflict conflict) {
    return ConflictResolutionResult(
      winner: Winner.local, // افتراضياً نحتفظ بالمحلي
      data: conflict.localRecord,
      requiresReview: true, // يتطلب مراجعة
    );
  }

  /// حل احتياطي باستخدام الطابع الزمني
  ConflictResolutionResult _timestampFallback(SyncConflict conflict) {
    final localTime = _extractTimestamp(conflict.localRecord);
    final remoteTime = conflict.remoteChange.timestamp;

    if (localTime.isAfter(remoteTime)) {
      return ConflictResolutionResult(
        winner: Winner.local,
        data: conflict.localRecord,
        requiresReview: false,
      );
    } else {
      return ConflictResolutionResult(
        winner: Winner.remote,
        data: conflict.remoteChange.payload,
        requiresReview: false,
      );
    }
  }

  /// استخراج الطابع الزمني من السجل
  DateTime _extractTimestamp(Map<String, dynamic> record) {
    final updatedAt = record['updated_at'];
    if (updatedAt is String) {
      return DateTime.tryParse(updatedAt) ?? DateTime.now();
    }
    if (updatedAt is DateTime) {
      return updatedAt;
    }
    return DateTime.now();
  }

  /// الحصول على أولوية الجهاز
  int _getDevicePriority(String deviceId) {
    // يمكن تخصيص هذا المنطق حسب احتياجات التطبيق
    // مثلاً: قراءة من الإعدادات أو قاعدة البيانات
    return 100; // افتراضي
  }
}

/// محلل الدمج الذكي
abstract class SmartMergeResolver {
  /// محاولة دمج سجلين
  /// يع null إذا كان الدمج غير ممكن
  Map<String, dynamic>? tryMerge({
    required String table,
    required Map<String, dynamic> local,
    required Map<String, dynamic> remote,
  });
}

/// محلل الدمج الافتراضي
class DefaultSmartMergeResolver implements SmartMergeResolver {
  @override
  Map<String, dynamic>? tryMerge({
    required String table,
    required Map<String, dynamic> local,
    required Map<String, dynamic> remote,
  }) {
    // إنشاء نسخة مدمجة
    final merged = Map<String, dynamic>.from(local);

    bool hasConflict = false;

    for (final entry in remote.entries) {
      final key = entry.key;
      final remoteValue = entry.value;
      final localValue = local[key];

      if (localValue == null) {
        // الحقل موجود في البعيد فقط
        merged[key] = remoteValue;
      } else if (localValue != remoteValue) {
        // تعارض في القيمة
        hasConflict = true;

        // محاولة حل التعارض حسب نوع الحقل
        final resolved = _resolveFieldConflict(
          key: key,
          local: localValue,
          remote: remoteValue,
          table: table,
        );

        if (resolved != null) {
          merged[key] = resolved;
          hasConflict = false; // تم الحل
        }
      }
    }

    // إذا بقيت تعارضات غير محلولة، نعيد null
    if (hasConflict) return null;

    return merged;
  }

  /// حل تعارض في حقل محدد
  dynamic _resolveFieldConflict({
    required String key,
    required dynamic local,
    required dynamic remote,
    required String table,
  }) {
    // تجاهل الحقول الميتة (metadata)
    if (key.startsWith('_') || key == 'id' || key == 'uuid') {
      return local;
    }

    // حلول خاصة حسب نوع الحقل
    if (local is num && remote is num) {
      // للأرقام: اختيار الأعلى (مفيد للعدادات)
      if (key.contains('count') ||
          key.contains('total') ||
          key.contains('amount')) {
        return local > remote ? local : remote;
      }
    }

    if (local is bool && remote is bool) {
      // للقيم المنطقية: true تفوز (مفيد للأعلام)
      return local || remote;
    }

    if (local is List && remote is List) {
      // للقوائم: دمج بدون تكرار
      final combined = [...local, ...remote];
      return combined.toSet().toList();
    }

    if (local is Map && remote is Map) {
      // للخرائط: دمج متكرر
      return {
        ...local as Map<String, dynamic>,
        ...remote as Map<String, dynamic>,
      };
    }

    // لا يمكن الحل تلقائياً
    return null;
  }
}

/// مدير التعارضات
/// يتتبع جميع التعارضات ويساعد في حلها
class ConflictManager {
  ConflictManager({int maxHistory = 100}) : _maxHistory = maxHistory;
  final List<SyncConflict> _conflicts = [];
  final int _maxHistory;

  /// قائمة التعارضات
  List<SyncConflict> get conflicts => List.unmodifiable(_conflicts);

  /// التعارضات النشطة (غير المحلولة)
  List<SyncConflict> get activeConflicts =>
      _conflicts.where((c) => c.resolution == null).toList();

  /// إضافة تعارض جديد
  void addConflict(SyncConflict conflict) {
    _conflicts.add(conflict);

    // الحفاظ على حد التاريخ
    if (_conflicts.length > _maxHistory) {
      _conflicts.removeAt(0);
    }
  }

  /// حل تعارض
  void resolveConflict(
    String conflictId,
    ConflictResolution resolution, {
    String? resolvedBy,
  }) {
    final conflict = _conflicts.firstWhere(
      (c) => c.id == conflictId,
      orElse: () => throw StateError('Conflict not found: $conflictId'),
    );

    // نسخة محدثة مع الحل
    final resolvedIndex = _conflicts.indexOf(conflict);
    _conflicts[resolvedIndex] = SyncConflict(
      id: conflict.id,
      table: conflict.table,
      uuid: conflict.uuid,
      remoteChange: conflict.remoteChange,
      localRecord: conflict.localRecord,
      detectedAt: conflict.detectedAt,
      resolution: resolution,
      resolvedBy: resolvedBy,
      resolvedAt: DateTime.now(),
    );
  }

  /// الحصول على إحصائيات التعارضات
  ConflictStats getStats() {
    final byTable = <String, int>{};
    final byResolution = <ConflictResolution?, int>{};

    for (final conflict in _conflicts) {
      byTable[conflict.table] = (byTable[conflict.table] ?? 0) + 1;
      byResolution[conflict.resolution] =
          (byResolution[conflict.resolution] ?? 0) + 1;
    }

    return ConflictStats(
      total: _conflicts.length,
      active: activeConflicts.length,
      resolved: _conflicts.where((c) => c.resolution != null).length,
      byTable: byTable,
      byResolution: byResolution,
    );
  }

  /// تنظيف التعارضات المحلولة القديمة
  void cleanup({Duration? olderThan}) {
    final cutoff = DateTime.now().subtract(
      olderThan ?? const Duration(days: 7),
    );

    _conflicts.removeWhere(
      (c) =>
          c.resolution != null &&
          c.resolvedAt != null &&
          c.resolvedAt!.isBefore(cutoff),
    );
  }
}

/// إحصائيات التعارضات
class ConflictStats {
  ConflictStats({
    required this.total,
    required this.active,
    required this.resolved,
    required this.byTable,
    required this.byResolution,
  });
  final int total;
  final int active;
  final int resolved;
  final Map<String, int> byTable;
  final Map<ConflictResolution?, int> byResolution;

  @override
  String toString() =>
      'ConflictStats(total: $total, active: $active, resolved: $resolved)';
}
