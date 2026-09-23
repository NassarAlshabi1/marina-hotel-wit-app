package com.marina.marina.presentation.payments

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marina.marina.domain.model.Booking
import com.marina.marina.domain.model.BookingNight
import com.marina.marina.domain.model.Payment
import com.marina.marina.domain.repository.BookingNightsRepository
import com.marina.marina.domain.repository.BookingsRepository
import com.marina.marina.domain.repository.PaymentsRepository
import com.marina.marina.domain.repository.RoomsRepository
import com.marina.marina.domain.repository.SyncRepository
import com.marina.marina.domain.util.BookingFinancials
import com.marina.marina.domain.util.CurrencyFormatter
import com.marina.marina.domain.util.HotelTimeEngine
import com.marina.marina.domain.util.StatusUtils
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch

/**
 * دفع الحجز — 1:1 port of `booking_checkout_screen.dart` (l.119-186):
 * expected/actual nights via `nightsWithCutoff`, per-night ledger preferred
 * with the per-night-discount fallback formula, remaining clamped to
 * [0, totalDue], payments loaded live, and the hard completion gate.
 */
data class CheckoutUiState(
    val isLoading: Boolean = true,
    val booking: Booking? = null,
    val nights: List<BookingNight> = emptyList(),
    val payments: List<Payment> = emptyList(),
    val roomPrice: Double = 0.0,
    val isProcessing: Boolean = false,
    val checkedOut: Boolean = false,
    val message: String? = null,
    val error: String? = null
) {
    val expectedNights: Int
        get() = booking?.let { b ->
            if (b.expectedNights > 0) b.expectedNights else {
                val checkin = HotelTimeEngine.parseDate(b.checkinDate)
                val planned = HotelTimeEngine.parseDate(b.checkoutDate)
                if (checkin != null) HotelTimeEngine.nightsWithCutoff(checkin, planned) else 1
            }
        } ?: 1

    val actualNights: Int
        get() = booking?.let { b ->
            val checkin = HotelTimeEngine.parseDate(b.checkinDate) ?: return@let expectedNights
            val effective = HotelTimeEngine.parseDate(b.actualCheckout)
                ?: System.currentTimeMillis()
            HotelTimeEngine.nightsWithCutoff(checkin, effective)
        } ?: expectedNights

    /** Dart l.128-158 — ledger first, per-night discount fallback otherwise. */
    val nightTotal: Double
        get() {
            val booking = booking ?: return 0.0
            if (nights.isNotEmpty()) {
                return nights.sumOf { if (it.finalRate > 0) it.finalRate else it.nightlyRate }
            }
            val checkin = HotelTimeEngine.parseDate(booking.checkinDate)
            val actualCheckout = HotelTimeEngine.parseDate(booking.actualCheckout)
            if (booking.discount > 0 && booking.discountType == "per_night" && checkin != null) {
                val checkout = actualCheckout ?: System.currentTimeMillis()
                val discountedNights = HotelTimeEngine.countNightsWithDiscount(
                    checkin, checkout, booking.discountStartDate
                )
                val fullNights = (actualNights - discountedNights).coerceIn(0, actualNights)
                val discountedRate = (roomPrice - booking.discount).coerceIn(0.0, roomPrice)
                return (fullNights * roomPrice) + (discountedNights * discountedRate)
            }
            return actualNights * roomPrice
        }

    val totalDue: Double
        get() {
            val booking = booking ?: return 0.0
            return if (booking.discount > 0 && booking.discountType == "total") {
                (nightTotal - booking.discount).coerceIn(0.0, nightTotal)
            } else nightTotal
        }

    val totalPaid: Double get() = payments.filter { !it.isVoided }.sumOf { it.amount }

    /** Dart l.183: `(totalDue - totalPaid).clamp(0, totalDue)`. */
    val remaining: Double get() = (totalDue - totalPaid).coerceIn(0.0, totalDue)

    val hasExtraNightsAfterCutoff: Boolean
        get() = booking?.let { b ->
            b.actualCheckout == null && HotelTimeEngine.isAfterCutoff(System.currentTimeMillis()) &&
                actualNights > expectedNights
        } ?: false
}

