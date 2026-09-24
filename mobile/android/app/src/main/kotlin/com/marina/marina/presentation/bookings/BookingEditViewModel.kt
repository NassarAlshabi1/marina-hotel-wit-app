package com.marina.marina.presentation.bookings

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marina.marina.domain.model.BlacklistEntry
import com.marina.marina.domain.model.Booking
import com.marina.marina.domain.model.Payment
import com.marina.marina.domain.model.Room
import com.marina.marina.domain.repository.BlacklistRepository
import com.marina.marina.domain.repository.BookingsRepository
import com.marina.marina.domain.repository.PaymentsRepository
import com.marina.marina.domain.repository.RoomsRepository
import com.marina.marina.domain.repository.SyncRepository
import com.marina.marina.domain.util.CurrencyFormatter
import com.marina.marina.domain.util.HotelTimeEngine
import com.marina.marina.domain.util.StatusUtils
import dagger.hilt.android.lifecycle.HiltViewModel
import java.util.Calendar
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
    val guestNationality: String = "يمني",
    val guestAddress: String = "",
    val roomNumber: String = "",
    val checkinDate: String = "",
    val checkoutDate: String = "",
    val status: String = "محجوزة",
    val notes: String = "",
    val hasAdvancePayment: Boolean = false,
    val advanceAmount: String = "",
    val advanceMethod: String = "نقدي",
    val advanceNotes: String = ""
)

/** أنواع سناك-بار بنفس ألوان Dart في booking_edit.dart. */
enum class BookingEditSnackKind { RED, RED_DARK, ORANGE }

data class BookingEditSnackbar(
    val text: String,
    val kind: BookingEditSnackKind = BookingEditSnackKind.RED,
    /** تحذير القائمة السوداء — محتوى متعدد الأسطر مع زر «متابعة الحجز». */
    val blacklistEntry: BlacklistEntry? = null
)

data class BookingEditUiState(
    val isLoading: Boolean = false,
    val isEdit: Boolean = false,
    val booking: Booking? = null,
    /** الغرف الشاغرة فقط — Dart _buildRoomSelector (rooms.filter(isRoomAvailable)). */
    val availableRooms: List<Room> = emptyList(),
    /** Room pre-selected from the Rooms/Dashboard flow (initialRoomNumber). */
    val preselectedRoom: String = "",
    /** Dart l.145-151: الحالة الافتراضية حسب ساعة الإنشاء (9:00–14:00 → مؤقت). */
    val defaultStatus: String = "محجوزة",
    val saved: Boolean = false,
    val isSaving: Boolean = false,
    /** مؤشر حالة المزامنة في AppBar — Dart _buildSyncIndicator (l.875-931). */
    val isSyncing: Boolean = false,
    val pendingSyncCount: Int = 0,
    val snackbar: BookingEditSnackbar? = null
)

