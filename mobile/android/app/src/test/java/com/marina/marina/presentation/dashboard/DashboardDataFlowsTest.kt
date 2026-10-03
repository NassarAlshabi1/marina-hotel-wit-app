package com.marina.marina.presentation.dashboard

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class DashboardDataFlowsTest {
    @Test fun oneSourceForTwoConsumersStopsWhenIdleAndReloadsOnReturn() = runTest {
        var starts = 0
        var stops = 0
        val shared = flow {
            starts++
            try {
                emit(starts)
                awaitCancellation()
            } finally { stops++ }
        }.shareDashboardSource(backgroundScope, StandardTestDispatcher(testScheduler))
        runCurrent()
        assertEquals(0, starts)
        val firstValues = mutableListOf<Int>()
        val secondValues = mutableListOf<Int>()
        val first = backgroundScope.launch { shared.collect { firstValues.add(it) } }
        val second = backgroundScope.launch { shared.collect { secondValues.add(it) } }
        runCurrent()
        assertEquals(1, starts)
        assertEquals(listOf(1), firstValues)
        assertEquals(listOf(1), secondValues)
        first.cancel()
        runCurrent()
        assertEquals(0, stops)
        second.cancel()
        runCurrent()
        assertEquals(1, stops)
        val refreshed = mutableListOf<Int>()
        backgroundScope.launch { shared.collect { refreshed.add(it) } }
        runCurrent()
        assertEquals(2, starts)
        assertEquals(listOf(2), refreshed)
    }

    @Test fun databaseFailuresReachConsumerErrorHandlers() = runTest {
        val shared = flow<Int> { throw IllegalStateException("database unavailable") }
            .shareDashboardSource(backgroundScope, StandardTestDispatcher(testScheduler))
        val errors = mutableListOf<String?>()
        repeat(2) {
            backgroundScope.launch {
                shared.catch { errors.add(it.message) }.collect()
            }
        }
        runCurrent()
        assertEquals(listOf("database unavailable", "database unavailable"), errors)
    }
}
