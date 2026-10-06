package com.marina.marina.data.sync

/**
 * سياسات سلامة السحب — نقل حرفي لعقود `CloudflareSyncManager` في Flutter
 * (`mobile/lib/services/cloudflare_sync_manager.dart`، فرع
 * feat/cloudflare-sync-execution) إلى محرك Kotlin:
 *
 *  • **حراس المؤشر المسموم** (طبقات دفاع ثلاثية — Dart l.227/553/2081/2534):
 *    مؤشر سحب محفوظ بطوابع ميلي-ثانية (≥1e11) أو بطوابع sentinel/مستقبلية
 *    (≥2e9، أثر سكربت استعادة) يُعمي الجهاز للأبد: كل كتابة خادمية جديدة
 *    (ثواني ~1.79e9) تقع دونه في `WHERE updated_at > cursor` فلا تصل أبداً.
 *    الحد الثابت 2e9 يبقى صالحاً حتى سنة 2033 (الثواني الحالية تحت 2e9).
 *  • **رفض مؤشر خادم يتجاوز `server_time` المُعلن في الرد نفسه** بأكثر من
 *    هامش سنة (Dart l.2081) — مرآة عتبة الخادم FUTURE_TIMESTAMP_THRESHOLD:
 *    الصفحة لا تُطبَّق والدورة تفشل بلا تقدّم للمؤشر.
 *  • **بوابة مسح الحذفيات التاريخي لمرة واحدة** (Dart l.1794
 *    و_sweepHistoricalTombstones): الأجهزة التي سحبت أثناء نافذة العقد
 *    القديم (worker كان يفلتر tombstones من السحب) تجاوز مؤشرها حذفيات
 *    لم تُبَث لها أبداً. نافذة `tombstones_only=1` رخيصة، لا تمس المؤشر
 *    الرئيسي، وفشلها (شبكة/HTTP) يؤجّلها للدورة القادمة.
 *
 * كل الدوال هنا نقية وقابلة للاختبار بلا شبكة ولا قاعدة بيانات؛
 * [com.marina.marina.data.repository.SyncManager] يملك التدفق والتسجيل فقط.
 */

/** الحد الثابت للمؤشر المسموم: فوقه = طوابع ميلي/sentinel (سنة 2033 سقفاً). */
internal const val MAX_SANE_PULL_CURSOR_FUTURE = 2_000_000_000L

/** هامش تقدّم مؤشر الخادم على وقت الخادم المُعلن: سنة كاملة (Dart l.240). */
internal const val MAX_PULL_CURSOR_AHEAD_OF_SERVER_SEC = 366L * 24L * 60L * 60L

/** قرار فحص المؤشر المحفوظ عند الإقلاع/بداية الدورة. */
internal data class StoredCursorDecision(
    val poisoned: Boolean,
    val stored: Long
) {
    val mustReset: Boolean get() = poisoned
}

/**
 * فحص المؤشر المحفوظ (Dart `initialize` l.553): قيمة فوق الحد الثابت =
 * تسمم مؤكد (ميلي أو sentinel) → تصفير المؤشر + إسقاط علامة full sync
 * ليبدأ الجهاز سحباً كاملاً نظيفاً.
 */
internal fun evaluateStoredCursor(stored: Long): StoredCursorDecision =
    StoredCursorDecision(poisoned = stored > MAX_SANE_PULL_CURSOR_FUTURE, stored = stored)

/**
 * حارس أثناء التشغيل (Dart l.2081): مؤشر خادم يتقدّم فوق المؤشر المعلوم
 * المحلي بينما يتجاوز `server_time` المُعلن في الرد بأكثر من هامش سنة =
 * صفوف مسمومة ما زالت تُقدَّم (worker غير مُصلح/بيانات مستعادة).
 * غياب `server_time` (worker قديم) لا يمنع — طبقة التثبيت النهائية
 * ([isPendingCursorSafeToInstall]) تحكم بحد ثابت صرف.
 */
internal fun isServerCursorRejected(serverCursor: Long, serverTime: Long?): Boolean {
    if (serverTime == null) return false
    return serverCursor > serverTime + MAX_PULL_CURSOR_AHEAD_OF_SERVER_SEC
}

/**
 * حارس التثبيت النهائي (Dart l.2534): المؤشر المرشّح للكتابة فوق الحد
 * الثابت = لا يُخزَّن أبداً، بل يُصفَّر مع علامة full sync.
 */
internal fun isPendingCursorSafeToInstall(pendingCursor: Long): Boolean =
    pendingCursor <= MAX_SANE_PULL_CURSOR_FUTURE

/**
 * بوابة مسح الحذفيات التاريخي (Dart l.1794):
 *  • العلم لم يُضبط بعد، و
 *  • الجهاز قائم فعلاً (مؤشر > 0 أو اكتمل full sync سابقاً) — التثبيت
 *    الجديد سيجلب كل الحذفيات ضمن سحبه الكامل نفسه، فالمسح الإضافي هدر.
 */
internal fun tombstoneSweepDue(
    sweepDone: Boolean,
    storedCursor: Long,
    fullSyncComplete: Boolean
): Boolean = !sweepDone && (storedCursor > 0L || fullSyncComplete)
