package com.marina.marina.data.sync

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SyncEpochPolicyTest {
    @Test
    fun `missing epoch from an older worker leaves state unchanged`() {
        val decision = SyncEpochPolicy.evaluate(
            storedEpoch = "epoch-a",
            responseEpoch = null,
            pageBuiltFromZero = false
        )

        assertEquals(null, decision.epochToPersist)
        assertFalse(decision.restartFromZero)
    }

    @Test
    fun `first epoch observation is adopted without a full pull`() {
        val decision = SyncEpochPolicy.evaluate(
            storedEpoch = null,
            responseEpoch = "epoch-a",
            pageBuiltFromZero = false
        )

        assertEquals("epoch-a", decision.epochToPersist)
        assertFalse(decision.restartFromZero)
    }

    @Test
    fun `epoch change invalidates a page requested with an old cursor`() {
        val decision = SyncEpochPolicy.evaluate(
            storedEpoch = "epoch-a",
            responseEpoch = "epoch-b",
            pageBuiltFromZero = false
        )

        assertEquals("epoch-b", decision.epochToPersist)
        assertTrue(decision.restartFromZero)
    }

    @Test
    fun `changed epoch on first page from zero is adopted in place`() {
        val decision = SyncEpochPolicy.evaluate(
            storedEpoch = "epoch-a",
            responseEpoch = "epoch-b",
            pageBuiltFromZero = true
        )

        assertEquals("epoch-b", decision.epochToPersist)
        assertFalse(decision.restartFromZero)
    }

    @Test
    fun `second generation observed after restarting from zero does not loop`() {
        val decision = SyncEpochPolicy.evaluate(
            storedEpoch = "epoch-b",
            responseEpoch = "epoch-c",
            pageBuiltFromZero = true
        )

        assertEquals("epoch-c", decision.epochToPersist)
        assertFalse(decision.restartFromZero)
    }

    @Test
    fun `blank and whitespace epochs are ignored`() {
        val decision = SyncEpochPolicy.evaluate(
            storedEpoch = "epoch-a",
            responseEpoch = "   ",
            pageBuiltFromZero = false
        )

        assertEquals(null, decision.epochToPersist)
        assertFalse(decision.restartFromZero)
    }
}
