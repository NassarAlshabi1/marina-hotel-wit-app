package com.marina.marina.presentation.blacklist

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marina.marina.domain.model.BlacklistEntry
import com.marina.marina.domain.repository.BlacklistRepository
import com.marina.marina.domain.util.ArabicNameMatcher
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch

data class BlacklistUiState(
    val isLoading: Boolean = true,
    val entries: List<BlacklistEntry> = emptyList(),
    val query: String = "",
    val error: String? = null,
    val message: String? = null
)

@HiltViewModel
class BlacklistViewModel @Inject constructor(
    private val repository: BlacklistRepository
) : ViewModel() {

    private val _state = MutableStateFlow(BlacklistUiState())
    val state: StateFlow<BlacklistUiState> = _state.asStateFlow()
    private var watchJob: Job? = null

    init { observe("") }

    fun setQuery(query: String) {
        _state.value = _state.value.copy(query = query)
        observe(query.trim())
    }

    private fun observe(query: String) {
        watchJob?.cancel()
        val flow = if (query.length >= 2) repository.searchActive(query) else repository.getActive()
        watchJob = flow
            .onEach { entries -> _state.value = _state.value.copy(isLoading = false, entries = entries, error = null) }
            .catch { e -> _state.value = _state.value.copy(isLoading = false, error = e.message) }
            .launchIn(viewModelScope)
    }

    /** Returns blacklist hits for a guest name using triple-token matching. */
    suspend fun checkGuest(guestName: String): List<BlacklistEntry> {
        if (guestName.isBlank()) return emptyList()
        return repository.getActive().first()
            .filter { ArabicNameMatcher.tripleMatch(it.name, guestName) }
    }

    fun save(entry: BlacklistEntry) {
        viewModelScope.launch {
            try {
                if (entry.id == 0L) repository.insert(entry) else repository.update(entry)
                _state.value = _state.value.copy(message = "تم الحفظ")
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = e.message)
            }
        }
    }

    fun toggleActive(entry: BlacklistEntry) {
        viewModelScope.launch {
            try { repository.setActive(entry.id, !entry.active) }
            catch (e: Exception) { _state.value = _state.value.copy(error = e.message) }
        }
    }

    fun delete(entry: BlacklistEntry) {
        viewModelScope.launch {
            try { repository.softDelete(entry.id) }
            catch (e: Exception) { _state.value = _state.value.copy(error = e.message) }
        }
    }

    fun consumeMessage() { _state.value = _state.value.copy(message = null, error = null) }
}
