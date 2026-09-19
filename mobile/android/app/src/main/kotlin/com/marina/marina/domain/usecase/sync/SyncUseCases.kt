package com.marina.marina.domain.usecase.sync

import com.marina.marina.domain.model.SyncUiState
import com.marina.marina.domain.repository.SyncRepository
import javax.inject.Inject
import kotlinx.coroutines.flow.StateFlow

class ObserveSyncStateUseCase @Inject constructor(
    private val syncRepository: SyncRepository
) {
    operator fun invoke(): StateFlow<SyncUiState> = syncRepository.syncState
}

class RequestSyncUseCase @Inject constructor(
    private val syncRepository: SyncRepository
) {
    suspend operator fun invoke(): SyncUiState = syncRepository.syncNow()
}

class PullOnlyUseCase @Inject constructor(
    private val syncRepository: SyncRepository
) {
    suspend operator fun invoke(): Int = syncRepository.pullOnly()
}
