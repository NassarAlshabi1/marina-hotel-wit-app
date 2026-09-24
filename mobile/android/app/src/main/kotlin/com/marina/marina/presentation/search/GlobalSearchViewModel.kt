package com.marina.marina.presentation.search

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marina.marina.data.search.GlobalSearchQuery
import com.marina.marina.data.search.GlobalSearchResults
import com.marina.marina.data.search.GlobalSearchService
import com.marina.marina.data.search.SearchEntityKind
import com.marina.marina.domain.session.UserSessionManager
import com.marina.marina.domain.util.HotelTimeEngine
import dagger.hilt.android.lifecycle.HiltViewModel
import java.util.Calendar
import javax.inject.Inject
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** نطاق التاريخ المختار — نظير `_DateMode` في Dart. */
enum class SearchDateMode(val label: String) {
    ALL("كل الفترات"),
    TODAY("اليوم"),
    WEEK("آخر 7 أيام"),
    MONTH("هذا الشهر"),
    CUSTOM("مخصص")
}

/** حالة شاشة البحث الشامل — نظير `_GlobalSearchScreenState`. */
data class GlobalSearchUiState(
    val text: String = "",
    val searching: Boolean = false,
    val results: GlobalSearchResults? = null,
    val selectedKinds: Set<SearchEntityKind> = emptySet(),
    val dateMode: SearchDateMode = SearchDateMode.ALL,
    val customFromDay: String? = null,
    val customToDay: String? = null,
    val includeDeleted: Boolean = false,
    val includeInactivePayments: Boolean = false,
    val isAdmin: Boolean = false,
    val allowedKinds: Set<SearchEntityKind> = SearchEntityKind.entries.toSet()
) {
    val minQueryLength: Int get() = 2

    /** تسمية النطاق المخصص — نظير `_dateModeLabel`. */
    val dateModeLabel: String
        get() = if (dateMode == SearchDateMode.CUSTOM) {
            "${customFromDay ?: "؟"} → ${customToDay ?: "؟"}"
        } else {
            dateMode.label
        }

    val isBelowMinQuery: Boolean get() = text.trim().length < minQueryLength
}

/**
 * البحث الشامل — ViewModel فوق [GlobalSearchService]:
 * debounce 300ms وحد أدنى حرفان — لا استعلام لكل ضغطة.
 */
@HiltViewModel
class GlobalSearchViewModel @Inject constructor(
    private val service: GlobalSearchService,
    sessionManager: UserSessionManager
) : ViewModel() {

    private val _state = MutableStateFlow(GlobalSearchUiState())
    val state: StateFlow<GlobalSearchUiState> = _state.asStateFlow()

    private var debounceJob: Job? = null
    private var searchJob: Job? = null

    init {
        // المدير (أو صلاحية all) يرى كل الأنواع — غيره بأنواعه المسموحة
        val user = sessionManager.currentUser.value
        val isAdmin = user?.isAdmin == true
        service.configure(if (user == null || isAdmin) null else user.permissions.toSet())
        _state.value = _state.value.copy(
            isAdmin = isAdmin,
            allowedKinds = service.allowedKinds
        )
    }

    /** تغيير نص البحث — يعيد ضبط مؤجّل الـ debounce (300ms). */
    fun onQueryChanged(text: String) {
        _state.value = _state.value.copy(text = text)
        debounceJob?.cancel()
        debounceJob = viewModelScope.launch {
            delay(300)
            runSearch()
        }
    }

    fun submitSearch() {
        debounceJob?.cancel()
        runSearch()
    }

    fun clearQuery() {
        _state.value = _state.value.copy(text = "", results = null, searching = false)
        debounceJob?.cancel()
        searchJob?.cancel()
    }

    fun toggleKind(kind: SearchEntityKind) {
        val current = _state.value.selectedKinds
        _state.value = _state.value.copy(
            selectedKinds = if (current.contains(kind)) current - kind else current + kind
        )
        runSearch()
    }

    fun selectAllKinds() {
        _state.value = _state.value.copy(selectedKinds = emptySet())
        runSearch()
    }

    fun setDateMode(mode: SearchDateMode) {
        _state.value = _state.value.copy(dateMode = mode)
        runSearch()
    }

    fun setCustomRange(fromDay: String, toDay: String) {
        _state.value = _state.value.copy(
            dateMode = SearchDateMode.CUSTOM,
            customFromDay = fromDay,
            customToDay = toDay
        )
        runSearch()
    }

    /** خيارات المدير — نظير `_AdminToggle.apply`. */
    fun toggleIncludeDeleted() {
        _state.value = _state.value.copy(includeDeleted = !_state.value.includeDeleted)
        runSearch()
    }

    fun toggleIncludeInactivePayments() {
        _state.value = _state.value.copy(includeInactivePayments = !_state.value.includeInactivePayments)
        runSearch()
    }

    private fun runSearch() {
        val s = _state.value
        val text = s.text.trim()
        if (text.length < s.minQueryLength) {
            searchJob?.cancel()
            _state.value = s.copy(results = null, searching = false)
            return
        }
        val (fromDay, toDay) = currentDayRange(s)
        searchJob?.cancel()
        searchJob = viewModelScope.launch {
            _state.value = _state.value.copy(searching = true)
            try {
                val results = service.search(
                    GlobalSearchQuery(
                        text = text,
                        fromDay = fromDay,
                        toDay = toDay,
                        includeDeleted = _state.value.includeDeleted,
                        includeInactivePayments = _state.value.includeInactivePayments,
                        kinds = _state.value.selectedKinds.ifEmpty { null }
                    )
                )
                _state.value = _state.value.copy(results = results, searching = false)
            } catch (_: Exception) {
                _state.value = _state.value.copy(searching = false)
            }
        }
    }

    /** نظير `_currentDayRange` — نطاق الأيام الفندقية حسب النمط. */
    private fun currentDayRange(s: GlobalSearchUiState): Pair<String?, String?> {
        val today = HotelTimeEngine.currentHotelDayKey()
        return when (s.dateMode) {
            SearchDateMode.ALL -> null to null
            SearchDateMode.TODAY -> today to today
            SearchDateMode.WEEK -> {
                // 6 أيام مضت عند 14:01 — بداية اليوم الفندقي قبل 6 أيام
                val cal = Calendar.getInstance()
                cal.add(Calendar.DAY_OF_YEAR, -6)
                cal.set(Calendar.HOUR_OF_DAY, 14)
                cal.set(Calendar.MINUTE, 1)
                cal.set(Calendar.SECOND, 0)
                cal.set(Calendar.MILLISECOND, 0)
                HotelTimeEngine.hotelDayKey(cal.timeInMillis) to today
            }
            SearchDateMode.MONTH -> {
                val cal = Calendar.getInstance()
                cal.set(Calendar.DAY_OF_MONTH, 1)
                cal.set(Calendar.HOUR_OF_DAY, 14)
                cal.set(Calendar.MINUTE, 1)
                cal.set(Calendar.SECOND, 0)
                cal.set(Calendar.MILLISECOND, 0)
                HotelTimeEngine.hotelDayKey(cal.timeInMillis) to today
            }
            SearchDateMode.CUSTOM -> s.customFromDay to s.customToDay
        }
    }
}
