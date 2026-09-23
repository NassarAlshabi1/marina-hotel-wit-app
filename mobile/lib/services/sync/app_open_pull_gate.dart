import 'package:shared_preferences/shared_preferences.dart';

import '../sync_constants.dart';

/// نتيجة فحص بوابة سحب فتح التطبيق: القرار + الحقول التشخيصية اللازمة
/// لسطر سجل بلا إعادة اشتقاقها في كل موقع استدعاء.
typedef AppOpenPullGateStatus = ({
  bool shouldPull,
  Duration elapsedSinceLastPull,
  Duration remainingUntilNextPull,
});

/// بوابة زمنية موحّدة لسحب "فتح التطبيق" (الإقلاع البارد عبر
/// main.dart::_startRealtimeSync، والعودة من الخلفية عبر
/// UnifiedSyncOrchestrator::onAppForeground).
///
/// ✅ (توحيد 2026-09-23): كان المساران يطبّقان نفس المنطق (قراءة
/// [SyncConstants.lastAppOpenPullKey]، مقارنته بـ
/// [SyncConstants.appOpenSyncInterval]، وختمه بعد نجاح سحب فعلي فقط)
/// بنسختين منفصلتين قابلتين للانحراف عن بعضهما عند أي تعديل مستقبلي
/// (تعديل الفاصل الزمني أو مفتاح prefs في ملف دون الآخر). استُخلص هنا
/// كمصدر وحيد للحقيقة — القرار والختم فقط؛ استدعاء عملية السحب الفعلية
/// يبقى مسؤولية كل مسار (يختلفان: الإقلاع البارد سحب فقط، والعودة من
/// الخلفية رفع دائماً + سحب مشروط).
abstract final class AppOpenPullGate {
  /// يفحص [SyncConstants.lastAppOpenPullKey] المخزَّن في [prefs] ويُعيد
  /// القرار مع بيانات السجل التشخيصية. `shouldPull == true` دوماً إن لم
  /// يُسجَّل أي سحب سابق.
  static AppOpenPullGateStatus check(
    SharedPreferences prefs, {
    DateTime? now,
  }) {
    final effectiveNow = now ?? DateTime.now();
    final lastPullEpochMs = prefs.getInt(SyncConstants.lastAppOpenPullKey);
    if (lastPullEpochMs == null) {
      return (
        shouldPull: true,
        elapsedSinceLastPull: Duration.zero,
        remainingUntilNextPull: Duration.zero,
      );
    }

    final lastPull = DateTime.fromMillisecondsSinceEpoch(lastPullEpochMs);
    final elapsed = effectiveNow.difference(lastPull);
    final remaining = SyncConstants.appOpenSyncInterval - elapsed;
    return (
      shouldPull: elapsed >= SyncConstants.appOpenSyncInterval,
      elapsedSinceLastPull: elapsed,
      remainingUntilNextPull: remaining.isNegative ? Duration.zero : remaining,
    );
  }

  /// يُستدعى بعد نجاح سحب فعلي فقط — يختم مؤشر "آخر سحب" بالوقت الحالي.
  /// لا تستدعِ هذه الدالة عند تخطي السحب أو فشله (راجع تعليق
  /// [SyncConstants.lastAppOpenPullKey] — ختم غير مشروط يقمع أي سحب
  /// حقيقي لاحق حتى [SyncConstants.appOpenSyncInterval] كاملة).
  static Future<void> markPulled(SharedPreferences prefs, {DateTime? now}) {
    return prefs.setInt(
      SyncConstants.lastAppOpenPullKey,
      (now ?? DateTime.now()).millisecondsSinceEpoch,
    );
  }
}
