import 'dart:async';
import 'package:flutter/foundation.dart';

enum LockCategory { mainSync, deltaSync, queueProcessing, screenSync }

enum LockPriority { critical, high, normal, low }

class LockAcquisitionResult {
  final bool acquired;
  final String? holder;
  final Duration waitTime;
  final String? failureReason;

  const LockAcquisitionResult({
    required this.acquired,
    this.holder,
    required this.waitTime,
    this.failureReason,
  });
}

class LockStatus {
  final bool isLocked;
  final String? currentHolder;
  final DateTime? acquiredAt;
  final int waitingCount;

  const LockStatus({
    required this.isLocked,
    this.currentHolder,
    this.acquiredAt,
    required this.waitingCount,
  });

  Duration? get heldDuration =>
      acquiredAt != null ? DateTime.now().difference(acquiredAt!) : null;
}

class _LockState {
  bool isLocked = false;
  String? currentHolder;
  DateTime? acquiredAt;
  Completer<void>? _completer;
  int waitingCount = 0;
  final List<String> waitingHolders = [];

  void reset() {
    isLocked = false;
    currentHolder = null;
    acquiredAt = null;
    _completer = null;
    waitingCount = 0;
    waitingHolders.clear();
  }

  Future<void> get available {
    if (!isLocked) return Future.value();
    _completer ??= Completer<void>();
    return _completer!.future;
  }

  void notifyAvailable() {
    if (_completer != null && !_completer!.isCompleted) {
      _completer!.complete();
      _completer = null;
    }
  }
}

class _LockEvent {
  final DateTime timestamp;
  final LockCategory category;
  final String holder;
  final String action;
  final Duration? duration;

  const _LockEvent({
    required this.timestamp,
    required this.category,
    required this.holder,
    required this.action,
    this.duration,
  });

  @override
  String toString() {
    final categoryName = category.name;
    final durationStr = duration != null
        ? ' (${duration!.inMilliseconds}ms)'
        : '';
    return '${timestamp.toIso8601String().substring(11, 23)} - $action: $holder on $categoryName$durationStr';
  }
}

class UnifiedLockManager {
  static final UnifiedLockManager instance = UnifiedLockManager._();
  UnifiedLockManager._();

  final Map<LockCategory, _LockState> _locks = {
    for (var category in LockCategory.values) category: _LockState(),
  };

  final List<_LockEvent> _eventLog = [];
  static const int _maxLogSize = 100;

  static const Map<LockPriority, Duration> _timeouts = {
    LockPriority.critical: Duration(seconds: 5),
    LockPriority.high: Duration(seconds: 15),
    LockPriority.normal: Duration(seconds: 30),
    LockPriority.low: Duration(minutes: 1),
  };

  Future<LockAcquisitionResult> acquire({
    required LockCategory category,
    required String holder,
    LockPriority priority = LockPriority.normal,
    Duration? customTimeout,
  }) async {
    final startTime = DateTime.now();
    final timeout = customTimeout ?? _timeouts[priority]!;
    final lock = _locks[category]!;

    if (detectPotentialDeadlock(holder, category)) {
      final result = LockAcquisitionResult(
        acquired: false,
        holder: lock.currentHolder,
        waitTime: DateTime.now().difference(startTime),
        failureReason: 'Potential deadlock detected',
      );

      _addEvent(
        _LockEvent(
          timestamp: DateTime.now(),
          category: category,
          holder: holder,
          action: 'deadlock-detected',
          duration: result.waitTime,
        ),
      );

      debugPrint(
        '🔒⚠️ [UnifiedLockManager] Deadlock detected: $holder requesting ${category.name} (held by ${lock.currentHolder})',
      );

      return result;
    }

    // إصلاح Race Condition: فحص متزامن سريع قبل await لتجنب تسرب القفل
    // عندما يكون القفل متاحاً، نحصل عليه فوراً بدون yield للـ event loop
    if (!lock.isLocked) {
      lock.isLocked = true;
      lock.currentHolder = holder;
      lock.acquiredAt = DateTime.now();

      final waitTime = DateTime.now().difference(startTime);

      _addEvent(
        _LockEvent(
          timestamp: DateTime.now(),
          category: category,
          holder: holder,
          action: 'acquire',
          duration: waitTime,
        ),
      );

      return LockAcquisitionResult(
        acquired: true,
        holder: holder,
        waitTime: waitTime,
      );
    }

    lock.waitingCount++;
    lock.waitingHolders.add(holder);

    try {
      await lock.available.timeout(
        timeout,
        onTimeout: () {
          final result = LockAcquisitionResult(
            acquired: false,
            holder: lock.currentHolder,
            waitTime: DateTime.now().difference(startTime),
            failureReason: 'Timeout after ${timeout.inSeconds}s',
          );

          _addEvent(
            _LockEvent(
              timestamp: DateTime.now(),
              category: category,
              holder: holder,
              action: 'timeout',
              duration: result.waitTime,
            ),
          );

          debugPrint(
            '🔒⏱️ [UnifiedLockManager] Timeout: $holder waiting for ${category.name} after ${timeout.inSeconds}s',
          );

          throw TimeoutException('Lock acquisition timeout');
        },
      );

      // إعادة فحص حالة القفل بعد await لتجنب Race Condition
      // قد يكون caller آخر قد حصل على القفل أثناء انتظارنا
      if (lock.isLocked) {
        return LockAcquisitionResult(
          acquired: false,
          holder: lock.currentHolder,
          waitTime: DateTime.now().difference(startTime),
          failureReason: 'Lock still held after wait',
        );
      }

      lock.isLocked = true;
      lock.currentHolder = holder;
      lock.acquiredAt = DateTime.now();

      final waitTime = DateTime.now().difference(startTime);

      _addEvent(
        _LockEvent(
          timestamp: DateTime.now(),
          category: category,
          holder: holder,
          action: 'acquire',
          duration: waitTime,
        ),
      );

      if (waitTime.inMilliseconds > 100) {
        debugPrint(
          '🔒⏳ [UnifiedLockManager] Lock acquired: $holder on ${category.name} after ${waitTime.inMilliseconds}ms',
        );
      }

      return LockAcquisitionResult(
        acquired: true,
        holder: holder,
        waitTime: waitTime,
      );
    } on TimeoutException catch (_) {
      return LockAcquisitionResult(
        acquired: false,
        holder: lock.currentHolder,
        waitTime: DateTime.now().difference(startTime),
        failureReason: 'Timeout after ${timeout.inSeconds}s',
      );
    } finally {
      lock.waitingCount--;
      lock.waitingHolders.remove(holder);
    }
  }

