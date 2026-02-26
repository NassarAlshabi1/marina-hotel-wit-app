/// Vector Clock Implementation
/// للتعرف على الترتيب الزمني الحقيقي بين الأجهزة المتعددة
/// واكتشاف التعارضات بشكل دقيق
library;

import 'dart:convert';
import 'dart:math' as math;
import 'models/sync_models.dart';

/// Vector Clock - ساعة متجهة للأجهزة المتعددة
///
/// كل جهاز لديه عداد خاص به
/// عند استلام تغيير من جهاز آخر، ندمج العدادات
class VectorClock {
  VectorClock([Map<String, int>? initial])
      : clocks = Map<String, int>.from(initial ?? {});

  /// إنشاء من JSON
  factory VectorClock.fromJson(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    return VectorClock(map.map((k, v) => MapEntry(k, v as int)));
  }

  /// إنشاء ساعة جديدة بناءً على مجموعة من الأجهزة
  factory VectorClock.forDevices(List<String> deviceIds) {
    return VectorClock({
      for (final id in deviceIds) id: 0,
    });
  }

  /// ساعة فارغة
  factory VectorClock.empty() => VectorClock({});

  /// ساعة جديدة لجهاز واحد
  factory VectorClock.forDevice(String deviceId) {
    return VectorClock({deviceId: 0});
  }
  final Map<String, int> clocks;

  /// تحويل إلى JSON
  String toJson() => jsonEncode(clocks);

  /// زيادة العداد للجهاز الحالي
  VectorClock increment(String deviceId) {
    final newClocks = Map<String, int>.from(clocks);
    newClocks[deviceId] = (newClocks[deviceId] ?? 0) + 1;
    return VectorClock(newClocks);
  }

  /// دمج ساعتين (يحدث عند استلام تغيير من جهاز آخر)
  VectorClock merge(VectorClock other) {
    final newClocks = Map<String, int>.from(clocks);

    for (final entry in other.clocks.entries) {
      newClocks[entry.key] = math.max(
        newClocks[entry.key] ?? 0,
        entry.value,
      );
    }

    return VectorClock(newClocks);
  }

  /// مقارنة ساعتين
  ///
  /// LOCAL_NEWER: السجل المحلي أحدث
  /// REMOTE_NEWER: السجل البعيد أحدث
  /// CONCURRENT: كلاهما له تغييرات لا يعرف عنها الآخر (تعارض حقيقي)
  /// EQUAL: متساويتان
  VectorClockComparison compare(VectorClock other) {
    bool localDominates = false;
    bool remoteDominates = false;

    // الحصول على جميع أجهزة الطرفين
    final allDevices = {...clocks.keys, ...other.clocks.keys};

    for (final deviceId in allDevices) {
      final localValue = clocks[deviceId] ?? 0;
      final remoteValue = other.clocks[deviceId] ?? 0;

      if (localValue > remoteValue) {
        localDominates = true;
      } else if (remoteValue > localValue) {
        remoteDominates = true;
      }

      // إذا كان كلاهما يهيمنان، فهما متزامنان (تعارض)
      if (localDominates && remoteDominates) {
        return VectorClockComparison.concurrent;
      }
    }

    // تحديد النتيجة
    if (localDominates) return VectorClockComparison.localNewer;
    if (remoteDominates) return VectorClockComparison.remoteNewer;
    return VectorClockComparison.equal;
  }

  /// التحقق من أن هذه الساعة تحدث قبل ساعة أخرى
  bool happensBefore(VectorClock other) {
    return compare(other) == VectorClockComparison.remoteNewer;
  }

  /// التحقق من أن هذه الساعة تحدث بعد ساعة أخرى
  bool happensAfter(VectorClock other) {
    return compare(other) == VectorClockComparison.localNewer;
  }

  /// التحقق من وجود تعارض
  bool hasConflict(VectorClock other) {
    return compare(other) == VectorClockComparison.concurrent;
  }

  /// الحصول على قيمة جهاز محدد
  int? getDeviceClock(String deviceId) => clocks[deviceId];

  /// الحصول على أعلى قيمة في الساعة
  int get maxClock {
    if (clocks.isEmpty) return 0;
    return clocks.values.reduce(math.max);
  }

  /// الحصول على مجموع جميع العدادات
  int get totalClock {
    return clocks.values.fold(0, (sum, val) => sum + val);
  }

  /// نسخة نظيفة من الساعة
  VectorClock copy() => VectorClock(Map<String, int>.from(clocks));

  @override
  String toString() => 'VectorClock($clocks)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! VectorClock) return false;

    if (clocks.length != other.clocks.length) return false;

    for (final entry in clocks.entries) {
      if (other.clocks[entry.key] != entry.value) return false;
    }

    return true;
  }

  @override
  int get hashCode => clocks.hashCode;
}

/// مدير Vector Clock للتطبيق
/// يتتبع ساعات جميع الأجهزة المعروفة
class VectorClockManager {
  VectorClockManager({required String deviceId})
      : _deviceId = deviceId,
        _currentClock = VectorClock.forDevice(deviceId);

  /// استعادة من JSON
  factory VectorClockManager.fromStorageJson(Map<String, dynamic> json) {
    final deviceId = json['deviceId'] as String;
    final clocks = (json['clocks'] as Map<String, dynamic>).map(
      (k, v) => MapEntry(k, v as int),
    );

    final manager = VectorClockManager(deviceId: deviceId);
    manager._currentClock = VectorClock(clocks);
    return manager;
  }
  String _deviceId;
  VectorClock _currentClock;

  String get deviceId => _deviceId;
  VectorClock get currentClock => _currentClock;

