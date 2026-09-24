package com.marina.marina.presentation.bookings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marina.marina.domain.model.Booking
import com.marina.marina.domain.repository.BookingsRepository
import com.marina.marina.domain.repository.PaymentsRepository
import com.marina.marina.domain.repository.RoomsRepository
import com.marina.marina.domain.repository.SyncRepository
import com.marina.marina.domain.util.HotelTimeEngine
import com.marina.marina.domain.util.StatusUtils
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch

/**
 * صف قائمة الحجوزات — نقل 1:1 لحسابات `_BookingRow` في
 * bookings_list.dart (فرع feat/cloudflare-sync-execution):
 *
 *  • بدون checkout مسجّل → احتساب ديناميكي للليالي من الآن (Time.nightsWithCutoff).
 *  • expectedNights = الحقل المخزّن إن كان > 0 وإلا الاحتساب من الوصول.
 *  • totalAmount = الليالي الفعلية × سعر الغرفة.
 *  • paid = مجموع المدفوعات غير الملغاة (watchTotalPaidForBooking في Dart).
 *  • remaining = (الإجمالي − المدفوع) محصور في [0, الإجمالي].
 *  • لون/نص حالة الدفعة: مسددة (أخضر) / جزئياً (برتقالي) / غير مسددة (أحمر).
 *  • شارة حالة الحجز: مؤقت/محجوزة/مكتمل/ملغي/غير معروف بنفس ألوان Dart
 *    (Colors.orange.shade100, green.shade100, blue.shade100, red.shade100, grey.shade100).
 */
data class BookingRowUi(
    val booking: Booking,
    val index: Int,
    val expectedNights: Int,
    val actualNights: Int,
    val pricePerNight: Double,
    val totalAmount: Double,
    val paid: Double,
    val remaining: Double,
    val nightsLabel: String,
    val plannedText: String?,
    val actualText: String?,
    val paymentStatusText: String,
    /** ARGB لون حالة الدفعة (Colors.green/orange/red في Dart). */
    val paymentStatusColor: Long,
    val bookingStatusText: String,
    /** ARGB خلفية شارة حالة الحجز (shade100 في Dart). */
    val bookingStatusColor: Long
)

/** رسالة سناك-بار مع لون الخلفية (نظير رسائل SnackBar في Dart). */
data class BookingsSnackbar(val text: String, val isError: Boolean = false, val isWarning: Boolean = false)

data class BookingsUiState(
    val isLoading: Boolean = true,
    val isSyncing: Boolean = false,
    val rows: List<BookingRowUi> = emptyList(),
    val error: String? = null,
    val snackbar: BookingsSnackbar? = null
)