  void release({required LockCategory category, required String holder}) {
    final lock = _locks[category]!;

    if (!lock.isLocked) {
      debugPrint(
        '🔒⚠️ [UnifiedLockManager] Attempted to release unlocked ${category.name} by $holder',
      );
      return;
    }

    if (lock.currentHolder != holder) {
      debugPrint(
        '🔒⚠️ [UnifiedLockManager] Lock mismatch: $holder trying to release ${category.name} held by ${lock.currentHolder}',
      );
      return;
    }

    final heldDuration = lock.acquiredAt != null
        ? DateTime.now().difference(lock.acquiredAt!)
        : Duration.zero;

    _addEvent(
      _LockEvent(
        timestamp: DateTime.now(),
        category: category,
        holder: holder,
        action: 'release',
        duration: heldDuration,
      ),
    );

    if (heldDuration.inSeconds > 5) {
      debugPrint(
        '🔒⏱️ [UnifiedLockManager] Lock held for ${heldDuration.inSeconds}s: $holder on ${category.name}',
      );
    }

    // إصلاح race condition: إعادة تعيين الحالة قبل إشعار المنتظرين
    // هذا يمنع المنتظرين من رؤية حالة قفل غير صحيحة عند الاستيقاظ
    lock.reset();
    lock.notifyAvailable();
  }

  Future<T?> runWithLock<T>({
    required LockCategory category,
    required String holder,
    required Future<T> Function() operation,
    LockPriority priority = LockPriority.normal,
  }) async {
    final result = await acquire(
      category: category,
      holder: holder,
      priority: priority,
    );

    if (!result.acquired) {
      debugPrint(
        '🔒❌ [UnifiedLockManager] Failed to acquire lock: $holder on ${category.name} - ${result.failureReason}',
      );
      return null;
    }

    try {
      return await operation();
    } finally {
      release(category: category, holder: holder);
    }
  }

  Map<LockCategory, LockStatus> getStatus() {
    return Map.fromEntries(
      _locks.entries.map(
        (entry) => MapEntry(
          entry.key,
          LockStatus(
            isLocked: entry.value.isLocked,
            currentHolder: entry.value.currentHolder,
            acquiredAt: entry.value.acquiredAt,
            waitingCount: entry.value.waitingCount,
          ),
        ),
      ),
    );
  }

  List<_LockEvent> getRecentEvents({int limit = 20}) {
    final count = _eventLog.length;
    if (count <= limit) return List.from(_eventLog);
    return _eventLog.sublist(count - limit);
  }

  bool detectPotentialDeadlock(String holder, LockCategory requested) {
    final requestedLock = _locks[requested]!;

    if (!requestedLock.isLocked) return false;

    final blockedByHolder = requestedLock.currentHolder;
    if (blockedByHolder == null) return false;

    final heldByHolder = _locks.entries
        .where((e) => e.value.currentHolder == holder && e.value.isLocked)
        .map((e) => e.key)
        .toList();

    if (heldByHolder.isEmpty) return false;

    return heldByHolder.any(
      (cat) => _locks[cat]?.waitingHolders.contains(blockedByHolder) ?? false,
    );
  }

  void _addEvent(_LockEvent event) {
    _eventLog.add(event);
    if (_eventLog.length > _maxLogSize) {
      _eventLog.removeAt(0);
    }
  }

  void printDiagnostics() {
    debugPrint('🔒📊 [UnifiedLockManager] === Lock Status ===');
    final status = getStatus();
    for (var entry in status.entries) {
      final s = entry.value;
      final categoryName = entry.key.name;
      if (s.isLocked) {
        final duration = s.heldDuration?.inSeconds ?? 0;
        debugPrint(
          '  $categoryName: LOCKED by ${s.currentHolder} for ${duration}s (${s.waitingCount} waiting)',
        );
      } else {
        debugPrint('  $categoryName: FREE');
      }
    }

    debugPrint('🔒📋 [UnifiedLockManager] === Recent Events ===');
    final events = getRecentEvents(limit: 10);
    for (var event in events) {
      debugPrint('  $event');
    }
  }
}
