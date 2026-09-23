package com.marina.marina.presentation.bookings

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marina.marina.domain.model.BlacklistEntry
import com.marina.marina.domain.model.Booking
import com.marina.marina.domain.model.Payment
import com.marina.marina.domain.repository.BlacklistRepository
import com.marina.marina.domain.repository.BookingsRepository
import com.marina.marina.domain.repository.PaymentsRepository
import com.marina.marina.domain.repository.RoomsRepository
import com.marina.marina.domain.util.BookingFinancials
import com.marina.marina.domain.util.CurrencyFormatter
import com.marina.marina.domain.util.HotelTimeEngine
import com.marina.marina.domain.util.StatusUtils
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch

/** All booking-editor form fields (Dart booking_edit.dart full guest model). */
data class BookingEditForm(
    val guestName: String = "",
    val guestPhone: String = "",
    val guestIdType: String = "بطاقة شخصية",
    val guestIdNumber: String = "",
    val guestIdIssueDate: String = "",
    val guestIdIssuePlace: String = "",
    val guestNationality: String = "",
    val guestEmail: String = "",
    val guestAddress: String = "",
    val roomNumber: String = "",
    val checkinDate: String = "",
    val checkoutDate: String = "",
    val status: String = "",
    val notes: String = "",
    val advanceEnabled: Boolean = false,
    val advanceAmount: String = "",
    val advanceMethod: String = "نقدي",
    val advanceNotes: String = ""
)

data class BookingEditUiState(
    val isLoading: Boolean = false,
    val isEdit: Boolean = false,
    val booking: Booking? = null,
    val availableRooms: List<com.marina.marina.domain.model.Room> = emptyList(),
    /** Room pre-selected from the Rooms/Dashboard flow (initialRoomNumber). */
    val preselectedRoom: String = "",
    val saved: Boolean = false,
    val isSaving: Boolean = false,
    val error: String? = null,
    /** Dart security warning (l.622-713): a blacklisted guest name match. */
    val blacklistWarning: BlacklistEntry? = null
)

