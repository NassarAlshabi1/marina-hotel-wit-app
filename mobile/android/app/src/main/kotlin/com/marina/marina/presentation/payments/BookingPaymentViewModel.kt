package com.marina.marina.presentation.payments

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marina.marina.domain.model.Booking
import com.marina.marina.domain.model.Payment
import com.marina.marina.domain.repository.BookingsRepository
import com.marina.marina.domain.repository.PaymentsRepository
import com.marina.marina.domain.repository.RoomsRepository
import com.marina.marina.domain.util.HotelTimeEngine
import com.marina.marina.domain.util.StatusUtils
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch

data class BookingPaymentUiState(
    val isLoading: Boolean = false,
    val booking: Booking? = null,
    val payments: List<Payment> = emptyList(),
    val roomPrice: Double = 0.0,
    val error: String? = null,
    val message: String? = null,
    val finished: Boolean = false
) {
    val totalPaid: Double get() = payments.sumOf { it.amount }
    val totalDue: Double
        get() {
            val b = booking ?: return 0.0
            val nights = if (b.calculatedNights > 0) b.calculatedNights else b.expectedNights
            return (nights * roomPrice) - b.discount
        }
    val remaining: Double get() = (totalDue - totalPaid).coerceAtLeast(0.0)
    val isFullyPaid: Boolean get() = totalDue > 0 && totalPaid >= totalDue
    val nights: Int
        get() {
            val b = booking ?: return 0
            return if (b.calculatedNights > 0) b.calculatedNights else b.expectedNights
        }
}

@HiltViewModel
class BookingPaymentViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val bookingsRepository: BookingsRepository,
    private val paymentsRepository: PaymentsRepository,
    private val roomsRepository: RoomsRepository
) : ViewModel() {

    private val bookingId: Long = savedStateHandle.get<Long>("bookingId") ?: 0L

    private val _state = MutableStateFlow(BookingPaymentUiState(isLoading = true))
    val state: StateFlow<BookingPaymentUiState> = _state.asStateFlow()

    init {
        combine(
            bookingsRepository.getAll(),
            paymentsRepository.getByBooking(bookingId)
        ) { bookings, payments ->
            bookings.find { it.id == bookingId } to payments
        }.onEach { (booking, payments) ->
            val price = booking?.let { roomsRepository.getByNumber(it.roomNumber)?.price } ?: 0.0
            _state.value = _state.value.copy(
                isLoading = false,
                booking = booking,
                payments = payments,
                roomPrice = price,
                error = null
            )
        }.launchIn(viewModelScope)
    }

    fun consumeMessage() {
        _state.value = _state.value.copy(message = null)
    }

    /**
     * Records a payment and refreshes the booking's denormalized financial
     * cache (totalDueCached / totalPaidCached / remainingBalanceCached /
     * isFullyPaid) exactly like the Flutter app does on every payment save.
     */
    fun addPayment(amount: Double, method: String, revenueType: String, notes: String?) {
        val booking = _state.value.booking ?: return
        if (amount <= 0) {
            _state.value = _state.value.copy(message = "المبلغ غير صالح")
            return
        }
        viewModelScope.launch {
            try {
                paymentsRepository.insert(
                    Payment(
                        bookingLocalId = booking.id,
                        roomNumber = booking.roomNumber,
                        amount = amount,
                        paymentMethod = method,
                        revenueType = revenueType,
                        notes = notes
                    )
                )
                refreshBookingFinancialCache()
                _state.value = _state.value.copy(message = "تم تسجيل الدفعة")
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = e.message)
            }
        }
    }

    fun voidPayment(payment: Payment, reason: String) {
        viewModelScope.launch {
            try {
                paymentsRepository.void(payment.id, voidedBy = "user", voidReason = reason)
                refreshBookingFinancialCache()
                _state.value = _state.value.copy(message = "تم إلغاء الدفعة")
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = e.message)
            }
        }
    }

    /**
     * Completes checkout: booking -> مكتمل, actualCheckout stamped, calculated
     * nights finalized (extra night if after 14:01), and the room is freed.
     */
    fun completeCheckout() {
        val booking = _state.value.booking ?: return
        viewModelScope.launch {
            try {
                val now = System.currentTimeMillis()
                val checkinMillis = HotelTimeEngine.parseDate(booking.checkinDate) ?: now
                val finalNights = HotelTimeEngine.calculateDays(checkinMillis, now)
                bookingsRepository.checkout(
                    id = booking.id,
                    status = "مكتمل",
                    actualCheckout = HotelTimeEngine.formatIso(now)
                )
                bookingsRepository.update(
                    booking.copy(
                        status = "مكتمل",
                        actualCheckout = HotelTimeEngine.formatIso(now),
                        calculatedNights = finalNights
                    )
                )
                // Free the room.
                roomsRepository.getByNumber(booking.roomNumber)?.let { room ->
                    if (StatusUtils.isRoomOccupied(room.status)) {
                        roomsRepository.update(room.copy(status = "شاغرة"))
                    }
                }
                refreshBookingFinancialCache()
                _state.value = _state.value.copy(message = "تم إتمام المغادرة بنجاح")
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = e.message)
            }
        }
    }

    private suspend fun refreshBookingFinancialCache() {
        val booking = _state.value.booking ?: return
        val price = _state.value.roomPrice
        val nights = if (booking.calculatedNights > 0) booking.calculatedNights else booking.expectedNights
        val totalDue = (nights * price) - booking.discount
        val paid = _state.value.payments.sumOf { it.amount }
        bookingsRepository.update(
            booking.copy(
                totalDueCached = totalDue,
                totalPaidCached = paid,
                remainingBalanceCached = (totalDue - paid).coerceAtLeast(0.0),
                isFullyPaid = paid >= totalDue && totalDue > 0,
                calculatedNights = nights
            )
        )
    }
}
