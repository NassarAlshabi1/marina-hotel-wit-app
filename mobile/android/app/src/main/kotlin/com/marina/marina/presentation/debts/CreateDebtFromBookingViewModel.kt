package com.marina.marina.presentation.debts

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marina.marina.domain.model.Booking
import com.marina.marina.domain.model.Debt
import com.marina.marina.domain.repository.BookingsRepository
import com.marina.marina.domain.repository.DebtsRepository
import com.marina.marina.domain.repository.SyncRepository
import com.marina.marina.domain.util.HotelTimeEngine
import dagger.hilt.android.lifecycle.HiltViewModel
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.launch

/** Dart _DebtData (create_debt_from_booking.dart l.554-567). */
data class DebtComputation(
    val nights: Int,
    val roomRate: Double,
    val total: Double,
    val paid: Double
) {
    /** Dart: `double get remaining => (total - paid).clamp(0, total)`. */
    val remaining: Double get() = (total - paid).coerceIn(0.0, total)
}

/**
 * Dart create_debt_from_booking.dart — the user picks an active booking,
 * a debt period, computes the amount from the booking's cached nightly
 * rate, then creates the debt. No booking is selected initially (Dart
 * l.24: `_selectedBooking = null`).
 */
data class CreateDebtUiState(
    val isLoading: Boolean = true,
    val isComputing: Boolean = false,
    val isProcessing: Boolean = false,
    /** حجوزات نشطة (غير مكتملة/ملغاة) — Dart l.101-169. */
    val selectableBookings: List<Booking> = emptyList(),
    val selectedBooking: Booking? = null,
    val fromDate: String = "",
    val toDate: String = "",
    val computation: DebtComputation? = null,
    val amountText: String = "",
    val notes: String = "",
    /** للرجوع دون حفظ عند وجود تغييرات — Dart _hasUnsavedChanges l.519-523. */
    val saved: Boolean = false,
    val error: String? = null
) {
    val hasUnsavedChanges: Boolean
        get() = selectedBooking != null || computation != null ||
            amountText.isNotEmpty() || notes.isNotEmpty()
}

