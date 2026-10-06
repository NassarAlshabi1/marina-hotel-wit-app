package com.marina.marina.data.remote

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.marina.marina.di.EncryptedSharedPreferencesManager
import java.net.URI
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Regression coverage for the boundary between endpoint aliases and data-source
 * identity. A custom hostname remains an alias/failover setting, not a provider
 * migration; the source pin is independent of hostname and cursor state.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class SyncProviderPortabilityAuditTest {

    private lateinit var context: Context
    private lateinit var endpoints: WorkerEndpoints
    private lateinit var preferences: SyncPreferences

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        context.getSharedPreferences("marina_cloudflare_prefs", Context.MODE_PRIVATE)
            .edit().clear().commit()
        context.getSharedPreferences("marina_secure_prefs", Context.MODE_PRIVATE)
            .edit().clear().commit()
        WorkerEndpoints.resetForTests()
        endpoints = WorkerEndpoints(context)
        preferences = SyncPreferences(EncryptedSharedPreferencesManager(context))
    }

    @After
    fun tearDown() {
        context.getSharedPreferences("marina_cloudflare_prefs", Context.MODE_PRIVATE)
            .edit().clear().commit()
        context.getSharedPreferences("marina_secure_prefs", Context.MODE_PRIVATE)
            .edit().clear().commit()
        WorkerEndpoints.resetForTests()
    }

    @Test
    fun `audit custom hostname is still coupled to the builtin Cloudflare failover`() {
        endpoints.setCustomUrl("sync.next-provider.example")

        val candidates = endpoints.candidatesFor(URI(endpoints.active)).map { it.host }

        assertEquals("https://sync.next-provider.example", endpoints.active)
        assertEquals(
            listOf("sync.next-provider.example", "marina-hotel-api.adenmarina2.workers.dev"),
            candidates
        )
    }

    @Test
    fun `audit hostname change leaves the global cursor epoch and auth token reusable`() {
        preferences.saveLastPullCursor(8_123L)
        preferences.saveSyncEpoch("old-cloudflare-generation")
        preferences.saveSyncSourceId("0123456789abcdef0123456789abcdef")
        preferences.saveAuthToken("old-provider-token")
        preferences.setTimestampNormalizationDone(true)

        endpoints.setCustomUrl("sync.next-provider.example")
        WorkerEndpoints.resetForTests()

        val reloadedEndpoints = WorkerEndpoints(context)
        val reloadedPreferences = SyncPreferences(EncryptedSharedPreferencesManager(context))
        assertEquals("https://sync.next-provider.example", reloadedEndpoints.active)
        assertEquals(8_123L, reloadedPreferences.getLastPullCursor())
        assertEquals("old-cloudflare-generation", reloadedPreferences.getSyncEpoch())
        assertEquals("0123456789abcdef0123456789abcdef", reloadedPreferences.getSyncSourceId())
        assertEquals("old-provider-token", reloadedPreferences.getAuthToken())
        assertTrue(reloadedPreferences.isTimestampNormalizationDone())
    }
}