@HiltViewModel
class BookingCheckoutViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val bookingsRepository: BookingsRepository,
    private val paymentsRepository: PaymentsRepository,
    private val nightsRepository: BookingNightsRepository,
    private val roomsRepository: RoomsRepository,
    private val syncRepository: SyncRepository
) : ViewModel() {

    private val bookingId: Long = savedStateHandle.get<Long>("bookingId") ?: 0L

    private val _state = MutableStateFlow(CheckoutUiState())
    val state: StateFlow<CheckoutUiState> = _state.asStateFlow()

    init {
        kotlinx.coroutines.flow.combine(
            bookingsRepository.getAll(),
            paymentsRepository.getByBooking(bookingId)
        ) { bookings, payments ->
            bookings.find { it.id == bookingId } to payments
        }.onEach { (booking, payments) ->
            if (booking == null) {
                _state.value = _state.value.copy(isLoading = false, booking = null)
                return@onEach
            }
            val nights = nightsRepository.getByBooking(booking.id)
            val price = roomsRepository.getByNumber(booking.roomNumber)?.price ?: 0.0
            _state.value = _state.value.copy(
                isLoading = false,
                booking = booking,
                payments = payments,
                nights = nights,
                roomPrice = price,
                error = null
            )
        }.launchIn(viewModelScope)
    }

    fun consumeMessage() {
        _state.value = _state.value.copy(message = null, error = null)
    }

    /** Dart `_addPayment` (l.442-654) — no serverBookingId, revenue type selectable. */
    fun addPayment(amount: Double, method: String, revenueType: String, notes: String?) {
        val booking = _state.value.booking ?: return
        if (amount <= 0) {
            _state.value = _state.value.copy(message = "يرجى إدخال مبلغ صحيح")
            return
        }
        if (amount % 1.0 != 0.0) {
            _state.value = _state.value.copy(message = "المبلغ يجب أن يكون بدون كسور")
            return
        }
        viewModelScope.launch {
            try {
                _state.value = _state.value.copy(isProcessing = true)
                paymentsRepository.insert(
                    Payment(
                        bookingLocalId = booking.id,
                        roomNumber = booking.roomNumber,
                        amount = amount,
                        paymentMethod = method,
                        revenueType = revenueType,
                        notes = notes?.takeIf { it.isNotBlank() }
                    )
                )
                try { syncRepository.syncNow() } catch (_: Exception) { }
                _state.value = _state.value.copy(
                    isProcessing = false,
                    message = "تم إضافة الدفعة بنجاح"
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(isProcessing = false, error = "حدث خطأ: ${e.message}")
            }
        }
    }

    /**
     * Dart `_completeCheckout` (l.656-741): status → 'مكتمل', actualCheckout
     * stamped, calculatedNights finalized, room freed (occupancy refresh).
     */
    fun completeCheckout() {
        val booking = _state.value.booking ?: return
        viewModelScope.launch {
            try {
                _state.value = _state.value.copy(isProcessing = true)
                val now = System.currentTimeMillis()
                val checkin = HotelTimeEngine.parseDate(booking.checkinDate) ?: now
                val finalNights = HotelTimeEngine.nightsWithCutoff(checkin, now)
                // Single write — one row update + one outbox entry (Dart
                // repo.update). The old checkout()+update() pair wrote twice.
                bookingsRepository.update(
                    booking.copy(
                        status = "مكتمل",
                        actualCheckout = HotelTimeEngine.formatIso(now),
                        calculatedNights = finalNights
                    )
                )
                roomsRepository.getByNumber(booking.roomNumber)?.let { room ->
                    if (StatusUtils.isRoomOccupied(room.status)) {
                        roomsRepository.update(room.copy(status = "شاغرة"))
                    }
                }
                try { syncRepository.syncNow() } catch (_: Exception) { }
                _state.value = _state.value.copy(
                    isProcessing = false,
                    checkedOut = true,
                    message = "تم إتمام الحجز بنجاح"
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(isProcessing = false, error = "حدث خطأ: ${e.message}")
            }
        }
    }
}