@HiltViewModel
class CreateDebtFromBookingViewModel @Inject constructor(
    private val bookingsRepository: BookingsRepository,
    private val debtsRepository: DebtsRepository,
    private val syncRepository: SyncRepository
) : ViewModel() {

    private val _state = MutableStateFlow(CreateDebtUiState())
    val state: StateFlow<CreateDebtUiState> = _state.asStateFlow()

    fun load(preselectedBookingId: Long) {
        viewModelScope.launch {
            try {
                // Dart l.101-169 — كل حجز ليس checked_out أو cancelled.
                val all = bookingsRepository.getAll().firstOrNull() ?: emptyList()
                val selectable = all.filter { b ->
                    b.status != "checked_out" && b.status != "cancelled"
                }
                // التطابق الافتراضي مع Dart: لا اختيار مبدئي. يُختار الحجز فقط
                // إذا وصل عبر المسار create_debt/{bookingId} بقيمة صريحة.
                val selected = if (preselectedBookingId > 0) {
                    selectable.find { it.id == preselectedBookingId }
                } else {
                    null
                }
                _state.value = CreateDebtUiState(
                    isLoading = false,
                    selectableBookings = selectable,
                    selectedBooking = selected,
                    fromDate = selected?.checkinDate?.take(10) ?: "",
                    toDate = selected?.let { resolveCheckout(it) } ?: ""
                )
            } catch (e: Exception) {
                _state.value = CreateDebtUiState(isLoading = false, error = e.message)
            }
        }
    }

    /** Dart l.151-162 — اختيار الحجز يملأ فترة الدين من تاريخ الدخول/الخروج. */
    fun selectBooking(bookingId: Long) {
        val booking = _state.value.selectableBookings.find { it.id == bookingId } ?: return
        _state.value = _state.value.copy(
            selectedBooking = booking,
            fromDate = booking.checkinDate.take(10),
            toDate = resolveCheckout(booking),
            computation = null
        )
    }

    fun setFromDate(date: String) {
        _state.value = _state.value.copy(fromDate = date, computation = null)
    }

    fun setToDate(date: String) {
        _state.value = _state.value.copy(toDate = date, computation = null)
    }

    fun setAmountText(text: String) {
        _state.value = _state.value.copy(amountText = text)
    }

    fun setNotes(text: String) {
        _state.value = _state.value.copy(notes = text)
    }

    /**
     * Dart _computeDebt (l.314-350): nights = to - from (أيام)؛ سعر الليلة
     * = totalDueCached / totalNightsCached؛ الإجمالي = السعر × الليالي؛
     * المدفوع = totalPaidCached.
     */
    fun computeDebt() {
        val booking = _state.value.selectedBooking ?: return
        _state.value = _state.value.copy(isComputing = true)
        try {
            val from = HotelTimeEngine.parseDate(_state.value.fromDate)
            val to = HotelTimeEngine.parseDate(_state.value.toDate)
            if (from == null || to == null) {
                _state.value = _state.value.copy(isComputing = false, error = "فترة غير صالحة")
                return
            }
            val nights = TimeUnit.MILLISECONDS.toDays(to - from).toInt()
            if (nights <= 0) {
                _state.value = _state.value.copy(isComputing = false, error = "فترة غير صالحة")
                return
            }

            val nightlyRate = if (booking.totalNightsCached > 0) {
                booking.totalDueCached / booking.totalNightsCached
            } else {
                0.0
            }
            val total = nightlyRate * nights
            val paid = booking.totalPaidCached

            val computation = DebtComputation(
                nights = nights,
                roomRate = nightlyRate,
                total = total,
                paid = paid
            )
            _state.value = _state.value.copy(
                isComputing = false,
                error = null,
                computation = computation,
                amountText = com.marina.marina.domain.util.CurrencyFormatter.formatAmount(computation.remaining)
            )
        } catch (e: Exception) {
            _state.value = _state.value.copy(isComputing = false, error = e.message)
        }
    }

    /** Dart _createDebt (l.442-495) — ينشئ الدين ويُرجع للقائمة. */
    fun createDebt() {
        val booking = _state.value.selectedBooking ?: return
        if (_state.value.computation == null) return

        val amount = com.marina.marina.domain.util.CurrencyFormatter.parseAmount(_state.value.amountText)
        if (amount == null || amount <= 0) {
            _state.value = _state.value.copy(error = "يرجى إدخال مبلغ صحيح")
            return
        }

        _state.value = _state.value.copy(isProcessing = true)
        viewModelScope.launch {
            try {
                val now = System.currentTimeMillis()
                val today = HotelTimeEngine.formatIso(now).take(10)
                val from = _state.value.fromDate
                val to = _state.value.toDate
                debtsRepository.insert(
                    Debt(
                        bookingLocalId = booking.id,
                        guestName = booking.guestName,
                        guestPhone = booking.guestPhone,
                        checkinDate = from,
                        checkoutDate = to,
                        dateRecorded = today,
                        debtReason = "دين من حجز الغرفة ${booking.roomNumber} للفترة $from - $to",
                        totalAmount = amount,
                        paidAmount = 0.0,
                        remainingAmount = amount,
                        paymentDate = today,
                        note = _state.value.notes.ifEmpty { null }
                    )
                )
                // ✅ رفع فوري لدين جديد منشأ من حجز (نظير pushLocalChanges في Dart).
                try {
                    syncRepository.pushOnly()
                } catch (_: Exception) {
                }
                _state.value = _state.value.copy(isProcessing = false, saved = true)
            } catch (e: Exception) {
                _state.value = _state.value.copy(isProcessing = false, error = "حدث خطأ: ${e.message}")
            }
        }
    }

    fun consumeError() {
        _state.value = _state.value.copy(error = null)
    }

    /** Dart _resolveCheckout (l.503-517): actual → planned → now. */
    private fun resolveCheckout(booking: Booking): String {
        val actual = booking.actualCheckout?.takeIf { it.isNotEmpty() }?.let { HotelTimeEngine.parseDate(it) }
        if (actual != null) return HotelTimeEngine.formatIso(actual).take(10)
        val planned = booking.checkoutDate?.takeIf { it.isNotEmpty() }?.let { HotelTimeEngine.parseDate(it) }
        if (planned != null) return HotelTimeEngine.formatIso(planned).take(10)
        return HotelTimeEngine.formatIso(System.currentTimeMillis()).take(10)
    }
}
