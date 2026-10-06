package com.marina.marina.data.remote.realtime

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * طابور أحداث Realtime — debounce 500ms ثم cooldown 15s مع حارس in-flight
 * ومتابعة trailing، وفشل السحب لا يهضم الحدث (نفس عقد Flutter).
 */
@OptIn(ExperimentalCoroutinesApi::class)
class RealtimePullSchedulerTest {

    private class Harness(
        private val schedulerScope: kotlinx.coroutines.CoroutineScope,
        var clock: Long
    ) {
        var pulls = 0
        var failNext = false
        lateinit var scheduler: RealtimePullScheduler

        fun build() {
            scheduler = RealtimePullScheduler(
                scope = schedulerScope,
                now = { clock },
                execute = {
                    pulls++
                    val failed = failNext
                    failNext = false
                    !failed
                }
            )
        }
    }

    @Test
    fun burstOfEventsIsDebouncedIntoASinglePull() = runTest {
        val harness = Harness(this, clock = 1_000L).also { it.build() }
        harness.scheduler.onRemoteChange()
        harness.scheduler.onRemoteChange()
        harness.scheduler.onRemoteChange()

        advanceTimeBy(REALTIME_DEBOUNCE_MS - 1)
        runCurrent()
        assertEquals(0, harness.pulls)

        advanceTimeBy(1)
        runCurrent()
        assertEquals(1, harness.pulls)
    }

    @Test
    fun changesDuringCooldownAreDeferredThenPulledOnce() = runTest {
        val harness = Harness(this, clock = 10_000L).also { it.build() }
        harness.scheduler.onRemoteChange()
        advanceTimeBy(REALTIME_DEBOUNCE_MS)
        runCurrent()
        assertEquals(1, harness.pulls)

        // حدث بعد ثانية من السحب الأول: داخل التهدئة (15s) → لا سحب فوري.
        advanceTimeBy(1_000)
        harness.clock += 1_000
        harness.scheduler.onRemoteChange()
        advanceTimeBy(REALTIME_DEBOUNCE_MS)
        runCurrent()
        assertEquals(1, harness.pulls)

        // بعد انقضاء التهدئة كاملة يُنفَّذ السحب المؤجل مرة واحدة.
        advanceTimeBy(REALTIME_PULL_COOLDOWN_MS)
        harness.clock += REALTIME_PULL_COOLDOWN_MS
        runCurrent()
        assertEquals(2, harness.pulls)
    }

    @Test
    fun failedPullKeepsTheEventQueuedAndRetriesAfterCooldown() = runTest {
        val harness = Harness(this, clock = 50_000L).also { it.build() }
        harness.failNext = true
        harness.scheduler.onRemoteChange()
        advanceTimeBy(REALTIME_DEBOUNCE_MS)
        runCurrent()
        assertEquals(1, harness.pulls)

        advanceTimeBy(REALTIME_PULL_COOLDOWN_MS + 1)
        harness.clock += REALTIME_PULL_COOLDOWN_MS + 1
        runCurrent()
        assertEquals(2, harness.pulls)
    }

    @Test
    fun cancelPendingStopsScheduledWork() = runTest {
        val harness = Harness(this, clock = 5_000L).also { it.build() }
        harness.scheduler.onRemoteChange()
        harness.scheduler.cancelPending()
        advanceTimeBy(REALTIME_DEBOUNCE_MS * 4)
        runCurrent()
        assertEquals(0, harness.pulls)
    }

    @Test
    fun cooldownRemainingReflectsTheLastFire() = runTest {
        val harness = Harness(this, clock = 20_000L).also { it.build() }
        assertEquals(0L, harness.scheduler.cooldownRemainingMs())
        harness.scheduler.onRemoteChange()
        advanceTimeBy(REALTIME_DEBOUNCE_MS)
        runCurrent()
        assertEquals(REALTIME_PULL_COOLDOWN_MS, harness.scheduler.cooldownRemainingMs())
        harness.clock += 5_000
        assertEquals(REALTIME_PULL_COOLDOWN_MS - 5_000, harness.scheduler.cooldownRemainingMs())
        harness.clock += REALTIME_PULL_COOLDOWN_MS
        assertEquals(0L, harness.scheduler.cooldownRemainingMs())
    }
}
