package com.marina.marina.domain.model

/**
 * حالة المزامنة الفورية (Realtime WebSocket) كما تعرضها الواجهات —
 * مرآة تشخيصات Flutter (`CloudflareRealtimeSync`: connected/lastError/
 * lastErrorAt/lastEventAt/lastConnectedAt/connectAttempts + شارة
 * `pendingRemoteChangesCount`) بصيغة أنقى تصلح لعرض Settings/Dashboard.
 */
data class RealtimeSyncState(
    /** المفتاح المحلي مفعّل + مزامنة Cloudflare مفعّلة. */
    val enabled: Boolean = false,
    /** قناة WebSocket مفتوحة الآن. */
    val connected: Boolean = false,
    /** عدد محاولات الاتصال الفعلية منذ بدء الاستماع (تشمل الفاشلة). */
    val connectAttempts: Int = 0,
    /** إعادة اتصال مجدولة الآن (backoff/rearm). */
    val reconnecting: Boolean = false,
    /** تغييرات بعيدة وصلت ولم يُستهلك حدثها بسحب ناجح بعد. */
    val pendingRemoteChanges: Int = 0,
    /** وقت آخر اتصال ناجح — null إن لم ينجح أي اتصال بعد. */
    val lastConnectedAt: Long? = null,
    /** وقت آخر إطار مستلم على المقبس (أي نوع) — دليل حياة الاتصال. */
    val lastEventAt: Long? = null,
    /** آخر خطأ اتصال مختصر (≤160 حرفاً) — null إن لم يفشل أي اتصال. */
    val lastError: String? = null,
    val lastErrorAt: Long? = null
) {
    val hasRemoteChanges: Boolean get() = pendingRemoteChanges > 0
}
