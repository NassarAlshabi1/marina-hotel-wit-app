package com.marina.marina.presentation.reports

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marina.marina.domain.model.Booking
import com.marina.marina.domain.model.Payment
import com.marina.marina.domain.repository.BookingsRepository
import com.marina.marina.domain.repository.PaymentsRepository
import com.marina.marina.domain.util.CurrencyFormatter
import com.marina.marina.domain.util.HotelTimeEngine
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.launch

/**
 * تقرير دفوعات النزلاء — 1:1 port of `payments_report_screen.dart`:
 * hotel-day range query (excludeVoided + excludePendingBalance), optional
 * room filter, room vs other totals, per-booking totalDue/remaining sums,
 * 4-tile summary + rows + PDF export.
 */
data class PaymentReportRow(
    val payment: Payment,
    val booking: Booking?,
    val roomNumber: String,
    val payerName: String,
    val bookingCode: String?
)

data class PaymentsReportUiState(
    val isLoading: Boolean = false,
    val range: ReportDateRange = ReportDateRange.defaultHotelDay(),
    val rooms: List<String> = emptyList(),
    val selectedRoom: String? = null,
    val rows: List<PaymentReportRow> = emptyList(),
    val totalRoomPaid: Double = 0.0,
    val totalOtherPaid: Double = 0.0,
    val totalDue: Double = 0.0,
    val totalRemaining: Double = 0.0
) {
    val totalAll: Double get() = totalRoomPaid + totalOtherPaid

    val isRoomPayment: (Payment) -> Boolean = { p ->
        val rt = p.revenueType.trim().lowercase()
        rt.isEmpty() || rt == "room" || rt == "غرفة" || rt == "إقامة"
    }
}

@HiltViewModel
class PaymentsReportViewModel @Inject constructor(
    private val paymentsRepository: PaymentsRepository,
    private val bookingsRepository: BookingsRepository
) : ViewModel() {

    private val _state = MutableStateFlow(PaymentsReportUiState())
    val state: StateFlow<PaymentsReportUiState> = _state.asStateFlow()

    init { fetch() }

    fun setRange(range: ReportDateRange) {
        _state.value = _state.value.copy(range = range)
        fetch()
    }

    fun setRoom(room: String?) {
        _state.value = _state.value.copy(selectedRoom = room)
        fetch()
    }

    fun fetch() {
        val current = _state.value
        viewModelScope.launch {
            try {
                _state.value = current.copy(isLoading = true)
                val range = _state.value.range
                val payments = paymentsRepository.listFilteredByHotelDay(
                    fromHotelDay = range.fromHotelDayKey,
                    toHotelDay = range.toHotelDayKey,
                    roomNumber = _state.value.selectedRoom,
                    excludeVoided = true,
                    excludePendingBalance = true
                )
                val bookings = bookingsRepository.getAll().firstOrNull() ?: emptyList()
                val rooms = bookings.map { it.roomNumber }.distinct().sorted()

                val rows = payments.mapNotNull { p ->
                    val booking = bookings.find { it.id == p.bookingLocalId }
                    // Unparseable paymentDate rows are skipped (Dart l.186-191).
                    if (HotelTimeEngine.parseDate(p.paymentDate) == null) return@mapNotNull null
                    PaymentReportRow(
                        payment = p,
                        booking = booking,
                        roomNumber = booking?.roomNumber ?: p.roomNumber ?: "غير محدد",
                        payerName = booking?.guestName ?: p.revenueType,
                        bookingCode = booking?.id?.let { it.toString().padStart(6, '0') }
                    )
                }

                var totalRoomPaid = 0.0
                var totalOtherPaid = 0.0
                val bookingsWithPayments = mutableSetOf<Long>()
                rows.forEach { row ->
                    val rt = row.payment.revenueType.trim().lowercase()
                    val isRoom = rt.isEmpty() || rt == "room" || rt == "غرفة" || rt == "إقامة"
                    if (isRoom) totalRoomPaid += row.payment.amount else totalOtherPaid += row.payment.amount
                    row.booking?.let { bookingsWithPayments.add(it.id) }
                }
                var totalDue = 0.0
                var totalRemaining = 0.0
                bookings.filter { it.id in bookingsWithPayments }.forEach {
                    totalDue += it.totalDueCached
                    totalRemaining += it.remainingBalanceCached
                }

                _state.value = _state.value.copy(
                    isLoading = false,
                    rooms = rooms,
                    rows = rows,
                    totalRoomPaid = totalRoomPaid,
                    totalOtherPaid = totalOtherPaid,
                    totalDue = totalDue,
                    totalRemaining = totalRemaining
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(isLoading = false)
            }
        }
    }
}
