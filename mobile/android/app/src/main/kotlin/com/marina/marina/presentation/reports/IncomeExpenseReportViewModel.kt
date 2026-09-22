package com.marina.marina.presentation.reports

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marina.marina.domain.model.Expense
import com.marina.marina.domain.model.Payment
import com.marina.marina.domain.repository.BookingsRepository
import com.marina.marina.domain.repository.DebtsRepository
import com.marina.marina.domain.repository.EmployeesRepository
import com.marina.marina.domain.repository.ExpensesRepository
import com.marina.marina.domain.repository.PaymentsRepository
import com.marina.marina.domain.util.HotelTimeEngine
import com.marina.marina.domain.util.StatusUtils
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.launch
import java.util.Calendar

/**
 * تقرير الدخل والمصروفات — 1:1 port of `income_expense_report_screen.dart`:
 * merged income+expense entries (non-cash deductions excluded — the "cash
 * contract"), detailed/summary modes, daily/monthly/yearly grouping with
 * Arabic labels, the four financial indicators and CSV export.
 */
data class IncomeExpenseEntry(
    val date: Long,
    val isIncome: Boolean,
    val description: String,
    val amount: Double,
    val roomNumber: String,
    val guestName: String,
    val paymentMethod: String,
    val revenueType: String,
    val isSalary: Boolean
)

data class ReportGroup(
    val key: String,
    val label: String,
    val entries: List<IncomeExpenseEntry>,
    val incomeTotal: Double,
    val expenseTotal: Double,
    val salaryTotal: Double
) {
    val net: Double get() = incomeTotal - expenseTotal
    val count: Int get() = entries.size
}

data class IncomeExpenseReportUiState(
    val isLoading: Boolean = false,
    val range: ReportDateRange = ReportDateRange.defaultHotelDay(),
    val detailedMode: Boolean = true,
    val groupBy: String = "daily", // daily | monthly | yearly
    val entries: List<IncomeExpenseEntry> = emptyList(),
    val groups: List<ReportGroup> = emptyList(),
    val incomeTotal: Double = 0.0,
    val expenseTotal: Double = 0.0,
    val salaryTotal: Double = 0.0,
    val net: Double = 0.0,
    val unsettledDebtsAmount: Double = 0.0,
    val activeEmployees: Int = 0,
    val totalSalaryObligation: Double = 0.0,
    val bookingsInPeriod: Int = 0
) {
    // Dart l.463-473 — financial indicators.
    val profitMargin: Double get() = if (incomeTotal > 0) net / incomeTotal * 100 else 0.0
    val expenseRatio: Double get() = if (incomeTotal > 0) expenseTotal / incomeTotal * 100 else 0.0
    val salaryExpenseRatio: Double get() = if (incomeTotal > 0) salaryTotal / incomeTotal * 100 else 0.0
    val debtCoverage: Double get() = if (unsettledDebtsAmount > 0 && net > 0) net / unsettledDebtsAmount else 0.0
}

private val nonCashDeductionTypes = setOf("خصم راتب", "خصم من الراتب", "خصم", "غياب")
private val cashSalaryTypes = setOf("رواتب", "سحب راتب", "سحب من الراتب", "سلفة")

private val arabicMonths = mapOf(
    1 to "يناير", 2 to "فبراير", 3 to "مارس", 4 to "أبريل", 5 to "مايو", 6 to "يونيو",
    7 to "يوليو", 8 to "أغسطس", 9 to "سبتمبر", 10 to "أكتوبر", 11 to "نوفمبر", 12 to "ديسمبر"
)
private val arabicDayNames = mapOf(
    Calendar.SUNDAY to "الأحد", Calendar.MONDAY to "الاثنين", Calendar.TUESDAY to "الثلاثاء",
    Calendar.WEDNESDAY to "الأربعاء", Calendar.THURSDAY to "الخميس",
    Calendar.FRIDAY to "الجمعة", Calendar.SATURDAY to "السبت"
)

