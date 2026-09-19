package com.marina.marina.domain.repository

import com.marina.marina.domain.model.SyncUiState
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.StateFlow

interface SyncRepository {
    val syncState: StateFlow<SyncUiState>
    fun pendingCount(): Flow<Int>
    suspend fun syncNow(): SyncUiState
    suspend fun pullOnly(): Int
}
