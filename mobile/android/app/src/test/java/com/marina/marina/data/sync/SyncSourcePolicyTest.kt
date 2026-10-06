package com.marina.marina.data.sync

import com.marina.marina.data.remote.CloudflareConfig
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SyncSourcePolicyTest {
    private val sourceA = "0123456789abcdef0123456789abcdef"
    private val sourceB = "fedcba9876543210fedcba9876543210"

    @Test
    fun `expected source id is derived from configured D1 database id`() {
        assertEquals(
            CloudflareConfig.D1_DATABASE_ID.replace("-", ""),
            CloudflareConfig.EXPECTED_SYNC_SOURCE_ID
        )
    }

    @Test
    fun `first compatible source is accepted for one-time pinning`() {
        val decision = SyncSourcePolicy.evaluate(
            storedSourceId = null,
            providerId = "cloudflare-d1",
            responseSourceId = sourceA,
            protocolVersion = 1,
            expectedSourceId = sourceA
        )

        assertEquals(SyncSourceDecision.Accepted(sourceA, shouldPin = true), decision)
    }

    @Test
    fun `same source remains accepted and does not rewrite the pin`() {
        val decision = SyncSourcePolicy.evaluate(
            storedSourceId = sourceA,
            providerId = "cloudflare-d1",
            responseSourceId = sourceA.uppercase(),
            protocolVersion = 1
        )

        assertEquals(SyncSourceDecision.Accepted(sourceA, shouldPin = false), decision)
    }

    @Test
    fun `different source is rejected without an automatic rebind`() {
        val decision = SyncSourcePolicy.evaluate(
            storedSourceId = sourceA,
            providerId = "cloudflare-d1",
            responseSourceId = sourceB,
            protocolVersion = 1
        )

        assertTrue(decision is SyncSourceDecision.Rejected)
        assertEquals(SyncSourceDecision.Rejection.SOURCE_CHANGED,
            (decision as SyncSourceDecision.Rejected).reason)
    }

    @Test
    fun `first bind is limited to the source explicitly configured for this adapter`() {
        val decision = SyncSourcePolicy.evaluate(
            storedSourceId = null,
            providerId = "cloudflare-d1",
            responseSourceId = sourceB,
            protocolVersion = 1,
            expectedSourceId = sourceA
        )

        assertEquals(SyncSourceDecision.Rejection.SOURCE_NOT_CONFIGURED,
            (decision as SyncSourceDecision.Rejected).reason)
    }

    @Test
    fun `missing source identity or protocol never uses legacy compatibility`() {
        val missingSource = SyncSourcePolicy.evaluate(null, "cloudflare-d1", null, 1)
        val missingVersion = SyncSourcePolicy.evaluate(null, "cloudflare-d1", sourceA, null)

        assertEquals(SyncSourceDecision.Rejection.MISSING_IDENTITY,
            (missingSource as SyncSourceDecision.Rejected).reason)
        assertEquals(SyncSourceDecision.Rejection.UNSUPPORTED_PROTOCOL,
            (missingVersion as SyncSourceDecision.Rejected).reason)
    }

    @Test
    fun `unknown provider or malformed source cannot silently become the pinned source`() {
        val unknownProvider = SyncSourcePolicy.evaluate(null, "other-provider", sourceA, 1)
        val malformedId = SyncSourcePolicy.evaluate(null, "cloudflare-d1", "not-an-id", 1)

        assertEquals(SyncSourceDecision.Rejection.UNSUPPORTED_PROVIDER,
            (unknownProvider as SyncSourceDecision.Rejected).reason)
        assertEquals(SyncSourceDecision.Rejection.MISSING_IDENTITY,
            (malformedId as SyncSourceDecision.Rejected).reason)
    }
}
