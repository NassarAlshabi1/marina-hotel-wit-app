package com.marina.marina.data.sync

import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import com.marina.marina.data.remote.SyncPreferences
import dagger.hilt.android.AndroidEntryPoint
import javax.inject.Inject

/**
 * خدمة رسائل Firebase — نظير `FcmService` في Flutter
 * (`mobile/lib/services/fcm_service.dart`، فرع feat/cloudflare-sync-execution)
 * بقدر ما يخص مسار السحب فقط:
 *
 *  • عقد المصدر: `type` (أو `source`) = `marina_sync` وإلا تُتجاهل الرسالة.
 *  • **echo filter**: رسالة من نفس الجهاز (`senderDeviceId` == deviceId)
 *    لا تُطلق سحباً.
 *  • الإشارة تُسلَّم إلى [AutoSyncEngine.onRemoteSignal]: في الواجهة =
 *    شارة + سحب دلتا مُدمج؛ في الخلفية = تُحفظ وتُستهلك عند العودة
 *    (بديل Android صريح لبدء شبكة من عملية غير ظاهرة).
 *
 * ما لم يُنقل عمداً: إشعارات FCM المحلية وعرض الحمولة — ليست جزءاً من
 * عقد سحب التغييرات، وهذا التغيير محصور في مسار السحب.
 */
@AndroidEntryPoint
class MarinaMessagingService : FirebaseMessagingService() {

    @Inject lateinit var autoSyncEngine: AutoSyncEngine
    @Inject lateinit var preferences: SyncPreferences

    override fun onMessageReceived(message: RemoteMessage) {
        val data = message.data
        // التصفية كلها في [RemoteSignalPolicy] الخالصة (مصدر + صدى) — تُختبر
        // بدقة بلا Hilt ولا محاكٍ، ويبقى هنا التوصيل فقط.
        if (!RemoteSignalPolicy.isSyncMessage(data)) return
        if (RemoteSignalPolicy.isOwnEcho(data, preferences.getDeviceId())) return
        autoSyncEngine.onRemoteSignal(source = FCM_SOURCE)
    }

    override fun onNewToken(token: String) {
        // تسجيل توكن الأجهزة ليس جزءاً من عقد سحب التغييرات — لا تغيير هنا.
    }

    companion object {
        /** وسم المصدر في تشخيصات العميل (شارة Realtime). */
        const val FCM_SOURCE = "fcm"

        /** نفس مصدر رسائل Flutter (`data['type'] == 'marina_sync'`). */
        const val MARINA_SYNC_SOURCE = RemoteSignalPolicy.MARINA_SYNC_SOURCE
    }
}
