package com.marina.marina.presentation.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marina.marina.data.diagnostics.SyncHealthReport
import com.marina.marina.data.diagnostics.SyncHealthRepository
import com.marina.marina.data.remote.SyncPreferences
import com.marina.marina.domain.repository.SyncRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@HiltViewModel
class SyncHealthViewModel @Inject constructor(
    private val health: SyncHealthRepository,
    private val preferences: SyncPreferences,
    sync: SyncRepository
) : ViewModel() {
    data class State(
        val report: SyncHealthReport? = null, val loading: Boolean = true, val error: String? = null,
        val lastPush: Long = 0, val lastPull: Long = 0, val enabled: Boolean? = null,
        val errorCount: Int = 0
    )
    private val mutable = MutableStateFlow(State())
    val state = mutable.asStateFlow()
    val syncState = sync.syncState
    private var refreshJob: Job? = null

    fun refresh(): Job {
        refreshJob?.takeIf { it.isActive }?.let { return it }
        return viewModelScope.launch {
            mutable.value = mutable.value.copy(loading = true, error = null)
            try {
                val report = health.read()
                mutable.value = withContext(Dispatchers.IO) {
                    State(report = report, loading = false, lastPush = preferences.getLastPushTs(),
                        lastPull = preferences.getLastPullTs(), enabled = preferences.getCloudflareSyncEnabled(),
                        errorCount = preferences.getSyncErrorHistory().size)
                }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                mutable.value = mutable.value.copy(loading = false, error = error.message ?: "تعذر قراءة حالة المزامنة")
            }
        }.also { refreshJob = it }
    }
}
