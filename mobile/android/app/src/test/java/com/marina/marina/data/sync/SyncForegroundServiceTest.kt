package com.marina.marina.data.sync

import android.app.Service
import android.content.ComponentName
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class SyncForegroundServiceTest {
    private class RecordingContext(base: Context) : ContextWrapper(base) {
        var starts = 0
        var stops = 0
        var reject = false
        override fun startForegroundService(service: Intent): ComponentName {
            check(!reject) { "Background start denied" }
            starts++
            return ComponentName(this, SyncForegroundService::class.java)
        }
        override fun stopService(service: Intent): Boolean { stops++; return true }
    }

    @Test
    fun preflightAndNestedOperationShareServiceUntilLastRelease() {
        val context = RecordingContext(ApplicationProvider.getApplicationContext())
        val lifetime = SyncForegroundLifetime(context)
        val preflight = lifetime.acquire()
        val operation = lifetime.acquire()
        assertEquals(1, context.starts)
        preflight.close()
        preflight.close()
        assertEquals(0, context.stops)
        operation.close()
        assertEquals(1, context.stops)
        lifetime.acquire().close()
        assertEquals(2, context.starts)
        assertEquals(2, context.stops)
    }

    @Test
    fun rejectedStartDoesNotLeakReferenceCount() {
        val context = RecordingContext(ApplicationProvider.getApplicationContext())
        val lifetime = SyncForegroundLifetime(context)
        context.reject = true
        assertTrue(runCatching { lifetime.acquire() }.isFailure)
        context.reject = false
        lifetime.acquire().close()
        assertEquals(1, context.starts)
        assertEquals(1, context.stops)
    }

    @Test
    fun serviceImmediatelyPostsNotificationAndDoesNotRestartStaleSync() {
        val controller = Robolectric.buildService(SyncForegroundService::class.java).create()
        val service = controller.get()
        try {
            val notification = shadowOf(service).lastForegroundNotification
            assertNotNull(notification)
            assertEquals(SyncForegroundService.CHANNEL_ID, notification.channelId)
            assertEquals(Service.START_NOT_STICKY, service.onStartCommand(null, 0, 1))
        } finally { controller.destroy() }
        assertTrue(shadowOf(service).isForegroundStopped)
    }
}
