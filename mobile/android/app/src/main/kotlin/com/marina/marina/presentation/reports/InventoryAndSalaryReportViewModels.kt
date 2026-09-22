package com.marina.marina.presentation.reports

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marina.marina.domain.model.InventoryItem
import com.marina.marina.domain.model.InventoryTransaction
import com.marina.marina.domain.model.SalaryWithdrawal
import com.marina.marina.domain.repository.EmployeesRepository
import com.marina.marina.domain.repository.InventoryRepository
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

// ---------------------------------------------------------------------------
// التقرير المخزني — port of `inventory_report_screen.dart`
// ---------------------------------------------------------------------------

data class InventoryReportRow(
    val item: InventoryItem,
    val totalIn: Double,
    val totalOut: Double,
    val totalAdjustment: Double,
    val movementCount: Int
) {
    val isLowStock: Boolean get() = item.minimumQuantity > 0 && item.currentQuantity <= item.minimumQuantity
}

data class InventoryReportUiState(
    val isLoading: Boolean = false,
    val range: ReportDateRange = ReportDateRange.defaultHotelDay(),
    val categories: List<String> = emptyList(),
    val selectedCategory: String? = null,
    val rows: List<InventoryReportRow> = emptyList(),
    val totalIn: Double = 0.0,
    val totalOut: Double = 0.0,
    val totalAdjustment: Double = 0.0,
    val movementCount: Int = 0
) {
    val lowStockCount: Int get() = rows.count { it.isLowStock }
}

@HiltViewModel
class InventoryReportViewModel @Inject constructor(
    private val inventoryRepository: InventoryRepository
) : ViewModel() {

    private val _state = MutableStateFlow(InventoryReportUiState())
    val state: StateFlow<InventoryReportUiState> = _state.asStateFlow()

    init { fetch() }

    fun setRange(range: ReportDateRange) {
        _state.value = _state.value.copy(range = range)
        fetch()
    }

    fun setCategory(category: String?) {
        _state.value = _state.value.copy(selectedCategory = category)
        fetch()
    }

    fun fetch() {
        viewModelScope.launch {
            try {
                _state.value = _state.value.copy(isLoading = true)
                val range = _state.value.range
                val items = inventoryRepository.getAllItems().firstOrNull() ?: emptyList()
                val filteredItems = items.filter {
                    _state.value.selectedCategory == null || it.category == _state.value.selectedCategory
                }
                val categories = items.mapNotNull { it.category?.takeIf { c -> c.isNotBlank() } }.distinct().sorted()

                val rows = filteredItems.map { item ->
                    val txs = inventoryRepository.getTransactionsForItem(item.id).firstOrNull() ?: emptyList()
                    val inRange = txs.filter { it.transactionTime in range.from..range.to }
                    InventoryReportRow(
                        item = item,
                        totalIn = inRange.filter { it.transactionType == "in" }.sumOf { it.quantity },
                        totalOut = inRange.filter { it.transactionType == "out" }.sumOf { it.quantity },
                        totalAdjustment = inRange.filter { it.transactionType == "adjustment" }.sumOf { it.quantity },
                        movementCount = inRange.size
                    )
                }.sortedWith(
                    // Low-stock items float to top (Dart ORDER BY contract).
                    compareBy({ !it.isLowStock }, { it.item.name })
                )

                _state.value = _state.value.copy(
                    isLoading = false,
                    categories = categories,
                    rows = rows,
                    totalIn = rows.sumOf { it.totalIn },
                    totalOut = rows.sumOf { it.totalOut },
                    totalAdjustment = rows.sumOf { it.totalAdjustment },
                    movementCount = rows.sumOf { it.movementCount }
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(isLoading = false)
            }
        }
    }
}

// ---------------------------------------------------------------------------
// تقرير سحبيات الرواتب — port of `salary_withdrawals_report_screen.dart`
// ---------------------------------------------------------------------------

data class SalaryWithdrawalRow(
    val withdrawal: SalaryWithdrawal,
    val employeeName: String
) {
    val isDeduction: Boolean
        get() = withdrawal.withdrawalType.contains("خصم") || withdrawal.withdrawalType.contains("deduction")
}

data class SalaryWithdrawalGroup(
    val employeeId: Long,
    val employeeName: String,
    val rows: List<SalaryWithdrawalRow>,
    val totalAmount: Double
)

data class SalaryReportUiState(
    val isLoading: Boolean = false,
    val range: ReportDateRange = ReportDateRange.defaultHotelDay(),
    val employees: List<Pair<Long, String>> = emptyList(),
    val selectedEmployeeId: Long? = null,
    val rows: List<SalaryWithdrawalRow> = emptyList(),
    val groups: List<SalaryWithdrawalGroup> = emptyList(),
    val totalAmount: Double = 0.0
) {
    val selectedEmployeeName: String?
        get() = employees.find { it.first == selectedEmployeeId }?.second
}

@HiltViewModel
class SalaryReportViewModel @Inject constructor(
    private val salaryWithdrawalsRepository: SalaryWithdrawalsRepository,
    private val employeesRepository: EmployeesRepository
) : ViewModel() {

    private val _state = MutableStateFlow(SalaryReportUiState())
    val state: StateFlow<SalaryReportUiState> = _state.asStateFlow()

    init { fetch() }

    fun setRange(range: ReportDateRange) {
        _state.value = _state.value.copy(range = range)
        fetch()
    }

    fun setEmployee(id: Long?) {
        _state.value = _state.value.copy(selectedEmployeeId = id)
        fetch()
    }

    fun fetch() {
        viewModelScope.launch {
            try {
                _state.value = _state.value.copy(isLoading = true)
                val range = _state.value.range
                val employees = (employeesRepository.getAll().firstOrNull() ?: emptyList())
                    .sortedBy { it.name }
                val withdrawals = salaryWithdrawalsRepository.getAll().firstOrNull() ?: emptyList()

                val rows = withdrawals.map { w ->
                    SalaryWithdrawalRow(
                        withdrawal = w,
                        employeeName = employees.find { it.id == w.employeeId }?.name
                            ?: w.employeeName.ifBlank { "غير محدد" }
                    )
                }.filter { row ->
                    val selected = _state.value.selectedEmployeeId
                    selected == null || row.withdrawal.employeeId == selected
                }.filter { row ->
                    // Hotel-day range on hotelDayKey with withdrawDate fallback.
                    val key = row.withdrawal.hotelDayKey
                        ?: HotelTimeEngine.hotelDayKey(row.withdrawal.withdrawDate)
                    key >= range.fromHotelDayKey && key <= range.toHotelDayKey
                }.sortedByDescending { it.withdrawal.withdrawDate }

                val groups = rows.groupBy { it.withdrawal.employeeId }
                    .map { (id, list) ->
                        SalaryWithdrawalGroup(
                            employeeId = id,
                            employeeName = list.firstOrNull()?.employeeName ?: "غير محدد",
                            rows = list,
                            totalAmount = list.sumOf { it.withdrawal.amount }
                        )
                    }
                    .sortedByDescending { g -> g.rows.maxOfOrNull { it.withdrawal.withdrawDate } ?: 0L }

                _state.value = _state.value.copy(
                    isLoading = false,
                    employees = employees.map { it.id to it.name },
                    rows = rows,
                    groups = groups,
                    totalAmount = rows.sumOf { it.withdrawal.amount }
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(isLoading = false)
            }
        }
    }
}
