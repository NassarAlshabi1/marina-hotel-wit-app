import 'dart:async';
import 'package:flutter/foundation.dart';
import 'unified_lock_manager.dart';

/// مسؤول عن جدولة المزامنة فقط - لا يعرف تفاصيل المزامنة
/// 
/// الاستخدام:
/// ```dart
/// final scheduler = SyncScheduler(
///   onSyncTrigger: () async => await performSync(),
///   isEnabled: () => settings.syncEnabled,
/// );
/// await scheduler.start();
/// ```
class SyncScheduler {
  SyncScheduler({
    required this.onSyncTrigger,
    required this.isEnabled,
    this.quickCheckInterval = const Duration(minutes: 1),
    this.fullSyncInterval = const Duration(hours: 24),
  });

  final Future<void> Function() onSyncTrigger;
  final bool Function() isEnabled;
  final Duration quickCheckInterval;
  final Duration fullSyncInterval;

  Timer? _quickCheckTimer;
  Timer? _fullSyncTimer;
  bool _isRunning = false;

  bool get isRunning => _isRunning;

  /// بدء الجدولة
  Future<void> start() async {
    final lockResult = await UnifiedLockManager.instance.acquire(
      category: LockCategory.mainSync,
      holder: 'SyncScheduler.start',
      priority: LockPriority.normal,
    );
    
    if (!lockResult.acquired) {
      debugPrint('❌ SyncScheduler: فشل الحصول على القفل: ${lockResult.failureReason}');
      return;
    }
    
    if (_isRunning) {
      UnifiedLockManager.instance.release(
        category: LockCategory.mainSync,
        holder: 'SyncScheduler.start',
      );
      return;
    }
    
    _isRunning = true;
    
    UnifiedLockManager.instance.release(
      category: LockCategory.mainSync,
      holder: 'SyncScheduler.start',
    );
    
    _quickCheckTimer = Timer.periodic(quickCheckInterval, (_) async {
      if (isEnabled()) {
        await _safelyTriggerSync();
      }
    });

    _fullSyncTimer = Timer.periodic(fullSyncInterval, (_) async {
      if (isEnabled()) {
        await _safelyTriggerSync();
      }
    });

    debugPrint('📅 SyncScheduler: بدأت الجدولة - فحص كل ${quickCheckInterval.inMinutes} دقيقة');
  }

  /// إيقاف الجدولة
  Future<void> stop() async {
    final lockResult = await UnifiedLockManager.instance.acquire(
      category: LockCategory.mainSync,
      holder: 'SyncScheduler.stop',
      priority: LockPriority.critical,
    );
    
    if (!lockResult.acquired) {
      debugPrint('❌ SyncScheduler: فشل الحصول على القفل: ${lockResult.failureReason}');
      return;
    }
    
    try {
      _quickCheckTimer?.cancel();
      _fullSyncTimer?.cancel();
      _quickCheckTimer = null;
      _fullSyncTimer = null;
      _isRunning = false;
      debugPrint('🛑 SyncScheduler: توقفت الجدولة');
    } finally {
      // إصلاح: await على release لضمان إطلاق القفل بشكل صحيح
      await UnifiedLockManager.instance.release(
        category: LockCategory.mainSync,
        holder: 'SyncScheduler.stop',
      );
    }
  }

  /// تشغيل المزامنة بأمان (مع معالجة الأخطاء)
  Future<void> _safelyTriggerSync() async {
    try {
      await onSyncTrigger();
    } catch (e) {
      debugPrint('❌ SyncScheduler: خطأ في المزامنة المجدولة: $e');
    }
  }

  /// تعديل الفترة الزمنية ديناميكياً
  Future<void> updateInterval(Duration newQuickInterval, {Duration? newFullInterval}) async {
    if (_isRunning) {
      await stop();
    }
    await start();
  }

  /// تشغيل مزامنة فورية
  Future<void> triggerNow() async {
    if (isEnabled()) {
      await _safelyTriggerSync();
    }
  }

  /// تنظيف الموارد
  void dispose() {
    _quickCheckTimer?.cancel();
    _fullSyncTimer?.cancel();
  }
}
