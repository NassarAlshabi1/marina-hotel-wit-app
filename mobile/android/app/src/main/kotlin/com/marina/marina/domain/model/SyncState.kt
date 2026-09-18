package com.marina.marina.domain.model

/** UI-facing snapshot of the local sync cursor (see [com.marina.marina.data.local.entity.SyncStateEntity]). */
data class SyncState(
    val lastServerTs: Long = 0,
    val lastPullTs: Long = 0,
    val lastPushTs: Long = 0,
    val isSyncing: Boolean = false,
    val fullSyncComplete: Boolean = false
)