@HiltViewModel
class BookingEditViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val bookingsRepository: BookingsRepository,
    private val roomsRepository: RoomsRepository,
    private val paymentsRepository: PaymentsRepository,
    private val blacklistRepository: BlacklistRepository
) : ViewModel() {

    private val bookingId: Long = savedStateHandle.get<Long>("bookingId") ?: 0L
    private val preselectedRoom: String = savedStateHandle.get<String>("roomNumber") ?: ""

    private val _state = MutableStateFlow(
        BookingEditUiState(isLoading = true, isEdit = bookingId > 0, preselectedRoom = preselectedRoom)
    )
    val state: StateFlow<BookingEditUiState> = _state.asStateFlow()

    init {
        combine(bookingsRepository.getAll(), roomsRepository.getAll()) { bookings, rooms ->
            val editing = bookings.find { it.id == bookingId }
            // Rooms that are free (or the room already used by this booking).
            val freeRooms = rooms.filter {
                StatusUtils.isRoomAvailable(it.status) || (editing != null && it.roomNumber == editing.roomNumber)
            }
            editing to freeRooms
        }.onEach { (editing, freeRooms) ->
            _state.value = _state.value.copy(
                isLoading = false,
                booking = editing,
                availableRooms = freeRooms
            )
        }.launchIn(viewModelScope)
    }

    fun dismissBlacklistWarning() {
        _state.value = _state.value.copy(blacklistWarning = null)
    }

    /**
     * Dart `_saveBooking` (l.560-873) — validation, blacklist security check,
     * nightsWithCutoff, phone normalization, room occupancy sync, advance
     * payment, and the auto-checkout rule for status 'مكتمل'.
     */
    fun save(form: BookingEditForm, overrideBlacklist: Boolean = false) {
        if (_state.value.isSaving) return // Dart _isSaving double-tap guard.
        viewModelScope.launch {
            _state.value = _state.value.copy(isSaving = true, error = null)
            try {
                val name = form.guestName.trim()
                if (name.isEmpty() || form.guestIdNumber.trim().isEmpty()) {
                    _state.value = _state.value.copy(
                        isSaving = false,
                        error = "يرجى تعبئة اسم النزيل ورقم الهوية"
                    )
                    return@launch
                }
                if (form.roomNumber.isBlank()) {
                    _state.value = _state.value.copy(isSaving = false, error = "يرجى اختيار غرفة")
                    return@launch
                }
                val checkinMillis = HotelTimeEngine.parseDate(form.checkinDate)
                if (checkinMillis == null) {
                    _state.value = _state.value.copy(isSaving = false, error = "تاريخ الدخول غير صالح")
                    return@launch
                }
                val checkoutMillis = HotelTimeEngine.parseDate(form.checkoutDate)
                if (checkoutMillis != null && checkoutMillis < checkinMillis) {
                    _state.value = _state.value.copy(isSaving = false, error = "تاريخ المغادرة يجب أن يكون بعد تاريخ الوصول")
                    return@launch
                }

                // Dart l.622-713 — blacklist security check (first-3-name match).
                if (!overrideBlacklist) {
                    val match = blacklistRepository.findBlacklistMatch(name)
                    if (match != null) {
                        _state.value = _state.value.copy(isSaving = false, blacklistWarning = match)
                        return@launch
                    }
                } else {
                    _state.value = _state.value.copy(blacklistWarning = null)
                }

                val existing = _state.value.booking
                // Dart l.605-618 — nightsWithCutoff everywhere; a NEW booking
                // without a checkout date counts as exactly 1 night.
                val nights = when {
                    existing == null && checkoutMillis == null -> 1
                    checkoutMillis == null -> existing?.calculatedNights ?: 1
                    else -> HotelTimeEngine.nightsWithCutoff(checkinMillis, checkoutMillis)
                }

                // Dart l.145-149 — default status from the CURRENT hour
                // (9:00–14:00 => مؤقت, otherwise محجوزة).
                val defaultStatus = java.util.Calendar.getInstance().get(java.util.Calendar.HOUR_OF_DAY)
                    .let { if (it in 9..13) "مؤقت" else "محجوزة" }
                val requestedStatus = form.status.trim()
                    .ifBlank { existing?.status ?: defaultStatus }

                // Dart l.739-787 — editing the status to 'مكتمل' mirrors the
                // checkout screen: actual checkout stamped, nights finalized.
                var actualCheckout: String? = existing?.actualCheckout
                var finalNights = nights
                if (requestedStatus == "مكتمل" && existing != null && existing.actualCheckout.isNullOrBlank()) {
                    val now = System.currentTimeMillis()
                    actualCheckout = HotelTimeEngine.formatIso(now)
                    finalNights = HotelTimeEngine.nightsWithCutoff(checkinMillis, now)
                }

                val booking = (existing ?: Booking()).copy(
                    guestName = name,
                    guestPhone = BookingFinancials.cleanAndFormatPhone(form.guestPhone),
                    guestIdType = form.guestIdType.trim().ifBlank { "بطاقة شخصية" },
                    guestIdNumber = form.guestIdNumber.trim(),
                    guestIdIssueDate = form.guestIdIssueDate.trim().ifBlank { null },
                    guestIdIssuePlace = form.guestIdIssuePlace.trim().ifBlank { null },
                    guestNationality = form.guestNationality.trim().ifBlank { "غير معروف" },
                    guestEmail = form.guestEmail.trim().ifBlank { null },
                    guestAddress = form.guestAddress.trim().ifBlank { null },
                    roomNumber = form.roomNumber,
                    checkinDate = form.checkinDate.trim(),
                    checkoutDate = form.checkoutDate.trim().ifBlank { null },
                    status = requestedStatus,
                    actualCheckout = actualCheckout,
                    notes = form.notes.trim().ifBlank { null },
                    expectedNights = nights,
                    calculatedNights = finalNights,
                    hotelDayCheckin = HotelTimeEngine.hotelDayKey(checkinMillis)
                )

                if (existing == null) {
                    bookingsRepository.insert(booking)
                } else {
                    bookingsRepository.update(booking)
                }

                // Room occupancy sync (Dart refreshAllRoomOccupancy sweep):
                // the previous room is freed when the booking moved rooms or
                // ended; the new room is occupied while the booking is active.
                syncRoomOccupancy(existing, booking)

                // Dart l.804-840 — advance payment (دفعة مقدمة) recorded as a
                // 'deposit' revenue payment for the new booking.
                if (form.advanceEnabled) {
                    val advanceAmount = CurrencyFormatter.parseAmount(form.advanceAmount) ?: 0.0
                    if (advanceAmount > 0) {
                        try {
                            paymentsRepository.insert(
                                Payment(
                                    bookingLocalId = booking.id,
                                    roomNumber = booking.roomNumber,
                                    amount = advanceAmount,
                                    paymentMethod = form.advanceMethod,
                                    revenueType = "deposit",
                                    notes = form.advanceNotes.trim().ifBlank { "دفعة مقدمة" }
                                )
                            )
                        } catch (_: Exception) {
                            _state.value = _state.value.copy(
                                error = "تم حفظ الحجز لكن فشل حفظ الدفعة المقدمة"
                            )
                        }
                    }
                }

                _state.value = _state.value.copy(isSaving = false, saved = true)
            } catch (e: Exception) {
                _state.value = _state.value.copy(isSaving = false, error = e.message ?: "فشل حفظ الحجز")
            }
        }
    }

    private suspend fun syncRoomOccupancy(old: Booking?, new: Booking) {
        val bookingActive = new.status !in listOf("مكتمل", "ملغي")
        // Free the OLD room when the booking moved away or ended.
        if (old != null && (old.roomNumber != new.roomNumber || !bookingActive)) {
            val allBookings = bookingsRepository.getAll().firstOrNull() ?: emptyList()
            val stillUsed = allBookings.any {
                it.roomNumber == old.roomNumber && it.id != new.id &&
                    it.status !in listOf("مكتمل", "ملغي")
            }
            if (!stillUsed) {
                roomsRepository.getByNumber(old.roomNumber)?.let { room ->
                    if (!StatusUtils.isRoomAvailable(room.status)) {
                        roomsRepository.update(room.copy(status = "شاغرة"))
                    }
                }
            }
        }
        // Occupy the NEW room while the booking is active.
        if (bookingActive) {
            roomsRepository.getByNumber(new.roomNumber)?.let { room ->
                if (StatusUtils.isRoomAvailable(room.status)) {
                    roomsRepository.update(room.copy(status = "محجوزة"))
                }
            }
        }
    }
}
