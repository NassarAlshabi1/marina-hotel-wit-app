package com.marina.marina.presentation.dashboard

import com.marina.marina.domain.repository.SyncRepository
import kotlinx.coroutines.flow.first

/** Manual pull guard uses a fresh DB count, never the cached display badge. */
internal suspend fun runDashboardDirectionalSync(sync: SyncRepository, push: Boolean): DashboardEvent {
    if (sync.syncState.value.isSyncing) return DashboardEvent.Error("توجد عملية مزامنة أخرى جارية")
    val outstanding = sync.undeliveredCount().first()
    if (!push && outstanding > 0) {
        return DashboardEvent.Error("يجب رفع $outstanding تغييراً محلياً قبل السحب")
    }
    val count = if (push) sync.pushOnly() else sync.pullOnly()
    if (count < 0) {
        val message = if (sync.syncState.value.isSyncing) "توجد عملية مزامنة أخرى جارية"
            else sync.syncState.value.lastMessage.ifBlank { "تعذرت المزامنة؛ أعد المحاولة" }
        return DashboardEvent.SyncFailed(message)
    }
    return DashboardEvent.SyncCompleted(
        pushedCount = if (push) count else 0,
        pulledCount = if (push) 0 else count
    )
}
