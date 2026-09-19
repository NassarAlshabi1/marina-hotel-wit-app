package com.marina.marina.presentation.information

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marina.marina.domain.model.Booking
import com.marina.marina.domain.repository.BookingsRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach

/** One registry row derived from a booking's guest fields. */
data class GuestRegistryRow(
    val bookingId: Long,
    val roomNumber: String,
    val guestName: String,
    val nationality: String,
    val idNumber: String,
    val idType: String,
    val idIssueDate: String,
    val idIssuePlace: String,
    val checkinDate: String
)

data class InformationUiState(
    val isLoading: Boolean = false,
    val rows: List<GuestRegistryRow> = emptyList(),
    val searchQuery: String = "",
    val error: String? = null
) {
    val filtered: List<GuestRegistryRow>
        get() {
            val q = searchQuery.trim()
            if (q.isBlank()) return rows
            return rows.filter {
                it.guestName.contains(q, ignoreCase = true) ||
                    it.roomNumber.contains(q) ||
                    it.idNumber.contains(q) ||
                    it.nationality.contains(q, ignoreCase = true)
            }
        }
}

@HiltViewModel
class InformationViewModel @Inject constructor(
    bookingsRepository: BookingsRepository
) : ViewModel() {

    private val _state = MutableStateFlow(InformationUiState(isLoading = true))
    val state: StateFlow<InformationUiState> = _state.asStateFlow()

    init {
        bookingsRepository.getAll().onEach { bookings ->
            val rows = bookings
                .filter { it.guestName.isNotBlank() }
                .map { it.toRegistryRow() }
                .sortedByDescending { it.checkinDate }
            _state.value = _state.value.copy(isLoading = false, rows = rows, error = null)
        }.launchIn(viewModelScope)
    }

    fun setSearchQuery(query: String) {
        _state.value = _state.value.copy(searchQuery = query)
    }
}

private fun Booking.toRegistryRow(): GuestRegistryRow = GuestRegistryRow(
    bookingId = id,
    roomNumber = roomNumber,
    guestName = guestName,
    nationality = guestNationality.ifBlank { "—" },
    idNumber = guestIdNumber.ifBlank { "—" },
    idType = guestIdType.ifBlank { "—" },
    idIssueDate = guestIdIssueDate?.take(10) ?: "—",
    idIssuePlace = guestIdIssuePlace ?: "—",
    checkinDate = checkinDate.take(10)
)
