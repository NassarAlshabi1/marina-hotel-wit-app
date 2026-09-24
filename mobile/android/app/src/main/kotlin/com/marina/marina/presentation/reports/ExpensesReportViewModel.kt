package com.marina.marina.presentation.reports

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marina.marina.domain.model.Expense
import com.marina.marina.domain.model.SalaryWithdrawal
import com.marina.marina.domain.repository.EmployeesRepository
import com.marina.marina.domain.repository.ExpensesRepository
import com.marina.marina.domain.repository.SalaryWithdrawalsRepository
import com.marina.marina.domain.util.CurrencyFormatter
import com.marina.marina.domain.util.HotelTimeEngine
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.launch

/**
 * تقرير المصروفات — 1:1 port of `expenses_report_screen.dart`:
 * hotel-day range query with type filter + the salary-withdrawal merge with
 * the 3-tier dedup contract (expenseId map / `exp_<id>` reason / amount+
 * employee+day match), grouped by type with subtotals sorted descending.
 */
data class ExpenseReportRow(
    val date: String,
    val displayDate: String,
    val type: String,
    val description: String,
    val amount: Double,
    val employeeId: Long?,
    val employeeName: String?,
    val isSalaryWithdrawal: Boolean
)

data class ExpenseTypeGroup(
    val type: String,
    val rows: List<ExpenseReportRow>,
    val subtotal: Double
)

data class ExpensesReportUiState(
    val isLoading: Boolean = false,
    val range: ReportDateRange = ReportDateRange.defaultHotelDay(),
    val availableTypes: List<String> = emptyList(),
    val selectedType: String? = null, // null = الكل
    val groups: List<ExpenseTypeGroup> = emptyList(),
    val totalAmount: Double = 0.0,
    val salaryTotal: Double = 0.0,
    val salaryCount: Int = 0
) {
    val operationalTotal: Double get() = totalAmount - salaryTotal
    val operationalCount: Int get() = groups.sumOf { it.rows.size } - salaryCount
}

private val salaryTypes = setOf("رواتب", "سحب راتب", "سحب من الراتب", "خصم راتب", "خصم من الراتب")
private val cashSalaryTypes = setOf("رواتب", "سحب راتب", "سحب من الراتب", "سلفة")

private fun isSalaryType(type: String?) = type != null && salaryTypes.any { it.contains(type) || type.contains(it) }

/** Dart expenses_report_screen.dart l.57-71 — type يحتوي إحدى الكلمات المفتاحية. */
private fun isSalaryTypeFamily(type: String?): Boolean {
    if (type == null) return false
    return salaryTypes.any { type.contains(it) }
}

/**
 * Dart expenses_report_screen.dart l.1379-1394 — أفضل حالة: كلاهما يحمل
 * hotelDayKey (مساواة مباشرة)؛ احتياطياً مقارنة جزء التاريخ (10 أحرف) للسجلات
 * القديمة التي لا تحمل مفتاح اليوم الفندقي.
 */
private fun hotelDayKeysMatch(
    expenseHotelDayKey: String?,
    swHotelDayKey: String?,
    expenseDate: String,
    swWithdrawDate: Long
): Boolean {
    if (!expenseHotelDayKey.isNullOrEmpty() && !swHotelDayKey.isNullOrEmpty()) {
        return expenseHotelDayKey == swHotelDayKey
    }
    return extractDatePart(expenseDate) == extractDatePart(HotelTimeEngine.formatIso(swWithdrawDate))
}

/** Dart _extractDatePart (l.1416-1419). */
private fun extractDatePart(dateStr: String): String =
    if (dateStr.length >= 10) dateStr.substring(0, 10) else dateStr.trim()

