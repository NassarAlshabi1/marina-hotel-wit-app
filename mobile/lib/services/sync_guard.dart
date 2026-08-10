import 'package:flutter/foundation.dart';

/// حارس مشترك لمنع تداخل عمليات المزامنة عبر الخدمات المختلفة.
///
/// ✅ إصلاح P2-10: بدلاً من دمج 8 Timer.periodic مختلفة (التي تشغّلها
/// `SmartSyncManager`, `GoogleDriveUnifiedSyncCoordinator`, `AppwriteSyncManager`)
/// في موجد موحد واحد — وهو refactor معماري كبير ومخاطر عالية — نضيف هذا
/// الحارس الخفيف كطبقة throttle عبرية.
///
/// ✅ P0-I (double-acquire fix): canStart + markStarted الآن atomic عبر
/// `tryAcquire`. هذا يمنع race condition حيث يمكن لخدمتين استدعاء canStart
/// في نفس اللحظة، كلاهما يرى "لا توجد مزامنة نشطة"، وكلاهما يستدعي
/// markStarted. قبل الإصلاح، كانت كلتا الخدمتين تشتغلان متداخلتين.
///
/// الاستخدام (الصحيح):
/// ```dart
/// if (!SyncGuard.tryAcquire(label: 'smart_sync')) return; // atomic
/// try {
///   await _performSync();
/// } finally {
///   SyncGuard.release(label: 'smart_sync');
/// }
/// ```
class SyncGuard {
  SyncGuard._();

  /// وقت بدء آخر مزامنة نشطة عبر جميع الخدمات.
  static DateTime? _activeSyncStartedAt;

  /// اسم الخدمة التي تُنفّذ المزامنة الحالية (للتشخيص).
  static String? _activeSyncLabel;

  /// ✅ P0-I: tryAcquire — atomic check-and-set.
  /// يُعيد true إذا تم الحجز بنجاح، false إذا كانت مزامنة أخرى نشطة.
  /// يجب استدعاء [release] في finally بنفس الـ label.
  static bool tryAcquire({required String label}) {
    if (_activeSyncStartedAt != null) {
      final elapsed = DateTime.now().difference(_activeSyncStartedAt!);
      // إذا مضت أكثر من 10 دقائق على "مزامنة نشطة"، فمن المحتمل أنها علقت
      // (deadlock أو crash) — اسمح بمزامنة جديدة كـ safety valve.
      if (elapsed <= const Duration(minutes: 10)) {
        return false;
      }
      debugPrint(
        '⚠️ SyncGuard: stale lock detected (label=$_activeSyncLabel, '
        'elapsed=${elapsed.inSeconds}s) — force-releasing and allowing $label',
      );
    }
    _activeSyncStartedAt = DateTime.now();
    _activeSyncLabel = label;
    return true;
  }

  /// ✅ P0-I: release — يحرر القفل فقط إذا كان الـ label مطابقاً.
  /// هذا يمنع "release بالخطأ" من خدمة أخرى. إذا اختلفت الـ label،
  /// نتجاهل (لأن الـ lock مملوك لخدمة أخرى).
  static void release({required String label}) {
    if (_activeSyncLabel != label) {
      debugPrint(
        '⚠️ SyncGuard.release($label) called but lock is held by '
        '$_activeSyncLabel — ignoring (prevents accidental release)',
      );
      return;
    }
    _activeSyncStartedAt = null;
    _activeSyncLabel = null;
  }

  /// تحقق ما إذا كان يمكن بدء مزامنة جديدة الآن.
  ///
  /// ⚠️ DEPRECATED — استخدم [tryAcquire] بدلاً منه (atomic).
  /// تم الإبقاء للتوافق مع الكود القائم.
  static bool canStart({required String label}) {
    if (_activeSyncStartedAt == null) return true;
    final elapsed = DateTime.now().difference(_activeSyncStartedAt!);
    if (elapsed > const Duration(minutes: 10)) {
      debugPrint(
        '⚠️ SyncGuard.canStart($label): stale lock (label=$_activeSyncLabel, '
        'elapsed=${elapsed.inSeconds}s) — would allow',
      );
      return true;
    }
    return false;
  }

  /// سجّل بدء مزامنة. يجب استدعاؤها فوراً بعد [canStart] تُعيد true.
  ///
  /// ⚠️ DEPRECATED — استخدم [tryAcquire] بدلاً منه (atomic).
  static void markStarted({required String label}) {
    _activeSyncStartedAt = DateTime.now();
    _activeSyncLabel = label;
  }

  /// سجّل انتهاء المزامنة. يجب استدعاؤها في `finally` block دائماً.
  ///
  /// ⚠️ DEPRECATED — استخدم [release] بدلاً منه (with label).
  static void markFinished() {
    _activeSyncStartedAt = null;
    _activeSyncLabel = null;
  }

  /// حالة التشخيص — هل توجد مزامنة نشطة الآن؟
  static bool get isActive => _activeSyncStartedAt != null;

  /// معرّف الخدمة النشطة حالياً (للتشخيص فقط).
  static String? get activeLabel => _activeSyncLabel;
}