@HiltViewModel
class BookingEditViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val bookingsRepository: BookingsRepository,
    private val roomsRepository: RoomsRepository,
    private val paymentsRepository: PaymentsRepository,
    private val blacklistRepository: BlacklistRepository,
    private val syncRepository: SyncRepository
) : ViewModel() {

    private val bookingId: Long = savedStateHandle.get<Long>("bookingId") ?: 0L
    private val preselectedRoom: String = savedStateHandle.get<String>("roomNumber") ?: ""

    private val _state = MutableStateFlow(
        BookingEditUiState(
            isLoading = true,
            isEdit = bookingId > 0,
            preselectedRoom = preselectedRoom,
            defaultStatus = defaultStatusByHour()
        )
    )
    val state: StateFlow<BookingEditUiState> = _state.asStateFlow()

    init {
        combine(bookingsRepository.getAll(), roomsRepository.getAll()) { bookings, rooms ->
            val editing = bookings.find { it.id == bookingId }
            // Dart l.1104-1110 — availableRooms: الغرف الشاغرة فقط مرتبة
            // بمقارنة نصية على رقم الغرفة (الغرفة الحالية للحجز تظهر في
            // الواجهة كعنصر «(الحالي)» وليس هنا).
            val available = rooms
                .filter { StatusUtils.isRoomAvailable(it.status) }
                .sortedBy { it.roomNumber }
            editing to available
        }.onEach { (editing, available) ->
            _state.value = _state.value.copy(
                isLoading = false,
                booking = editing,
                availableRooms = available
            )
        }.launchIn(viewModelScope)

        // مؤشر المزامنة في AppBar — Dart StreamBuilder<SyncStatus>:
        // syncing → مؤشر دوّار، pending → سحابة رفع برتقالية، synced → سحابة خضراء.
        syncRepository.syncState.onEach { sync ->
            _state.value = _state.value.copy(isSyncing = sync.isSyncing)
        }.launchIn(viewModelScope)
        syncRepository.pendingCount().onEach { pending ->
            _state.value = _state.value.copy(pendingSyncCount = pending)
        }.launchIn(viewModelScope)
    }

    /** Dart l.145-151: 9:00–13:59 → «مؤقت»، وإلا «محجوزة». */
    private fun defaultStatusByHour(): String {
        val hour = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)
        return if (hour in 9..13) "مؤقت" else "محجوزة"
    }

    fun consumeSnackbar() {
        _state.value = _state.value.copy(snackbar = null)
    }

    /**
     * Dart `_saveBooking` (l.560-873) — نفس العقد بالكامل: تحقق، تطبيع هاتف،
     * فحص تسلسل التواريخ، فحص القائمة السوداء (غير معطِّل — تحذير فقط)، حفظ،
     * دفعة مقدمة كـ deposit، تحديث إشغال الغرف، رفع فوري ثم مزامنة وإغلاق.
     */
    fun save(form: BookingEditForm) {
        if (_state.value.isSaving) return // Dart _isSaving double-tap guard.
        viewModelScope.launch {
            fun snack(text: String, kind: BookingEditSnackKind) {
                _state.value = _state.value.copy(snackbar = BookingEditSnackbar(text, kind))
            }
            // ✅ تحقق النموذج — Dart l.565-577: نفس الرسالة الحمراء.
            if (form.guestName.trim().isEmpty() || form.guestIdNumber.trim().isEmpty()) {
                snack("يرجى تعبئة اسم النزيل ورقم الهوية", BookingEditSnackKind.RED)
                return@launch
            }
            if (form.roomNumber.trim().isEmpty()) {
                snack("مطلوب", BookingEditSnackKind.RED)
                return@launch
            }
            // ✅ تحقق الدفعة المقدمة — Dart l.505-519.
            if (form.hasAdvancePayment) {
                if (form.advanceAmount.trim().isEmpty()) {
                    snack("مطلوب عند تحديد دفعة مقدمة", BookingEditSnackKind.RED)
                    return@launch
                }
                val advance = CurrencyFormatter.parseAmount(form.advanceAmount)
                if (advance == null || advance <= 0) {
                    snack("المبلغ يجب أن يكون أكبر من صفر", BookingEditSnackKind.RED)
                    return@launch
                }
            }

            _state.value = _state.value.copy(isSaving = true)
            try {
                val existing = _state.value.booking
                val name = form.guestName.trim()
                val phone = normalizePhone(form.guestPhone)
                val nationality = form.guestNationality.trim().ifEmpty { "غير معروف" }
                val roomNumber = form.roomNumber.trim()
                val checkin = form.checkinDate.trim()
                val checkout = form.checkoutDate.trim().ifEmpty { null }
                val expectedNights = expectedNightsFor(form.checkinDate, form.checkoutDate, existing)

                // ✅ فحص تسلسل التواريخ — Dart l.592-602.
                val checkinMillis = HotelTimeEngine.parseDate(checkin)
                val checkoutMillis = checkout?.let { HotelTimeEngine.parseDate(it) }
                if (checkinMillis != null && checkoutMillis != null && checkoutMillis < checkinMillis) {
                    snack("تاريخ المغادرة يجب أن يكون بعد تاريخ الوصول", BookingEditSnackKind.RED)
                    _state.value = _state.value.copy(isSaving = false)
                    return@launch
                }

                val calculatedNights = when {
                    checkinMillis == null -> expectedNights
                    checkoutMillis == null && existing == null -> 1
                    else -> HotelTimeEngine.nightsWithCutoff(checkinMillis, checkoutMillis)
                }
                val notes = form.notes.trim().ifEmpty { null }

                // فحص القائمة السوداء (Dart l.622-713) — مطابقة أول 3 أسماء.
                // لا يوقف الحجز — يعرض التحذير فقط مع زر «متابعة الحجز» الشكلي.
                val blacklistedMatch = blacklistRepository.findBlacklistMatch(name)
                if (blacklistedMatch != null) {
                    _state.value = _state.value.copy(
                        snackbar = BookingEditSnackbar(
                            "تحذير أمني — اسم في القائمة السوداء",
                            kind = BookingEditSnackKind.RED_DARK,
                            blacklistEntry = blacklistedMatch
                        )
                    )
                }

                val newBookingId: Long
                if (existing == null) {
                    newBookingId = bookingsRepository.insert(
                        Booking(
                            roomNumber = roomNumber,
                            guestName = name,
                            guestPhone = phone,
                            guestIdType = form.guestIdType,
                            guestIdNumber = form.guestIdNumber.trim(),
                            guestIdIssueDate = form.guestIdIssueDate.trim().ifEmpty { null },
                            guestIdIssuePlace = form.guestIdIssuePlace.trim().ifEmpty { null },
                            guestNationality = nationality,
                            guestAddress = form.guestAddress.trim().ifEmpty { null },
                            checkinDate = checkin,
                            checkoutDate = checkout,
                            status = form.status,
                            notes = notes,
                            expectedNights = expectedNights,
                            calculatedNights = calculatedNights,
                            hotelDayCheckin = checkinMillis?.let { HotelTimeEngine.hotelDayKey(it) }
                        )
                    )
                } else {
                    newBookingId = existing.id

                    // ✅ عند تغيير الحالة إلى «مكتمل» — تسجيل المغادرة الفعلية
                    // تلقائياً وتحرير الغرفة (Dart l.739-767، نفس _completeCheckout).
                    val wasNotCompleted = existing.status != "مكتمل"
                    val isNowCompleted = form.status == "مكتمل"
                    var actualCheckoutValue: String? = null
                    var checkoutCalculatedNights: Int? = null
                    if (isNowCompleted && wasNotCompleted) {
                        val now = System.currentTimeMillis()
                        actualCheckoutValue = HotelTimeEngine.formatIso(now)
                        checkoutCalculatedNights = HotelTimeEngine.nightsWithCutoff(
                            checkinMillis ?: now, now
                        )
                    }

                    bookingsRepository.update(
                        existing.copy(
                            roomNumber = roomNumber,
                            guestName = name,
                            guestPhone = phone,
                            guestIdType = form.guestIdType,
                            guestIdNumber = form.guestIdNumber.trim(),
                            guestIdIssueDate = form.guestIdIssueDate.trim().ifEmpty { null },
                            guestIdIssuePlace = form.guestIdIssuePlace.trim().ifEmpty { null },
                            guestNationality = nationality,
                            guestAddress = form.guestAddress.trim().ifEmpty { null },
                            checkinDate = checkin,
                            checkoutDate = checkout,
                            actualCheckout = actualCheckoutValue ?: existing.actualCheckout,
                            status = form.status,
                            notes = notes,
                            expectedNights = expectedNights,
                            calculatedNights = checkoutCalculatedNights ?: calculatedNights
                        )
                    )
                }

                // ✅ رفع فوري (push-only) — Dart l.799-807 pushLocalChanges.
                launch { runCatching { syncRepository.pushOnly() } }

                // ✅ حفظ الدفعة المقدمة — Dart l.804-840 (revenueType: deposit).
                if (form.hasAdvancePayment) {
                    val advanceAmount = CurrencyFormatter.parseAmount(form.advanceAmount) ?: 0.0
                    if (advanceAmount > 0) {
                        try {
                            paymentsRepository.insert(
                                Payment(
                                    bookingLocalId = newBookingId,
                                    roomNumber = roomNumber,
                                    amount = advanceAmount,
                                    paymentDate = HotelTimeEngine.formatIso(System.currentTimeMillis()),
                                    notes = form.advanceNotes.trim().ifEmpty { null },
                                    paymentMethod = form.advanceMethod,
                                    revenueType = "deposit"
                                )
                            )
                        } catch (e: Exception) {
                            _state.value = _state.value.copy(
                                snackbar = BookingEditSnackbar(
                                    "تم حفظ الحجز لكن فشل حفظ الدفعة المقدمة: $e",
                                    kind = BookingEditSnackKind.ORANGE
                                )
                            )
                        }
                    }
                }

                // ✅ تحديث حالة الغرف بعد الحفظ (Dart refreshAllRoomOccupancy).
                refreshRoomOccupancy(existing, form.status, roomNumber)

                // مزامنة ثم إغلاق — Dart l.862-866 (await syncNow ثم pop).
                runCatching { syncRepository.syncNow() }
                _state.value = _state.value.copy(isSaving = false, saved = true)
            } catch (e: IllegalStateException) {
                // خطأ منطقي (مثل: حجز مزدوج لنفس الغرفة) — Dart StateError l.849-858.
                _state.value = _state.value.copy(
                    isSaving = false,
                    snackbar = BookingEditSnackbar(
                        e.message ?: "فشل حفظ الحجز",
                        kind = BookingEditSnackKind.RED_DARK
                    )
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isSaving = false,
                    snackbar = BookingEditSnackbar("فشل حفظ الحجز: $e", kind = BookingEditSnackKind.RED_DARK)
                )
            }
        }
    }

    /**
     * عدد الليالي المتوقع — Dart _recalculateExpectedNights (l.981-1000):
     * nightsWithCutoff(checkin, checkout ?? الآن) عند قابلية تحليل الوصول،
     * وإلا القيمة المخزّنة (أو 1 لحجز جديد).
     */
    private fun expectedNightsFor(checkinText: String, checkoutText: String, existing: Booking?): Int {
        val checkin = HotelTimeEngine.parseDate(checkinText.trim())
            ?: return existing?.expectedNights ?: 1
        val checkout = HotelTimeEngine.parseDate(checkoutText.trim())
        return HotelTimeEngine.nightsWithCutoff(checkin, checkout)
    }

    /**
     * تحديث إشغال الغرف — التقريب المحلي لـ Dart refreshAllRoomOccupancy:
     * تحرير الغرفة القديمة عند إنهاء الحجز أو نقله، وإشغال الغرفة الجديدة
     * ما دام الحجز نشطاً. الأخطاء تُتجاهل (Dart: dlog فقط).
     */
    private suspend fun refreshRoomOccupancy(old: Booking?, newStatus: String, roomNumber: String) {
        try {
            val bookingActive = StatusUtils.isBookingActive(newStatus)
            if (old != null && (old.roomNumber != roomNumber || !bookingActive)) {
                val stillUsed = bookingsRepository.getAll().firstOrNull()?.any {
                    it.roomNumber == old.roomNumber && it.id != old.id &&
                        StatusUtils.isBookingActive(it.status)
                } ?: false
                if (!stillUsed) {
                    roomsRepository.getByNumber(old.roomNumber)?.let { room ->
                        if (!StatusUtils.isRoomAvailable(room.status)) {
                            roomsRepository.update(room.copy(status = "شاغرة"))
                        }
                    }
                }
            }
            if (bookingActive) {
                roomsRepository.getByNumber(roomNumber)?.let { room ->
                    if (StatusUtils.isRoomAvailable(room.status)) {
                        roomsRepository.update(room.copy(status = "محجوزة"))
                    }
                }
            }
        } catch (_: Exception) {
            // Dart: dlog فقط — لا تُعطّل أخطاء الإشغال الحفظ.
        }
    }

    /**
     * Dart `_normalizePhone` (l.1152-1168) — أرقام فقط: حذف بادئة 00،
     * حذف الصفر الافتتاحي للطول 10، وإضافة بادئة 967 إن لم توجد.
     */
    private fun normalizePhone(value: String): String {
        val digitsOnly = value.filter { it.isDigit() }
        if (digitsOnly.isEmpty()) return value.trim()
        var normalized = digitsOnly
        if (normalized.startsWith("00") && normalized.length > 2) {
            normalized = normalized.substring(2)
        }
        if (normalized.startsWith("0") && normalized.length == 10) {
            normalized = normalized.substring(1)
        }
        if (normalized.startsWith("967")) return normalized
        return "967$normalized"
    }
}