@HiltViewModel
class ExpensesReportViewModel @Inject constructor(
    private val expensesRepository: ExpensesRepository,
    private val salaryWithdrawalsRepository: SalaryWithdrawalsRepository,
    private val employeesRepository: EmployeesRepository
) : ViewModel() {

    private val _state = MutableStateFlow(ExpensesReportUiState())
    val state: StateFlow<ExpensesReportUiState> = _state.asStateFlow()

    init { fetch() }

    fun setRange(range: ReportDateRange) {
        _state.value = _state.value.copy(range = range)
        fetch()
    }

    fun setType(type: String?) {
        _state.value = _state.value.copy(selectedType = type)
        fetch()
    }

    fun fetch() {
        viewModelScope.launch {
            try {
                _state.value = _state.value.copy(isLoading = true)
                val range = _state.value.range
                val selectedType = _state.value.selectedType

                val expenses = expensesRepository.listFilteredByHotelDay(
                    fromHotelDay = range.fromHotelDayKey,
                    toHotelDay = range.toHotelDayKey,
                    expenseType = selectedType
                )
                val employees = employeesRepository.getAll().firstOrNull() ?: emptyList()

                // Distinct types for the dropdown — 'سحب راتب' filtered out (Dart l.164-169).
                val allTypes = expensesRepository.getAllOnce()
                    .map { it.expenseType }
                    .distinct()
                    .filter { it.isNotBlank() && it != "سحب راتب" }
                    .sorted()

                // ------------------------------------------------------------------
                // Salary-withdrawal merge with the Dart 3-tier dedup (l.284-510).
                // ------------------------------------------------------------------
                val rows = mutableListOf<ExpenseReportRow>()
                val addedExpenseIds = mutableSetOf<Long>()
                val showSalary = selectedType == null || isSalaryType(selectedType)

                expenses.forEach { e ->
                    addedExpenseIds.add(e.id)
                    rows.add(
                        ExpenseReportRow(
                            date = e.date,
                            displayDate = (e.hotelDayKey ?: e.date.take(10)),
                            type = e.expenseType,
                            description = e.description,
                            amount = e.amount,
                            employeeId = e.relatedId,
                            employeeName = employees.find { emp -> emp.id == e.relatedId }?.name,
                            isSalaryWithdrawal = false
                        )
                    )
                }

                if (showSalary) {
                    val withdrawals = salaryWithdrawalsRepository.getAll().firstOrNull() ?: emptyList()
                    val rangeFrom = range.fromHotelDayKey
                    val rangeTo = range.toHotelDayKey
                    withdrawals.filter { w ->
                        val key = w.hotelDayKey
                            ?: HotelTimeEngine.hotelDayKey(w.withdrawDate)
                        key == null || (key >= rangeFrom && key <= rangeTo)
                    }.forEach { w ->
                        // Dart l.437-439: السحوبات المباشرة (direct_withdrawal_)
                        // لا تُطابق أبداً — ليس لها مصروف مقابل أصلاً وتُعرض دائماً.
                        val isDirectWithdrawal = w.reason?.startsWith("direct_withdrawal_") == true

                        // Tier 2 (Dart l.445-456): رابط معرفي مباشر عبر exp_<id>.
                        val linkedExpenseId = Regex("exp_(\\d+)").find(w.reason ?: "")?.groupValues?.get(1)?.toLongOrNull()
                        val refMatched = linkedExpenseId != null && linkedExpenseId in addedExpenseIds

                        // Tier 3 (Dart l.459-481): شبكة أمان للسجلات القديمة —
                        // نفس نوع راتب + نفس الموظف + نفس اليوم الفندقي + نفس المبلغ.
                        val dataMatch = !refMatched && expenses.any { e ->
                            isSalaryTypeFamily(e.expenseType) &&
                                e.relatedId == w.employeeId &&
                                hotelDayKeysMatch(e.hotelDayKey, w.hotelDayKey, e.date, w.withdrawDate) &&
                                kotlin.math.abs(e.amount) == kotlin.math.abs(w.amount)
                        }

                        val hasMatchingExpense = !isDirectWithdrawal && (refMatched || dataMatch)
                        if (!hasMatchingExpense) {
                            val isDeduction = (w.withdrawalType.contains("خصم") || w.withdrawalType.contains("deduction"))
                            val displayType = if (isDeduction) "خصم من الراتب" else "سحب راتب"
                            val employee = employees.find { it.id == w.employeeId }
                            rows.add(
                                ExpenseReportRow(
                                    date = "",
                                    displayDate = w.hotelDayKey ?: HotelTimeEngine.hotelDayKey(w.withdrawDate),
                                    type = displayType,
                                    description = (w.reason ?: "") + (w.description?.let { " — $it" } ?: ""),
                                    amount = w.amount,
                                    employeeId = w.employeeId,
                                    employeeName = employee?.name ?: w.employeeName.ifBlank { null },
                                    isSalaryWithdrawal = true
                                )
                            )
                        }
                    }
                }

                // Sort newest first (Dart l.528).
                val sorted = rows.sortedByDescending { it.displayDate }

                // Group by type; groups ordered by subtotal descending (Dart l.205-220).
                val grouped = sorted.groupBy { it.type }
                    .map { (type, list) -> ExpenseTypeGroup(type, list, list.sumOf { it.amount }) }
                    .sortedByDescending { it.subtotal }

                val total = sorted.sumOf { it.amount }
                val salaryRows = sorted.filter { cashSalaryTypes.contains(it.type.trim()) }

                _state.value = _state.value.copy(
                    isLoading = false,
                    availableTypes = allTypes,
                    groups = grouped,
                    totalAmount = total,
                    salaryTotal = salaryRows.sumOf { it.amount },
                    salaryCount = salaryRows.size
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(isLoading = false)
            }
        }
    }
}
