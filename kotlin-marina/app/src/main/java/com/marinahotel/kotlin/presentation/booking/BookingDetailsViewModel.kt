package com.marinahotel.kotlin.presentation.booking

import androidx.annotation.StringRes
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marinahotel.kotlin.R
import com.marinahotel.kotlin.data.repository.HotelRepository
import com.marinahotel.kotlin.domain.model.BookingStatus
import com.marinahotel.kotlin.domain.model.Payment
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.max

class BookingDetailsViewModel(
    private val repository: HotelRepository,
    private val bookingId: Int
) : ViewModel() {

    private val zoneId = ZoneId.systemDefault()
    private val dateFormatter = DateTimeFormatter.ofPattern("dd MMM yyyy", Locale.getDefault())
    private val dateTimeFormatter = DateTimeFormatter.ofPattern("dd MMM yyyy - HH:mm", Locale.getDefault())

    private val _state = MutableStateFlow(BookingDetailsUiState())
    val state: StateFlow<BookingDetailsUiState> = _state.asStateFlow()

    private val eventsFlow = MutableSharedFlow<BookingDetailsEvent>()
    val events: SharedFlow<BookingDetailsEvent> = eventsFlow

    init {
        if (bookingId <= 0) {
            viewModelScope.launch {
                eventsFlow.emit(BookingDetailsEvent.ShowMessage(R.string.error_missing_booking))
            }
            _state.update { it.copy(isLoading = false) }
        } else {
            observeBooking()
        }
    }

    private fun observeBooking() {
        viewModelScope.launch {
            repository.observeBookingDetails(bookingId).collect { summary ->
                if (summary == null) {
                    _state.update { it.copy(isLoading = false) }
                    eventsFlow.emit(BookingDetailsEvent.ShowMessage(R.string.error_missing_booking))
                } else {
                    val nights = if (summary.booking.checkoutDate != null) {
                        max(1, summary.booking.calculatedNights)
                    } else {
                        computeNights(summary.booking.checkinDate, System.currentTimeMillis())
                    }
                    val totalAmount = summary.room.price * nights
                    val totalPaid = summary.payments.sumOf { it.amount }
                    val remainingAmount = max(totalAmount - totalPaid, 0)
                    val paymentItems = summary.payments.sortedByDescending { it.paymentDate }.map { payment ->
                        PaymentItem(
                            id = payment.id,
                            amount = payment.amount,
                            method = payment.paymentMethod,
                            notes = payment.notes.orEmpty(),
                            paymentDate = payment.paymentDate
                        )
                    }
                    _state.update {
                        it.copy(
                            isLoading = false,
                            bookingId = summary.booking.id,
                            guestName = summary.guest.name,
                            guestPhone = summary.guest.phone,
                            guestIdNumber = summary.guest.idNumber,
                            guestIdType = summary.guest.idType,
                            guestNationality = summary.guest.nationality,
                            roomNumber = summary.room.number,
                            roomType = summary.room.type,
                            status = summary.booking.status,
                            checkinDate = summary.booking.checkinDate,
                            checkoutDate = summary.booking.checkoutDate,
                            notes = summary.booking.notes,
                            nights = nights,
                            totalAmount = totalAmount,
                            paidAmount = totalPaid,
                            remainingAmount = remainingAmount,
                            payments = paymentItems,
                            isCheckoutEnabled = remainingAmount == 0 && summary.booking.status == BookingStatus.RESERVED
                        )
                    }
                }
            }
        }
    }

    fun onPaymentAmountChanged(value: String) {
        _state.update { it.copy(paymentAmountInput = value.filter { char -> char.isDigit() }, paymentAmountError = null) }
    }

    fun onPaymentMethodChanged(value: String) {
        _state.update { it.copy(paymentMethodInput = value, paymentMethodError = null) }
    }

    fun onPaymentNotesChanged(value: String) {
        _state.update { it.copy(paymentNotesInput = value) }
    }

    fun onAddPaymentClicked() {
        val current = _state.value
        val amount = current.paymentAmountInput.toIntOrNull()
        if (amount == null || amount <= 0) {
            _state.update { it.copy(paymentAmountError = R.string.error_payment_amount) }
            return
        }
        if (current.paymentMethodInput.isBlank()) {
            _state.update { it.copy(paymentMethodError = R.string.error_payment_method) }
            return
        }
        viewModelScope.launch {
            _state.update {
                it.copy(
                    isAddingPayment = true,
                    paymentAmountError = null,
                    paymentMethodError = null
                )
            }
            try {
                val payment = Payment(
                    bookingId = bookingId,
                    amount = amount,
                    paymentDate = System.currentTimeMillis(),
                    paymentMethod = current.paymentMethodInput,
                    notes = current.paymentNotesInput.ifBlank { null }
                )
                repository.addPayment(payment)
                _state.update {
                    it.copy(
                        isAddingPayment = false,
                        paymentAmountInput = "",
                        paymentMethodInput = "",
                        paymentNotesInput = ""
                    )
                }
                eventsFlow.emit(BookingDetailsEvent.ShowMessage(R.string.message_payment_added))
            } catch (exception: Exception) {
                _state.update { it.copy(isAddingPayment = false) }
                eventsFlow.emit(BookingDetailsEvent.ShowMessage(R.string.error_payment_amount))
            }
        }
    }

    fun onCheckoutClicked() {
        val current = _state.value
        if (!current.isCheckoutEnabled) {
            if (current.remainingAmount > 0) {
                viewModelScope.launch {
                    eventsFlow.emit(BookingDetailsEvent.ShowMessage(R.string.error_outstanding_amount))
                }
            }
            return
        }
        viewModelScope.launch {
            eventsFlow.emit(BookingDetailsEvent.ConfirmCheckout)
        }
    }

    fun onCheckoutConfirmed() {
        viewModelScope.launch {
            _state.update { it.copy(isCheckoutInProgress = true) }
            try {
                repository.checkOut(bookingId)
                _state.update { it.copy(isCheckoutInProgress = false) }
                eventsFlow.emit(BookingDetailsEvent.ShowMessage(R.string.message_checkout_success))
            } catch (exception: Exception) {
                _state.update { it.copy(isCheckoutInProgress = false) }
                eventsFlow.emit(BookingDetailsEvent.ShowMessage(R.string.error_missing_booking))
            }
        }
    }

    fun formatDate(timestamp: Long?): String {
        if (timestamp == null || timestamp == 0L) return ""
        val instant = Instant.ofEpochMilli(timestamp)
        return dateFormatter.format(instant.atZone(zoneId).toLocalDate())
    }

    fun formatDateTime(timestamp: Long): String {
        val instant = Instant.ofEpochMilli(timestamp)
        return dateTimeFormatter.format(instant.atZone(zoneId))
    }

    private fun computeNights(checkin: Long, checkout: Long): Int {
        val diff = max(0L, checkout - checkin)
        val nights = (diff / MILLIS_PER_DAY).toInt()
        return max(1, nights)
    }

    data class BookingDetailsUiState(
        val isLoading: Boolean = true,
        val bookingId: Int = 0,
        val guestName: String = "",
        val guestPhone: String = "",
        val guestIdNumber: String = "",
        val guestIdType: String = "",
        val guestNationality: String? = null,
        val roomNumber: String = "",
        val roomType: String = "",
        val status: BookingStatus = BookingStatus.RESERVED,
        val checkinDate: Long = 0L,
        val checkoutDate: Long? = null,
        val notes: String? = null,
        val nights: Int = 1,
        val totalAmount: Int = 0,
        val paidAmount: Int = 0,
        val remainingAmount: Int = 0,
        val payments: List<PaymentItem> = emptyList(),
        val paymentAmountInput: String = "",
        val paymentMethodInput: String = "",
        val paymentNotesInput: String = "",
        @StringRes val paymentAmountError: Int? = null,
        @StringRes val paymentMethodError: Int? = null,
        val isAddingPayment: Boolean = false,
        val isCheckoutInProgress: Boolean = false,
        val isCheckoutEnabled: Boolean = false
    )

    data class PaymentItem(
        val id: Int,
        val amount: Int,
        val method: String,
        val notes: String,
        val paymentDate: Long
    )

    sealed class BookingDetailsEvent {
        data class ShowMessage(@StringRes val messageRes: Int) : BookingDetailsEvent()
        object ConfirmCheckout : BookingDetailsEvent()
    }

    companion object {
        private const val MILLIS_PER_DAY = 86_400_000L
    }
}
