package com.marina.marina.data.remote.realtime

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** أرقام Realtime المنقولة حرفياً من Flutter — بلا شبكة. */
class RealtimePolicyTest {

    @Test
    fun backoffDoublesToOneMinuteThenStaysCapped() {
        assertEquals(1_000L, realtimeBackoffDelayMs(0))
        assertEquals(2_000L, realtimeBackoffDelayMs(1))
        assertEquals(4_000L, realtimeBackoffDelayMs(2))
        assertEquals(8_000L, realtimeBackoffDelayMs(3))
        assertEquals(16_000L, realtimeBackoffDelayMs(4))
        assertEquals(32_000L, realtimeBackoffDelayMs(5))
        assertEquals(60_000L, realtimeBackoffDelayMs(6))
        assertEquals(60_000L, realtimeBackoffDelayMs(20))
    }

    @Test
    fun backoffToleratesNegativeAttempts() {
        assertEquals(1_000L, realtimeBackoffDelayMs(-3))
    }

    @Test
    fun httpsBaseIsUpgradedToWssBecauseWebSocketsRejectHttps() {
        assertEquals("wss://api.example.com", toWebSocketBase("https://api.example.com"))
        assertEquals("ws://api.example.com", toWebSocketBase("http://api.example.com"))
        assertEquals("wss://api.example.com", toWebSocketBase("wss://api.example.com"))
        // المنفذ الصريح محفوظ.
        assertEquals("wss://api.example.com:8443", toWebSocketBase("https://api.example.com:8443"))
        // المسار الزائد مقصوص — القاعدة وحدها.
        assertEquals("wss://api.example.com", toWebSocketBase("https://api.example.com/api/sync"))
    }

    @Test
    fun realtimeUrlTargetsHubWithAllEntitiesAndEncodedDeviceId() {
        assertEquals(
            "wss://marina-hotel-api.adenmarina2.workers.dev/api/realtime?deviceId=cf_dev_1&entity=*",
            buildRealtimeUrl("https://marina-hotel-api.adenmarina2.workers.dev", "cf_dev_1")
        )
        // الجهاز الفارغ/الغائب يرسل "unknown" كما في Dart.
        assertTrue(buildRealtimeUrl("https://x.example", null).endsWith("deviceId=unknown&entity=*"))
        // ترميز query صحيح للمعرّفات غير الآمنة.
        assertTrue(buildRealtimeUrl("https://x.example", "dev 1+2").contains("deviceId=dev+1%2B2"))
    }

    @Test
    fun socketErrorsAreShortenedForDiagnostics() {
        assertEquals("socket closed", shortenRealtimeError(null))
        assertEquals("socket closed", shortenRealtimeError("  "))
        assertEquals("boom", shortenRealtimeError("boom"))
        val long = "x".repeat(400)
        val shortened = shortenRealtimeError(long)
        assertEquals(REALTIME_MAX_ERROR_LENGTH, shortened.length)
        assertTrue(shortened.endsWith("..."))
        assertFalse(shortened.contains(" "))
    }
}