  /// تسجيل حدث محلي جديد
  VectorClock recordLocalEvent() {
    return _currentClock = _currentClock.increment(_deviceId);
  }

  /// تسجيل استلام حدث من جهاز آخر
  VectorClock recordRemoteEvent(VectorClock remoteClock) {
    // لا نزيد العداد هنا - ذلك يحدث فقط للأحداث المحلية
    return _currentClock = _currentClock.merge(remoteClock);
  }

  /// مقارنة مع ساعة بعيدة
  VectorClockComparison compareWith(VectorClock remoteClock) {
    return _currentClock.compare(remoteClock);
  }

  /// تحديث معرف الجهاز
  void updateDeviceId(String newDeviceId) {
    if (_deviceId == newDeviceId) return;

    // نقل قيمة العداد القديم إلى الجديد
    final oldValue = _currentClock.getDeviceClock(_deviceId) ?? 0;
    final newClocks = Map<String, int>.from(_currentClock.clocks);

    newClocks.remove(_deviceId);
    newClocks[newDeviceId] = oldValue;

    _deviceId = newDeviceId;
    _currentClock = VectorClock(newClocks);
  }

  /// إضافة جهاز جديد معروف
  void addKnownDevice(String deviceId) {
    if (!_currentClock.clocks.containsKey(deviceId)) {
      _currentClock = VectorClock({
        ..._currentClock.clocks,
        deviceId: 0,
      });
    }
  }

  /// التحقق من وجود تعارض مع ساعة أخرى
  bool hasConflictWith(VectorClock other) {
    return _currentClock.hasConflict(other);
  }

  /// التحقق مما إذا كان الحدث المحلي أحدث من ساعة أخرى
  bool isLocalNewer(VectorClock remoteClock) {
    return _currentClock.compare(remoteClock) ==
        VectorClockComparison.localNewer;
  }

  /// تحويل إلى JSON للتخزين
  Map<String, dynamic> toStorageJson() => {
        'deviceId': _deviceId,
        'clocks': _currentClock.clocks,
      };

  @override
  String toString() =>
      'VectorClockManager(device: $_deviceId, clock: $_currentClock)';
}

/// امتدادات مفيدة على DeltaChange
extension DeltaChangeVectorClock on DeltaChange {
  /// الحصول على VectorClock من التغيير
  VectorClock get vectorClockObject {
    return VectorClock.fromJson(vectorClock);
  }

  /// مقارنة مع سجل محلي
  VectorClockComparison compareWithLocal(Map<String, dynamic> localRecord) {
    final localClockStr = localRecord['vector_clock'] as String?;
    if (localClockStr == null) {
      return VectorClockComparison.remoteNewer;
    }

    final localClock = VectorClock.fromJson(localClockStr);
    return vectorClockObject.compare(localClock);
  }
}

/// مراقب التعارضات
/// يسجل جميع التعارضات المكتشفة للمراجعة
class ConflictMonitor {
  ConflictMonitor({this.maxHistory = 100});
  final List<DetectedConflict> _conflicts = [];
  final int maxHistory;

  List<DetectedConflict> get conflicts => List.unmodifiable(_conflicts);

  /// تسجيل تعارض جديد
  void recordConflict({
    required String table,
    required String uuid,
    required VectorClock localClock,
    required VectorClock remoteClock,
    required Map<String, dynamic> localData,
    required Map<String, dynamic> remoteData,
  }) {
    _conflicts.add(DetectedConflict(
      table: table,
      uuid: uuid,
      localClock: localClock,
      remoteClock: remoteClock,
      localData: localData,
      remoteData: remoteData,
      detectedAt: DateTime.now(),
    ));

    // الحفاظ على حد التاريخ
    if (_conflicts.length > maxHistory) {
      _conflicts.removeAt(0);
    }
  }

  /// الحصول على التعارضات النشطة
  List<DetectedConflict> get activeConflicts =>
      _conflicts.where((c) => !c.resolved).toList();

  /// حل تعارض
  void resolveConflict(String uuid, ConflictResolution resolution) {
    final conflict = _conflicts.firstWhere(
      (c) => c.uuid == uuid && !c.resolved,
      orElse: () => throw StateError('Conflict not found: $uuid'),
    );
    conflict.resolve(resolution);
  }

  /// إحصائيات التعارضات
  Map<String, dynamic> get stats => {
        'total': _conflicts.length,
        'active': activeConflicts.length,
        'resolved': _conflicts.where((c) => c.resolved).length,
        'byTable': _groupByTable(),
      };

  Map<String, int> _groupByTable() {
    final result = <String, int>{};
    for (final conflict in _conflicts) {
      result[conflict.table] = (result[conflict.table] ?? 0) + 1;
    }
    return result;
  }
}

/// تفاصيل تعارض مكتشف
class DetectedConflict {
  DetectedConflict({
    required this.table,
    required this.uuid,
    required this.localClock,
    required this.remoteClock,
    required this.localData,
    required this.remoteData,
    required this.detectedAt,
  });
  final String table;
  final String uuid;
  final VectorClock localClock;
  final VectorClock remoteClock;
  final Map<String, dynamic> localData;
  final Map<String, dynamic> remoteData;
  final DateTime detectedAt;
  bool resolved = false;
  ConflictResolution? resolution;
  DateTime? resolvedAt;

  void resolve(ConflictResolution res) {
    resolved = true;
    resolution = res;
    resolvedAt = DateTime.now();
  }

  /// وصف قابل للقراءة
  String get description {
    return 'Conflict in $table/$uuid:\n'
        '  Local:  ${localClock.toJson()}\n'
        '  Remote: ${remoteClock.toJson()}';
  }
}
