package com.marinahotel.kotlin.presentation.dashboard

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marinahotel.kotlin.R
import com.marinahotel.kotlin.data.repository.HotelRepository
import com.marinahotel.kotlin.domain.model.AlertLevel
import com.marinahotel.kotlin.domain.model.BookingStatus
import com.marinahotel.kotlin.domain.model.RoomStatus
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

class DashboardViewModel(
    private val repository: HotelRepository
) : ViewModel() {

    private val eventsFlow = MutableSharedFlow<DashboardEvent>()
    val events: SharedFlow<DashboardEvent> = eventsFlow

    private val dateFormatter = DateTimeFormatter.ofPattern("dd MMM yyyy", Locale.getDefault())

    val uiState: StateFlow<DashboardUiState> = combine(
        repository.observeRooms(),
        repository.observeBookings(),
        repository.observeActiveAlerts()
    ) { rooms, bookings, alerts ->
        val activeBookings = bookings.filter { it.booking.status == BookingStatus.RESERVED }
        val bookingByRoom = activeBookings.associateBy { it.booking.roomNumber }

        val roomUi = rooms.map { room ->
            val summary = bookingByRoom[room.number]
            val statusLabel = when (room.status) {
                RoomStatus.VACANT -> R.string.label_room_status_vacant
                RoomStatus.RESERVED -> R.string.label_room_status_reserved
                RoomStatus.MAINTENANCE -> R.string.label_room_status_maintenance
            }
            val backgroundRes = when (room.status) {
                RoomStatus.VACANT -> R.color.color_success
                RoomStatus.RESERVED -> R.color.color_error
                RoomStatus.MAINTENANCE -> R.color.color_warning
            }
            RoomUiModel(
                roomNumber = room.number,
                floor = room.number.firstOrNull()?.digitToIntOrNull() ?: 0,
                status = room.status,
                occupantName = summary?.guest?.name,
                bookingId = summary?.booking?.id,
                backgroundColorRes = backgroundRes,
                strokeColorRes = R.color.color_outline,
                statusLabelRes = statusLabel
            )
        }.sortedWith(compareBy<RoomUiModel> { it.floor }.thenBy { it.roomNumber })

        val alertsUi = alerts.map { note ->
            val colorRes = when (note.alertType) {
                AlertLevel.HIGH -> R.color.color_error
                AlertLevel.MEDIUM -> R.color.color_warning
                AlertLevel.LOW -> R.color.color_info
            }
            AlertUiModel(
                id = note.id,
                text = note.text,
                meta = note.alertUntil?.let { formatDate(it) },
                level = note.alertType,
                accentColorRes = colorRes
            )
        }

        DashboardUiState(
            alerts = alertsUi,
            rooms = roomUi,
            isLoading = false
        )
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), DashboardUiState())

    fun onRoomSelected(room: RoomUiModel) {
        viewModelScope.launch {
            when (room.status) {
                RoomStatus.VACANT -> eventsFlow.emit(DashboardEvent.OpenNewBooking(room.roomNumber))
                RoomStatus.RESERVED -> room.bookingId?.let { eventsFlow.emit(DashboardEvent.OpenBookingDetails(it)) }
                RoomStatus.MAINTENANCE -> eventsFlow.emit(DashboardEvent.ShowMessage(R.string.message_room_maintenance))
            }
        }
    }

    private fun formatDate(timestamp: Long): String {
        val instant = Instant.ofEpochMilli(timestamp)
        return dateFormatter.format(instant.atZone(ZoneId.systemDefault()).toLocalDate())
    }

    sealed class DashboardEvent {
        data class OpenNewBooking(val roomNumber: String) : DashboardEvent()
        data class OpenBookingDetails(val bookingId: Int) : DashboardEvent()
        data class ShowMessage(val messageRes: Int) : DashboardEvent()
    }
}
