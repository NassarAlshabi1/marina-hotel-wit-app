package com.marina.marina.presentation.dashboard

import com.marina.marina.domain.model.SyncUiState
import com.marina.marina.domain.repository.SyncRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test

class DashboardDirectionalSyncTest {
    private class FakeSync(var undelivered: Int = 0, var result: Int = 4) : SyncRepository {
        override val syncState = MutableStateFlow(SyncUiState())
        var pushes = 0
        var pulls = 0
        override fun pendingCount() = flowOf(0) // stale/insufficient pending-only badge
        override fun undeliveredCount() = flowOf(undelivered)
        override suspend fun pushOnly(): Int { pushes++; return result }
        override suspend fun pullOnly(): Int { pulls++; return result }
        override suspend fun fullPull(): Int = error("Must not reset the pull cursor")
        override suspend fun syncNow(): SyncUiState = error("Must not combine directions")
    }

    @Test fun localUndeliveredRowsBlockPullEvenWhenPendingBadgeIsZero() = runTest {
        val sync = FakeSync(undelivered = 3)
        assertTrue(runDashboardDirectionalSync(sync, false) is DashboardEvent.Error)
        assertEquals(0, sync.pulls)
        assertEquals(0, sync.pushes)
    }

    @Test fun pushAndPullRemainSeparateAndReportActualCounts() = runTest {
        val sync = FakeSync(undelivered = 3)
        assertEquals(DashboardEvent.SyncCompleted(4, 0), runDashboardDirectionalSync(sync, true))
        sync.undelivered = 0
        assertEquals(DashboardEvent.SyncCompleted(0, 4), runDashboardDirectionalSync(sync, false))
        assertEquals(1, sync.pushes)
        assertEquals(1, sync.pulls)
    }

    @Test fun failureAndBusyResultsNeverBecomeSuccess() = runTest {
        val sync = FakeSync(result = -1)
        assertTrue(runDashboardDirectionalSync(sync, true) is DashboardEvent.SyncFailed)
        sync.syncState.value = SyncUiState(isSyncing = true)
        assertTrue(runDashboardDirectionalSync(sync, false) is DashboardEvent.Error)
        assertEquals(0, sync.pulls)
    }
}
