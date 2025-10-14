package com.marinahotel.kotlin.presentation.booking

import androidx.annotation.ColorRes
import androidx.annotation.StringRes
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marinahotel.kotlin.R
import com.marinahotel.kotlin.data.repository.HotelRepository
import com.marinahotel.kotlin.domain.model.BookingStatus
import com.marinahotel.kotlin.domain.model.RoomStatus
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.max

class BookingListViewModel(
    private val repository: HotelRepository
) : ViewModel() {

    private val searchQuery = MutableStateFlow("")
    private val eventsFlow = MutableSharedFlow<BookingListEvent>()
    val events: SharedFlow<BookingListEvent> = eventsFlow

    private val dateFormatter = DateTimeFormatter.ofPattern("dd MMM yyyy", Locale.getDefault())

    val uiState: StateFlow<BookingListUiState> = combine(
        repository.observeBookings(),
        searchQuery
    ) { summaries, query ->
        val filtered = if (query.isBlank()) {
            summaries
        } else {
            summaries.filter { summary ->
                summary.guest.name.contains(query, ignoreCase = true) ||
                    summary.room.number.contains(query, ignoreCase = true)
            }
        }

        val items = filtered.map { summary ->
            val nights = if (summary.booking.checkoutDate != null) {
                max(1, summary.booking.calculatedNights)
            } else {
                computeNights(summary.booking.checkinDate, System.currentTimeMillis())
            }
            val totalAmount = summary.room.price * nights
            val totalPaid = summary.payments.sumOf { it.amount }
            val remaining = max(totalAmount - totalPaid, 0)

            val status = when (summary.booking.status) {
                BookingStatus.RESERVED -> StatusUi(
                    labelRes = R.string.label_booking_status_reserved,
                    colorRes = R.color.color_info
                )
                BookingStatus.COMPLETED -> StatusUi(
                    labelRes = R.string.label_booking_status_completed,
                    colorRes = R.color.color_success
                )
                BookingStatus.CANCELLED -> StatusUi(
                    labelRes = R.string.label_booking_status_cancelled,
                    colorRes = R.color.color_error
                )
            }

            BookingListItem(
                id = summary.booking.id,
                guestName = summary.guest.name,
                roomNumber = summary.room.number,
                status = status,
                checkinDateText = formatDate(summary.booking.checkinDate),
                checkoutDateText = summary.booking.checkoutDate?.let { formatDate(it) },
                totalAmount = totalAmount,
                remainingAmount = remaining,
                nights = nights,
                roomStatus = summary.room.status
            )
        }

        BookingListUiState(
            items = items,
            isLoading = false
        )
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), BookingListUiState())

    fun onSearchQueryChanged(query: String) {
        searchQuery.value = query
    }

    fun onBookingSelected(item: BookingListItem) {
        viewModelScope.launch {
            eventsFlow.emit(BookingListEvent.OpenBookingDetails(item.id))
        }
    }

    fun onAddBooking() {
        viewModelScope.launch {
            eventsFlow.emit(BookingListEvent.CreateBooking)
        }
    }

    private fun formatDate(timestamp: Long): String {
        val instant = Instant.ofEpochMilli(timestamp)
        return dateFormatter.format(instant.atZone(ZoneId.systemDefault()).toLocalDate())
    }

    private fun computeNights(checkin: Long, checkout: Long): Int {
        val millisPerNight = 86_400_000L
        val diff = max(0L, checkout - checkin)
        val nights = (diff / millisPerNight).toInt()
        return max(1, nights)
    }

    data class StatusUi(@StringRes val labelRes: Int, @ColorRes val colorRes: Int)

    data class BookingListItem(
        val id: Int,
        val guestName: String,
        val roomNumber: String,
        val status: StatusUi,
        val checkinDateText: String,
        val checkoutDateText: String?,
        val totalAmount: Int,
        val remainingAmount: Int,
        val nights: Int,
        val roomStatus: RoomStatus
    )

    data class BookingListUiState(
        val items: List<BookingListItem> = emptyList(),
        val isLoading: Boolean = true
    )

    sealed class BookingListEvent {
        object CreateBooking : BookingListEvent()
        data class OpenBookingDetails(val bookingId: Int) : BookingListEvent()
    }
}
