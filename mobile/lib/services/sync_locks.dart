import 'dart:async';
import 'package:synchronized/synchronized.dart';
import 'package:flutter/foundation.dart';

/// ⭐ إصلاح: أقفال المزامنة مع timeout لتجنب Deadlock
class SyncLocks {
  SyncLocks._();

  static final mainSyncLock = Lock();

  static final deltaSyncLock = Lock();

  static final autoEngineLock = Lock();

  static final queueLock = Lock();

  static final smartSyncLock = Lock();

  static final baseSyncLock = Lock();

  static final schedulerLock = Lock();

  static final appwriteSyncLock = Lock();

  static final screenSyncLock = Lock();

  /// ⭐ المهلة الافتراضية للقفل (30 ثانية)
  static const defaultLockTimeout = Duration(seconds: 30);

  /// ⭐ تنفيذ عملية مع قفل و timeout لتجنب Deadlock
  /// 
  /// مثال:
  /// ```dart
  /// await SyncLocks.withLock(
  ///   SyncLocks.appwriteSyncLock,
  ///   () async {
  ///     // العملية المحمية
  ///   },
  ///   timeout: Duration(seconds: 60),
  /// );
  /// ```
  static Future<T?> withLock<T>(
    Lock lock,
    Future<T> Function() operation, {
    Duration timeout = defaultLockTimeout,
    String? operationName,
  }) async {
    final name = operationName ?? 'SyncOperation';
    final completer = Completer<T?>();
    
    // تعيين timeout
    final timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        debugPrint('⏱️ $name: انتهت مهلة القفل بعد ${timeout.inSeconds} ثانية');
        completer.complete(null);
      }
    });

    try {
      final result = await lock.synchronized(() async {
        if (completer.isCompleted) return null;
        
        try {
          final value = await operation();
          if (!completer.isCompleted) {
            completer.complete(value);
          }
          return value;
        } catch (e) {
          if (!completer.isCompleted) {
            completer.completeError(e);
          }
          rethrow;
        }
      });
      
      timer.cancel();
      return result;
    } catch (e) {
      timer.cancel();
      debugPrint('❌ $name: خطأ في العملية: $e');
      if (!completer.isCompleted) {
        completer.complete(null);
      }
      return null;
    }
  }

  /// ⭐ التحقق من أن القفل غير مشغول
  static bool isLocked(Lock lock) {
    return lock.locked;
  }

  /// ⭐ انتظار القفل حتى يصبح متاحاً (مع timeout)
  static Future<bool> waitForUnlock(
    Lock lock, {
    Duration timeout = defaultLockTimeout,
  }) async {
    if (!lock.locked) return true;

    final completer = Completer<bool>();
    final timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        debugPrint('⏱️ انتهت مهلة انتظار القفل');
        completer.complete(false);
      }
    });

    // محاولة الحصول على القفل ثم تحريره فوراً
    try {
      await lock.synchronized(() {
        if (!completer.isCompleted) {
          completer.complete(true);
        }
      });
    } catch (e) {
      if (!completer.isCompleted) {
        completer.complete(false);
      }
    } finally {
      timer.cancel();
    }

    return completer.future;
  }

  /// ⭐ تشخيص حالة جميع الأقفال
  static Map<String, bool> diagnoseLocks() {
    return {
      'mainSyncLock': mainSyncLock.locked,
      'deltaSyncLock': deltaSyncLock.locked,
      'autoEngineLock': autoEngineLock.locked,
      'queueLock': queueLock.locked,
      'smartSyncLock': smartSyncLock.locked,
      'baseSyncLock': baseSyncLock.locked,
      'schedulerLock': schedulerLock.locked,
      'appwriteSyncLock': appwriteSyncLock.locked,
      'screenSyncLock': screenSyncLock.locked,
    };
  }

  /// ⭐ طباعة حالة الأقفال للتشخيص
  static void printLockStatus() {
    final status = diagnoseLocks();
    final lockedOnes = status.entries.where((e) => e.value).toList();
    
    if (lockedOnes.isEmpty) {
      debugPrint('🔓 جميع الأقفال متاحة');
    } else {
      debugPrint('🔒 الأقفال المشغولة: ${lockedOnes.map((e) => e.key).join(', ')}');
    }
  }
}

/// ⭐ تمديد Lock مع إضافة timeout
extension LockTimeoutExtension on Lock {
  /// تنفيذ عملية مع timeout
  Future<T?> withTimeout<T>(
    Future<T> Function() operation, {
    Duration timeout = SyncLocks.defaultLockTimeout,
    String? operationName,
  }) {
    return SyncLocks.withLock(this, operation, timeout: timeout, operationName: operationName);
  }
}
