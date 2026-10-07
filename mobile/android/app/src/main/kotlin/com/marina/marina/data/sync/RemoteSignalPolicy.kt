package com.marina.marina.data.sync

/**
 * سياسة إشارة التغيير البعيد (FCM/Realtime) — منطق خالص بلا أي اعتماد على
 * أندرويد، فيُختبر مباشرةً بدقة بلا محاكٍ ولا شبكة (نظير
 * `handleIncomingMessage`/`_onData` في Dart القابلة للاختبار).
 *
 * المستهلكان:
 *  • [MarinaMessagingService] — تصفية رسالة FCM: المصدر ثم صدى الجهاز نفسه.
 *  • [AutoSyncEngine] — قرار ما يُفعل بالإشارة: تجاهل/تسليم فوري/تأجيل
 *    حتى العودة للواجهة.
 *
 * مرجع Flutter: `fcm_service.dart` l.230-250 (تصفية المصدر والصدى)
 * وl.253-285 (`_triggerPull`)، و`cloudflare_realtime_sync.dart`
 * l.497-520 (echo filter لحدث WebSocket).
 */
internal object RemoteSignalPolicy {

    /** نفس مصدر رسائل Flutter: `data['type'] == 'marina_sync'`. */
    const val MARINA_SYNC_SOURCE = "marina_sync"

    /** ما يُفعل بالإشارة الواردة. */
    enum class Decision { IGNORE, DELIVER, DEFER }

    /**
     * هل الرسالة إشارة مزامنة؟ يُقرأ `type` أولاً ثم `source` — نفس ترتيب
     * Dart حرفياً (`data['type'] ?? data['source']`).
     */
    fun isSyncMessage(data: Map<String, String>): Boolean =
        (data["type"] ?: data["source"]) == MARINA_SYNC_SOURCE

    /**
     * echo filter: رسالة من نفس الجهاز لا تُطلق سحباً.
     *
     * المطابقة الحرفية لعقد Flutter: `senderDeviceId != null && myId ==
     * senderDeviceId` — ولذلك:
     *  • `senderDeviceId` غائب ⇒ **ليست** صدى (نسحب على أي حال، نفس تعليق
     *    Dart: «لا يوجد معرف جهاز مرسل — نسحب على أي حال»).
     *  • `deviceId` المحلي غائب ⇒ لا مطابقة ⇒ نسحب.
     *  • مطابقة تامة (بما فيها سلسلتان فارغتان) ⇒ صدى.
     */
    fun isOwnEcho(data: Map<String, String>, ownDeviceId: String?): Boolean {
        val sender = data["senderDeviceId"] ?: return false
        return sender == ownDeviceId
    }

    /**
     * قرار الإشارة: المفتاح المعطّل يتجاهلها كلياً؛ الواجهة تُسلّمها لمسار
     * السحب فوراً؛ الخلفية تؤجلها حتى العودة (قيد Android على بدء عمل
     * شبكي من عملية غير ظاهرة — بديل موثق لا ادعاء مطابقة).
     */
    fun decide(masterSyncEnabled: Boolean, foreground: Boolean): Decision = when {
        !masterSyncEnabled -> Decision.IGNORE
        foreground -> Decision.DELIVER
        else -> Decision.DEFER
    }

    /**
     * هل تُستهلك الإشارة المؤجَّلة الآن؟ لا تُستهلك — ولا تُسقَط — حتى
     * يكتمل الشرطان معاً؛ إشارة عُدنا للواجهة مع شبكة ممنوعة (wifi-only
     * بلا واي فاي مثلاً) تبقى مؤجلة للعودة التالية.
     */
    fun shouldConsumeDeferred(masterSyncEnabled: Boolean, networkAllowed: Boolean): Boolean =
        masterSyncEnabled && networkAllowed
}
