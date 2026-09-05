import 'package:marina_hotel_mobile/utils/debug_log.dart';

import 'sync_constants.dart';
import 'sync_priority.dart';

/// ✅ Wave 5 (2026-08-12): SyncGuard — ownership-aware lock mechanism.
///
/// حارس مشترك لمنع تداخل عمليات المزامنة عبر الخدمات المختلفة.
///
/// ✅ إصلاح P2-10: بدلاً من دمج 8 Timer.periodic مختلفة (التي تشغّلها
/// `SmartSyncManager`, `GoogleDriveUnifiedSyncCoordinator`, `AppwriteSyncManager`)
/// في موجد موحد واحد — وهو refactor معماري كبير ومخاطر عالية — نضيف هذا
/// الحارس الخفيف كطبقة throttle عبرية.
///
/// ✅ Wave 5 (2026-08-12): ownership-safe release.
/// كل عملية تحصل على `SyncLockToken` فريدة عند `tryAcquire`. لا يمكن
/// `release(token)` فك القفل إلا بنفس الـ token (أو عند expiry/stale).
/// هذا يمنع:
/// - **stale release**: عملية قديمة تفك lock تم اكتسابه بعملية أحدث
/// - **cross-release**: عملية تفك lock عملية أخرى
/// - **double-acquire misuse**: اكتساب جديد قبل تحرير القديم بدون تسجيل
///
/// الاستخدام (الجديد):
/// ```dart
/// final token = SyncGuard.tryAcquire(label: 'smart_sync');
/// if (token == null) return; // acquire failed
/// try {
///   await _performSync();
/// } finally {
///   SyncGuard.release(token);
/// }
/// ```
///
/// التوافق الرجعي: `tryAcquire` القديم الذي يُرجع bool ما زال يعمل، لكن
/// لا يوفر ownership safety. يُنصح بالمهاجرة للـ token API.
class SyncGuard {
  SyncGuard._();

  /// الإعدادات الحالية (الافتراضية)
  static const _defaultStaleLockTimeout =
      SyncConstants.syncGuardMaxHoldDuration;

  static Duration _staleLockTimeout = _defaultStaleLockTimeout;

  static void configureTimeouts({
    Duration? lockTimeout,
    Duration? staleLockTimeout,
  }) {
    // lockTimeout هو الاسم التاريخي لنفس مهلة الكشف عن القفل المنتهي.
    // نبقيه للتوافق مع الاستدعاءات القديمة، وتعطى القيمة الجديدة أولوية.
    final timeout = staleLockTimeout ?? lockTimeout;
    if (timeout != null) {
      _staleLockTimeout = timeout;
    }
  }

  /// وقت بدء آخر مزامنة نشطة عبر جميع الخدمات.
  static DateTime? _activeSyncStartedAt;

  /// اسم الخدمة التي تُنفّذ المزامنة الحالية (للتشخيص).
  static String? _activeSyncLabel;

  /// ✅ Wave 5: ownership token — معرّف فريد لكل عملية اكتسبت القفل.
  /// يُستخدم للتحقق من أن `release()` يُستدعى من نفس العملية.
  static int _activeSyncToken = 0;

  /// مولّد token متزايد لضمان الفريدة.
  static int _tokenCounter = 0;

  /// تحقق ما إذا كان يمكن بدء مزامنة جديدة الآن.
  ///
  /// ⚠️ **محفوظة للتوافق الرجعي** — يُنصح باستخدام [tryAcquire] (الذي
  /// يُرجع token) بدلاً منها.
  static bool canStart({required String label}) {
    if (_activeSyncStartedAt == null) return true;
    final elapsed = DateTime.now().difference(_activeSyncStartedAt!);
    if (elapsed > _staleLockTimeout) {
      dlog(
        () =>
            '⚠️ SyncGuard: stale lock detected (label=$_activeSyncLabel, '
            'elapsed=${elapsed.inSeconds}s) — allowing $label to proceed',
      );
      // ✅ Sync Safety Fix: مسح الـ stale lock فوراً
      _activeSyncStartedAt = null;
      _activeSyncLabel = null;
      _activeSyncToken = 0;
      return true;
    }
    return false;
  }

  /// ✅ Wave 5 (2026-08-12): atomic try-acquire مع ownership token.
  ///
  /// يدمج canStart + markStarted في عملية واحدة ذرية. يُرجع `SyncLockToken`
  /// فريد إذا تم اكتساب القفل، أو `null` إذا كانت مزامنة أخرى نشطة.
  ///
  /// **الاستخدام**:
  /// ```dart
  /// final token = SyncGuard.tryAcquire(label: 'appwrite_sync');
  /// if (token == null) return;
  /// try {
  ///   await sync();
  /// } finally {
  ///   SyncGuard.release(token);
  /// }
  /// ```
  ///
  /// **ownership safety**: فقط `release(token)` بنفس الـ token يفك القفل.
  /// هذا يمنع stale release و cross-release (انظر [release]).
  static SyncLockToken? tryAcquire({
    required String label,
    SyncPriority? priority,
  }) {
    if (!canStart(label: label)) {
      dlog(
        () =>
            '🔒 SyncGuard: tryAcquire REJECTED for "$label" — '
            'active="$_activeSyncLabel" '
            '(elapsed=${(_activeSyncStartedAt != null) ? DateTime.now().difference(_activeSyncStartedAt!).inSeconds : 0}s)',
      );
      return null;
    }
    _tokenCounter += 1;
    _activeSyncToken = _tokenCounter;
    _activeSyncStartedAt = DateTime.now();
    _activeSyncLabel = label;
    dlog(
      () =>
          '🔒 SyncGuard: tryAcquire GRANTED for "$label" (token=#$_activeSyncToken)',
    );
    return SyncLockToken._(_activeSyncToken, label);
  }

