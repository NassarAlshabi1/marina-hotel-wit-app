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
        val source = data["type"] ?: data["source"]
        if (source != MARINA_SYNC_SOURCE) return
        val senderDeviceId = data["senderDeviceId"]
        val ownDeviceId = preferences.getDeviceId()
        if (!senderDeviceId.isNullOrEmpty() && senderDeviceId == ownDeviceId) return
        autoSyncEngine.onRemoteSignal(source = "fcm")
    }

    override fun onNewToken(token: String) {
        // تسجيل توكن الأجهزة ليس جزءاً من عقد سحب التغييرات — لا تغيير هنا.
    }

    companion object {
        /** نفس مصدر رسائل Flutter (`data['type'] == 'marina_sync'`). */
        const val MARINA_SYNC_SOURCE = "marina_sync"
    }
}