@HiltViewModel
class IncomeExpenseReportViewModel @Inject constructor(
    private val paymentsRepository: PaymentsRepository,
    private val expensesRepository: ExpensesRepository,
    private val bookingsRepository: BookingsRepository,
    private val debtsRepository: DebtsRepository,
    private val employeesRepository: EmployeesRepository
) : ViewModel() {

    private val _state = MutableStateFlow(IncomeExpenseReportUiState())
    val state: StateFlow<IncomeExpenseReportUiState> = _state.asStateFlow()

    init { fetch() }

    fun setRange(range: ReportDateRange) {
        _state.value = _state.value.copy(range = range)
        fetch()
    }

    fun setDetailedMode(detailed: Boolean) {
        _state.value = _state.value.copy(detailedMode = detailed)
    }

    fun setGroupBy(groupBy: String) {
        _state.value = _state.value.copy(groupBy = groupBy)
        regroup()
    }

    fun fetch() {
        viewModelScope.launch {
            try {
                _state.value = _state.value.copy(isLoading = true)
                val range = _state.value.range

                val payments = paymentsRepository.listFilteredByHotelDay(
                    fromHotelDay = range.fromHotelDayKey,
                    toHotelDay = range.toHotelDayKey,
                    excludeVoided = true,
                    excludePendingBalance = true
                )
                val expenses = expensesRepository.listFilteredByHotelDay(
                    fromHotelDay = range.fromHotelDayKey,
                    toHotelDay = range.toHotelDayKey
                )
                val bookings = bookingsRepository.getAll().firstOrNull() ?: emptyList()
                val debts = debtsRepository.getAll().firstOrNull() ?: emptyList()
                val employees = employeesRepository.getAll().firstOrNull() ?: emptyList()

                // Income entries (Dart l.2876): desc from room or generic.
                val income = payments.mapNotNull { p ->
                    val date = HotelTimeEngine.parseDate(p.paymentDate) ?: return@mapNotNull null
                    IncomeExpenseEntry(
                        date = date,
                        isIncome = true,
                        description = if (!p.roomNumber.isNullOrBlank()) "دفعة من حجز رقم ${p.roomNumber}" else "دفعة من حجز",
                        amount = p.amount,
                        roomNumber = p.roomNumber ?: "",
                        guestName = "",
                        paymentMethod = p.paymentMethod,
                        revenueType = p.revenueType,
                        isSalary = false
                    )
                }

                // Expenses: non-cash deductions dropped entirely (l.2897-2899).
                val expenseEntries = expenses.mapNotNull { e ->
                    if (e.expenseType.trim() in nonCashDeductionTypes) return@mapNotNull null
                    val date = HotelTimeEngine.parseDate(e.date) ?: return@mapNotNull null
                    IncomeExpenseEntry(
                        date = date,
                        isIncome = false,
                        description = e.description.ifBlank { e.expenseType },
                        amount = e.amount,
                        roomNumber = "",
                        guestName = "",
                        paymentMethod = "",
                        revenueType = e.expenseType,
                        isSalary = e.expenseType.trim() in cashSalaryTypes
                    )
                }

                val all = (income + expenseEntries).sortedByDescending { it.date }
                val incomeTotal = income.sumOf { it.amount }
                val expenseTotal = expenseEntries.sumOf { it.amount }
                val salaryTotal = expenseEntries.filter { it.isSalary }.sumOf { it.amount }
                val unsettled = debts.filter { !it.isSettled }.sumOf { it.remainingAmount }
                val activeEmployees = employees.filter { StatusUtils.isEmployeeActive(it.status) }
                val bookingsInPeriod = bookings.count {
                    val day = it.checkinDate.take(10)
                    day >= range.fromHotelDayKey && day <= range.toHotelDayKey
                }

                _state.value = _state.value.copy(
                    isLoading = false,
                    entries = all,
                    incomeTotal = incomeTotal,
                    expenseTotal = expenseTotal,
                    salaryTotal = salaryTotal,
                    net = incomeTotal - expenseTotal,
                    unsettledDebtsAmount = unsettled,
                    activeEmployees = activeEmployees.size,
                    totalSalaryObligation = activeEmployees.sumOf { it.basicSalary },
                    bookingsInPeriod = bookingsInPeriod
                )
                regroup()
            } catch (e: Exception) {
                _state.value = _state.value.copy(isLoading = false)
            }
        }
    }

    private fun regroup() {
        val current = _state.value
        val groups = when (current.groupBy) {
            "monthly" -> current.entries.groupBy { entry ->
                val cal = Calendar.getInstance().apply { timeInMillis = entry.date }
                "%04d-%02d".format(cal.get(Calendar.YEAR), cal.get(Calendar.MONTH) + 1)
            }
            "yearly" -> current.entries.groupBy { entry ->
                val cal = Calendar.getInstance().apply { timeInMillis = entry.date }
                "%04d".format(cal.get(Calendar.YEAR))
            }
            else -> current.entries.groupBy { entry ->
                val cal = Calendar.getInstance().apply { timeInMillis = entry.date }
                "%04d-%02d-%02d".format(
                    cal.get(Calendar.YEAR), cal.get(Calendar.MONTH) + 1, cal.get(Calendar.DAY_OF_MONTH)
                )
            }
        }.map { (key, list) ->
            val label = groupLabel(key)
            ReportGroup(
                key = key,
                label = label,
                entries = list.sortedByDescending { it.date },
                incomeTotal = list.filter { it.isIncome }.sumOf { it.amount },
                expenseTotal = list.filter { !it.isIncome }.sumOf { it.amount },
                salaryTotal = list.filter { !it.isIncome && it.isSalary }.sumOf { it.amount }
            )
        }.sortedByDescending { it.key }

        _state.value = current.copy(groups = groups)
    }

    private fun groupLabel(key: String): String = when (_state.value.groupBy) {
        "monthly" -> {
            val parts = key.split("-")
            "${arabicMonths[parts[1].toInt()]} ${parts[0]}"
        }
        "yearly" -> "$key م"
        else -> {
            val cal = Calendar.getInstance()
            HotelTimeEngine.parseDate(key + " 12:00:00")?.let { cal.timeInMillis = it }
            "${cal.get(Calendar.DAY_OF_MONTH)} ${arabicMonths[cal.get(Calendar.MONTH) + 1]} ${cal.get(Calendar.YEAR)} (${arabicDayNames[cal.get(Calendar.DAY_OF_WEEK)]})"
        }
    }

    /** Dart `_exportCsv` (l.2075-2145) — exact template. */
    fun buildCsv(): String {
        val state = _state.value
        val sb = StringBuilder("\uFEFF")
        sb.append("النوع,التاريخ,الوصف,المبلغ,التصنيف\n")
        state.entries.sortedBy { it.date }.forEach { e ->
            val type = if (e.isIncome) "دخل" else "مصروف"
            val classification = when {
                e.isIncome -> "دفعة"
                e.isSalary -> "راتب"
                else -> e.revenueType
            }
            val desc = e.description.replace("\"", "\"\"")
            val date = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US).format(java.util.Date(e.date))
            sb.append("$type,$date,\"$desc\",${e.amount.toInt()},$classification\n")
        }
        sb.append("\nالملخص\n")
        sb.append("إجمالي الدخل,${state.incomeTotal.toInt()}\n")
        sb.append("إجمالي المصروفات,${state.expenseTotal.toInt()}\n")
        sb.append("مصروفات الرواتب,${state.salaryTotal.toInt()}\n")
        sb.append("صافي الربح,${state.net.toInt()}\n")
        return sb.toString()
    }
}
