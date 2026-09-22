package com.marina.marina.presentation.reports

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marina.marina.domain.model.Booking
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
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.launch

/**
 * تقرير مدفوعات النزلاء التفصيلي — port of `guest_payments_detail_report_screen.dart`:
 * live booking list with search / status filter (partial/unpaid/overpaid) /
 * sort (room/remaining/name), coverage-based auto-checkout estimate per
 * booking, summary bar and WhatsApp per-guest statement.
 */
data class GuestDetailRow(
    val booking: Booking,
    val nightlyRate: Double,
    val actualDays: Int,
    val paidNights: Int,
    val autoCheckoutMillis: Long?,
    val isAutoExtended: Boolean,
    val paidPercent: Double
)

data class GuestDetailUiState(
    val isLoading: Boolean = true,
    val rows: List<GuestDetailRow> = emptyList(),
    val searchQuery: String = "",
    val filterStatus: String = "all", // all | partial | unpaid | overpaid
    val sortBy: String = "room", // room | remaining | name
    val showOnlyActive: Boolean = true,
    val totalDue: Double = 0.0,
    val totalPaid: Double = 0.0,
    val totalRemaining: Double = 0.0,
    val totalSurplus: Double = 0.0
)

@HiltViewModel
class GuestDetailReportViewModel @Inject constructor(
    private val bookingsRepository: BookingsRepository,
    private val paymentsRepository: PaymentsRepository,
    private val roomsRepository: RoomsRepository
) : ViewModel() {

    private val _state = MutableStateFlow(GuestDetailUiState())
    val state: StateFlow<GuestDetailUiState> = _state.asStateFlow()

    init {
        viewModelScope.launch {
            bookingsRepository.getAll().collect { bookings ->
                rebuild(bookings)
            }
        }
    }

    private suspend fun rebuild(bookings: List<Booking>) {
        val payments = paymentsRepository.getAllIncludingVoidedOnce()
        val current = _state.value
        val rows = bookings.filter { !current.showOnlyActive || StatusUtils.isBookingActive(it.status) }
            .map { booking ->
                val bookingPayments = payments.filter { it.bookingLocalId == booking.id }
                val roomRate = roomsRepository.getByNumber(booking.roomNumber)?.price ?: 0.0
                val summary = BookingFinancials.calculate(booking, roomRate, bookingPayments)
                val balance = BookingFinancials.stayBalance(booking, roomRate, summary.paidAmount)
                val consumedCost = if (summary.nightsCount > 0 && roomRate > 0) {
                    summary.nightsCount * roomRate
                } else summary.totalAmount
                GuestDetailRow(
                    booking = booking,
                    nightlyRate = if (roomRate > 0) roomRate else if (booking.calculatedNights > 0) {
                        booking.totalDueCached / booking.calculatedNights
                    } else 0.0,
                    actualDays = summary.nightsCount,
                    paidNights = balance.totalPaidNights,
                    autoCheckoutMillis = balance.autoCheckoutMillis,
                    isAutoExtended = balance.isAutoExtended,
                    paidPercent = if (consumedCost > 0) (booking.totalPaidCached / consumedCost * 100) else 100.0
                )
            }
        _state.value = current.copy(isLoading = false, rows = rows)
    }

    fun setSearch(query: String) { _state.value = _state.value.copy(searchQuery = query) }
    fun setFilterStatus(status: String) { _state.value = _state.value.copy(filterStatus = status) }
    fun setSortBy(sort: String) { _state.value = _state.value.copy(sortBy = sort) }
    fun setShowOnlyActive(active: Boolean) {
        _state.value = _state.value.copy(showOnlyActive = active)
        viewModelScope.launch { rebuild(bookingsRepository.getAll().firstOrNull() ?: emptyList()) }
    }

    /** Applies search/status/sort (Dart _filterAndSort l.268-303). */
    fun filteredRows(): List<GuestDetailRow> {
        val state = _state.value
        var list = state.rows
        val q = state.searchQuery.trim().lowercase()
        if (q.isNotBlank()) {
            list = list.filter {
                it.booking.guestName.lowercase().contains(q) ||
                    it.booking.roomNumber.lowercase().contains(q) ||
                    it.booking.guestPhone.lowercase().contains(q)
            }
        }
        list = when (state.filterStatus) {
            "partial" -> list.filter { it.booking.totalPaidCached > 0 && it.booking.remainingBalanceCached > 0 }
            "unpaid" -> list.filter { it.booking.totalPaidCached <= 0 }
            "overpaid" -> list.filter { it.booking.remainingBalanceCached < 0 }
            else -> list
        }
        return when (state.sortBy) {
            "remaining" -> list.sortedByDescending { it.booking.remainingBalanceCached }
            "name" -> list.sortedBy { it.booking.guestName }
            else -> list.sortedBy { it.booking.roomNumber }
        }
    }

    fun recalcTotals(rows: List<GuestDetailRow>) {
        _state.value = _state.value.copy(
            totalDue = rows.sumOf { it.booking.totalDueCached },
            totalPaid = rows.sumOf { it.booking.totalPaidCached },
            totalRemaining = rows.sumOf { it.booking.remainingBalanceCached.coerceAtLeast(0.0) },
            totalSurplus = rows.sumOf { (-it.booking.remainingBalanceCached).coerceAtLeast(0.0) }
        )
    }

    /** Per-guest statement message (WhatsApp). */
    fun buildGuestStatement(row: GuestDetailRow): String {
        val b = row.booking
        val checkin = HotelTimeEngine.parseDate(b.checkinDate)
        val sb = StringBuilder()
        sb.append("كشف حساب نزيل - MARINA HOTEL\n━━━━━━━━━━━\n")
        sb.append("النزيل: ${b.guestName}\nغرفة: ${b.roomNumber}\n")
        sb.append("الوصول: ${checkin?.let { HotelTimeEngine.formatDisplayDateOnly(it) } ?: "—"}\n")
        sb.append("الأيام المقضية: ${row.actualDays} يوم\n")
        sb.append("سعر الليلة: ${CurrencyFormatter.formatAmount(row.nightlyRate)} ريال\n")
        sb.append("إجمالي العقد: ${CurrencyFormatter.formatAmount(b.totalDueCached)} ريال\n")
        sb.append("إجمالي المدفوع: ${CurrencyFormatter.formatAmount(b.totalPaidCached)} ريال\n")
        if (b.remainingBalanceCached >= 0) {
            sb.append("المتبقي (عليه): ${CurrencyFormatter.formatAmount(b.remainingBalanceCached)} ريال\n")
        } else {
            sb.append("المتبقي (له): ${CurrencyFormatter.formatAmount(-b.remainingBalanceCached)} ريال\n")
        }
        row.autoCheckoutMillis?.let {
            sb.append("المغادرة التلقائية: ${HotelTimeEngine.formatDisplayDateOnly(it)} (${row.paidNights} ليلة مدفوعة)\n")
        }
        sb.append("━━━━━━━━━━━\nمارينا هوتل | 9677734587456")
        return sb.toString()
    }
}
