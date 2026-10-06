package com.marina.marina.data.remote.realtime

import android.app.Application
import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.marina.marina.data.remote.SyncPreferences
import com.marina.marina.data.remote.WorkerEndpoints
import com.marina.marina.di.EncryptedSharedPreferencesManager
import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * عميل Realtime — القرارات التي يمكن إثباتها بلا أي شبكة: بوابة الإعداد،
 * echo filter، شارة التغييرات، والتشخيصات. لا اختبار هنا يفتح مقبساً
 * حقيقياً؛ مسار الاتصال يخرج قبل `newWebSocket` عند غياب توكن Worker.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class)
class CloudflareRealtimeClientTest {

    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private val prefs: SyncPreferences get() = SyncPreferences(EncryptedSharedPreferencesManager(context))

    private fun client(preferences: SyncPreferences = prefs): CloudflareRealtimeClient =
        CloudflareRealtimeClient(OkHttpClient(), WorkerEndpoints(context), preferences)

    @Test
    fun startDoesNothingWhileTheLocalToggleIsOff() {
        val preferences = prefs
        preferences.setCloudflareSyncEnabled(true)
        preferences.setRealtimeSyncEnabled(false)
        val subject = client(preferences)
        try {
            subject.start()
            assertFalse(subject.isListeningForTest)
            assertFalse(subject.realtimeState.value.enabled)
            assertEquals(0, subject.realtimeState.value.connectAttempts)
            // مسار العودة للواجهة يحترم المفتاح أيضاً (لا مقبس ولا محاولة).
            subject.ensureStarted()
            assertFalse(subject.isListeningForTest)
            assertEquals(0, subject.realtimeState.value.connectAttempts)

            // عند التفعيل يعمل الاستئناف عادياً ثم يتوقف بأمان.
            preferences.setRealtimeSyncEnabled(true)
            subject.ensureStarted()
            assertTrue(subject.isListeningForTest)
            assertTrue(subject.realtimeState.value.enabled)
        } finally {
            subject.stop()
        }
    }

    @Test
    fun eventsFromOtherDevicesRaiseTheBadgeAndOwnEchoIsIgnored() {
        val preferences = prefs
        preferences.setCloudflareSyncEnabled(true)
        preferences.setRealtimeSyncEnabled(true)
        preferences.saveDeviceId("device-own")
        val subject = client(preferences)
        try {
            subject.handleIncomingMessage(
                RealtimeMessage(type = "change", entity = "bookings", deviceId = "device-other")
            )
            assertEquals(1, subject.realtimeState.value.pendingRemoteChanges)
            assertTrue(subject.realtimeState.value.hasRemoteChanges)

            // صدى جهازنا: لا شارة ولا سحب.
            subject.handleIncomingMessage(
                RealtimeMessage(type = "change", entity = "bookings", deviceId = "device-own")
            )
            assertEquals(1, subject.realtimeState.value.pendingRemoteChanges)

            // رسالة بلا deviceId (أو نوع غير change) لا تزيد الشارة.
            subject.handleIncomingMessage(RealtimeMessage(type = "presence", entity = "rooms", deviceId = "device-other"))
            assertEquals(1, subject.realtimeState.value.pendingRemoteChanges)
        } finally {
            subject.stop()
        }
    }

    @Test
    fun malformedFramesStillProveSocketLivenessWithoutRaisingTheBadge() {
        val preferences = prefs
        preferences.setCloudflareSyncEnabled(true)
        preferences.setRealtimeSyncEnabled(true)
        preferences.saveDeviceId("device-own")
        val subject = client(preferences)
        try {
            subject.handleMessageText("not json")
            assertNotNull(subject.realtimeState.value.lastEventAt)
            assertEquals(0, subject.realtimeState.value.pendingRemoteChanges)
        } finally {
            subject.stop()
        }
    }

    @Test
    fun disabledToggleIgnoresRemoteSignalsEntirely() {
        val preferences = prefs
        preferences.setCloudflareSyncEnabled(true)
        preferences.setRealtimeSyncEnabled(false)
        val subject = client(preferences)
        try {
            subject.noteRemoteChange("fcm")
            assertEquals(0, subject.realtimeState.value.pendingRemoteChanges)
        } finally {
            subject.stop()
        }
    }

    @Test
    fun stopClearsBadgeAndDiagnosticsRemainReadable() {
        val preferences = prefs
        preferences.setCloudflareSyncEnabled(true)
        preferences.setRealtimeSyncEnabled(true)
        preferences.saveDeviceId("device-own")
        val subject = client(preferences)
        subject.noteRemoteChange("ws")
        assertEquals(1, subject.realtimeState.value.pendingRemoteChanges)
        subject.noteSocketIssueForTest("boom")
        assertEquals("boom", subject.realtimeState.value.lastError)
        subject.stop()
        // stop() يصفّر الشارة ويغلق الاستماع — الاتصال ليس مفتوحاً بلا شبكة.
        assertFalse(subject.isListeningForTest)
        assertEquals(0, subject.realtimeState.value.pendingRemoteChanges)
        assertFalse(subject.realtimeState.value.connected)
    }

    @Test
    fun connectWithoutAWorkerTokenRecordsARecoverableIssueAndNeverThrows() {
        val preferences = prefs
        preferences.setCloudflareSyncEnabled(true)
        preferences.setRealtimeSyncEnabled(true)
        val subject = client(preferences)
        try {
            subject.start()
            subject.connectForTest()
            assertNotNull(subject.realtimeState.value.lastError)
            assertNull(preferences.getAuthToken())
        } finally {
            subject.stop()
        }
    }

    @Test
    fun clearRemoteChangesResetsOnlyTheBadge() {
        val preferences = prefs
        preferences.setCloudflareSyncEnabled(true)
        preferences.setRealtimeSyncEnabled(true)
        preferences.saveDeviceId("device-own")
        val subject = client(preferences)
        try {
            subject.noteRemoteChange("ws")
            subject.noteRemoteChange("fcm")
            assertEquals(2, subject.realtimeState.value.pendingRemoteChanges)
            subject.clearRemoteChanges()
            assertEquals(0, subject.realtimeState.value.pendingRemoteChanges)
            assertFalse(subject.realtimeState.value.hasRemoteChanges)
        } finally {
            subject.stop()
        }
    }
}
