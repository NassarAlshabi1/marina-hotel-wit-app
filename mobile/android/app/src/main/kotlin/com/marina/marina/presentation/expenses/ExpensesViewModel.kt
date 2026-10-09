package com.marina.marina.presentation.expenses

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marina.marina.domain.model.Employee
import com.marina.marina.domain.model.Expense
import com.marina.marina.domain.repository.EmployeesRepository
import com.marina.marina.domain.repository.ExpensesRepository
import com.marina.marina.domain.session.UserSessionManager
import com.marina.marina.domain.util.HotelTimeEngine
import com.marina.marina.presentation.reports.ReportDateRange
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch

/**
 * Expenses screen state — mirrors the Dart screen behaviour in
 * `expenses_list.dart`: hotel-day range query through the repository
 * (l.249-287), dynamic type filter minus سلفة (l.99-105), debounced search
 * (l.436-444), permission gates (l.111, 692-693) and Arabic feedback
 * strings (l.870, 884, 1389).
 */
data class ExpensesUiState(
    val isLoading: Boolean = false,
    /** Result of the current listFilteredByHotelDay query (Dart _expensesStream). */
    val expenses: List<Expense> = emptyList(),
    /** Active employees — the dialog dropdown source (Dart availableEmployees). */
    val employees: List<Employee> = emptyList(),
    val searchQuery: String = "",
    /** Dart _selectedFilterType — null = كل الأنواع. */
    val selectedType: String? = null,
    /** Manual range; its hotel-day keys are the contract keys (14:01/14:00). */
    val range: ReportDateRange = ReportDateRange.defaultHotelDay(),
    /** Dart _filterActive — false = the current hotel day only. */
    val filterActive: Boolean = false,
    val canCreate: Boolean = false,
    val canUpdate: Boolean = false,
    val canDelete: Boolean = false,
    val error: String? = null,
    val message: String? = null
) {
    /**
     * Dart _expenseTypes (l.99-105): the dynamic catalog minus سلفة (its
     * amounts also appear as خصم installments, so showing it duplicates
     * rows). Kotlin parity: the default catalog union with every type
     * already present in data (the legacy/custom-type protection).
     */
    val typeOptions: List<String>
        get() = (kDefaultExpenseTypes.filter { it != SALARY_ADVANCE_ACTION } + expenses.map { it.expenseType })
            .distinct()

    /**
     * Dart dedup (l.941-967): multi-device sync can deliver the same person
     * under different autoIncrement ids, so dedup by localUuid first, then
     * by name as the fallback for blank/legacy uuid rows.
     */
    val availableEmployees: List<Employee>
        get() {
            val seenUuids = HashSet<String>()
            val seenNames = HashSet<String>()
            return employees.filter { employee ->
                val uuid = employee.localUuid.trim()
                if (uuid.isNotEmpty() && !seenUuids.add(uuid)) return@filter false
                val nameKey = employee.name.trim()
                if (nameKey.isNotEmpty() && !seenNames.add(nameKey)) return@filter false
                true
            }
        }

    /** Dart filteredTotal/filteredCount (l.151-155) — computed from the queried list. */
    val filteredTotal: Double get() = expenses.sumOf { it.amount }
    val filteredCount: Int get() = expenses.size
}

private data class FilterSnapshot(
    val search: String,
    val type: String?,
    val range: ReportDateRange,
    val active: Boolean
)

