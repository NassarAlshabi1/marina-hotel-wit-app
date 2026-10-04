package com.marina.marina.presentation.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marina.marina.data.diagnostics.MaintenanceReport
import com.marina.marina.data.diagnostics.MaintenanceRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

@HiltViewModel
class MaintenanceViewModel @Inject constructor(private val repository: MaintenanceRepository) : ViewModel() {
    data class State(val loading: Boolean = false, val report: MaintenanceReport? = null, val error: String? = null)
    private val mutable = MutableStateFlow(State())
    val state = mutable.asStateFlow()

    fun refresh() = load(mutable.value.report?.page ?: 0)
    fun previousPage() = load(((mutable.value.report?.page ?: 0) - 1).coerceAtLeast(0))
    fun nextPage() {
        val report = mutable.value.report ?: return
        if (report.hasNext) load(report.page + 1)
    }

    private fun load(page: Long) {
        if (mutable.value.loading) return
        mutable.value = mutable.value.copy(loading = true, error = null)
        viewModelScope.launch {
            try {
                mutable.value = State(report = repository.read(page))
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                // Do not expose SQL or potentially sensitive payloads in exception text.
                mutable.value = mutable.value.copy(error = "تعذر قراءة فحص الصيانة. أعد المحاولة.")
            } finally {
                mutable.value = mutable.value.copy(loading = false)
            }
        }
    }
}
