package com.marina.marina.presentation.debts

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marina.marina.domain.model.Booking
import com.marina.marina.domain.model.Debt
import com.marina.marina.domain.repository.BookingsRepository
import com.marina.marina.domain.repository.DebtsRepository
import com.marina.marina.domain.util.HotelTimeEngine
import dagger.hilt.android.lifecycle.HiltViewModel
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.launch

/** Dart debt computation (create_debt_from_booking.dart l.295-382). */
data class DebtComputation(
    val nights: Int,
    val nightlyRate: Double,
    val total: Double,
    val paid: Double,
    val remaining: Double
)

data class CreateDebtUiState(
    val isLoading: Boolean = true,
    val isComputing: Boolean = false,
    val isSaving: Boolean = false,
    /** Active bookings available for selection (Dart l.101-169). */
    val selectableBookings: List<Booking> = emptyList(),
    val selectedBooking: Booking? = null,
    /** Debt period (from/to) — defaults to the booking stay on select. */
    val fromDate: String = "",
    val toDate: String = "",
    val computation: DebtComputation? = null,
    val saved: Boolean = false,
    val error: String? = null
)

@HiltViewModel
class CreateDebtFromBookingViewModel @Inject constructor(
    private val bookingsRepository: BookingsRepository,
    private val debtsRepository: DebtsRepository,
    private val roomsRepository: com.marina.marina.domain.repository.RoomsRepository
) : ViewModel() {

    private val _state = MutableStateFlow(CreateDebtUiState())
    val state: StateFlow<CreateDebtUiState> = _state.asStateFlow()

    fun load(bookingId: Long) {
        viewModelScope.launch {
            try {
                // Dart l.101-169 — every booking that is not checked-out or
                // cancelled can carry a debt.
                val all = bookingsRepository.getAll().firstOrNull() ?: emptyList()
                val selectable = all.filter {
                    it.status !in listOf("مكتمل", "completed", "ملغي", "cancelled", "غادر", "departed")
                }
                val selected = all.find { it.id == bookingId } ?: selectable.firstOrNull()
                _state.value = CreateDebtUiState(
                    isLoading = false,
                    selectableBookings = selectable,
                    selectedBooking = selected
                )
                selected?.let { selectBooking(it.id) }
            } catch (e: Exception) {
                _state.value = CreateDebtUiState(isLoading = false, error = e.message)
            }
        }
    }

    /**
     * Dart l.151-162 — selecting a booking prefills the debt period:
     * from = checkin, to = actualCheckout ?? checkoutDate ?? now.
     */
    fun selectBooking(bookingId: Long) {
        val booking = _state.value.selectableBookings.find { it.id == bookingId } ?: return
        val from = booking.checkinDate.take(10)
        val to = (booking.actualCheckout ?: booking.checkoutDate)
            ?.take(10)
            ?: HotelTimeEngine.formatIso(System.currentTimeMillis()).take(10)
        _state.value = _state.value.copy(
            selectedBooking = booking,
            fromDate = from,
            toDate = to,
            computation = null
        )
    }

    fun setPeriod(from: String, to: String) {
        _state.value = _state.value.copy(fromDate = from, toDate = to, computation = null)
    }

    /**
     * Dart "احسب الدين" (l.295-350): nights = to - from (days); the nightly
     * rate is derived from the booking's cached totals (totalDue / totalNights);
     * total = rate x nights; paid = totalPaidCached; remaining is clamped.
     */
    fun computeDebt() {
        val booking = _state.value.selectedBooking ?: return
        viewModelScope.launch {
            _state.value = _state.value.copy(isComputing = true)
            try {
                val from = HotelTimeEngine.parseDate(_state.value.fromDate)
                val to = HotelTimeEngine.parseDate(_state.value.toDate)
                if (from == null || to == null || to <= from) {
                    _state.value = _state.value.copy(isComputing = false, error = "فترة غير صالحة")
                    return@launch
                }
                val nights = TimeUnit.MILLISECONDS.toDays(to - from).toInt()
                if (nights <= 0) {
                    _state.value = _state.value.copy(isComputing = false, error = "فترة غير صالحة")
                    return@launch
                }
                // Dart l.295-350 — nightlyRate = totalDueCached / totalNightsCached;
                // the room price covers bookings whose cache has not been filled.
                val totalNights = if (booking.calculatedNights > 0) booking.calculatedNights else booking.expectedNights
                val totalDue = if (booking.totalDueCached > 0) {
                    booking.totalDueCached
                } else {
                    val roomRate = roomsRepository.getByNumber(booking.roomNumber)?.price ?: 0.0
                    roomRate * totalNights
                }
                val nightlyRate = if (totalNights > 0) totalDue / totalNights else 0.0
                val total = nightlyRate * nights
                val paid = booking.totalPaidCached
                val remaining = (total - paid).coerceIn(0.0, total)
                _state.value = _state.value.copy(
                    isComputing = false,
                    error = null,
                    computation = DebtComputation(nights, nightlyRate, total, paid, remaining)
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(isComputing = false, error = e.message)
            }
        }
    }

    /**
     * Dart save (l.460-487): debt carries bookingLocalId, the guest, the stay
     * dates, the auto reason "دين من حجز الغرفة N للفترة ...", today's
     * dateRecorded, and the note.
     */
    fun saveDebt(amount: Double, notes: String) {
        val booking = _state.value.selectedBooking ?: return
        viewModelScope.launch {
            _state.value = _state.value.copy(isSaving = true)
            try {
                if (amount <= 0) {
                    _state.value = _state.value.copy(isSaving = false, error = "يرجى إدخال مبلغ صحيح")
                    return@launch
                }
                val today = HotelTimeEngine.formatIso(System.currentTimeMillis()).take(10)
                val from = _state.value.fromDate
                val to = _state.value.toDate
                val autoReason = "دين من حجز الغرفة ${booking.roomNumber} للفترة $from إلى $to"
                debtsRepository.insert(
                    Debt(
                        bookingLocalId = booking.id,
                        guestName = booking.guestName,
                        guestPhone = booking.guestPhone,
                        checkinDate = booking.checkinDate,
                        checkoutDate = booking.checkoutDate.orEmpty(),
                        dateRecorded = today,
                        debtReason = autoReason,
                        totalAmount = amount,
                        paidAmount = 0.0,
                        remainingAmount = amount,
                        paymentDate = today,
                        note = notes.trim().ifBlank { null }
                    )
                )
                _state.value = _state.value.copy(isSaving = false, saved = true)
            } catch (e: Exception) {
                _state.value = _state.value.copy(isSaving = false, error = e.message)
            }
        }
    }
}
