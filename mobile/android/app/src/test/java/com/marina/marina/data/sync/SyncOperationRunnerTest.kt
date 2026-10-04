package com.marina.marina.data.sync

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class SyncOperationRunnerTest {
    @Test
    fun foregroundLeaseSurvivesScreenAndIsReleasedAtCompletion() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val owner = CoroutineScope(SupervisorJob() + dispatcher)
        var leases = 0
        val runner = SyncOperationRunner(owner, dispatcher) {
            leases++
            AutoCloseable { leases-- }
        }
        val finish = CompletableDeferred<Unit>()
        try {
            val screen = launch { runner.runIfIdle(onBusy = { -1 }) { finish.await(); 1 } }
            runCurrent()
            assertEquals(1, leases)
            screen.cancel()
            runCurrent()
            assertEquals(1, leases)
            finish.complete(Unit)
            advanceUntilIdle()
            assertEquals(0, leases)
        } finally { owner.cancel() }
    }

    @Test
    fun rejectedForegroundStartDoesNotExecuteWorkAndUnlocksAdmission() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val owner = CoroutineScope(SupervisorJob() + dispatcher)
        var reject = true
        var failed = false
        val runner = SyncOperationRunner(owner, dispatcher) {
            check(!reject) { "Synthetic Android background-start restriction" }
            AutoCloseable {}
        }
        try {
            assertTrue(runCatching {
                runner.runIfIdle(onBusy = { -1 }, onFinished = { failed = it != null }) {
                    error("Must not run without foreground protection")
                }
            }.isFailure)
            assertTrue(failed)
            reject = false
            assertEquals(1, runner.runIfIdle(onBusy = { -1 }) { 1 })
        } finally { owner.cancel() }
    }

    @Test
    fun systemTimeoutCancelsWorkReleasesForegroundAndAllowsLaterRetry() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val owner = CoroutineScope(SupervisorJob() + dispatcher)
        var leases = 0
        var cancelled = false
        val runner = SyncOperationRunner(owner, dispatcher) {
            leases++
            AutoCloseable { leases-- }
        }
        try {
            val screen = launch {
                runCatching {
                    runner.runIfIdle(onBusy = { -1 }, onFinished = { cancelled = it is CancellationException }) {
                        CompletableDeferred<Unit>().await()
                        1
                    }
                }
            }
            runCurrent()
            runner.cancelForSystemStop()
            advanceUntilIdle()
            screen.join()
            assertTrue(cancelled)
            assertEquals(0, leases)
            assertEquals(2, runner.runIfIdle(onBusy = { -1 }) { 2 })
        } finally { owner.cancel() }
    }

    @Test
    fun rejectedSettingsStartReportsFailureWithoutStartingPreflight() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val owner = CoroutineScope(SupervisorJob() + dispatcher)
        val runner = SyncOperationRunner(owner, dispatcher) { error("Start denied") }
        var failed = false
        var executed = false
        runner.launch(onStartFailure = { failed = true }) { executed = true }.join()
        advanceUntilIdle()
        assertTrue(failed)
        assertFalse(executed)
        owner.cancel()
    }

    @Test
    fun cancellingScreenDoesNotCancelAcceptedSyncOrReleaseItsLock() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val owner = CoroutineScope(SupervisorJob() + dispatcher)
        val runner = SyncOperationRunner(owner, dispatcher)
        val finish = CompletableDeferred<Unit>()
        var completed = false
        var completionCalls = 0
        try {
            val screen = launch {
                runner.runIfIdle(onBusy = { -1 }, onFinished = { completionCalls++ }) {
                    finish.await()
                    completed = true
                    7
                }
            }
            runCurrent()
            screen.cancel()
            runCurrent()
            assertFalse(completed)
            assertEquals(-1, runner.runIfIdle(onBusy = { -1 }) { error("Must not overlap") })
            assertEquals(0, completionCalls)
            finish.complete(Unit)
            advanceUntilIdle()
            assertTrue(completed)
            assertEquals(1, completionCalls)
            assertEquals(8, runner.runIfIdle(onBusy = { -1 }) { 8 })
        } finally {
            owner.cancel()
        }
    }

    @Test
    fun admissionIsPublishedBeforeDispatchAndBusyRequestNeverExecutes() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val owner = CoroutineScope(SupervisorJob() + dispatcher)
        val runner = SyncOperationRunner(owner, dispatcher)
        val finish = CompletableDeferred<Unit>()
        var accepted = 0
        var writes = 0
        try {
            val first = async {
                runner.runIfIdle(onBusy = { -1 }, onAccepted = { accepted++ }) {
                    writes++
                    finish.await()
                    1
                }
            }
            runCurrent()
            assertEquals(1, accepted)
            assertEquals(-1, runner.runIfIdle(onBusy = { -1 }, onAccepted = { accepted++ }) { writes++; 2 })
            assertEquals(1, accepted)
            assertEquals(1, writes)
            finish.complete(Unit)
            assertEquals(1, first.await())
        } finally {
            owner.cancel()
        }
    }

    @Test
    fun failureReleasesAdmissionAndDoesNotPoisonLaterOperations() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val owner = CoroutineScope(SupervisorJob() + dispatcher)
        val runner = SyncOperationRunner(owner, dispatcher)
        var failedCompletion = false
        try {
            val result = runCatching {
                runner.runIfIdle(onBusy = { -1 }, onFinished = { failedCompletion = it is IllegalStateException }) {
                    error("Synthetic failure")
                }
            }
            assertTrue(result.isFailure)
            assertTrue(failedCompletion)
            assertEquals(4, runner.runIfIdle(onBusy = { -1 }) { 4 })
        } finally {
            owner.cancel()
        }
    }

    @Test
    fun cancelledCallerIsNotAdmitted() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val owner = CoroutineScope(SupervisorJob() + dispatcher)
        val runner = SyncOperationRunner(owner, dispatcher)
        var accepted = false
        try {
            val screen = launch {
                currentCoroutineContext().cancel()
                try {
                    runner.runIfIdle(onBusy = { -1 }, onAccepted = { accepted = true }) { 1 }
                } catch (_: CancellationException) {
                    // Already-disposed screen must not submit a new operation.
                }
            }
            screen.join()
            assertFalse(accepted)
            assertEquals(2, runner.runIfIdle(onBusy = { -1 }) { 2 })
        } finally {
            owner.cancel()
        }
    }

    @Test
    fun ownerCancellationBeforeBodyStartsStillRunsCompletion() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val owner = CoroutineScope(SupervisorJob() + dispatcher)
        val runner = SyncOperationRunner(owner, dispatcher)
        var bodyStarted = false
        var finished = false
        val result = runCatching {
            runner.runIfIdle(onBusy = { -1 }, onAccepted = { owner.cancel() },
                onFinished = { finished = it is CancellationException }) {
                bodyStarted = true
                1
            }
        }
        advanceUntilIdle()
        assertTrue(result.exceptionOrNull() is CancellationException)
        assertFalse(bodyStarted)
        assertTrue(finished)
    }

    @Test
    fun admissionCallbackFailureDoesNotLeaveBusyLock() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val owner = CoroutineScope(SupervisorJob() + dispatcher)
        val runner = SyncOperationRunner(owner, dispatcher)
        var finished = false
        try {
            assertTrue(runCatching {
                runner.runIfIdle(onBusy = { -1 }, onAccepted = { error("Synthetic admission failure") },
                    onFinished = { finished = true }) { 1 }
            }.isFailure)
            assertTrue(finished)
            assertEquals(3, runner.runIfIdle(onBusy = { -1 }) { 3 })
        } finally {
            owner.cancel()
        }
    }

    @Test
    fun settingsPreflightContinuesAfterOriginatingScreenIsDisposed() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val owner = CoroutineScope(SupervisorJob() + dispatcher)
        val screen = CoroutineScope(SupervisorJob() + dispatcher)
        val runner = SyncOperationRunner(owner, dispatcher)
        val connectionReady = CompletableDeferred<Unit>()
        var synced = false
        try {
            screen.launch {
                runner.launch {
                    connectionReady.await()
                    runner.runIfIdle(onBusy = { false }) { synced = true; true }
                }
            }
            runCurrent()
            screen.cancel()
            connectionReady.complete(Unit)
            advanceUntilIdle()
            assertTrue(synced)
        } finally {
            screen.cancel()
            owner.cancel()
        }
    }
}
