import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/debug_log.dart';
import 'appwrite_sync_manager.dart';

/// تصنيف نتيجة تقييم «السحب الكامل بعد التخطي» — لتغطية اختبارية دقيقة
/// لكل فرع من فروع السياسة دون الحاجة لمدير مزامنة حقيقي.
enum BootstrapFullPullOutcome {
  /// المستخدم لم يتخطَّ شاشة تسجيل الدخول (سجّل دخوله أو دخل بحساب محفوظ)
  /// — لا مجال لأي سحب بعد التخطي.
  notApplicable,

  /// سبق إتمام سحب كامل: إمّا العلامة مضبوطة من إطلاق سابق، أو
  /// manager.isFullSyncCompleted=true (سحب كامل نجح بأي مسار آخر كالإعدادات).
  alreadyDone,

  /// نجح السحب الكامل الآن — علامة الإتمام ضُبطت بعد نجاح السحب فقط.
  succeeded,

  /// فشل السحب الآن (لا شبكة / worker غير متاح / فشل جزئي) — العلامة تبقى
  /// فارغة لإعادة المحاولة تلقائياً عند الإطلاق التالي.
  failed,
}

/// ✅ (2026-09-06) طلب المستخدم: «عند تثبيت التطبيق والضغط على زر
/// المتابعة بدون مزامنة يتم سحب full sync».
///
/// يضمن أن تخطي شاشة تسجيل الدخول («المتابعة بدون مزامنة») يُنتج سحباً
/// كاملاً (full sync pull) من Cloudflare D1، وأنه **يُعاد تلقائياً عند
/// كل إطلاق حتى ينجح**.
///
/// لماذا هذه الخدمة؟ (ثغرة السلوك السابق — بأدلة الكود):
/// - محاولة السحب الوحيدة كانت لحظة التخطي (fire-and-forget صامتة في
///   google_drive_login_screen.dart — الأصل 2026-09-01).
/// - إن فشلت (لا شبكة / worker غير متاح / فشل تسجيل دخول الـ worker):
///   1. شاشة تسجيل الدخول لا تظهر مجدداً بعد التخطي —
///      backup_provider.dart:171 requiresDriveLogin =
///      !isSignedIn && !driveLoginSkipped، وdrive_login_skipped=true
///      بمجرد تأكيد «المتابعة بدون مزامنة» — فلا إعادة محاولة منها.
///   2. المسارات الخلفية (UnifiedSyncOrchestrator.onAppForeground →
///      _syncAppwrite pull) تعمل بـ deltaOnly:true الذي يرفض بدء
///      full sync على جهاز في مرحلة bootstrap (نمط حارس الركود
///      ASM:760 — unified_sync_orchestrator.dart:519).
///   3. النتيجة: قاعدة بيانات فارغة إلى ما لا نهاية ما لم يفتح المستخدم
///      الإعدادات يدوياً — عكس طلب المستخدم صراحة.
///
/// الدلالة (idempotent — آمن للاستدعاء من مواقع متعددة):
/// - التنفيذ فقط إذا: تخطَّ المستخدم + (علامة الإتمام غير مضبوطة) +
///   (!manager.isFullSyncCompleted).
/// - علامة الإتمام تُضبط **بعد** اكتمال السحب فقط (نفس دلالات علم
///   2026-09-01: SUCCESS → ضبط، FAILURE → تبقى فارغة لإعادة المحاولة).
/// - من سبق له سحب كامل بأي مسار تُقرَب العلامة ويُنهى العمل بلا سحب
///   إضافي (منع ازدواج السحب الكامل).
class BootstrapFullPull {
  BootstrapFullPull._();

  /// علم «تم السحب الكامل بعد التخطي» — نفس مفتاح 2026-09-01
  /// (appwrite_pull_after_drive_skip_done) حفاظاً على توافق بيانات
  /// التركيبات القائمة؛ يُضبط بعد اكتمال السحب فقط.
  static const String pullDoneFlagKey = 'appwrite_pull_after_drive_skip_done';

  /// علم تخطي تسجيل الدخول — مطابق لـ
  /// BackupStatusNotifier._driveLoginSkippedKey (backup_provider.dart:26).
  static const String driveLoginSkippedKey = 'drive_login_skipped';

  static bool _inFlight = false;

  /// هل السحب قيد التنفيذ الآن؟ — حماية من التداخل بين نداء لحظة
  /// التخطي (شاشة الدخول) ونداء إطلاق الـ shell في نفس الجلسة.
  static bool get isRunning => _inFlight;

  /// النواة الصافية القابلة للاختبار: تقييم الشروط وتنفيذ السحب عبر
  /// مُغلَّفات محقونة — بلا SharedPreferences ولا HTTP حقيقي.
  @visibleForTesting
  static Future<BootstrapFullPullOutcome> evaluate({
    required bool driveLoginSkipped,
    required bool pullDoneFlag,
    required bool isFullSyncCompleted,
    required Future<bool> Function() initializeAndFullPull,
    required Future<void> Function(bool value) setPullDoneFlag,
  }) async {
    if (!driveLoginSkipped) {
      return BootstrapFullPullOutcome.notApplicable;
    }
    if (pullDoneFlag || isFullSyncCompleted) {
      // تقارب العلامتين: من أتم سحباً كاملاً بأي مسار نعتبر طلب التخطي
      // مجاباً — منع أي سحب كامل إضافي غير مطلوب.
      if (!pullDoneFlag) {
        await setPullDoneFlag(true);
      }
      return BootstrapFullPullOutcome.alreadyDone;
    }
    final ok = await initializeAndFullPull();
    if (ok) {
      await setPullDoneFlag(true);
      return BootstrapFullPullOutcome.succeeded;
    }
    // الفشل لا يضبط العلامة — إعادة المحاولة عند الإطلاق القادم.
    return BootstrapFullPullOutcome.failed;
  }

  /// نقطة الإدخال الإنتاجية — تُستدعى من:
  /// 1. شاشة تسجيل الدخول لحظة تأكيد «المتابعة بدون مزامنة» (فوري).
  /// 2. HomeShell عند كل إطلاق (main.dart) — إعادة المحاولة التلقائية
  ///    حتى النجاح.
  ///
  /// يعيد true إذا كان السحب الكامل مكتماً (سابقاً أو الآن). الاستدعاء
  /// المتداخل يعيد false فوراً بلا تنفيذ (in-flight guard).
  static Future<bool> ensureFullPullAfterSkip({
    required AppwriteSyncManager manager,
    SharedPreferences? prefs,
  }) async {
    if (_inFlight) {
      return false;
    }
    _inFlight = true;
    try {
      final sp = prefs ?? await SharedPreferences.getInstance();
      final outcome = await evaluate(
        driveLoginSkipped: sp.getBool(driveLoginSkippedKey) ?? false,
        pullDoneFlag: sp.getBool(pullDoneFlagKey) ?? false,
        isFullSyncCompleted: manager.isFullSyncCompleted,
        initializeAndFullPull: () async {
          await manager.initialize();
          return manager.pullAllDataWithDisabledFK();
        },
        setPullDoneFlag: (value) async {
          await sp.setBool(pullDoneFlagKey, value);
        },
      );
      dlog(() => '⬇️ BootstrapFullPull: $outcome');
      return outcome == BootstrapFullPullOutcome.succeeded ||
          outcome == BootstrapFullPullOutcome.alreadyDone;
    } catch (e) {
      dlog(() => '❌ BootstrapFullPull error: $e');
      return false;
    } finally {
      _inFlight = false;
    }
  }
}
