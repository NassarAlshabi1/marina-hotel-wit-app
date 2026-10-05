package com.marina.marina.data.sync

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test

class AutomaticDeltaGateTest {
    private class Fixture {
        var enabled = true
        var online = true
        var foreground = true
        var last = 0L
        var now = 10 * AUTOMATIC_PULL_INTERVAL_MS
        var tick = 0L
        var health = true
        var result = 0
        var probes = 0
        var pulls = 0
        var duringProbe: suspend () -> Unit = {}
        val gate = AutomaticDeltaGate({ enabled }, { online }, { last }, { now }, { tick }, {
            probes++
            duringProbe()
            health
        }, {
            pulls++
            if (result >= 0) last = now // Only the simulated manager owns the success stamp.
            result
        }, { foreground })
    }

    @Test fun offlineDoesNotProbePullOrAdvanceAnySuccessStamp() = runTest {
        val f = Fixture().apply { online = false }
        f.gate.check(true)
        assertEquals(AutomaticDeltaStatus.OFFLINE, f.gate.status.value)
        assertEquals(0, f.probes); assertEquals(0, f.pulls); assertEquals(0L, f.last)
    }

    @Test fun workerOrDatabaseFailureKeepsLocalModeAndRetriesWithBackoff() = runTest {
        val f = Fixture().apply { health = false }
        f.gate.check(true)
        assertEquals(AutomaticDeltaStatus.UNREACHABLE, f.gate.status.value)
        repeat(10) { f.gate.check(true) }
        assertEquals(1, f.probes); assertEquals(0, f.pulls); assertEquals(0L, f.last)
        f.tick = 30_000; f.health = true
        f.gate.check(true)
        assertEquals(1, f.pulls); assertEquals(f.now, f.last)
    }

    @Test fun eachEntryMayCheckD1ButOnlyAnHourOldSuccessAllowsAutomaticDelta() = runTest {
        val f = Fixture().apply { last = now - AUTOMATIC_PULL_INTERVAL_MS + 1 }
        f.gate.check(true)
        assertEquals(1, f.probes); assertEquals(0, f.pulls)
        assertEquals(AutomaticDeltaStatus.CURRENT, f.gate.status.value)
        f.tick = 30_000; f.now++
        f.gate.check(false)
        assertEquals(1, f.pulls)
        f.tick += 60_000
        f.gate.check(false)
        assertEquals(2, f.probes) // Timer does not keep probing within the successful hour.
        f.gate.check(true)
        assertEquals(3, f.probes); assertEquals(1, f.pulls)
    }

    @Test fun manualPullDuringProbeSuppressesAutomaticDuplicate() = runTest {
        val f = Fixture()
        f.duringProbe = { f.last = f.now }
        f.gate.check(true)
        assertEquals(0, f.pulls)
    }

    @Test fun failedOrBusyPullDoesNotPostponeRetryForOneHour() = runTest {
        val f = Fixture().apply { result = -1 }
        f.gate.check(true)
        assertEquals(0L, f.last)
        assertEquals(AutomaticDeltaStatus.RETRY, f.gate.status.value)
        f.tick = 30_000; f.result = 0
        f.gate.check(false)
        assertEquals(2, f.pulls); assertEquals(f.now, f.last)
    }

    @Test fun overlappingEntryAndConnectivitySignalsShareOneProbe() = runTest {
        val f = Fixture()
        val entered = CompletableDeferred<Unit>()
        val release = CompletableDeferred<Unit>()
        f.duringProbe = { entered.complete(Unit); release.await() }
        val first = async { f.gate.check(true) }
        entered.await()
        f.gate.check(true)
        release.complete(Unit); first.await()
        assertEquals(1, f.probes); assertEquals(1, f.pulls)
    }

    @Test fun cancellationReleasesGateWithoutRecordingSuccess() = runTest {
        val f = Fixture()
        f.duringProbe = { throw CancellationException("cancel") }
        try { f.gate.check(true); fail("Cancellation swallowed") } catch (_: CancellationException) { }
        assertEquals(0L, f.last)
        f.duringProbe = {}; f.tick = 30_000
        f.gate.check(true)
        assertEquals(1, f.pulls)
    }

    @Test fun disabledNetworkLostAndBackgroundDuringProbeNeverStartPull() = runTest {
        val disabled = Fixture().apply { enabled = false }
        disabled.gate.check(true)
        assertEquals(0, disabled.probes)
        val offline = Fixture()
        offline.duringProbe = { offline.online = false }
        offline.gate.check(true)
        assertEquals(0, offline.pulls)
        val background = Fixture()
        background.duringProbe = { background.foreground = false }
        background.gate.check(true)
        assertEquals(0, background.pulls)
    }

    @Test fun firstUseAndClockRollbackAreDueButRecentSuccessIsNot() {
        assertTrue(automaticPullDue(100, 0))
        assertTrue(automaticPullDue(100, 101))
        assertFalse(automaticPullDue(100, 100))
        assertFalse(automaticPullDue(AUTOMATIC_PULL_INTERVAL_MS, 1))
        assertTrue(automaticPullDue(AUTOMATIC_PULL_INTERVAL_MS + 1, 1))
    }
}
