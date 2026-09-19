package com.marina.marina.domain.model

data class SyncUiState(
    val isSyncing: Boolean = false,
    val lastSyncAt: Long = 0,
    val lastMessage: String = "",
    val isError: Boolean = false,
    val pushedCount: Int = 0,
    val pulledCount: Int = 0
)
