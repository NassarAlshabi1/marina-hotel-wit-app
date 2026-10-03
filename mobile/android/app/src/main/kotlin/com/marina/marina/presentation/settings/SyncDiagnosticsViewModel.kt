package com.marina.marina.presentation.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marina.marina.data.remote.SyncErrorRecord
import com.marina.marina.data.remote.SyncPreferences
import com.marina.marina.domain.repository.SyncRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach

@HiltViewModel
class SyncDiagnosticsViewModel @Inject constructor(
    private val syncPreferences: SyncPreferences,
    syncRepository: SyncRepository
) : ViewModel() {

    data class UiState(
        val errors: List<SyncErrorRecord> = emptyList()
    )

    private val _state = MutableStateFlow(UiState())
    val state = _state.asStateFlow()

    init {
        refresh()
        syncRepository.syncState.onEach { sync ->
            if (sync.isError) refresh()
        }.launchIn(viewModelScope)
    }

    fun refresh() {
        _state.value = _state.value.copy(errors = syncPreferences.getSyncErrorHistory())
    }

    fun clearHistory() {
        syncPreferences.clearSyncErrorHistory()
        refresh()
    }
}