@OptIn(ExperimentalCoroutinesApi::class, FlowPreview::class)
@HiltViewModel
class ExpensesViewModel @Inject constructor(
    private val expensesRepository: ExpensesRepository,
    private val employeesRepository: EmployeesRepository,
    private val userSessionManager: UserSessionManager
) : ViewModel() {

    private val _state = MutableStateFlow(ExpensesUiState(isLoading = true))
    val state: StateFlow<ExpensesUiState> = _state.asStateFlow()

    private val searchFlow = MutableStateFlow("")
    private val selectedTypeFlow = MutableStateFlow<String?>(null)
    private val rangeFlow = MutableStateFlow(ReportDateRange.defaultHotelDay())
    private val filterActiveFlow = MutableStateFlow(false)
    private val reloadTrigger = MutableStateFlow(0)

    init {
        // Dart authProvider.canPerform('expenses', …) (l.111, 692-693, 815-819).
        userSessionManager.currentUser.onEach { user ->
            _state.value = _state.value.copy(
                canCreate = user?.canPerform("expenses", "create") ?: false,
                canUpdate = user?.canPerform("expenses", "update") ?: false,
                canDelete = user?.canPerform("expenses", "delete") ?: false
            )
        }.launchIn(viewModelScope)

        // Employees feed the card names and the dialog dropdown.
        employeesRepository.getAll().onEach { employees ->
            _state.value = _state.value.copy(employees = employees)
        }.launchIn(viewModelScope)

        // Dart _buildExpensesStream (l.249-287): every filter change rebuilds
        // one repository query — hotel-day range with type + search pushed
        // down to listFilteredByHotelDay, not client-side filtering.
        combine(
            searchFlow.debounce(300), // Dart _debounceTimer (l.436-444)
            selectedTypeFlow,
            rangeFlow,
            filterActiveFlow,
            reloadTrigger
        ) { query, type, range, active, _ ->
            FilterSnapshot(query, type, range, active)
        }.flatMapLatest { snapshot ->
            flow {
                _state.value = _state.value.copy(isLoading = true)
                // Dart l.260-274: without a manual filter both ends are the
                // current hotel day (14:01 → 14:00).
                val fromKey = if (snapshot.active) snapshot.range.fromHotelDayKey
                else HotelTimeEngine.currentHotelDayKey()
                val toKey = if (snapshot.active) snapshot.range.toHotelDayKey
                else HotelTimeEngine.currentHotelDayKey()
                val rows = expensesRepository.listFilteredByHotelDay(
                    fromHotelDay = fromKey,
                    toHotelDay = toKey,
                    expenseType = snapshot.type,
                    search = snapshot.search.trim().takeIf { it.isNotBlank() }
                )
                _state.value = _state.value.copy(isLoading = false, expenses = rows, error = null)
                emit(rows)
            }
        }.catch { e ->
            // Dart snapshot.hasError branch (l.137-141).
            _state.value = _state.value.copy(
                isLoading = false,
                error = "حدث خطأ أثناء تحميل المصروفات: ${e.message}"
            )
        }.launchIn(viewModelScope)
    }

    fun setSearchQuery(query: String) {
        _state.value = _state.value.copy(searchQuery = query)
        searchFlow.value = query
    }

    fun selectType(type: String?) {
        _state.value = _state.value.copy(selectedType = type)
        selectedTypeFlow.value = type
    }

    fun setRange(range: ReportDateRange) {
        // Dart _pickDate (l.315-377): picking a date activates the manual filter.
        _state.value = _state.value.copy(range = range, filterActive = true)
        rangeFlow.value = range
        filterActiveFlow.value = true
    }

    fun clearDateFilter() {
        // Dart l.593-596.
        _state.value = _state.value.copy(filterActive = false)
        filterActiveFlow.value = false
    }

    /** Pull-to-refresh / manual reload (Dart _refreshExpensesStream). */
    fun refresh() {
        reloadTrigger.value++
    }

    fun consumeMessage() {
        _state.value = _state.value.copy(message = null, error = null)
    }

    /**
     * Dart archived-employee protection (l.970-983): the linked employee of
     * an edited expense may be soft-deleted, in which case it is fetched
     * through the raw lookup and displayed with a (مؤرشف) marker so saving
     * does not crash on a missing dropdown entry.
     */
    suspend fun getArchivedEmployee(id: Long): Employee? =
        employeesRepository.getByIdIncludingDeleted(id)

    /**
     * Dart _edit save path (l.1193-1331):
     * - رواتب: derive the storage type from the dialog action, link the
     *   employee (relatedId + employeeUuid written NOW — التوصية 1), and the
     *   repository mirrors the withdrawal in the same transaction.
     * - غير الرواتب: no employee link; update clears any old link (repo contract).
     * - hotelDayKey is always recomputed from the picked date via the 14:01 rule.
     */
    fun saveExpense(
        existing: Expense?,
        selectedType: String,
        salaryAction: String?,
        employee: Employee?,
        amount: Double,
        description: String,
        pickedDateKey: String
    ) {
        viewModelScope.launch {
            try {
                val isSalary = selectedType == SALARY_TYPE
                val savedType = if (isSalary) {
                    deriveSalaryExpenseType(salaryAction ?: SALARY_WITHDRAW_ACTION)
                } else {
                    selectedType
                }
                val hotelDayKey = hotelDayKeyFromPickedDate(pickedDateKey)
                if (existing == null) {
                    expensesRepository.insert(
                        Expense(
                            expenseType = savedType,
                            relatedId = if (isSalary) employee?.id else null,
                            employeeUuid = if (isSalary) employee?.localUuid else null,
                            description = description,
                            amount = amount,
                            date = pickedDateKey,
                            hotelDayKey = hotelDayKey
                        )
                    )
                } else {
                    expensesRepository.update(
                        existing.copy(
                            expenseType = savedType,
                            relatedId = if (isSalary) employee?.id else null,
                            // Dart l.1304-1306: non-salary passes '' so any stale
                            // link is cleared — the Kotlin repo does the same clear.
                            employeeUuid = if (isSalary) employee?.localUuid else "",
                            description = description,
                            amount = amount,
                            date = pickedDateKey,
                            hotelDayKey = hotelDayKey
                        )
                    )
                }
                autoExpandFilterIfNeeded(hotelDayKey)
                _state.value = _state.value.copy(message = "تم حفظ المصروف بنجاح")
                refresh()
            } catch (e: Exception) {
                // Dart l.1383-1393.
                _state.value = _state.value.copy(error = "فشل حفظ المصروف: ${e.message}")
            }
        }
    }

    /**
     * Dart _deleteExpense (l.850-885): the mirror (salary withdrawal) is
     * deleted first, then the expense — the Kotlin repository performs both
     * inside one transaction with the same ordering guarantees.
     */
    fun deleteExpense(expense: Expense) {
        viewModelScope.launch {
            try {
                expensesRepository.softDelete(expense.id)
                _state.value = _state.value.copy(message = "تم حذف المصروف بنجاح")
                refresh()
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = "فشل حذف المصروف: ${e.message}")
            }
        }
    }

    /**
     * Dart l.1333-1358: widen the manual range so an expense saved outside
     * the current filter window is always visible right after saving.
     */
    private fun autoExpandFilterIfNeeded(savedHotelDayKey: String) {
        val s = _state.value
        val currentFrom = if (s.filterActive) s.range.fromHotelDayKey else HotelTimeEngine.currentHotelDayKey()
        val currentTo = if (s.filterActive) s.range.toHotelDayKey else HotelTimeEngine.currentHotelDayKey()
        if (savedHotelDayKey < currentFrom || savedHotelDayKey > currentTo) {
            val minKey = minOf(savedHotelDayKey, currentFrom)
            val maxKey = maxOf(savedHotelDayKey, currentTo)
            val fromMs = HotelTimeEngine.parseDate("$minKey 14:01:00")
            val toMs = HotelTimeEngine.parseDate("$maxKey 14:01:00")
            if (fromMs != null && toMs != null) {
                val newRange = ReportDateRange(
                    HotelTimeEngine.hotelDayStart(fromMs),
                    HotelTimeEngine.hotelDayEnd(toMs) - 1
                )
                _state.value = _state.value.copy(range = newRange, filterActive = true)
                rangeFlow.value = newRange
                filterActiveFlow.value = true
            }
        }
    }
}
