package com.marina.marina.presentation.expenses

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marina.marina.domain.model.Expense
import com.marina.marina.domain.repository.EmployeesRepository
import com.marina.marina.domain.repository.ExpensesRepository
import com.marina.marina.domain.repository.SalaryWithdrawalsRepository
import com.marina.marina.domain.util.HotelTimeEngine
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch

data class ExpensesUiState(
    val isLoading: Boolean = false,
    val expenses: List<Expense> = emptyList(),
    val employeeNames: Map<Long, String> = emptyMap(),
    val searchQuery: String = "",
    val typeFilter: String = "today", // today (hotel day) | week | month | all
    val error: String? = null,
    val message: String? = null
) {
    private val todayKey: String = HotelTimeEngine.currentHotelDayKey()

    val filtered: List<Expense>
        get() {
            var list = expenses
            when (typeFilter) {
                "today" -> list = list.filter { it.hotelDayKey == todayKey }
                "week" -> {
                    // hotel-day keys sort lexicographically; compare the last 7 keys.
                    val recentKeys = generateSequence(todayKey) { key ->
                        HotelTimeEngine.parseDate(key)?.let { millis ->
                            HotelTimeEngine.hotelDayKey(millis - 24L * 60 * 60 * 1000)
                        }
                    }.take(7).toSet()
                    list = list.filter { it.hotelDayKey in recentKeys }
                }
                "month" -> {
                    val prefix = todayKey.take(7)
                    list = list.filter { (it.hotelDayKey ?: "").startsWith(prefix) }
                }
            }
            val q = searchQuery.trim()
            if (q.isNotBlank()) {
                list = list.filter {
                    it.expenseType.contains(q, ignoreCase = true) ||
                        it.description.contains(q, ignoreCase = true)
                }
            }
            return list
        }

    val filteredTotal: Double get() = filtered.sumOf { it.amount }
    val availableTypes: List<String> get() = expenses.map { it.expenseType }.distinct().sorted()

    val todayTotal: Double get() = expenses.filter { it.hotelDayKey == todayKey }.sumOf { it.amount }
}

@HiltViewModel
class ExpensesViewModel @Inject constructor(
    private val expensesRepository: ExpensesRepository,
    private val employeesRepository: EmployeesRepository,
    private val salaryWithdrawalsRepository: SalaryWithdrawalsRepository
) : ViewModel() {

    private val _state = MutableStateFlow(ExpensesUiState(isLoading = true))
    val state: StateFlow<ExpensesUiState> = _state.asStateFlow()

    init {
        combine(expensesRepository.getAll(), employeesRepository.getAll()) { expenses, employees ->
            expenses to employees.associate { it.id to it.name }
        }.onEach { (expenses, names) ->
            _state.value = _state.value.copy(isLoading = false, expenses = expenses, employeeNames = names, error = null)
        }.launchIn(viewModelScope)
    }

    fun setSearchQuery(query: String) {
        _state.value = _state.value.copy(searchQuery = query)
    }

    fun setTypeFilter(filter: String) {
        _state.value = _state.value.copy(typeFilter = filter)
    }

    fun consumeMessage() {
        _state.value = _state.value.copy(message = null)
    }

    /** أنواع إجراءات الرواتب — عقد Dart _isSalaryAction (expenses_list.dart l.1441-1451). */
    private val salaryActionTypes = setOf(
        "رواتب", "سحب راتب", "سحب من الراتب", "خصم راتب", "خصم من الراتب"
    )

    fun saveExpense(expense: Expense) {
        viewModelScope.launch {
            try {
                if (expense.id == 0L) {
                    val newId = expensesRepository.insert(expense)
                    // Dart expenses_list.dart l.1191-1214: مصروف راتب جديد
                    // بموظف مقترن → saveFromExpense يربط السحب عبر exp_<id>
                    // (إلا فلا ربط — نفس فرع Dart بدون موظف).
                    if (expense.expenseType in salaryActionTypes && expense.relatedId != null) {
                        salaryWithdrawalsRepository.saveFromExpense(
                            expenseId = newId,
                            employeeId = expense.relatedId!!,
                            employeeUuid = expense.employeeUuid,
                            employeeName = _state.value.employeeNames[expense.relatedId] ?: "",
                            action = expense.expenseType,
                            amount = expense.amount,
                            date = expense.date,
                            note = expense.description.takeIf { it.isNotBlank() },
                            hotelDayKey = expense.hotelDayKey ?: HotelTimeEngine.currentHotelDayKey()
                        )
                    }
                    _state.value = _state.value.copy(message = "تمت إضافة المصروف")
                } else {
                    // ✅ عقد Dart expenses_list.dart l.1216-1262 — التعديل يزامن
                    // السحب المقترن: مصروف راتب → saveFromExpense (upsert بالرابط
                    // exp_<id> فيبقى المبلغ متسقاً وإزالة تكرار التقرير سليمة)؛
                    // غير راتب → deleteByExpenseId + مسح رابط الموظف (relatedId /
                    // employeeUuid) كي لا يبقى رابط يتيم عند التحويل من راتب
                    // لنوع آخر — هذا هو سبب تكرار السحوبات في التقرير سابقاً.
                    val isSalary = expense.expenseType in salaryActionTypes
                    val prepared = if (isSalary) expense else expense.copy(relatedId = null, employeeUuid = "")
                    expensesRepository.update(prepared)
                    if (isSalary && expense.relatedId != null) {
                        salaryWithdrawalsRepository.saveFromExpense(
                            expenseId = expense.id,
                            employeeId = expense.relatedId!!,
                            employeeUuid = expense.employeeUuid,
                            employeeName = _state.value.employeeNames[expense.relatedId] ?: "",
                            action = expense.expenseType,
                            amount = expense.amount,
                            date = expense.date,
                            note = expense.description.takeIf { it.isNotBlank() },
                            hotelDayKey = expense.hotelDayKey ?: HotelTimeEngine.currentHotelDayKey()
                        )
                    } else {
                        salaryWithdrawalsRepository.deleteByExpenseId(expense.id)
                    }
                    _state.value = _state.value.copy(message = "تم تحديث المصروف")
                }
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = e.message)
            }
        }
    }

    fun deleteExpense(expense: Expense) {
        viewModelScope.launch {
            try {
                // Dart expenses_list.dart l.850-856: حذف السحب المقترن أولاً
                // ثم المصروف — حماية تكامل البيانات (لا سحوبات يتيمة تعود
                // لتظهر في التقرير بعد الحذف).
                salaryWithdrawalsRepository.deleteByExpenseId(expense.id)
                expensesRepository.softDelete(expense.id)
                _state.value = _state.value.copy(message = "تم حذف المصروف")
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = e.message)
            }
        }
    }
}
