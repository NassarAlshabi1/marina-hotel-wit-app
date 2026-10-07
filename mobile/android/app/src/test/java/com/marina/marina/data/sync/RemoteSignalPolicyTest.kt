package com.marina.marina.data.sync

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * عقد إشارة التغيير البعيد (FCM/Realtime) — منطق خالص يُختبر بلا أندرويد:
 * تصفية المصدر، echo filter، قرار التسليم/التأجيل، وبوابة استهلاك
 * الإشارة المؤجَّلة. المراجع في Dart: fcm_service.dart l.230-285
 * وcloudflare_realtime_sync.dart l.497-520.
 */
class RemoteSignalPolicyTest {

    // ─── 1) تصفية المصدر: type أولاً ثم source ────────────────────

    @Test
    fun syncMessageIsRecognizedFromTypeOrSourceOnly() {
        assertTrue(RemoteSignalPolicy.isSyncMessage(mapOf("type" to "marina_sync")))
        assertTrue(RemoteSignalPolicy.isSyncMessage(mapOf("source" to "marina_sync")))
        // type يتقدم على source — نفس `data['type'] ?? data['source']`.
        assertTrue(
            RemoteSignalPolicy.isSyncMessage(
                mapOf("type" to "marina_sync", "source" to "something_else")
            )
        )
        assertFalse(
            RemoteSignalPolicy.isSyncMessage(
                mapOf("type" to "something_else", "source" to "marina_sync")
            )
        )
        assertFalse(RemoteSignalPolicy.isSyncMessage(mapOf("type" to "chat")))
        assertFalse(RemoteSignalPolicy.isSyncMessage(emptyMap()))
        // المطابقة حرفية (لا تجاهل حالة الأحرف) — نفس Dart.
        assertFalse(RemoteSignalPolicy.isSyncMessage(mapOf("type" to "MARINA_SYNC")))
    }

    // ─── 2) echo filter: نفس عقد Dart بالحرف ─────────────────────

    @Test
    fun ownEchoMatchesOnlyWhenSenderIdEqualsThisDevice() {
        // صدى فعلي: مطابقة تامة.
        assertTrue(
            RemoteSignalPolicy.isOwnEcho(mapOf("senderDeviceId" to "dev-1"), "dev-1")
        )
        // جهاز آخر ⇒ ليست صدى (نسحب).
        assertFalse(
            RemoteSignalPolicy.isOwnEcho(mapOf("senderDeviceId" to "dev-2"), "dev-1")
        )
        // سلسلتان فارغتان مطابقة تامة ⇒ صدى (نفس `myId == senderDeviceId`).
        assertTrue(RemoteSignalPolicy.isOwnEcho(mapOf("senderDeviceId" to ""), ""))
        // إرسال بلا معرف جهاز ⇒ نسحب على أي حال (تعليق Dart صريح).
        assertFalse(RemoteSignalPolicy.isOwnEcho(emptyMap(), "dev-1"))
        // جهازنا بلا معرف بعد ⇒ لا مطابقة ممكنة ⇒ نسحب.
        assertFalse(
            RemoteSignalPolicy.isOwnEcho(mapOf("senderDeviceId" to "dev-1"), null)
        )
        // مفتاح مختلف (senderID) لا يُقرأ — العقد `senderDeviceId` فقط.
        assertFalse(
            RemoteSignalPolicy.isOwnEcho(mapOf("senderId" to "dev-1"), "dev-1")
        )
    }

    // ─── 3) قرار الإشارة ─────────────────────────────────────────

    @Test
    fun decisionIgnoresDisabledDeliversForegroundAndDefersBackground() {
        assertEquals(
            RemoteSignalPolicy.Decision.IGNORE,
            RemoteSignalPolicy.decide(masterSyncEnabled = false, foreground = true)
        )
        assertEquals(
            RemoteSignalPolicy.Decision.IGNORE,
            RemoteSignalPolicy.decide(masterSyncEnabled = false, foreground = false)
        )
        assertEquals(
            RemoteSignalPolicy.Decision.DELIVER,
            RemoteSignalPolicy.decide(masterSyncEnabled = true, foreground = true)
        )
        assertEquals(
            RemoteSignalPolicy.Decision.DEFER,
            RemoteSignalPolicy.decide(masterSyncEnabled = true, foreground = false)
        )
    }

    // ─── 4) بوابة استهلاك الإشارة المؤجَّلة ──────────────────────

    @Test
    fun deferredSignalIsConsumedOnlyWithSwitchAndNetwork() {
        assertTrue(
            RemoteSignalPolicy.shouldConsumeDeferred(masterSyncEnabled = true, networkAllowed = true)
        )
        assertFalse(
            RemoteSignalPolicy.shouldConsumeDeferred(masterSyncEnabled = true, networkAllowed = false)
        )
        assertFalse(
            RemoteSignalPolicy.shouldConsumeDeferred(masterSyncEnabled = false, networkAllowed = true)
        )
        assertFalse(
            RemoteSignalPolicy.shouldConsumeDeferred(masterSyncEnabled = false, networkAllowed = false)
        )
    }
}
