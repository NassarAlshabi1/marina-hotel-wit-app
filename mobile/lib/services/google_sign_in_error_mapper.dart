// ✅ (2026-09-10) مُخطِّئ أخطاء Google Sign-In إلى رسائل عربية قابلة للتنفيذ.
//
// السياق الهندسي: كان GoogleDriveSignInManager.signIn يبتلع الاستثناء
// الحقيقي (`catch { return null; }`) فلا يصل سبب الفشل أبداً إلى المستخدم —
// تُعرض «فشل تسجيل الدخول» عامة بلا دليل. هذه الدالة تُستدعى الآن في نهاية
// المسار بكل الأحوال، وتستخرج رمز ApiException من نص الاستثناء ثم تُترجمه.
//
// المرجع لرموز ApiException:
// https://developers.google.com/android/reference/com/google/android/gms/common/api/CommonStatusCodes
import 'package:flutter/services.dart' show PlatformException;

/// SHA-1 المسجّل لشهادة توقيع التطبيق في Google Cloud (aden-flutter) —
/// مطابق لـ google-services.json وشهادة release.keystore الموحّدة.
/// يُعرض في قسم التشخيص ليتحقق المستخدم عند ظهور DEVELOPER_ERROR.
const String kRegisteredSigningSha1 =
    '67:12:57:A2:9B:53:FA:71:AC:BC:0F:A8:C9:54:2F:3F:46:0B:A8:1C';

/// اسم الحزمة المسجّل في Google Cloud — لعرضه في قسم التشخيص.
const String kRegisteredPackageName = 'com.marina.marina';

/// يستخرج رمز ApiException الرقمي من أي استثناء (PlatformException أو نص).
///
/// رسالة الأندرويد تأتي بالشكل:
/// `com.google.android.gms.common.api.ApiException: 10: DEVELOPER_ERROR`
int? _extractApiExceptionCode(Object? error) {
  if (error == null) {
    return null;
  }
  final String text = error is PlatformException
      ? '${error.message ?? ''} ${error.details ?? ''} ${error.code}'
      : error.toString();
  final RegExpMatch? match = RegExp(
    r'ApiException:\s*(-?\d+)',
  ).firstMatch(text);
  if (match != null) {
    return int.tryParse(match.group(1)!);
  }
  return null;
}

String? _platformMessage(PlatformException e) =>
    e.message ?? e.details?.toString();

/// يترجم خطأ Google Sign-In (أو غيابه الكلي عند `null`) إلى رسالة عربية
/// تشرح السبب وتقول للمستخدم ماذا يفعل بالضبط.
String describeGoogleSignInFailure(Object? error) {
  // ── الحالة الأهم: لا استثناء وصلنا أصلاً (مسكوم في المدير) ──
  if (error == null) {
    return 'لم يصل سبب الفشل من خدمات Google. أعد المحاولة؛ إن تكرر '
        'فجرّب تسجيل الدخول من حساب Google على الجهاز أولاً.';
  }

  // ── رمز ApiException الرقمي هو الأدق إن وُجد ──
  final int? apiCode = _extractApiExceptionCode(error);
  final String codeLabel = apiCode != null ? ' (رمز $apiCode)' : '';

  switch (apiCode) {
    case 10: // DEVELOPER_ERROR
      return 'بيانات التطبيق غير مطابقة لإعدادات Google Cloud$codeLabel. '
          'تأكد أن التطبيق المثبّت موقّع بشهادة SHA-1 '
          '$kRegisteredSigningSha1 '
          'باسم الحزمة $kRegisteredPackageName داخل مشروع aden-flutter. '
          'إن كنت تستخدم بنية غير رسمية فهذا هو السبب.';
    case 7: // NETWORK_ERROR
      return 'تعذّر الوصول إلى خوادم Google$codeLabel. تحقق من الإنترنت '
          'وأعد المحاولة — بعض الشبكات تحجب نطاقات Google حتى مع عمل '
          'المتصفح.';
    case 4: // SIGN_IN_REQUIRED
      return 'انتهت صلاحية جلسة Google$codeLabel. أعد تسجيل الدخول '
          'بالضغط على الزر واختر حسابك.';
    case 8: // INTERNAL_ERROR
      return 'خطأ داخلي في خدمات Google Play$codeLabel. أعد المحاولة بعد '
          'قليل، وإن تكرر حدّث تطبيق «خدمات Google Play» من المتجر.';
    case 12500: // CONFIGURATION / consent
      return 'إعداد تسجيل الدخول غير مكتمل$codeLabel. تحقق من شاشة موافقة '
          'OAuth في Google Cloud: أضف النطاقين drive.file و drive.appdata '
          'وضع التطبيق في وضع Testing مع إضافة بريدك كمستخدم اختباري '
          '(Test user).';
    case 12501: // SIGN_IN_CANCELLED
      return 'أُلغي تسجيل الدخول$codeLabel. إن لم تلغِ أنت فأغلق التطبيق '
          'وحاول مرة أخرى واختر حساباً من القائمة.';
    case 12502: // SIGN_IN_IN_PROGRESS
      return 'تسجيل دخول سابق جارٍ بعد$codeLabel. انتظر ثوانٍ ثم أعد '
          'المحاولة.';
  }

  // ── لا رمز رقمي: نعتمد على رمز المنصة ──
  if (error is PlatformException) {
    final String detail = _platformMessage(error) ?? '';
    switch (error.code) {
      case 'network_error':
        return describeGoogleSignInFailure(
          'ApiException: 7: NETWORK_ERROR ${detail.isEmpty ? '' : detail}',
        );
      case 'sign_in_canceled':
        return describeGoogleSignInFailure(
          'ApiException: 12501: SIGN_IN_CANCELLED ${detail.isEmpty ? '' : detail}',
        );
      case 'sign_in_required':
        return describeGoogleSignInFailure(
          'ApiException: 4: SIGN_IN_REQUIRED ${detail.isEmpty ? '' : detail}',
        );
      case 'user_recoverable_auth':
      case 'failed_to_recover_auth':
        return 'حساب Google يحتاج تفويضاً جديداً${detail.isEmpty ? '' : ' ($detail)'}. '
            'أعد تسجيل الدخول ووافق على أذونات Drive عند طلبها.';
      case 'channel-error':
        return 'خدمات Google Play غير متاحة داخل التطبيق (channel-error). '
            'تأكد أن الجهاز مثبّت فيه خدمات Google Play وليس إصداراً '
            'بدونها.';
      case 'sign_in_failed':
        return 'فشل تسجيل الدخول في خدمات Google Play$codeLabel. '
            '${detail.isEmpty ? 'أعد المحاولة.' : 'التفاصيل: $detail'}';
      default:
        return 'فشل غير متوقع في تسجيل الدخول '
            '${detail.isEmpty ? '(${error.code})' : '($detail)'}';
    }
  }

  // ── أي شيء آخر: نعرض النص كما هو مع سياق عربي ──
  return 'فشل غير متوقع في تسجيل الدخول: $error';
}
