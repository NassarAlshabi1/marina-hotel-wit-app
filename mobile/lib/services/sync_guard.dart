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
  ///
  /// ⚠️ **محفوظة للتوافق الرجعي** — يُنصح باستخدام [tryAcquire] بدلاً منها.
  /// `canStart` + `markStarted` منفصلتان يسمحان بـ TOCTOU race: موضوعان
  /// يستدعيان `canStart` في وقت واحد قد يرى كل منهما true، ثم يستدعيان
  /// `markStarted` فيتداخلان. [tryAcquire] يدمج العمليتين ذريياً.
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
      // ✅ Sync Safety Fix (2026-08-10): مسح الـ stale lock فوراً لمنع
      // موضوع آخر من رؤية الـ stale lock واعتباره نشطاً. بدون هذا،
      // موضوعان قد يرى كل منهما الـ stale lock ويسمح لكليهما بالبدء.
      _activeSyncStartedAt = null;
      _activeSyncLabel = null;
      return true;
    }
    return false;
  }

  /// ✅ Sync Safety Fix (2026-08-10): atomic try-acquire.
  /// يدمج canStart + markStarted في عملية واحدة ذرية لمنع TOCTOU race.
  /// يُرجع true إذا تم اكتساب القفل، false إذا كانت مزامنة أخرى نشطة.
  ///
  /// **استخدام**: استبدل `if (!SyncGuard.canStart(label: X)) return;`
  /// + `SyncGuard.markStarted(label: X);` بـ
  /// `if (!SyncGuard.tryAcquire(label: X)) return;`.
  ///
  /// **Note**: Dart single-threaded event loop يجعل هذه الذرية فعلياً
  /// (لا يوجد preemption بين الـ check والـ set). لكن `tryAcquire` ما زال
  /// أفضل لأنه:
  /// 1. يقلل الـ boilerplate (سطر واحد بدل سطرين)
  /// 2. يمنع الأخطاء البشرية (نسيان markStarted بعد canStart)
  /// 3. يضمن أن الـ markStarted يحدث فوراً بعد الـ check بدون أي async gap
  /// 4. يسمح بإضافة diagnostic logging في مكان واحد
  static bool tryAcquire({required String label}) {
    if (!canStart(label: label)) {
      dlog(
        () =>
            '🔒 SyncGuard: tryAcquire REJECTED for "$label" — '
            'active="$_activeSyncLabel" '
            '(elapsed=${(_activeSyncStartedAt != null) ? DateTime.now().difference(_activeSyncStartedAt!).inSeconds : 0}s)',
      );
      return false;
    }
    markStarted(label: label);
    dlog(
      () => '🔒 SyncGuard: tryAcquire GRANTED for "$label"',
    );
    return true;
  }

  /// سجّل بدء مزامنة. يجب استدعاؤها فوراً بعد [canStart] تُعيد true.
  ///
  /// ⚠️ يُفضّل استخدام [tryAcquire] بدلاً من `canStart + markStarted`.
  static void markStarted({required String label}) {
    // ✅ Sync Safety Fix (2026-08-10): كشف double-acquire.
    // إذا كانت هناك مزامنة نشطة ولم تنتهِ صلاحيتها (stale)، هذا يشير إلى
    // bug في caller (نسيان markFinished في finally block). نسجّل تحذيراً
    // صريحاً ونُلغي الـ lock القديم (لأن caller الجديد سيتولى المسؤولية).
    if (_activeSyncStartedAt != null) {
      final elapsed = DateTime.now().difference(_activeSyncStartedAt!);
      if (elapsed <= _staleLockTimeout) {
        dlog(
          () =>
              '⚠️ SyncGuard: DOUBLE-ACQUIRE detected! Overwriting active '
              'sync (label=$_activeSyncLabel, elapsed=${elapsed.inSeconds}s) '
              'with "$label". This indicates a missing markFinished() in '
              'a finally block — please audit the caller.',
        );
      }
    }
    _activeSyncStartedAt = DateTime.now();
    _activeSyncLabel = label;
  }

  /// سجّل انتهاء المزامنة. يجب استدعاؤها في `finally` block دائماً.
  ///
  /// ✅ Sync Safety Fix (2026-08-10): تُسجّل رسالة تشخيصية للكشف عن
  /// finally blocks المفقودة. إذا لم تكن هناك مزامنة نشطة، هذا يشير إلى
  /// bug (markFinished استُدعيت بدون markStarted مقابلة).
  static void markFinished() {
    if (_activeSyncStartedAt == null) {
      dlog(
        () => '⚠️ SyncGuard: markFinished() called but no active sync! '
            'This indicates a missing or duplicate markStarted() call.',
      );
      return;
    }
    final elapsed = DateTime.now().difference(_activeSyncStartedAt!);
    dlog(
      () => '🔒 SyncGuard: markFinished() — label="$_activeSyncLabel" '
          '(elapsed=${elapsed.inSeconds}s)',
    );
    _activeSyncStartedAt = null;
    _activeSyncLabel = null;
  }

  /// حالة التشخيص — هل توجد مزامنة نشطة الآن؟
  static bool get isActive => _activeSyncStartedAt != null;

  /// معرّف الخدمة النشطة حالياً (للتشخيص فقط).
  static String? get activeLabel => _activeSyncLabel;
}
