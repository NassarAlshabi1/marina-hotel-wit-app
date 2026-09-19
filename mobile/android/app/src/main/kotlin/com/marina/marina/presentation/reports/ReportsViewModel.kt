package com.marina.marina.presentation.reports

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marina.marina.domain.repository.BookingsRepository
import com.marina.marina.domain.repository.DebtsRepository
import com.marina.marina.domain.repository.ExpensesRepository
import com.marina.marina.domain.repository.PaymentsRepository
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

/** One row of the payments report. */
data class PaymentReportRow(
    val bookingId: Long,
    val guestName: String,
    val roomNumber: String,
    val method: String,
    val hotelDayKey: String,
    val amount: Double
)

/** Per-type expense subtotal. */
data class ExpenseTypeGroup(
    val type: String,
    val total: Double,
    val count: Int
)

data class IncomeExpenseSummary(
    val totalIncome: Double = 0.0,
    val totalExpenses: Double = 0.0,
    val net: Double = 0.0,
    val bookingsCount: Int = 0,
    val activeBookings: Int = 0,
    val unsettledDebts: Int = 0,
    val unsettledDebtsTotal: Double = 0.0
)

data class ReportsUiState(
    val isLoading: Boolean = false,
    val range: String = "today", // today | week | month | all
    val paymentRows: List<PaymentReportRow> = emptyList(),
    val expenseGroups: List<ExpenseTypeGroup> = emptyList(),
    val summary: IncomeExpenseSummary = IncomeExpenseSummary(),
    val error: String? = null
) {
    val paymentsTotal: Double get() = paymentRows.sumOf { it.amount }
    val expensesTotal: Double get() = expenseGroups.sumOf { it.total }

    /** Range label shown in the header. */
    val rangeLabel: String
        get() = when (range) {
            "today" -> "اليوم الفندقي"
            "week" -> "آخر 7 أيام"
            "month" -> "الشهر الحالي"
            else -> "كل الفترات"
        }
}

@HiltViewModel
class ReportsViewModel @Inject constructor(
    paymentsRepository: PaymentsRepository,
    expensesRepository: ExpensesRepository,
    bookingsRepository: BookingsRepository,
    debtsRepository: DebtsRepository
) : ViewModel() {

    private data class ReportData(
        val payments: List<com.marina.marina.domain.model.Payment>,
        val expenses: List<com.marina.marina.domain.model.Expense>,
        val bookings: List<com.marina.marina.domain.model.Booking>,
        val debts: List<com.marina.marina.domain.model.Debt>
    )

    private var lastData: ReportData? = null

    private val _state = MutableStateFlow(ReportsUiState(isLoading = true))
    val state: StateFlow<ReportsUiState> = _state.asStateFlow()

    init {
        combine(
            paymentsRepository.getAll(),
            expensesRepository.getAll(),
            bookingsRepository.getAll(),
            debtsRepository.getAll()
        ) { payments, expenses, bookings, debts ->
            ReportData(payments, expenses, bookings, debts)
        }.onEach { data ->
            lastData = data
            _state.value = computeReport(_state.value.range, data, isLoading = false)
        }.launchIn(viewModelScope)
    }

    fun setRange(range: String) {
        val data = lastData ?: return
        _state.value = computeReport(range, data, isLoading = false)
    }

    private fun computeReport(range: String, data: ReportData, isLoading: Boolean): ReportsUiState {
        val todayKey = HotelTimeEngine.currentHotelDayKey()
        val monthPrefix = todayKey.take(7)

        fun inRange(key: String?): Boolean {
            val k = key ?: return range == "all"
            return when (range) {
                "today" -> k == todayKey
                "week" -> {
                    val recent = generateSequence(todayKey) { prev ->
                        HotelTimeEngine.parseDate(prev)?.let { HotelTimeEngine.hotelDayKey(it - 24L * 60 * 60 * 1000) }
                    }.take(7).toSet()
                    k in recent
                }
                "month" -> k.startsWith(monthPrefix)
                else -> true
            }
        }

        // ---- Payments rows ---------------------------------------------------
        val bookingNames = data.bookings.associate { it.id to (it.guestName to it.roomNumber) }
        val paymentRows = data.payments
            .filter { inRange(it.hotelDayKey) }
            .map { payment ->
                val (guest, room) = bookingNames[payment.bookingLocalId]
                    ?: ("—" to (payment.roomNumber ?: "—"))
                PaymentReportRow(
                    bookingId = payment.bookingLocalId ?: 0,
                    guestName = guest,
                    roomNumber = payment.roomNumber ?: room,
                    method = payment.paymentMethod,
                    hotelDayKey = payment.hotelDayKey ?: "—",
                    amount = payment.amount
                )
            }
            .sortedByDescending { it.hotelDayKey }

        // ---- Expense groups --------------------------------------------------
        val filteredExpenses = data.expenses.filter { inRange(it.hotelDayKey) }
        val expenseGroups = filteredExpenses
            .groupBy { it.expenseType }
            .map { (type, list) -> ExpenseTypeGroup(type, list.sumOf { it.amount }, list.size) }
            .sortedByDescending { it.total }

        // ---- Income / expense summary -----------------------------------------
        val totalIncome = paymentRows.sumOf { it.amount }
        val totalExpenses = filteredExpenses.sumOf { it.amount }
        val summary = IncomeExpenseSummary(
            totalIncome = totalIncome,
            totalExpenses = totalExpenses,
            net = totalIncome - totalExpenses,
            bookingsCount = data.bookings.size,
            activeBookings = data.bookings.count { StatusUtils.isBookingActive(it.status) },
            unsettledDebts = data.debts.count { !it.isSettled },
            unsettledDebtsTotal = data.debts.filter { !it.isSettled }.sumOf { it.remainingAmount }
        )

        return ReportsUiState(
            isLoading = isLoading,
            range = range,
            paymentRows = paymentRows,
            expenseGroups = expenseGroups,
            summary = summary,
            error = null
        )
    }
}
