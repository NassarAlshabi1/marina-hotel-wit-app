package com.marina.marina.presentation.employees

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marina.marina.domain.model.Employee
import com.marina.marina.domain.repository.EmployeesRepository
import com.marina.marina.domain.repository.ExpensesRepository
import com.marina.marina.domain.util.SalaryEntitlementCalculator
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach

/**
 * Dart SalaryEntitlementService parity: entitlements derive from the
 * employee-linked EXPENSES (months worked × salary − withdrawals − advances −
 * deductions), plus the monthly cycle card math from SalaryCycleCalculator.
 */
data class SalaryEntitlementsUiState(
    val isLoading: Boolean = true,
    val entitlements: List<SalaryEntitlementCalculator.Entitlement> = emptyList(),
    // Dart summary card (l.116-172).
    val totalCount: Int = 0,
    val totalEntitlements: Double = 0.0,
    val totalWithdrawals: Double = 0.0,
    val totalAdvances: Double = 0.0,
    val totalDeductions: Double = 0.0,
    val totalNet: Double = 0.0,
    // Dart monthly cycle card per employee (expandable) — keyed by employee id.
    val cycleResults: Map<Long, SalaryEntitlementCalculator.CycleResult> = emptyMap(),
    val error: String? = null,
    val message: String? = null
) {
    val isEmpty: Boolean get() = !isLoading && entitlements.isEmpty()
}

@HiltViewModel
class SalaryEntitlementsViewModel @Inject constructor(
    private val employeesRepository: EmployeesRepository,
    private val expensesRepository: ExpensesRepository
) : ViewModel() {

    private val _state = MutableStateFlow(SalaryEntitlementsUiState())
    val state: StateFlow<SalaryEntitlementsUiState> = _state.asStateFlow()

    init {
        combine(employeesRepository.getAll(), expensesRepository.getAll()) { employees, expenses ->
            employees to expenses
        }.onEach { (employees, expenses) ->
            rebuild(employees, expenses)
        }.launchIn(viewModelScope)
    }

    private fun rebuild(employees: List<Employee>, expenses: List<com.marina.marina.domain.model.Expense>) {
        try {
            val entitlements = SalaryEntitlementCalculator.calculateAll(employees, expenses)
            // Monthly cycle per employee (current cycle, carry-over 0 — the
            // Kotlin port keeps the pure math; auto carry-over writes happen
            // in the Dart service and are surfaced after a full sync).
            val cycles = entitlements.associate { ent ->
                ent.employee.id to SalaryEntitlementCalculator.calculateCycle(
                    SalaryEntitlementCalculator.CycleInput(
                        basicSalary = ent.basicSalary,
                        withdrawals = ent.totalWithdrawals,
                        advances = ent.totalAdvances,
                        installmentsPaid = ent.installmentsPaid,
                        deductions = ent.totalDeductions
                    )
                )
            }
            _state.value = _state.value.copy(
                isLoading = false,
                entitlements = entitlements,
                cycleResults = cycles,
                totalCount = entitlements.size,
                totalEntitlements = entitlements.sumOf { it.totalEntitlement },
                totalWithdrawals = entitlements.sumOf { it.totalWithdrawals },
                totalAdvances = entitlements.sumOf { it.totalAdvances },
                totalDeductions = entitlements.sumOf { it.totalDeductions },
                totalNet = entitlements.sumOf { it.netEntitlement },
                error = null
            )
        } catch (e: Exception) {
            _state.value = _state.value.copy(isLoading = false, error = "فشل تحميل البيانات: ${e.message}")
        }
    }

    fun consumeMessage() {
        _state.value = _state.value.copy(message = null, error = null)
    }
}