@HiltViewModel
class BookingsViewModel @Inject constructor(
    bookingsRepository: BookingsRepository,
    roomsRepository: RoomsRepository,
    paymentsRepository: PaymentsRepository,
    private val syncRepository: SyncRepository
) : ViewModel() {

    private val _state = MutableStateFlow(BookingsUiState())
    val state: StateFlow<BookingsUiState> = _state.asStateFlow()

    init {
        combine(
            bookingsRepository.getAll(),
            roomsRepository.getAll(),
            paymentsRepository.getAll()
        ) { bookings, rooms, payments ->
            Triple(bookings, rooms, payments)
        }
            .map { (bookings, rooms, payments) ->
                val prices = rooms.associate { it.roomNumber to it.price }
                val paidByBooking = payments
                    .groupBy { it.bookingLocalId }
                    .mapValues { (_, list) -> list.sumOf { it.amount } }
                buildRows(bookings, prices, paidByBooking)
            }
            .onEach { rows ->
                _state.value = _state.value.copy(isLoading = false, rows = rows, error = null)
            }
            .catch { e ->
                _state.value = _state.value.copy(
                    isLoading = false,
                    error = e.message ?: e.toString()
                )
            }
            .launchIn(viewModelScope)

        // حالة المزامنة الحية — لمؤشر الجهد أثناء السحب-للتحديث.
        syncRepository.syncState.onEach { sync ->
            _state.value = _state.value.copy(isSyncing = sync.isSyncing)
        }.launchIn(viewModelScope)
    }

    /**
     * الفلترة والترتيب — Dart bookings_list.dart l.88-100: إخفاء
     * مكتمل/completed/غادر/departed فقط (الملغي يبقى ظاهراً) مع ترتيب
     * تنازلي على تاريخ الوصول.
     */
    private fun buildRows(
        bookings: List<Booking>,
        prices: Map<String, Double>,
        paidByBooking: Map<Long?, Double>
    ): List<BookingRowUi> {
        val filtered = bookings
            .filter { b ->
                val status = b.status.lowercase()
                status != "مكتمل" && status != "completed" &&
                    status != "غادر" && status != "departed"
            }
            .sortedByDescending { it.checkinDate }

        return filtered.mapIndexed { i, booking ->
            val price = prices[booking.roomNumber] ?: 0.0
            val checkin = HotelTimeEngine.parseDate(booking.checkinDate)
            val plannedCheckout = booking.checkoutDate?.let { HotelTimeEngine.parseDate(it) }
            val actualCheckout = booking.actualCheckout?.let { HotelTimeEngine.parseDate(it) }

            // إذا لم يُسجَّل خروج → احتساب ديناميكي من الآن (Dart l.264-270).
            val hasNoCheckout = plannedCheckout == null && actualCheckout == null
            val dynamicNights =
                if (hasNoCheckout && checkin != null) HotelTimeEngine.nightsWithCutoff(checkin) else null

            val expectedNights = dynamicNights
                ?: (if (booking.expectedNights > 0) booking.expectedNights
                    else (if (checkin == null) 1 else HotelTimeEngine.nightsWithCutoff(checkin, plannedCheckout)))
            val actualNights = dynamicNights
                ?: (if (checkin == null) expectedNights
                    else HotelTimeEngine.nightsWithCutoff(checkin, actualCheckout ?: plannedCheckout))

            val totalAmount = actualNights * price
            val paid = paidByBooking[booking.id] ?: 0.0
            val remaining = (totalAmount - paid).coerceIn(0.0, totalAmount)

            val nightsLabel = if (actualNights != expectedNights) {
                "$expectedNights ($actualNights فعلي)"
            } else {
                expectedNights.toString()
            }
            val plannedText = plannedCheckout?.let { formatDate(it) }
            val actualText = actualCheckout?.let { formatDate(it) }

            // حالة الدفعة — Dart l.560-566.
            val paymentStatusColor: Long
            val paymentStatusText: String
            if (remaining <= 0.0) {
                paymentStatusColor = GREEN
                paymentStatusText = "مسددة"
            } else if (paid > 0) {
                paymentStatusColor = ORANGE
                paymentStatusText = "جزئياً"
            } else {
                paymentStatusColor = RED
                paymentStatusText = "غير مسددة"
            }

            // شارة حالة الحجز — Dart _buildBookingStatusChip l.707-737.
            val bookingStatusColor: Long
            val bookingStatusText: String
            if (isProvisional(booking.status)) {
                bookingStatusColor = ORANGE_100
                bookingStatusText = "مؤقت"
            } else if (StatusUtils.isBookingActive(booking.status)) {
                bookingStatusColor = GREEN_100
                bookingStatusText = "محجوزة"
            } else {
                when (booking.status.lowercase()) {
                    "completed", "مكتمل" -> {
                        bookingStatusColor = BLUE_100
                        bookingStatusText = "مكتمل"
                    }
                    "cancelled", "ملغي" -> {
                        bookingStatusColor = RED_100
                        bookingStatusText = "ملغي"
                    }
                    else -> {
                        bookingStatusColor = GREY_100
                        bookingStatusText = booking.status
                    }
                }
            }

            BookingRowUi(
                booking = booking,
                index = i + 1,
                expectedNights = expectedNights,
                actualNights = actualNights,
                pricePerNight = price,
                totalAmount = totalAmount,
                paid = paid,
                remaining = remaining,
                nightsLabel = nightsLabel,
                plannedText = plannedText,
                actualText = actualText,
                paymentStatusText = paymentStatusText,
                paymentStatusColor = paymentStatusColor,
                bookingStatusText = bookingStatusText,
                bookingStatusColor = bookingStatusColor
            )
        }
    }

    /** Dart StatusUtils.isProvisional (status_utils.dart l.107-109). */
    private fun isProvisional(status: String): Boolean =
        status.trim().lowercase() in setOf("مؤقت", "provisional")

    // ─── المزامنة اليدوية (سحب-للتحديث) ────────────────────────────────

    /**
     * Dart RefreshIndicator.onRefresh → triggerManualCloudflareSync
     * (showSuccessSnackbar: false) — دفعة + سحب مع نفس رسائل الخطأ/التحذير.
     */
    fun triggerManualSync() {
        if (_state.value.isSyncing) return
        viewModelScope.launch {
            try {
                val result = syncRepository.syncNow()
                when {
                    !result.isError -> Unit // بلا سناك-بار نجاح (Dart showSuccessSnackbar: false)
                    result.lastMessage.isBlank() ->
                        _state.value = _state.value.copy(
                            snackbar = BookingsSnackbar("المزامنة قيد التنفيذ بالفعل", isWarning = true)
                        )
                    else -> _state.value = _state.value.copy(
                        snackbar = BookingsSnackbar("⚠️ فشلت المزامنة: ${result.lastMessage}", isError = true)
                    )
                }
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    snackbar = BookingsSnackbar("❌ خطأ أثناء المزامنة: $e", isError = true)
                )
            }
        }
    }

    /**
     * نظير SyncActionButton في شريط العنوان (app_scaffold.dart يضيفه لكل
     * شاشة) — مزامنة عادية بلا forcePull وبنفس رسائله حرفياً:
     * «لا توجد تغييرات جديدة» / «تمت المزامنة: رفع X / سحب Y» / «فشل في المزامنة: …».
     */
    fun runShellSync() {
        if (_state.value.isSyncing) return
        viewModelScope.launch {
            try {
                val result = syncRepository.syncNow()
                _state.value = _state.value.copy(
                    snackbar = if (!result.isError) {
                        BookingsSnackbar(
                            if (result.pushedCount == 0 && result.pulledCount == 0) {
                                "لا توجد تغييرات جديدة"
                            } else {
                                "تمت المزامنة: رفع ${result.pushedCount} / سحب ${result.pulledCount}"
                            }
                        )
                    } else {
                        BookingsSnackbar(
                            "فشل في المزامنة: ${result.lastMessage.ifBlank { "سبب غير معروف" }}",
                            isError = true
                        )
                    }
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    snackbar = BookingsSnackbar("فشل في المزامنة: $e", isError = true)
                )
            }
        }
    }

    /** رسالة سناك-بار عامة (تُستهلك مرة واحدة). */
    fun showSnackbar(text: String, isError: Boolean = false, isWarning: Boolean = false) {
        _state.value = _state.value.copy(snackbar = BookingsSnackbar(text, isError, isWarning))
    }

    fun consumeSnackbar() {
        _state.value = _state.value.copy(snackbar = null)
    }

    /** Dart _formatDate (bookings_list.dart l.757-764) — dd/MM/yyyy. */
    private fun formatDate(millis: Long): String =
        HotelTimeEngine.formatDisplayDateOnly(millis)

    companion object {
        // ألوان Flutter Material المستخدمة في القائمة (Dart bookings_list.dart).
        const val GREEN = 0xFF4CAF50L   // Colors.green
        const val ORANGE = 0xFFFF9800L  // Colors.orange
        const val RED = 0xFFF44336L     // Colors.red
        const val GREEN_100 = 0xFFC8E6C9L  // Colors.green.shade100
        const val ORANGE_100 = 0xFFFFE0B2L // Colors.orange.shade100
        const val BLUE_100 = 0xFFBBDEFBL   // Colors.blue.shade100
        const val RED_100 = 0xFFFFCDD2L    // Colors.red.shade100
        const val GREY_100 = 0xFFF5F5F5L   // Colors.grey.shade100
    }
}