  /// ✅ Wave 5: تحرير القفل بـ ownership verification.
  ///
  /// فقط الـ token الصحيح (الذي اكتسب القفل) يستطيع فكه. هذا يمنع:
  /// - **stale release**: عملية قديمة تحاول فك lock اكتسبته عملية أحدث.
  ///   مثلاً: sync-A اكتسب القفل، ثم sync-B اكتسب القفل بعد stale timeout،
  ///   ثم sync-A يحاول فك القفل — يجب أن يُرفض.
  /// - **cross-release**: عملية تُفك lock عملية أخرى عن طريق الخطأ.
  ///
  /// **استثناء**: إذا القفل أصبح stale (تجاوز [_staleLockTimeout])، فإن
  /// أي token يُفك القفل بأمان (لأن الـ lock معتبر منتهي الصلاحية).
  ///
  /// **الاستخدام**:
  /// ```dart
  /// final token = SyncGuard.tryAcquire(label: 'sync');
  /// if (token == null) return;
  /// try {
  ///   await work();
  /// } finally {
  ///   SyncGuard.release(token); // ownership-safe
  /// }
  /// ```
  static void release(SyncLockToken token) {
    if (_activeSyncStartedAt == null) {
      // لا يوجد lock نشط — تسجيل فقط (لا يمكن release ما لا يملك)
      dlog(
        () =>
            '⚠️ SyncGuard: release(token=#${token._value}) called but no active sync '
            '(label="${token._label}")',
      );
      return;
    }

    final isOwner = token._value == _activeSyncToken && token._value > 0;
    final elapsed = DateTime.now().difference(_activeSyncStartedAt!);
    final isStale = elapsed > _staleLockTimeout;

    if (!isOwner && !isStale) {
      // ✅ ownership violation — عملية تحاول فك lock لا تملكه
      dlog(
        () =>
            '⚠️ SyncGuard: release REJECTED for token=#${token._value} '
            '(label="${token._label}") — current owner is token=#$_activeSyncToken '
            '(label="$_activeSyncLabel"). This is a stale/cross release attempt.',
      );
      return;
    }

    if (!isOwner && isStale) {
      // stale release — مسموح ولكن نسجل تحذيراً
      dlog(
        () =>
            '⚠️ SyncGuard: stale release accepted for token=#${token._value} '
            '(label="${token._label}") — lock was stale (elapsed=${elapsed.inSeconds}s, '
            'current_owner=#$_activeSyncToken/$_activeSyncLabel)',
      );
    } else {
      dlog(
        () =>
            '🔒 SyncGuard: release OK for token=#${token._value} '
            '(label="${token._label}", elapsed=${elapsed.inSeconds}s)',
      );
    }
    _activeSyncStartedAt = null;
    _activeSyncLabel = null;
    _activeSyncToken = 0;
  }

  /// سجّل بدء مزامنة. يجب استدعاؤها فوراً بعد [canStart] تُعيد true.
  ///
  /// ⚠️ يُفضّل استخدام [tryAcquire] (الذي يُرجع token) بدلاً من `canStart + markStarted`.
  /// `markStarted` لا يوفر ownership safety.
  static void markStarted({required String label}) {
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
    _tokenCounter += 1;
    _activeSyncToken = _tokenCounter;
    _activeSyncStartedAt = DateTime.now();
    _activeSyncLabel = label;
  }

  /// سجّل انتهاء المزامنة. يجب استدعاؤها في `finally` block دائماً.
  ///
  /// ⚠️ **محفوظة للتوافق الرجعي** — لا توفر ownership safety.
  /// يُنصح باستخدام [release] مع token بدلاً منها.
  static void markFinished() {
    if (_activeSyncStartedAt == null) {
      dlog(
        () =>
            '⚠️ SyncGuard: markFinished() called but no active sync! '
            'This indicates a missing or duplicate markStarted() call.',
      );
      return;
    }
    final elapsed = DateTime.now().difference(_activeSyncStartedAt!);
    dlog(
      () =>
          '🔒 SyncGuard: markFinished() — label="$_activeSyncLabel" '
          '(elapsed=${elapsed.inSeconds}s)',
    );
    _activeSyncStartedAt = null;
    _activeSyncLabel = null;
    _activeSyncToken = 0;
  }

  /// حالة التشخيص — هل توجد مزامنة نشطة الآن؟
  static bool get isActive => _activeSyncStartedAt != null;

  /// معرّف الخدمة النشطة حالياً (للتشخيص فقط).
  static String? get activeLabel => _activeSyncLabel;
}

/// ✅ Wave 5 (2026-08-12): SyncLockToken — ownership token لـ SyncGuard.
///
/// يُرجع من `SyncGuard.tryAcquire()` ويُستخدم في `SyncGuard.release(token)`
/// للتحقق من أن الـ release من نفس العملية التي اكتسبت القفل.
///
/// الـ token غير قابل للتزوير (private constructor) ويحتوي على:
/// - `_value`: معرّف فريد متزايد
/// - `_label`: اسم الخدمة التي اكتسبت القفل (للتشخيص)
class SyncLockToken {
  final int _value;
  final String _label;

  SyncLockToken._(this._value, this._label);

  @override
  String toString() => 'SyncLockToken(#$_value, $_label)';
}
