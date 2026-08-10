import 'package:flutter/foundation.dart';
import 'package:marina_hotel_mobile/utils/debug_log.dart';

/// حارس مشترك لمنع تداخل عمليات المزامنة عبر الخدمات المختلفة.
///
/// ✅ إصلاح P2-10: بدلاً من دمج 8 Timer.periodic مختلفة (التي تشغّلها
/// `SmartSyncManager`, `GoogleDriveUnifiedSyncCoordinator`, `AppwriteSyncManager`)
/// في موجد موحد واحد — وهو refactor معماري كبير ومخاطر عالية — نضيف هذا
/// الحارس الخفيف كطبقة throttle عبرية.
///
/// كل خدمة تستدعي [canStart] قبل بدء عملها الدوري. إذا كانت مزامنة أخرى
/// قيد التشغيل، تتخطى الخدمة هذه الدورة وتنتظر الدورة التالية. هذا يقلّل
/// بشكل كبير من تضارب العمليات واستهلاك البطارية دون الحاجة إلى إعادة
/// تصميم بنية المزامنة بالكامل.
///
/// الاستخدام:
/// ```dart
/// _syncCheckTimer = Timer.periodic(Duration(minutes: 2), (_) async {
///   if (!SyncGuard.canStart(label: 'smart_sync')) return;
///   SyncGuard.markStarted();
///   try {
///     await _performSync();
///   } finally {
///     SyncGuard.markFinished();
///   }
/// });
/// ```
class SyncGuard {
  SyncGuard._();

  /// الإعدادات الحالية (الافتراضية)
  /// يمكن تعديلها عبر Config أو ملف Olsen
  static const _defaultLockTimeout = Duration(minutes: 10);
  static const _defaultStaleLockTimeout = Duration(minutes: 10);
  
  /// يمكن تهيئة القيم الجديدة من أي مصدر (AppConfig.integrations)
  static Duration _lockTimeout = _defaultLockTimeout;
  static Duration _staleLockTimeout = _defaultStaleLockTimeout;
  
  /// ✅ الوقاية من lock studio: يمكن أن يتغير وقت الانتظار بناءً على حجم البيانات أو الحالة
  /// تساعد على تجنب EtBa但在关键时刻的死锁问题。
  static void configureTimeouts({
    Duration? lockTimeout,
    Duration? staleLockTimeout,
  }) {
    if (lockTimeout != null) {
      _lockTimeout = lockTimeout;
    }
    if (staleLockTimeout != null) {
      _staleLockTimeout = staleLockTimeout;
    }
  }

  /// وقت بدء آخر مزامنة نشطة عبر جميع الخدمات.
  static DateTime? _activeSyncStartedAt;

  /// اسم الخدمة التي تُنفّذ المزامنة الحالية (للتشخيص).
  static String? _activeSyncLabel;

  /// تحقق ما إذا كان يمكن بدء مزامنة جديدة الآن.
  ///
  /// [label] معرّف الخدمة التي تستدعي هذا التحقق (للتشخيص والتسجيل).
  /// يُعيد `true` إذا لم تكن هناك مزامنة نشطة، أو `false` إذا كانت
  /// مزامنة أخرى قيد التشغيل.
  static bool canStart({required String label}) {
    if (_activeSyncStartedAt == null) return true;
    final elapsed = DateTime.now().difference(_activeSyncStartedAt!);
    // إذا مضت أكثر من [_staleLockTimeout] على "مزامنة نشطة"، من المحتمل أنها علقت
    if (elapsed > _staleLockTimeout) {
      dlog(
        () =>
            '⚠️ SyncGuard: stale lock detected (label=$_activeSyncLabel, '
            'elapsed=${elapsed.inSeconds}s) — allowing $label to proceed',
      );
      return true;
    }
    return false;
  }

  /// ✅ Sync Safety Fix (2026-08-10): atomic try-acquire.
  /// يدمج canStart + markStarted في عملية واحدة ذرية لمنع TOCTOU race.
  /// يُرجع true إذا تم اكتساب القفل، false إذا كانت مزامنة أخرى نشطة.
  static bool tryAcquire({required String label}) {
    if (!canStart(label: label)) return false;
    markStarted(label: label);
    return true;
  }

  /// سجّل بدء مزامنة. يجب استدعاؤها فوراً بعد [canStart] تُعيد true.
  static void markStarted({required String label}) {
    _activeSyncStartedAt = DateTime.now();
    _activeSyncLabel = label;
  }

  /// سجّل انتهاء المزامنة. يجب استدعاؤها في `finally` block دائماً.
  static void markFinished() {
    _activeSyncStartedAt = null;
    _activeSyncLabel = null;
  }

  /// حالة التشخيص — هل توجد مزامنة نشطة الآن؟
  static bool get isActive => _activeSyncStartedAt != null;

  /// معرّف الخدمة النشطة حالياً (للتشخيص فقط).
  static String? get activeLabel => _activeSyncLabel;
}
